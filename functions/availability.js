/**
 * محرّك التوفّر — مصدر الحقيقة الوحيد لكل ما يخص جدول الطبيب.
 *
 * ## لماذا هذا الملف موجود
 *
 * قبل المرحلة 1ب كانت منطق «هل هذا يوم عمل؟» و«ما هي خانات هذا اليوم؟»
 * مكرّرة في مكانين مستقلّين: `patient_booking_screen.dart` (لعرضها) و
 * `functions/booking.js` (للتحقق منها وقت الحجز). أي تعديل في أحدهما دون
 * الآخر يعني أن الواجهة تعرض خانة يرفضها الخادم، أو العكس.
 *
 * هذا الملف هو **الطرف الوحيد** الذي يقرّر التوفّر على الخادم. `booking.js`
 * (الحجز)، و`lifecycle.js` (الإلغاء وإعادة الجدولة)، و`getAvailability`
 * (استعلام العرض) الثلاثة يستدعون نفس الدوال هنا — لا يعيد أيٌّ منها كتابة
 * الحساب. القرار النهائي يبقى دائماً لمعاملة الحجز نفسها (`slots/{slotId}`
 * تحت `runTransaction`)، لأن استجابة `getAvailability` قد تصبح قديمة قبل
 * لحظة الحجز الفعلية بجزء من الثانية.
 *
 * ## التوافق مع البيانات القديمة
 *
 * كل حقل جديد هنا (`workingPeriods`, `breaks`, `closedDates`, `vacations`,
 * `dateOverrides`, `workingDaysByWeekday`, `timezone`) **اختياري**. طبيب
 * بلا أيٍّ منها يسلك تماماً كما كان يسلك قبل هذه المرحلة — هذا مقصود ومُختبر:
 * `generateSlotTimes(doctor)` بلا تاريخ تُنتج نفس الخانات حرفياً، لأن أياً من
 * الحقول الجديدة لا وجود له في مستند طبيب لم يُحدَّث. لا هجرة بيانات هنا.
 */

// ===================== المنطقة الزمنية =====================

/** المنطقة الافتراضية حين لا يحمل مستند الطبيب حقل `timezone`. */
const DEFAULT_TIMEZONE = 'Africa/Cairo';

/**
 * منطقة عمل هذا الطبيب.
 *
 * التطبيق يستهدف مصر حالياً، لكن قفل `Africa/Cairo` داخل كل دالة يجعل دعم
 * عيادة في منطقة زمنية أخرى لاحقاً هجرة كبيرة. القراءة هنا من حقل اختياري
 * على مستند الطبيب، فإضافته لاحقاً لا تحتاج أكثر من كتابة الحقل.
 */
function clinicTimezone(doctor) {
  const tz = doctor && typeof doctor.timezone === 'string' ? doctor.timezone.trim() : '';
  return tz || DEFAULT_TIMEZONE;
}

const _dateFmtCache = new Map();
const _timeFmtCache = new Map();

function _dateFmt(tz) {
  if (!_dateFmtCache.has(tz)) {
    _dateFmtCache.set(tz, new Intl.DateTimeFormat('en-CA', {
      timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit',
    }));
  }
  return _dateFmtCache.get(tz);
}

function _timeFmt(tz) {
  if (!_timeFmtCache.has(tz)) {
    _timeFmtCache.set(tz, new Intl.DateTimeFormat('en-GB', {
      timeZone: tz, hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
    }));
  }
  return _timeFmtCache.get(tz);
}

/** اللحظة الحالية `{date, time}` بمنطقة زمنية معيّنة. */
function nowInZone(tz, now = new Date()) {
  return { date: _dateFmt(tz).format(now), time: _timeFmt(tz).format(now) };
}

/** اللحظة الحالية بتوقيت القاهرة — الاسم القديم، محفوظ للتوافق. */
function nowInCairo(now = new Date()) {
  return nowInZone(DEFAULT_TIMEZONE, now);
}

/** اللحظة الحالية بمنطقة عمل هذا الطبيب تحديداً. */
function nowForDoctor(doctor, now = new Date()) {
  return nowInZone(clinicTimezone(doctor), now);
}

/** اسم اليوم بالعربية — مطابق لـ `DateFormat('EEEE', 'ar')` في Dart. */
function arabicWeekday(dateStr) {
  const at = new Date(`${dateStr}T12:00:00Z`);
  return new Intl.DateTimeFormat('ar', {
    weekday: 'long', timeZone: 'UTC',
  }).format(at);
}

