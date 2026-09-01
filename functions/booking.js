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
 *
 * ## المرحلة 1ب
 *
 * منطق الجدول (أيام العمل، فترات العمل، الاستراحات، الاستثناءات، السعة)
 * انتقل إلى `availability.js` — «مصدر الحقيقة الوحيد» الذي يشاركه الحجز مع
 * `getAvailability` و`lifecycle.js` (الإلغاء وإعادة الجدولة). هذا الملف
 * يستورده بدل أن يعيد كتابته؛ الدوال المُصدَّرة من هنا لأغراض التوافق
 * (`generateSlotTimes`, `isWorkingDay`, ...) هي نفس الدوال هناك بلا تغيير
 * في السلوك.
 */

const {
  AppError: BookingError,
  fail,
  isValidDateStr,
  isValidTimeStr,
  generateSlotTimes,
  isWorkingDay,
  slotCapacity,
  slotDurationMinutes,
  slotIdFor,
  appointmentIdFor,
  nowForDoctor,
  nowInCairo,
  arabicWeekday,
  fetchBookableDoctor,
  assertSlotWithinSchedule,
  analyzeSameDay,
  planSlotReservation,
  ACTIVE_STATUSES,
  BOOKING_HORIZON_DAYS,
  DEFAULT_SLOTS,
} = require('./availability');
const {
  NOTIFICATION_TYPES,
  queueNotification,
  deliverPendingPush,
} = require('./notifications');
const admin = require('firebase-admin');

/** الحد الأقصى لنص سبب الزيارة. */
const MAX_REASON_LENGTH = 500;

const pad = (n) => String(n).padStart(2, '0');

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
 * @param {import('firebase-admin').messaging.Messaging} [args.messaging]
 *   لحقن بديل وهمي في الاختبارات — راجع `notifications.js`.
 */
async function bookAppointmentCore({
  db, uid, data, now = new Date(), messaging = admin.messaging(),
}) {
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

  const doctor = await fetchBookableDoctor(db, doctorId);

  // ---------- 3. الجدول ----------

  const cairoNow = nowForDoctor(doctor, now);
  assertSlotWithinSchedule(doctor, date, time, cairoNow);

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
    const { sameSlotCount, duplicateSameDay } = analyzeSameDay(sameDaySnap, {
      uid, time, excludeIds: [appointmentId],
    });
    if (duplicateSameDay) {
      fail('already-booked-same-day', 'already-exists',
        'لديك موعد محجوز مسبقاً عند هذا الطبيب في نفس اليوم');
    }

    // 5.ج — قفل الخانة.
    const plan = planSlotReservation({
      slotSnap, doctorId, date, time, uid, capacity, sameSlotCount,
    });
    if (plan.action === 'create') {
      tx.set(slotRef, { ...plan.data, createdAt: new Date(), updatedAt: new Date() });
    } else if (plan.action === 'update') {
      tx.update(slotRef, { ...plan.data, updatedAt: new Date() });
    } else if (plan.alreadyIn) {
      // القفل يحمل المريض بلا موعد قائم — بقايا حالة غير مكتملة.
      return { appointmentId, duplicate: true };
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

    // 5.هـ — إشعارات الحدث. داخل نفس المعاملة فتصبح in-app فوراً بذرّية
    // الحجز نفسه — لا إشعار بلا حجز ناجح فعلاً. تسليم Push بعدها بعيداً عن
    // المعاملة (راجع `notifications.js`).
    const notificationCtx = {
      doctorName: doctor.name, patientName: patient.name, date, startTime: time,
    };
    const notificationRefs = [
      queueNotification(tx, db, {
        recipientId: uid, recipientRole: 'patient',
        type: NOTIFICATION_TYPES.BOOKING_CONFIRMED,
        appointmentId, metadata: notificationCtx,
      }),
      queueNotification(tx, db, {
        recipientId: doctorId, recipientRole: 'doctor',
        type: NOTIFICATION_TYPES.NEW_APPOINTMENT,
        appointmentId, metadata: notificationCtx,
      }),
    ];

    return { appointmentId, duplicate: false, notificationRefs };
  });

  if (!outcome.duplicate && outcome.notificationRefs) {
    await deliverPendingPush({ db, messaging, refs: outcome.notificationRefs });
  }

  return {
    appointmentId: outcome.appointmentId,
    duplicate: outcome.duplicate,
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
  // مُصدَّرة للاختبارات ولإعادة الاستخدام — من `availability.js` فعلياً:
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
