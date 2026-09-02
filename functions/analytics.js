/**
 * التحليلات — قراءة فقط، ولا سلطة لها على شيء.
 *
 * ثلاث نقاط دخول، كلٌّ محصورة بصاحبها:
 *   - `getPatientAnalytics` — نشاط المريض نفسه.
 *   - `getDoctorAnalytics`  — عيادة الطبيب نفسه.
 *   - `getAdminAnalytics`   — المنصّة كلها، لحاملي صلاحية الإدارة وحدهم.
 *
 * ===================== لماذا على الخادم =====================
 *
 * لوحة الإدارة كانت تحسب أعدادها من العميل بـ `count()` على `users`. القواعد
 * تسمح لأي مستخدم مسجَّل بقراءة مستندات الأطباء (وهو ضروري ليظهروا في
 * البحث)، فكل استعلام عدّ نتيجتُه أطباءٌ كان ينجح لأي مستخدم — أي أن
 * إحصاءات المنصّة كانت متاحة للجميع عملياً. القواعد لا تستطيع التعبير عن
 * «العدّ للإدارة وحدها»، فالمكان الصحيح لهذا الحدّ هو دالة خادمية تفحص
 * `token.admin`.
 *
 * ===================== مصدر الحقيقة =====================
 *
 * لا مجموعة جديدة ولا عدّادات موازية. كل رقم هنا مشتقّ من المستندات
 * الموجودة أصلاً:
 *
 * | المقياس | المصدر | الحقول |
 * |---|---|---|
 * | المواعيد وحالاتها | `appointments` | `status`, `appointmentDate` |
 * | إعادة الجدولة | `appointments` | `rescheduledFrom` |
 * | التخصصات الأكثر طلباً | `appointments` | `doctorSpecialization` |
 * | تقييم الطبيب | `users` | `rating`, `reviews` |
 * | حالات الأطباء | `users` | `role`, `isVerified`, `disabled` |
 * | طلبات التوثيق | `doctorApplications` | `status` |
 *
 * `doctorSpecialization` منسوخ على الموعد وقت الحجز، فتجميع الطلب حسب
 * التخصص لا يحتاج قراءة مستند طبيب واحد.
 *
 * **التحليلات رصد لا سلطة**: لا شيء هنا يكتب، ولا رقم منها يدخل في قرار
 * حجز أو سعر أو توثيق. لو تعطّلت كلها لم يتأثر أي مسار عمل.
 *
 * ===================== المنطقة الزمنية =====================
 *
 * `appointmentDate` نصّ `yyyy-MM-dd` **بتوقيت العيادة** (افتراضه
 * `Africa/Cairo`، انظر `clinicTimezone`)، وهو ما يكتبه الخادم منذ المرحلة
 * 1أ. التجميع هنا يقع على هذا النصّ كما هو — فلا خلط بين UTC وتوقيت الجهاز
 * وتوقيت العيادة: اليوم في التقرير هو اليوم في العيادة.
 *
 * حدود المدى تُحسب أيضاً بتوقيت العيادة الافتراضي للمنصّة، لا بتوقيت
 * الخادم، حتى لا يزحف «آخر 7 أيام» بمقدار ساعتين.
 */

const {
  fail,
  normalizeStatusKey,
  ACTIVE_STATUSES,
} = require('./availability');

/** المنطقة التي تُحسب بها حدود المدى — نفس افتراض `clinicTimezone`. */
const ANALYTICS_TIMEZONE = 'Africa/Cairo';

/**
 * المديات المسموح بها. مجموعة مغلقة عمداً: العميل يختار من قائمة لا يرسل
 * تاريخين، فلا يمكن أن يطلب مسحاً لعشر سنوات.
 */
const RANGES = {
  '7d': { days: 7, bucket: 'day', label: 'آخر 7 أيام' },
  '30d': { days: 30, bucket: 'day', label: 'آخر 30 يوماً' },
  '90d': { days: 90, bucket: 'week', label: 'آخر 90 يوماً' },
  '365d': { days: 365, bucket: 'month', label: 'آخر سنة' },
};

const DEFAULT_RANGE = '30d';