/** ترتيب اليوم في الأسبوع (0 = الأحد ... 6 = السبت)، بمعزل عن التوقيت. */
function weekdayIndex(dateStr) {
  return new Date(`${dateStr}T12:00:00Z`).getUTCDay();
}

const ENGLISH_WEEKDAY_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

/** فرق الأيام بين تاريخين بصيغة yyyy-MM-dd. */
function daysBetween(fromStr, toStr) {
  const from = Date.parse(`${fromStr}T00:00:00Z`);
  const to = Date.parse(`${toStr}T00:00:00Z`);
  return Math.round((to - from) / 86400000);
}

/**
 * فرق الدقائق بين لحظتَي `(date, time)`، بشرط أن يكونا **بنفس المنطقة
 * الزمنية** (كلتاهما من `nowForDoctor` لنفس الطبيب، مثلاً).
 *
 * الحيلة: تحليل كلا الطرفين كأنهما UTC يُلغي إزاحة المنطقة الزمنية
 * الحقيقية جبرياً من الفرق، فتصح النتيجة بأي منطقة زمنية دون حساب الإزاحة
 * يدوياً أو التعامل مع التوقيت الصيفي.
 */
function minutesBetween(dateA, timeA, dateB, timeB) {
  const a = Date.parse(`${dateA}T${timeA}:00Z`);
  const b = Date.parse(`${dateB}T${timeB}:00Z`);
  return Math.round((b - a) / 60000);
}

const isValidDateStr = (v) =>
  typeof v === 'string' &&
  /^\d{4}-\d{2}-\d{2}$/.test(v) &&
  !Number.isNaN(Date.parse(`${v}T00:00:00Z`)) &&
  _dateFmt('UTC').format(new Date(`${v}T12:00:00Z`)) === v;

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

// ===================== خطأ عام موحّد =====================

/**
 * خطأ نطاق بسبب معروف — يستخدمه الحجز والإلغاء وإعادة الجدولة والتوفّر
 * جميعاً، حتى تُترجَم كل الأسباب بنفس الآلية في `functions/index.js`.
 */
class AppError extends Error {
  constructor(reason, code, message) {
    super(message);
    this.name = 'AppError';
    this.reason = reason;
    this.code = code;
  }
}

const fail = (reason, code, message) => {
  throw new AppError(reason, code, message);
};

// ===================== حالة الموعد =====================

/** الحالات التي تشغل خانة — مطابقة لـ `AppointmentStatus.occupying`. */
const OCCUPYING_STATUSES = new Set([
  'booked', 'scheduled', 'upcoming', 'pending', 'confirmed',
  'completed', 'done', 'pendingconfirmation',
]);

/** الحالات التي تُعدّ موعداً قائماً — مطابقة لـ `AppointmentStatus.isActive`. */
const ACTIVE_STATUSES = new Set([
  'booked', 'scheduled', 'upcoming', 'pending', 'confirmed',
]);

/** الحالات التي يمكن للمريض إلغاءها أو إعادة جدولتها — مطابقة لـ `isCancellable`. */
const CANCELLABLE_STATUSES = new Set(['booked', 'scheduled', 'upcoming', 'pending', 'confirmed']);

/** توحيد قيمة الحالة القادمة من Firestore لمقارنتها بالمجموعات أعلاه. */
const normalizeStatusKey = (raw) =>
  String(raw === undefined || raw === null ? 'Booked' : raw)
    .toLowerCase()
    .replace(/\s/g, '');

// ===================== جدول الطبيب: أيام العمل والاستثناءات =====================

/**
 * تجاوز خاص بتاريخ محدّد على مستند الطبيب.
 *
 * `doctor.dateOverrides` خريطة اختيارية `{ 'yyyy-MM-dd': {...} }` تغطي
 * إجازة مفاجئة، عطلة رسمية، أو تعديل ساعات يوم واحد — دون لمس الجدول
 * المتكرر. لا حاجة لواجهة إدارية بعد؛ الحقل يُقرأ إن وُجد ويُتجاهل إن غاب.
 */
function dateOverrideFor(doctor, dateStr) {
  if (!doctor || !dateStr) return null;
  const overrides = doctor.dateOverrides;
  if (!overrides || typeof overrides !== 'object') return null;
  const o = overrides[dateStr];
  return o && typeof o === 'object' ? o : null;
}

