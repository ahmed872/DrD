/**
 * محرّك الحجز على الخادم.
 *
 * ## لماذا انتقل الحجز إلى هنا
 *
 * قبل هذا الملف كان العميل هو من يقرّر الحجز: يحسب الخانات المتاحة، ويحدّد
 * السعة، ويرسل السعر واسم الطبيب واسم المريض ورقمه ضمن مستند الموعد. قواعد
 * الأمان تحرس ما تستطيع حراسته (السعة، التوثيق، ربط الموعد بقفل)، لكنها لا
 * تستطيع أن تعرف كم يساوي الكشف عند هذا الطبيب، ولا أن الساعة 03:00 فجراً
 * ليست ضمن دوامه. عميل معدَّل كان يكتب `price: 1` ويحجز خارج أوقات العمل.
 *
 * الآن العميل يرسل **طلباً**: أي طبيب، أي يوم، أي ساعة، ولماذا. وكل ما عدا
 * ذلك يستخرجه الخادم من Firestore.
 *
 * ## ما لم يتغيّر عمداً
 *
 * - **المعاملة الذرّية كما هي**: قفل الخانة والموعد يُكتبان معاً أو لا يُكتب
 *   أيٌّ منهما. هذا هو ضمان عدم الحجز المزدوج ولم يُمسّ.
 * - **شكل المستندات كما هو**: نفس أسماء الحقول ونفس صيغ المعرّفات، فالمواعيد
 *   القديمة تبقى مقروءة وكل الشاشات تعمل بلا تعديل.
 * - **توليد الخانات مطابق للواجهة حرفياً**: أي اختلاف هنا يعني أن التطبيق
 *   يعرض وقتاً ثم يرفضه الخادم.
 */

const CAIRO_TZ = 'Africa/Cairo';

/** أبعد يوم يُقبل الحجز فيه — مطابق لـ `lastDate` في منتقي التاريخ. */
const BOOKING_HORIZON_DAYS = 90;

/** الحد الأقصى لنص سبب الزيارة. */
const MAX_REASON_LENGTH = 500;

/**
 * الخانات الافتراضية حين يتعذّر تحليل `workingHours`.
 * منقولة حرفياً من `patient_booking_screen.dart` — لا تغيّرها هنا وحدها.
 */
const DEFAULT_SLOTS = [
  '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
  '14:00', '14:30', '15:00', '15:30', '16:00', '16:30',
];

/** الحالات التي تشغل خانة — مطابقة لـ `AppointmentStatus.occupying`. */
const OCCUPYING_STATUSES = new Set([
  'booked', 'scheduled', 'upcoming', 'pending', 'confirmed',
  'completed', 'done', 'pendingconfirmation',
]);

/** الحالات التي تُعدّ موعداً قائماً — مطابقة لـ `AppointmentStatus.isActive`. */
const ACTIVE_STATUSES = new Set([
  'booked', 'scheduled', 'upcoming', 'pending', 'confirmed',
]);

/**
 * خطأ حجز بسبب معروف.
 *
 * `reason` رمز ثابت يفهمه التطبيق ويترجمه لرسالة عربية، و`code` هو رمز
 * HttpsError القياسي. الرسالة هنا للسجلّات وللعرض، ولا تكشف بيانات مستخدم آخر.
 */
class BookingError extends Error {
  constructor(reason, code, message) {
    super(message);
    this.name = 'BookingError';
    this.reason = reason;
    this.code = code;
  }
}

const fail = (reason, code, message) => {
  throw new BookingError(reason, code, message);
};

// ===================== الوقت والتاريخ =====================

const _dateFmt = new Intl.DateTimeFormat('en-CA', {
  timeZone: CAIRO_TZ, year: 'numeric', month: '2-digit', day: '2-digit',
});
const _timeFmt = new Intl.DateTimeFormat('en-GB', {
  timeZone: CAIRO_TZ, hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
});

/**
 * اللحظة الحالية بتوقيت القاهرة.
 *
 * الدوال السحابية تعمل بتوقيت UTC، والعيادة تعمل بتوقيت مصر. المقارنة
 * بـ `new Date()` مباشرة كانت ستعتبر موعد الساعة 09:00 صباحاً «ماضياً» حتى
 * الساعة 11:00 بتوقيت القاهرة صيفاً. المقارنة تتم كنصوص `yyyy-MM-dd HH:mm`
 * فتتجنّب حساب الإزاحة يدوياً وتتعامل مع التوقيت الصيفي تلقائياً.
 */