/**
 * سقف المستندات لأي استعلام تحليلي.
 *
 * التجميع يقع على الخادم، فلا يُرسل مستند خام واحد إلى العميل. السقف حاجز
 * أمان: مدى سنة لعيادة مزدحمة يجب ألّا يتحوّل إلى قراءة مفتوحة. عند بلوغه
 * يُرفع `truncated` في الرد — لا يُخفى.
 */
const MAX_SCAN = 3000;

/** أقصى عدد عناصر في أي قائمة مرتَّبة (تخصصات، أطباء). */
const TOP_N = 8;

// ===================== أدوات التاريخ =====================

const _fmtCache = new Map();
function _fmt(tz) {
  if (!_fmtCache.has(tz)) {
    _fmtCache.set(tz, new Intl.DateTimeFormat('en-CA', {
      timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit',
    }));
  }
  return _fmtCache.get(tz);
}

/** `yyyy-MM-dd` لهذه اللحظة بتوقيت العيادة. */
function dateStrIn(date, tz = ANALYTICS_TIMEZONE) {
  return _fmt(tz).format(date);
}

/** يزيح نصّ تاريخ بعدد أيام، بحساب تقويمي لا حسابي. */
function shiftDays(dateStr, days) {
  const [y, m, d] = dateStr.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + days);
  return dt.toISOString().slice(0, 10);
}

/** مفتاح التجميع لتاريخ ما بحسب دقّة المدى. */
function bucketKey(dateStr, bucket) {
  if (bucket === 'day') return dateStr;
  if (bucket === 'month') return dateStr.slice(0, 7);
  // أسبوعي: يُنسب اليوم إلى الأحد الذي يسبقه (بداية الأسبوع في مصر).
  const [y, m, d] = dateStr.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() - dt.getUTCDay());
  return dt.toISOString().slice(0, 10);
}

/** يتحقق أن المدى من القائمة المغلقة ويُرجع حدوده. */
function resolveRange(raw, now) {
  const key = raw === undefined || raw === null ? DEFAULT_RANGE : String(raw);
  const range = RANGES[key];
  if (!range) {
    fail('invalid-argument', 'invalid-range',
      'المدى الزمني المطلوب غير مدعوم');
  }
  const to = dateStrIn(now);
  const from = shiftDays(to, -(range.days - 1));
  return { key, from, to, bucket: range.bucket, label: range.label };
}

// ===================== تصنيف الحالات =====================

/**
 * تصنيف موعد واحد إلى فئة تحليلية.
 *
 * يمرّ عبر `normalizeStatusKey` فتُقرأ الصيغ السبع القديمة كما تُقرأ
 * الجديدة — رقم لا يرى `done` مكتملاً رقمٌ خاطئ.
 */
function classify(status) {
  const key = normalizeStatusKey(status);
  if (key === 'completed' || key === 'done') return 'completed';
  if (key === 'cancelled' || key === 'canceled') return 'cancelled';
  if (key === 'noshow' || key === 'no_show') return 'noShow';
  if (ACTIVE_STATUSES.has(key)) return 'open';
  return 'other';
}

/// هيكل عدّادات فارغ — يضمن أن الرد ثابت الشكل ولو لم يوجد أي موعد.
///
/// `open` لا `upcoming`: المدى ينتهي **اليوم**، فما بقي فيه بحالة نشطة هو
/// موعد لم يُحسم بعد ضمن فترة التقرير — لا «كل المواعيد القادمة». طبيب
/// لديه موعد بعد أسبوع لا يظهر في تقرير آخر ثلاثين يوماً، وتسميته
/// «قادمة» كانت ستجعل الرقم يبدو ناقصاً وهو صحيح.
function emptyCounts() {
  return {
    total: 0, open: 0, completed: 0,
    cancelled: 0, noShow: 0, rescheduled: 0,
  };
}

/**
 * يقرأ مواعيد ضمن مدى ويجمّعها.
 *
 * القراءة محدودة بالمدى وبالسقف معاً، والتجميع يقع هنا فلا يعبر الشبكة إلا
 * الأرقام.
 */