/**
 * هل هذا التاريخ مُغلَق كلياً؟ (إجازة، عطلة رسمية، إغلاق طارئ).
 *
 * ثلاثة مصادر ممكنة، أيٌّ منها كافٍ للإغلاق:
 *   - `dateOverrides[date].closed === true` — إغلاق طارئ ليوم واحد.
 *   - `closedDates` — قائمة تواريخ مفردة (عطلات رسمية).
 *   - `vacations` — مدايات إجازة `{start, end}` شاملة الطرفين.
 */
function isClosedDate(doctor, dateStr) {
  const override = dateOverrideFor(doctor, dateStr);
  if (override && override.closed === true) return true;

  const closedDates = Array.isArray(doctor.closedDates) ? doctor.closedDates : [];
  if (closedDates.includes(dateStr)) return true;

  const vacations = Array.isArray(doctor.vacations) ? doctor.vacations : [];
  for (const v of vacations) {
    if (v && typeof v === 'object' &&
        typeof v.start === 'string' && typeof v.end === 'string' &&
        dateStr >= v.start && dateStr <= v.end) {
      return true;
    }
  }
  return false;
}

/**
 * مطابقة اليوم بأسماء `workingDays` العربية القديمة (`'السبت (Saturday)'`).
 *
 * منقولة حرفياً من الواجهة والنسخة الأصلية من `booking.js`: المطابقة
 * باحتواء اسم اليوم بالعربية داخل المفتاح، والافتراض عند غياب مفتاح مطابق
 * هو **يوم عمل**. هشاشة المطابقة بنص لغوي معروفة، والعلاج بلا هجرة بيانات
 * هو `workingDaysByWeekday` أدناه — قارئ توافقي يُفضَّل عليها إن وُجد.
 */
function legacyWorkingDayFlag(doctor, dateStr) {
  const workingDays = doctor.workingDays;
  if (!workingDays || typeof workingDays !== 'object') return true;

  const dayName = arabicWeekday(dateStr);
  for (const [key, value] of Object.entries(workingDays)) {
    if (String(key).includes(dayName)) return value === true;
  }
  return true;
}

/**
 * التمثيل الداخلي الموحَّد لأيام العمل — مفاتيحه ثابتة
 * (`sun`..`sat`) بمعزل عن اللغة أو ترتيب الكتابة.
 *
 * قارئ توافقي: يبني هذا التمثيل من `workingDaysByWeekday` إن كان الطبيب
 * قد اعتمد الصيغة الجديدة، وإلا من `workingDays` العربية القديمة عبر
 * `legacyWorkingDayFlag` لكل يوم. لا يُكتب شيء في قاعدة البيانات — تحويل
 * في الذاكرة فقط، عند الحاجة إليه.
 */
function normalizedWorkingDays(doctor, referenceDateStr = '2030-01-05') {
  const canonical = doctor.workingDaysByWeekday;
  const result = {};
  // 2030-01-05 سبت، فنبني عليه أسبوعاً مرجعياً كاملاً (سبت..جمعة) بلا
  // اعتماد على تاريخ استدعاء الدالة.
  const base = new Date(`${referenceDateStr}T12:00:00Z`);
  for (let i = 0; i < 7; i++) {
    const d = new Date(base.getTime() + i * 86400000);
    const iso = _dateFmt('UTC').format(d);
    const key = ENGLISH_WEEKDAY_KEYS[weekdayIndex(iso)];
    if (canonical && typeof canonical === 'object' && key in canonical) {
      result[key] = canonical[key] === true;
    } else {
      result[key] = legacyWorkingDayFlag(doctor, iso);
    }
  }
  return result;
}

/** هل يعمل هذا الطبيب في هذا التاريخ؟ (يوم الأسبوع + الاستثناءات). */
function isWorkingDay(doctor, dateStr) {
  if (isClosedDate(doctor, dateStr)) return false;

  const canonical = doctor.workingDaysByWeekday;
  if (canonical && typeof canonical === 'object') {
    const key = ENGLISH_WEEKDAY_KEYS[weekdayIndex(dateStr)];
    if (key in canonical) return canonical[key] === true;
  }
  return legacyWorkingDayFlag(doctor, dateStr);
}

// ===================== جدول الطبيب: مدة الخانة والسعة =====================

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

// ===================== جدول الطبيب: فترات العمل والاستراحات =====================