function nowInCairo(now = new Date()) {
  return { date: _dateFmt.format(now), time: _timeFmt.format(now) };
}

/** اسم اليوم بالعربية — مطابق لـ `DateFormat('EEEE', 'ar')` في Dart. */
function arabicWeekday(dateStr) {
  const at = new Date(`${dateStr}T12:00:00Z`);
  return new Intl.DateTimeFormat('ar', {
    weekday: 'long', timeZone: 'UTC',
  }).format(at);
}

/** فرق الأيام بين تاريخين بصيغة yyyy-MM-dd. */
function daysBetween(fromStr, toStr) {
  const from = Date.parse(`${fromStr}T00:00:00Z`);
  const to = Date.parse(`${toStr}T00:00:00Z`);
  return Math.round((to - from) / 86400000);
}

const isValidDateStr = (v) =>
  typeof v === 'string' &&
  /^\d{4}-\d{2}-\d{2}$/.test(v) &&
  !Number.isNaN(Date.parse(`${v}T00:00:00Z`)) &&
  _dateFmt.format(new Date(`${v}T12:00:00Z`)) === v;

const isValidTimeStr = (v) =>
  typeof v === 'string' &&
  /^([01]\d|2[0-3]):[0-5]\d$/.test(v);

/**
 * تحليل وقت بصيغة `hh:mm AM/PM` أو `HH:mm`.
 * منقول من `parseTime` داخل `_getAvailableTimeSlots` في الواجهة.
 */
function parseClockTime(raw) {
  const clean = String(raw).trim().toUpperCase();
  const isPm = clean.includes('PM');
  const isAm = clean.includes('AM');
  const digits = clean.replace(/AM|PM/g, '').trim().split(':');

  let hour = parseInt(digits[0], 10);
  const minute = digits.length > 1 ? parseInt(digits[1], 10) : 0;
  if (Number.isNaN(hour) || Number.isNaN(minute)) return null;

  if (isPm && hour !== 12) hour += 12;
  else if (isAm && hour === 12) hour = 0;

  return { hour, minute };
}

const pad = (n) => String(n).padStart(2, '0');

// ===================== جدول الطبيب =====================

/** مدة الخانة: نظام المجموعات ساعة كاملة، والفردي مدة الكشف المعلنة. */
function slotDurationMinutes(doctor) {
  if ((doctor.bookingSystemType || 'Individual') === 'Grouped') return 60;
  const raw = Number(doctor.sessionDuration);
  return Number.isFinite(raw) && raw > 0 ? Math.floor(raw) : 30;
}

/** سعة الخانة كما يعلنها مستند الطبيب — نفس ما تفرضه `firestore.rules`. */
function slotCapacity(doctor) {
  if ((doctor.bookingSystemType || 'Individual') !== 'Grouped') return 1;
  const raw = Number(doctor.maxPatientsPerSlot);
  return Number.isFinite(raw) && raw > 0 ? Math.floor(raw) : 4;
}

/**
 * أوقات بداية الخانات عند طبيب في يوم عمل.
 *
 * **نسخة مطابقة** لـ `_getAvailableTimeSlots` في
 * `lib/presentation/screens/patient_booking_screen.dart`، بما في ذلك
 * السقوط إلى `DEFAULT_SLOTS` عند تعذّر التحليل. أي انحراف هنا يعني أن
 * التطبيق يعرض وقتاً ثم يرفضه الخادم عند التأكيد.
 */
function generateSlotTimes(doctor) {
  const duration = slotDurationMinutes(doctor);
  const workingHours = doctor.workingHours || '09:00 AM - 05:00 PM';

  const parts = String(workingHours).split('-');
  if (parts.length !== 2) return DEFAULT_SLOTS;

  const start = parseClockTime(parts[0]);
  const end = parseClockTime(parts[1]);
  if (!start || !end) return DEFAULT_SLOTS;

  let cursor = start.hour * 60 + start.minute;
  let endMinutes = end.hour * 60 + end.minute;
  // دوام يمتد بعد منتصف الليل.
  if (endMinutes <= cursor) endMinutes += 24 * 60;

  const slots = [];
  while (cursor < endMinutes) {
    const h = Math.floor(cursor / 60) % 24;
    slots.push(`${pad(h)}:${pad(cursor % 60)}`);
    cursor += duration;
  }

  return slots.length ? slots : DEFAULT_SLOTS;
}