async function aggregateAppointments(db, { field, value, from, to, bucket }) {
  const snap = await db.collection('appointments')
    .where(field, '==', value)
    .where('appointmentDate', '>=', from)
    .where('appointmentDate', '<=', to)
    .orderBy('appointmentDate')
    .limit(MAX_SCAN)
    .get();

  const counts = emptyCounts();
  const series = new Map();
  const specialties = new Map();

  for (const doc of snap.docs) {
    const data = doc.data();
    const date = data.appointmentDate;
    if (typeof date !== 'string') continue;

    const kind = classify(data.status);
    counts.total++;
    if (kind !== 'other') counts[kind]++;
    if (data.rescheduledFrom) counts.rescheduled++;

    const key = bucketKey(date, bucket);
    const point = series.get(key) || { booked: 0, completed: 0, cancelled: 0 };
    point.booked++;
    if (kind === 'completed') point.completed++;
    if (kind === 'cancelled') point.cancelled++;
    series.set(key, point);

    const spec = (data.doctorSpecialization || '').trim();
    if (spec) specialties.set(spec, (specialties.get(spec) || 0) + 1);
  }

  return {
    counts,
    series: [...series.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([bucketKeyValue, v]) => ({ bucket: bucketKeyValue, ...v })),
    specialties: [...specialties.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, TOP_N)
      .map(([name, count]) => ({ name, count })),
    truncated: snap.size === MAX_SCAN,
  };
}

/** نسبة مئوية بمنزلة واحدة، وصفر آمن عند غياب المقام. */
function rate(part, whole) {
  if (!whole) return 0;
  return Math.round((part / whole) * 1000) / 10;
}

// ===================== نقاط الدخول =====================

async function getPatientAnalyticsCore({ db, uid, auth, data }) {
  if (!uid) fail('unauthenticated', 'unauthenticated', 'يجب تسجيل الدخول');
  void auth;

  const now = new Date();
  const range = resolveRange(data && data.range, now);

  // `patientId == uid` دائماً: المريض لا يمرّر معرّفاً، فلا مجال لطلب
  // تحليلات مريض آخر أصلاً.
  const agg = await aggregateAppointments(db, {
    field: 'patientId', value: uid,
    from: range.from, to: range.to, bucket: range.bucket,
  });

  return {
    ok: true,
    scope: 'patient',
    range: { key: range.key, from: range.from, to: range.to, label: range.label },
    timezone: ANALYTICS_TIMEZONE,
    generatedAt: now.toISOString(),
    counts: agg.counts,
    series: agg.series,
    truncated: agg.truncated,
  };
}

async function getDoctorAnalyticsCore({ db, uid, auth, data }) {
  if (!uid) fail('unauthenticated', 'unauthenticated', 'يجب تسجيل الدخول');
  void auth;

  // الصفة تُقرأ من مستند المستخدم لا مما يرسله الطالب.
  const userSnap = await db.collection('users').doc(uid).get();
  const user = userSnap.exists ? userSnap.data() : null;
  if (!user || user.role !== 'doctor') {
    fail('permission-denied', 'not-a-doctor',
      'هذه التحليلات متاحة للأطباء فقط');
  }

  const now = new Date();
  const range = resolveRange(data && data.range, now);

  const agg = await aggregateAppointments(db, {
    field: 'doctorId', value: uid,
    from: range.from, to: range.to, bucket: range.bucket,
  });

  const finished = agg.counts.completed + agg.counts.cancelled +
    agg.counts.noShow;

  return {
    ok: true,
    scope: 'doctor',
    range: { key: range.key, from: range.from, to: range.to, label: range.label },
    timezone: ANALYTICS_TIMEZONE,
    generatedAt: now.toISOString(),
    counts: agg.counts,
    series: agg.series,
    quality: {
      // المتوسط من المُجمَّع الذي تكتبه `createReview` في معاملة واحدة،
      // لا من حساب محلي على المراجعات.
      averageRating: typeof user.rating === 'number' ? user.rating : 0,
      reviewCount: typeof user.reviews === 'number' ? user.reviews : 0,
      // النِّسب على المنتهية لا على الإجمالي: موعد لم يحن بعد ليس فشلاً.
      completionRate: rate(agg.counts.completed, finished),
      cancellationRate: rate(agg.counts.cancelled, finished),
      noShowRate: rate(agg.counts.noShow, finished),
    },
    truncated: agg.truncated,
  };
}