/**
 * الخانات الافتراضية حين يتعذّر تحليل `workingHours`.
 * منقولة حرفياً من `patient_booking_screen.dart` — لا تغيّرها هنا وحدها.
 */
const DEFAULT_SLOTS = [
  '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
  '14:00', '14:30', '15:00', '15:30', '16:00', '16:30',
];

/** يحوّل مدى `'HH:mm AM/PM - HH:mm AM/PM'` إلى دقائق، أو `null` إن تعذّر. */
function parseLegacyRangeToMinutes(rangeStr) {
  const parts = String(rangeStr).split('-');
  if (parts.length !== 2) return null;
  const start = parseClockTime(parts[0]);
  const end = parseClockTime(parts[1]);
  if (!start || !end) return null;

  const startMinutes = start.hour * 60 + start.minute;
  let endMinutes = end.hour * 60 + end.minute;
  if (endMinutes <= startMinutes) endMinutes += 24 * 60; // دوام يمتد بعد منتصف الليل.
  return { startMinutes, endMinutes };
}

/** يحوّل فترة `{start, end}` (كلاهما `HH:mm`) إلى دقائق، أو `null` إن تعذّر. */
function parsePeriodToMinutes(period) {
  if (!period || typeof period !== 'object') return null;
  const start = parseClockTime(period.start);
  const end = parseClockTime(period.end);
  if (!start || !end) return null;

  const startMinutes = start.hour * 60 + start.minute;
  let endMinutes = end.hour * 60 + end.minute;
  if (endMinutes <= startMinutes) endMinutes += 24 * 60;
  return { startMinutes, endMinutes };
}

/**
 * فترة عمل `{startMinutes, endMinutes}` ناقص فترات استراحة، وقد تُنتج
 * أكثر من فترة واحدة.
 *
 * يدعم أكثر من استراحة في اليوم، وتُحاذى كل استراحة تلقائياً مع دورة
 * الفترة (لدعم دوام يمتد بعد منتصف الليل).
 */
function subtractBreaks(period, breaksList) {
  let segments = [period];
  for (const b of breaksList) {
    const bs = parseClockTime(b && b.start);
    const be = parseClockTime(b && b.end);
    if (!bs || !be) continue;

    let breakStart = bs.hour * 60 + bs.minute;
    let breakEnd = be.hour * 60 + be.minute;
    if (breakEnd <= breakStart) breakEnd += 24 * 60;

    const next = [];
    for (const seg of segments) {
      let s = breakStart;
      let e = breakEnd;
      while (e <= seg.startMinutes) { s += 24 * 60; e += 24 * 60; }

      if (s >= seg.endMinutes || e <= seg.startMinutes) {
        next.push(seg); // لا تقاطع.
        continue;
      }
      if (s > seg.startMinutes) {
        next.push({ startMinutes: seg.startMinutes, endMinutes: Math.min(s, seg.endMinutes) });
      }
      if (e < seg.endMinutes) {
        next.push({ startMinutes: Math.max(e, seg.startMinutes), endMinutes: seg.endMinutes });
      }
    }
    segments = next;
  }
  return segments.filter((s) => s.endMinutes > s.startMinutes);
}

/** فترات العمل الصريحة لهذا التاريخ إن وُجدت (تجاوز التاريخ ثم الحقل العام)، وإلا `null`. */
function effectiveWorkingPeriods(doctor, dateStr) {
  const override = dateOverrideFor(doctor, dateStr);
  if (override && Array.isArray(override.workingPeriods) && override.workingPeriods.length) {
    return override.workingPeriods;
  }
  if (Array.isArray(doctor.workingPeriods) && doctor.workingPeriods.length) {
    return doctor.workingPeriods;
  }
  return null;
}

/** نص `workingHours` الفعّال لهذا التاريخ (تجاوز التاريخ ثم الحقل العام). */
function effectiveWorkingHours(doctor, dateStr) {
  const override = dateOverrideFor(doctor, dateStr);
  if (override && typeof override.workingHours === 'string') return override.workingHours;
  return doctor.workingHours;
}

/** قائمة الاستراحات الفعّالة لهذا التاريخ (تجاوز التاريخ يستبدل القائمة العامة كلياً). */
function effectiveBreaks(doctor, dateStr) {
  const override = dateOverrideFor(doctor, dateStr);
  if (override && Array.isArray(override.breaks)) return override.breaks;
  return Array.isArray(doctor.breaks) ? doctor.breaks : [];
}