/**
 * هل هذا اليوم يوم عمل عند الطبيب؟
 *
 * مفاتيح `workingDays` نصوص مثل `'السبت (Saturday)'`، والمطابقة تتم باحتواء
 * اسم اليوم بالعربية — وهو ما تفعله الواجهة حرفياً. الافتراضي عند عدم وجود
 * مفتاح مطابق هو **يوم عمل**، مطابقةً للواجهة أيضاً: أي اختلاف في هذا
 * الافتراض يعني رفض الخادم لما عرضته الواجهة.
 *
 * (هشاشة المطابقة بنص لغوي مسجَّلة كدين تقني — العلاج نقل الجدول إلى بنية
 * مفاتيحها ثابتة، وهو تغيير بيانات خارج نطاق هذه المرحلة.)
 */
function isWorkingDay(doctor, dateStr) {
  const workingDays = doctor.workingDays;
  if (!workingDays || typeof workingDays !== 'object') return true;

  const dayName = arabicWeekday(dateStr);
  for (const [key, value] of Object.entries(workingDays)) {
    if (String(key).includes(dayName)) return value === true;
  }
  return true;
}

// ===================== المعرّفات =====================

/** مطابق لـ `SlotId.forSlot` في `lib/core/utils/slot_id.dart`. */
const slotIdFor = (doctorId, date, time) =>
  `${doctorId}_${date}_${time.replace(':', '-')}`;

/** مطابق لـ `SlotId.forAppointment`. */
const appointmentIdFor = (slotId, patientId) => `${slotId}__${patientId}`;

// ===================== مدخلات المريض =====================

/**
 * سبب الزيارة — النص الحر الوحيد الذي يقبله الخادم من المريض.
 *
 * يُقصّ ويُحدّ طوله، ولا يُستخدم في أي مسار قرار. بقية حقول المستند يكتبها
 * الخادم، فلا يستطيع الطلب أن يتحوّل إلى تحديث Firestore عشوائي.
 */
function normalizeReason(raw) {
  if (raw === undefined || raw === null) return '';
  if (typeof raw !== 'string') {
    fail('invalid-argument', 'invalid-argument', 'سبب الزيارة يجب أن يكون نصاً');
  }
  const trimmed = raw.trim().replace(/\s+/g, ' ');
  if (trimmed.length > MAX_REASON_LENGTH) {
    fail('invalid-argument', 'invalid-argument',
      `سبب الزيارة أطول من ${MAX_REASON_LENGTH} حرفاً`);
  }
  return trimmed;
}

// ===================== الحجز =====================

/**
 * تنفيذ حجز كامل: تحقّق من الطبيب والجدول والخانة، ثم كتابة ذرّية.
 *
 * @param {object}  args
 * @param {FirebaseFirestore.Firestore} args.db
 * @param {string}  args.uid   معرّف صاحب الطلب من رمز المصادقة — لا من الطلب.
 * @param {object}  args.data  حمولة الطلب من العميل.
 * @param {Date}    [args.now] لحقن الوقت في الاختبارات.
 */