async function getAdminAnalyticsCore({ db, uid, auth, data }) {
  if (!uid) fail('unauthenticated', 'unauthenticated', 'يجب تسجيل الدخول');
  if (!auth || !auth.token || auth.token.admin !== true) {
    fail('permission-denied', 'permission-denied',
      'هذه التحليلات متاحة للإدارة فقط');
  }

  const now = new Date();
  const range = resolveRange(data && data.range, now);

  const users = db.collection('users');
  const applications = db.collection('doctorApplications');

  // `count()` تجميع خادمي: لا يقرأ المستندات ولا يُحاسَب عليها كقراءات
  // مفردة. وهي الطريقة الوحيدة هنا لعدّ مجموعة كاملة بلا مسحها.
  const [
    patients, doctors, verifiedDoctors, suspendedDoctors, pendingApplications,
  ] = await Promise.all([
    users.where('role', '==', 'patient').count().get(),
    users.where('role', '==', 'doctor').count().get(),
    users.where('role', '==', 'doctor').where('isVerified', '==', true)
      .count().get(),
    users.where('role', '==', 'doctor').where('disabled', '==', true)
      .count().get(),
    applications.where('status', '==', 'pending').count().get(),
  ]);

  // اتجاه المواعيد على مستوى المنصّة: مدى محدود وسقف، والتجميع هنا.
  const snap = await db.collection('appointments')
    .where('appointmentDate', '>=', range.from)
    .where('appointmentDate', '<=', range.to)
    .orderBy('appointmentDate')
    .limit(MAX_SCAN)
    .get();

  const counts = emptyCounts();
  const series = new Map();
  const specialties = new Map();

  for (const doc of snap.docs) {
    const d = doc.data();
    if (typeof d.appointmentDate !== 'string') continue;

    const kind = classify(d.status);
    counts.total++;
    if (kind !== 'other') counts[kind]++;
    if (d.rescheduledFrom) counts.rescheduled++;

    const key = bucketKey(d.appointmentDate, range.bucket);
    const point = series.get(key) || { booked: 0, completed: 0, cancelled: 0 };
    point.booked++;
    if (kind === 'completed') point.completed++;
    if (kind === 'cancelled') point.cancelled++;
    series.set(key, point);

    const spec = (d.doctorSpecialization || '').trim();
    if (spec) specialties.set(spec, (specialties.get(spec) || 0) + 1);
  }

  const finished = counts.completed + counts.cancelled + counts.noShow;

  return {
    ok: true,
    scope: 'admin',
    range: { key: range.key, from: range.from, to: range.to, label: range.label },
    timezone: ANALYTICS_TIMEZONE,
    generatedAt: now.toISOString(),
    platform: {
      patients: patients.data().count,
      doctors: doctors.data().count,
      verifiedDoctors: verifiedDoctors.data().count,
      suspendedDoctors: suspendedDoctors.data().count,
      pendingApplications: pendingApplications.data().count,
    },
    counts,
    series: [...series.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([bucketKeyValue, v]) => ({ bucket: bucketKeyValue, ...v })),
    // تجميعية بحتة: اسم تخصص وعدد. لا اسم مريض ولا طبيب ولا أي معرّف.
    specialties: [...specialties.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, TOP_N)
      .map(([name, count]) => ({ name, count })),
    quality: {
      completionRate: rate(counts.completed, finished),
      cancellationRate: rate(counts.cancelled, finished),
    },
    truncated: snap.size === MAX_SCAN,
  };
}

module.exports = {
  getPatientAnalyticsCore,
  getDoctorAnalyticsCore,
  getAdminAnalyticsCore,
  // مُصدَّرة للاختبارات ولوثائق العقد.
  RANGES,
  DEFAULT_RANGE,
  MAX_SCAN,
  TOP_N,
  ANALYTICS_TIMEZONE,
  bucketKey,
  shiftDays,
  classify,
};