/**
 * أوقات بداية الخانات عند طبيب، في تاريخ معيّن أو بمعزل عن التاريخ.
 *
 * بلا `dateStr`: **نسخة مطابقة حرفياً** للسلوك الأصلي (قبل المرحلة 1ب) —
 * تحليل `workingHours` وحده، بلا استراحات ولا تجاوزات. هذا يحافظ على توافق
 * كل استدعاء قديم (`generateSlotTimes(doctor)` في اختبارات الحجز القائمة)
 * حرفاً بحرف.
 *
 * مع `dateStr`: تُضاف فترات العمل المتعددة (`workingPeriods`) أو الاستراحات
 * المستقطَعة من `workingHours`، وتجاوزات ذلك التاريخ تحديداً. طبيب بلا أيٍّ
 * من هذه الحقول يُنتج نفس النتيجة بالضبط سواء مُرِّر التاريخ أم لا.
 */
function generateSlotTimes(doctor, dateStr) {
  const duration = slotDurationMinutes(doctor);

  const explicitPeriods = effectiveWorkingPeriods(doctor, dateStr);
  let periods;
  if (explicitPeriods) {
    periods = explicitPeriods.map(parsePeriodToMinutes).filter(Boolean);
    if (!periods.length) return DEFAULT_SLOTS;
  } else {
    const workingHours = effectiveWorkingHours(doctor, dateStr) || '09:00 AM - 05:00 PM';
    const single = parseLegacyRangeToMinutes(workingHours);
    if (!single) return DEFAULT_SLOTS;
    periods = [single];
  }

  const breaks = effectiveBreaks(doctor, dateStr);
  if (breaks.length) {
    periods = periods.flatMap((p) => subtractBreaks(p, breaks));
  }

  periods = periods.slice().sort((a, b) => a.startMinutes - b.startMinutes);

  const seen = new Set();
  const slots = [];
  for (const { startMinutes, endMinutes } of periods) {
    let cursor = startMinutes;
    while (cursor < endMinutes) {
      const h = Math.floor(cursor / 60) % 24;
      const label = `${pad(h)}:${pad(cursor % 60)}`;
      if (!seen.has(label)) {
        seen.add(label);
        slots.push(label);
      }
      cursor += duration;
    }
  }

  if (!slots.length) return dateStr ? [] : DEFAULT_SLOTS;
  return slots;
}

// ===================== المعرّفات =====================

/** مطابق لـ `SlotId.forSlot` في `lib/core/utils/slot_id.dart`. */
const slotIdFor = (doctorId, date, time) =>
  `${doctorId}_${date}_${time.replace(':', '-')}`;

/** مطابق لـ `SlotId.forAppointment`. */
const appointmentIdFor = (slotId, patientId) => `${slotId}__${patientId}`;

// ===================== أفق الحجز =====================

/** أبعد يوم يُقبل الحجز فيه — مطابق لـ `lastDate` في منتقي التاريخ. */
const BOOKING_HORIZON_DAYS = 90;

// ===================== الطبيب القابل للحجز =====================

/**
 * يجلب مستند الطبيب ويتحقق من صلاحيته للحجز، أو يرمي `AppError` بسبب دقيق.
 * يستخدمها الحجز وإعادة الجدولة كلاهما — نفس الشروط بالضبط.
 */
async function fetchBookableDoctor(db, doctorId) {
  const snap = await db.collection('users').doc(doctorId).get();
  if (!snap.exists) {
    fail('doctor-not-found', 'not-found', 'هذا الطبيب غير موجود');
  }
  const doctor = snap.data();

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
  return doctor;
}

/**
 * يتحقق من أن `date`/`time` يقعان ضمن جدول الطبيب الفعلي ولم يفوتا بعد.
 * **القاعدة الحرجة**: هذه هي الدالة الوحيدة التي تقرّر «هل هذا الوقت
 * متاح؟» زمنياً وجدولياً — الحجز، `getAvailability`، وإعادة الجدولة
 * الثلاثة يستدعونها، فلا يختلف قرارهم أبداً.
 */
function assertSlotWithinSchedule(doctor, date, time, cairoNow) {
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
  if (!generateSlotTimes(doctor, date).includes(time)) {
    fail('slot-not-found', 'not-found', 'هذا الوقت ليس ضمن مواعيد الطبيب');
  }
}

// ===================== تحليل اليوم نفسه عند طبيب =====================