async function bookAppointmentCore({ db, uid, data, now = new Date() }) {
  if (!uid || typeof uid !== 'string') {
    fail('unauthenticated', 'unauthenticated', 'يجب تسجيل الدخول أولاً');
  }

  const payload = data && typeof data === 'object' ? data : {};

  // ---------- 1. مدخلات الطلب ----------

  const doctorId = payload.doctorId;
  if (typeof doctorId !== 'string' || !doctorId.trim()) {
    fail('invalid-argument', 'invalid-argument', 'معرّف الطبيب مطلوب');
  }
  // معرّف الطبيب يدخل في معرّف المستند، فلا يجوز أن يحمل محارف مسار.
  // نفس المحارف التي تنتجها Firebase Auth، لا أكثر.
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(doctorId)) {
    fail('invalid-argument', 'invalid-argument', 'معرّف الطبيب غير صالح');
  }

  const date = payload.date;
  if (!isValidDateStr(date)) {
    fail('invalid-argument', 'invalid-argument', 'التاريخ غير صالح');
  }

  const time = payload.time;
  if (!isValidTimeStr(time)) {
    fail('invalid-argument', 'invalid-argument', 'الوقت غير صالح');
  }

  // `patientId` يُقبل للتوافق مع الإصدارات القديمة، لكنه ليس حقيقة: الحجز
  // دائماً باسم صاحب رمز المصادقة.
  if (payload.patientId !== undefined && payload.patientId !== uid) {
    fail('permission-denied', 'permission-denied',
      'لا يمكن الحجز نيابة عن مستخدم آخر');
  }

  const reason = normalizeReason(payload.reason);

  // ---------- 2. الطبيب ----------

  const doctorSnap = await db.collection('users').doc(doctorId).get();
  if (!doctorSnap.exists) {
    fail('doctor-not-found', 'not-found', 'هذا الطبيب غير موجود');
  }
  const doctor = doctorSnap.data();

  if (doctor.role !== 'doctor') {
    fail('doctor-not-found', 'not-found', 'هذا الطبيب غير موجود');
  }
  if (doctor.isVerified !== true) {
    fail('doctor-not-verified', 'failed-precondition',
      'هذا الطبيب غير متاح للحجز حالياً');
  }
  if (doctor.disabled === true || doctor.active === false) {
    fail('doctor-disabled', 'failed-precondition',
      'هذا الطبيب غير متاح للحجز حالياً');
  }

  // ---------- 3. الجدول ----------

  const cairoNow = nowInCairo(now);

  if (date < cairoNow.date || (date === cairoNow.date && time <= cairoNow.time)) {
    fail('slot-expired', 'failed-precondition',
      'لا يمكن الحجز في وقت مضى، اختر موعداً لاحقاً');
  }
  if (daysBetween(cairoNow.date, date) > BOOKING_HORIZON_DAYS) {
    fail('slot-out-of-range', 'out-of-range',
      `الحجز متاح حتى ${BOOKING_HORIZON_DAYS} يوماً من اليوم`);
  }
  if (!isWorkingDay(doctor, date)) {
    fail('doctor-not-working', 'failed-precondition',
      'الطبيب لا يعمل في هذا اليوم');
  }
  if (!generateSlotTimes(doctor).includes(time)) {
    // الحماية التي لم تكن موجودة إطلاقاً: لا شيء كان يمنع حجز 03:00 فجراً.
    fail('slot-not-found', 'not-found', 'هذا الوقت ليس ضمن مواعيد الطبيب');
  }

  // ---------- 4. القيم التي يقرّرها الخادم ----------

  const capacity = slotCapacity(doctor);
  const duration = slotDurationMinutes(doctor);
  const price = Number.isFinite(Number(doctor.price)) ? Number(doctor.price) : 0;
  const slotId = slotIdFor(doctorId, date, time);
  const appointmentId = appointmentIdFor(slotId, uid);

  const startMinutes =
    parseInt(time.slice(0, 2), 10) * 60 + parseInt(time.slice(3), 10);
  const endMinutes = startMinutes + duration;
  const endTime = `${pad(Math.floor(endMinutes / 60) % 24)}:${pad(endMinutes % 60)}`;

  // بيانات المريض من مستنده هو، لا مما يرسله العميل.
  const patientSnap = await db.collection('users').doc(uid).get();
  if (!patientSnap.exists) {
    fail('patient-not-found', 'failed-precondition',
      'لم يكتمل ملفك الشخصي بعد');
  }
  const patient = patientSnap.data();

  // ---------- 5. المعاملة الذرّية ----------

  const slotRef = db.collection('slots').doc(slotId);
  const appointmentRef = db.collection('appointments').doc(appointmentId);
  const sameDayQuery = db.collection('appointments')
    .where('doctorId', '==', doctorId)
    .where('appointmentDate', '==', date);

  const outcome = await db.runTransaction(async (tx) => {
    const [slotSnap, existingSnap, sameDaySnap] = await Promise.all([
      tx.get(slotRef),
      tx.get(appointmentRef),
      tx.get(sameDayQuery),
    ]);

    // 5.أ — طلب مكرَّر.
    //
    // معرّف الموعد دالة في (الطبيب، اليوم، الوقت، المريض)، فإعادة إرسال نفس
    // الطلب — ضغطة مزدوجة أو إعادة محاولة من الشبكة — تصل إلى نفس المستند.
    // نُرجع النجاح نفسه بدل إنشاء حجز ثانٍ أو إظهار خطأ لا ذنب للمستخدم فيه.
    if (existingSnap.exists) {
      const status = String(existingSnap.data().status || '').toLowerCase();
      if (ACTIVE_STATUSES.has(status)) {
        return { appointmentId, duplicate: true };
      }
      // موعد ملغى سابقاً في نفس الخانة — يُعاد حجزه بالمسار الطبيعي أدناه.
    }

    // 5.ب — المواعيد القائمة في هذا اليوم عند هذا الطبيب.
    //
    // استعلام واحد يخدم فحصين، ويغطّي المواعيد القديمة التي أُنشئت قبل نظام
    // الأقفال فلا تملك مستند خانة يحميها.
    let sameSlotCount = 0;
    for (const doc of sameDaySnap.docs) {
      if (doc.id === appointmentId) continue;
      const d = doc.data();
      const status = String(d.status || 'Booked').toLowerCase().replace(/\s/g, '');

      if (d.patientId === uid && ACTIVE_STATUSES.has(status)) {
        fail('already-booked-same-day', 'already-exists',
          'لديك موعد محجوز مسبقاً عند هذا الطبيب في نفس اليوم');
      }

      if (!OCCUPYING_STATUSES.has(status)) continue;
      const raw = d.startTime || d.time;
      if (raw && String(raw).slice(0, 5) === time) sameSlotCount++;
    }

    // 5.ج — قفل الخانة.
    if (!slotSnap.exists) {
      if (sameSlotCount >= capacity) {
        fail('slot-unavailable', 'aborted',
          'للأسف تم حجز هذا الموعد للتو، اختر وقتاً آخر');
      }
      tx.set(slotRef, {
        doctorId,
        appointmentDate: date,
        startTime: time,
        capacity,
        bookedCount: 1,
        patientIds: [uid],
        createdAt: new Date(),
        updatedAt: new Date(),
      });
    } else {
      const slot = slotSnap.data();

      if (slot.doctorId !== doctorId ||
          slot.appointmentDate !== date ||
          slot.startTime !== time) {
        // لا يحدث في الاستخدام الطبيعي لأن المعرّف مشتق من الحقول نفسها.
        fail('slot-conflict', 'failed-precondition',
          'تعذّر إتمام الحجز، حاول مرة أخرى');
      }
      if (slot.closed === true || slot.cancelled === true) {
        fail('slot-closed', 'failed-precondition',
          'هذا الموعد مغلق حالياً');
      }

      const patientIds = Array.isArray(slot.patientIds) ? slot.patientIds : [];
      if (patientIds.includes(uid)) {
        // القفل يحمل المريض بلا موعد قائم — بقايا حالة غير مكتملة.
        return { appointmentId, duplicate: true };
      }

      // السعة المسجَّلة وقت إنشاء الخانة هي المرجع، حتى لا يُفسد تغيير
      // إعدادات الطبيب حجوزات قائمة.
      const recorded = Number(slot.capacity);
      const effectiveCapacity =
        Number.isFinite(recorded) && recorded > 0 ? recorded : capacity;
      const booked = Number(slot.bookedCount) || 0;

      if (booked >= effectiveCapacity || sameSlotCount >= effectiveCapacity) {
        fail('slot-unavailable', 'aborted',
          'للأسف تم حجز هذا الموعد للتو، اختر وقتاً آخر');
      }

      tx.update(slotRef, {
        bookedCount: booked + 1,
        patientIds: [...patientIds, uid],
        updatedAt: new Date(),
      });
    }

    // 5.د — الموعد. كل حقل هنا من مصدر موثوق على الخادم.
    tx.set(appointmentRef, {
      doctorId,
      patientId: uid,
      slotId,
      appointmentDate: date,
      startTime: time,
      endTime,
      duration,
      status: 'Booked',
      price,
      reason,
      patientName: patient.name || '',
      patientPhone: patient.phone || '',
      doctorName: doctor.name || '',
      doctorNameEn: doctor.nameEn || '',
      doctorSpecialization: doctor.specialization || '',
      clinicLocation: doctor.clinicLocation || '',
      clinicPhone: doctor.phone || '',
      bookedVia: 'callable',
      createdAt: new Date(),
    });

    return { appointmentId, duplicate: false };
  });

  return {
    ...outcome,
    slotId,
    doctorId,
    appointmentDate: date,
    startTime: time,
    endTime,
    price,
    status: 'Booked',
  };
}

module.exports = {
  bookAppointmentCore,
  BookingError,
  // مُصدَّرة للاختبارات ولإعادة الاستخدام:
  generateSlotTimes,
  isWorkingDay,
  slotCapacity,
  slotDurationMinutes,
  normalizeReason,
  nowInCairo,
  arabicWeekday,
  slotIdFor,
  appointmentIdFor,
  BOOKING_HORIZON_DAYS,
  DEFAULT_SLOTS,
};