/**
 * يفحص كل مواعيد طبيب في يوم واحد لغرضين معاً:
 *   - `sameSlotCount`: كم مريضاً يشغل هذه الخانة تحديداً (يغطي المواعيد
 *     القديمة بلا مستند خانة).
 *   - `duplicateSameDay`: هل لهذا المريض موعد قائم آخر في نفس اليوم؟
 *
 * `excludeIds` تستثني معرّفات مواعيد بعينها من كلا الفحصين — لازمة لإعادة
 * الجدولة: الموعد القديم الذي يُنقَل الآن لا يُحتسَب تعارضاً مع نفسه.
 */
function analyzeSameDay(sameDaySnap, { uid, time, excludeIds = [] }) {
  const excluded = new Set(excludeIds);
  let sameSlotCount = 0;
  let duplicateSameDay = false;

  for (const doc of sameDaySnap.docs) {
    if (excluded.has(doc.id)) continue;
    const d = doc.data();
    const status = normalizeStatusKey(d.status);

    if (d.patientId === uid && ACTIVE_STATUSES.has(status)) {
      duplicateSameDay = true;
    }

    if (!OCCUPYING_STATUSES.has(status)) continue;
    const raw = d.startTime || d.time;
    if (raw && String(raw).slice(0, 5) === time) sameSlotCount++;
  }

  return { sameSlotCount, duplicateSameDay };
}

// ===================== تخطيط الكتابة على قفل خانة (بلا أي I/O) =====================

/**
 * يقرر ماذا يُكتَب على `slots/{slotId}` لحجز مكان لمريض فيها، بناءً على
 * *لقطة مقروءة مسبقاً*. دالة خالصة عمداً: كل قراءة Firestore تتم قبلها في
 * المعاملة، فلا يخاطر أحد باستدعاء `get` بعد أول `set`/`update` — وهو خطأ
 * ممنوع في معاملات Firestore.
 *
 * تُستخدم من الحجز (`booking.js`) وإعادة الجدولة (`lifecycle.js`) معاً —
 * نفس قواعد السعة والإغلاق بالضبط.
 */
function planSlotReservation({ slotSnap, doctorId, date, time, uid, capacity, sameSlotCount }) {
  if (!slotSnap.exists) {
    if (sameSlotCount >= capacity) {
      fail('slot-unavailable', 'aborted', 'للأسف تم حجز هذا الموعد للتو، اختر وقتاً آخر');
    }
    return {
      action: 'create',
      slotId: slotSnap.id,
      data: {
        doctorId, appointmentDate: date, startTime: time,
        capacity, bookedCount: 1, patientIds: [uid],
      },
    };
  }

  const slot = slotSnap.data();
  if (slot.doctorId !== doctorId || slot.appointmentDate !== date || slot.startTime !== time) {
    fail('slot-conflict', 'failed-precondition', 'تعذّر إتمام الحجز، حاول مرة أخرى');
  }
  if (slot.closed === true || slot.cancelled === true) {
    fail('slot-closed', 'failed-precondition', 'هذا الموعد مغلق حالياً');
  }

  const patientIds = Array.isArray(slot.patientIds) ? slot.patientIds : [];
  if (patientIds.includes(uid)) {
    return { action: 'noop', slotId: slotSnap.id, alreadyIn: true };
  }

  const recorded = Number(slot.capacity);
  const effectiveCapacity = Number.isFinite(recorded) && recorded > 0 ? recorded : capacity;
  const booked = Number(slot.bookedCount) || 0;

  if (booked >= effectiveCapacity || sameSlotCount >= effectiveCapacity) {
    fail('slot-unavailable', 'aborted', 'للأسف تم حجز هذا الموعد للتو، اختر وقتاً آخر');
  }

  return {
    action: 'update',
    slotId: slotSnap.id,
    data: { bookedCount: booked + 1, patientIds: [...patientIds, uid] },
  };
}

/**
 * يقرر ماذا يُكتَب على `slots/{slotId}` لتحرير مكان مريض فيها — عكس
 * `planSlotReservation` تماماً. لا يمسّ مرضى آخرين مهما حدث: يحذف معرّف
 * صاحب الطلب فقط من القائمة، ولا ينقص العدّاد تحت الصفر أبداً.
 */
function planSlotRelease(slotSnap, uid) {
  if (!slotSnap.exists) return { action: 'noop' };

  const slot = slotSnap.data();
  const patientIds = Array.isArray(slot.patientIds) ? slot.patientIds : [];
  if (!patientIds.includes(uid)) return { action: 'noop' };

  const booked = Number(slot.bookedCount) || 0;
  return {
    action: 'update',
    data: {
      bookedCount: Math.max(0, booked - 1),
      patientIds: patientIds.filter((id) => id !== uid),
    },
  };
}

/** يزيح تاريخاً بصيغة `yyyy-MM-dd` بعدد أيام (قد يكون سالباً). */
function shiftDateStr(dateStr, days) {
  const base = Date.parse(`${dateStr}T00:00:00Z`);
  return _dateFmt('UTC').format(new Date(base + days * 86400000));
}

/** أقصى مدى زمني يُقبل في طلب واحد لـ `getAvailability` — يحدّ تكلفة الاستعلام. */
const MAX_AVAILABILITY_RANGE_DAYS = 31;

/**
 * استعلام التوفّر — واجهة القراءة الوحيدة التي يعتمدها العميل لعرض الخانات.
 *
 * **القاعدة الحرجة**: تستخدم نفس دوال الجدول التي يستخدمها الحجز
 * (`isWorkingDay`, `generateSlotTimes`, `slotCapacity`) عبر `availability.js`
 * حرفياً — لا نسخة موازية من منطق التوفّر. الاستجابة هنا مع ذلك **ليست**
 * المرجع النهائي: قد تصبح قديمة بجزء من الثانية قبل لحظة الحجز الفعلية،
 * ومعاملة `bookAppointment` هي الحكم الأخير دائماً.
 *
 * الطلب يحمل معرّفات ومدى فقط (`doctorId`, `dateFrom`, `dateTo`) — لا سعة
 * ولا عدّادات من العميل؛ الرد وحده يحملها، ومصدرها Firestore.
 */
async function getAvailabilityCore({ db, uid, data, now = new Date() }) {
  if (!uid || typeof uid !== 'string') {
    fail('unauthenticated', 'unauthenticated', 'يجب تسجيل الدخول أولاً');
  }

  const payload = data && typeof data === 'object' ? data : {};

  const doctorId = payload.doctorId;
  if (typeof doctorId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(doctorId)) {
    fail('invalid-argument', 'invalid-argument', 'معرّف الطبيب غير صالح');
  }

  const dateFrom = payload.dateFrom;
  const dateTo = payload.dateTo || dateFrom;
  if (!isValidDateStr(dateFrom) || !isValidDateStr(dateTo)) {
    fail('invalid-argument', 'invalid-argument', 'مدى التاريخ غير صالح');
  }
  if (dateTo < dateFrom) {
    fail('invalid-argument', 'invalid-argument', 'نهاية المدى قبل بدايته');
  }
  if (daysBetween(dateFrom, dateTo) > MAX_AVAILABILITY_RANGE_DAYS) {
    fail('invalid-argument', 'invalid-argument',
      `المدى المسموح به حتى ${MAX_AVAILABILITY_RANGE_DAYS} يوماً في الطلب الواحد`);
  }

  const doctor = await fetchBookableDoctor(db, doctorId);
  const nowInfo = nowForDoctor(doctor, now);

  // تقاطع المدى المطلوب مع أفق الحجز الفعلي — لا داعي لحساب أيام خارجه.
  const horizonEnd = shiftDateStr(nowInfo.date, BOOKING_HORIZON_DAYS);
  const effFrom = dateFrom > nowInfo.date ? dateFrom : nowInfo.date;
  const effTo = dateTo < horizonEnd ? dateTo : horizonEnd;

  if (effTo < effFrom) {
    return {
      ok: true, doctorId, timezone: clinicTimezone(doctor),
      generatedAt: nowInfo, dateFrom, dateTo, slots: [],
    };
  }

  const duration = slotDurationMinutes(doctor);
  const capacityDefault = slotCapacity(doctor);

  const [slotsSnap, appointmentsSnap] = await Promise.all([
    db.collection('slots')
      .where('doctorId', '==', doctorId)
      .where('appointmentDate', '>=', effFrom)
      .where('appointmentDate', '<=', effTo)
      .get(),
    db.collection('appointments')
      .where('doctorId', '==', doctorId)
      .where('appointmentDate', '>=', effFrom)
      .where('appointmentDate', '<=', effTo)
      .get(),
  ]);

  const slotsByKey = new Map();
  for (const doc of slotsSnap.docs) {
    const d = doc.data();
    slotsByKey.set(`${d.appointmentDate}_${d.startTime}`, { id: doc.id, ...d });
  }

  // نفس منطق `analyzeSameDay` لكن مجمَّعاً على مدى أيام كامل بدل يوم واحد،
  // لتغطية المواعيد القديمة بلا مستند خانة.
  const legacyCounts = new Map();
  for (const doc of appointmentsSnap.docs) {
    const d = doc.data();
    const status = normalizeStatusKey(d.status);
    if (!OCCUPYING_STATUSES.has(status)) continue;
    const raw = d.startTime || d.time;
    if (!raw) continue;
    const key = `${d.appointmentDate}_${String(raw).slice(0, 5)}`;
    legacyCounts.set(key, (legacyCounts.get(key) || 0) + 1);
  }

  const slots = [];
  let cursorDate = effFrom;
  let guard = 0;
  while (cursorDate <= effTo && guard <= MAX_AVAILABILITY_RANGE_DAYS + 1) {
    guard++;
    if (isWorkingDay(doctor, cursorDate)) {
      const times = generateSlotTimes(doctor, cursorDate);
      for (const time of times) {
        const key = `${cursorDate}_${time}`;
        const slotDoc = slotsByKey.get(key);

        let capacity = capacityDefault;
        let bookedCount = 0;
        let closed = false;

        if (slotDoc) {
          const recorded = Number(slotDoc.capacity);
          capacity = Number.isFinite(recorded) && recorded > 0 ? recorded : capacityDefault;
          bookedCount = Number(slotDoc.bookedCount) || 0;
          closed = slotDoc.closed === true || slotDoc.cancelled === true;
        } else {
          bookedCount = legacyCounts.get(key) || 0;
        }

        const remainingCapacity = Math.max(0, capacity - bookedCount);
        const startMinutes = parseInt(time.slice(0, 2), 10) * 60 + parseInt(time.slice(3), 10);
        const endMinutes = startMinutes + duration;
        const endTime = `${pad(Math.floor(endMinutes / 60) % 24)}:${pad(endMinutes % 60)}`;
        const isPast = cursorDate === nowInfo.date && time <= nowInfo.time;

        let status;
        if (closed) status = 'closed';
        else if (isPast) status = 'past';
        else if (remainingCapacity > 0) status = 'available';
        else status = 'full';

        slots.push({
          slotId: slotDoc ? slotDoc.id : slotIdFor(doctorId, cursorDate, time),
          date: cursorDate,
          startTime: time,
          endTime,
          capacity,
          bookedCount,
          remainingCapacity,
          status,
        });
      }
    }
    cursorDate = shiftDateStr(cursorDate, 1);
  }

  return {
    ok: true,
    doctorId,
    timezone: clinicTimezone(doctor),
    generatedAt: nowInfo,
    dateFrom, dateTo,
    slots,
  };
}

module.exports = {
  // زمن ومنطقة زمنية
  DEFAULT_TIMEZONE,
  clinicTimezone,
  nowInZone,
  nowInCairo,
  nowForDoctor,
  arabicWeekday,
  weekdayIndex,
  daysBetween,
  minutesBetween,
  isValidDateStr,
  isValidTimeStr,
  parseClockTime,

  // خطأ موحّد
  AppError,
  fail,

  // حالة الموعد
  OCCUPYING_STATUSES,
  ACTIVE_STATUSES,
  CANCELLABLE_STATUSES,
  normalizeStatusKey,

  // أيام العمل والاستثناءات
  isWorkingDay,
  isClosedDate,
  dateOverrideFor,
  normalizedWorkingDays,
  ENGLISH_WEEKDAY_KEYS,

  // مدة وسعة
  slotDurationMinutes,
  slotCapacity,

  // فترات العمل والخانات
  DEFAULT_SLOTS,
  generateSlotTimes,
  effectiveWorkingHours,
  effectiveWorkingPeriods,
  effectiveBreaks,
  subtractBreaks,

  // معرّفات
  slotIdFor,
  appointmentIdFor,

  // أفق الحجز والتحقق منه
  BOOKING_HORIZON_DAYS,
  fetchBookableDoctor,
  assertSlotWithinSchedule,

  // تحليل اليوم والتخطيط للكتابة
  analyzeSameDay,
  planSlotReservation,
  planSlotRelease,

  // استعلام التوفّر
  shiftDateStr,
  MAX_AVAILABILITY_RANGE_DAYS,
  getAvailabilityCore,
};
