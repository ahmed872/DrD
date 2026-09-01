const functions = require("firebase-functions");
const admin = require("firebase-admin");

const { bookAppointmentCore } = require("./booking");
const { cancelAppointmentCore, rescheduleAppointmentCore } = require("./lifecycle");
const { AppError, getAvailabilityCore } = require("./availability");
const {
  approveDoctorCore,
  rejectDoctorCore,
  suspendDoctorCore,
  restoreDoctorCore,
} = require("./admin");
const { sendAppointmentRemindersCore } = require("./reminders");

admin.initializeApp();

/**
 * يُشغّل دالة نطاق (`*Core`) خلف تحقق مصادقة موحَّد، ويترجم `AppError` إلى
 * `HttpsError` بنفس الآلية للجميع — الحجز، الإلغاء، إعادة الجدولة، التوفّر،
 * وإجراءات الإدارة.
 *
 * `auth` الكامل (`context.auth`) يمرّ مع `uid` — دوال الإدارة تحتاج
 * `auth.token.admin` (الـ Custom Claim الموقَّع) للتحقق من الصلاحية، وبقية
 * الدوال تتجاهله ببساطة.
 *
 * الرسالة الداخلية لأي خطأ غير متوقع لا تصل العميل أبداً؛ تُسجَّل فقط.
 */
function callable(name, core) {
  return functions.https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "يجب تسجيل الدخول أولاً",
        { reason: "unauthenticated" }
      );
    }

    try {
      const result = await core({
        db: admin.firestore(),
        uid: context.auth.uid,
        auth: context.auth,
        data,
      });
      return { ok: true, ...result };
    } catch (error) {
      if (error instanceof AppError) {
        throw new functions.https.HttpsError(error.code, error.message, {
          reason: error.reason,
        });
      }
      functions.logger.error(`${name} فشل`, {
        uid: context.auth.uid,
        error: error && error.message,
      });
      throw new functions.https.HttpsError(
        "internal",
        "تعذّر إتمام الطلب، حاول مرة أخرى",
        { reason: "internal" }
      );
    }
  });
}

/**
 * حجز موعد — نقطة الدخول الوحيدة للحجز.
 *
 * العميل يرسل **طلباً** لا قراراً: أي طبيب، أي يوم، أي ساعة، ولماذا. كل ما
 * عداه — السعر، السعة، مدة الكشف، اسم الطبيب، اسم المريض ورقمه، حالة الموعد،
 * ومعرّفات المستندات — يستخرجه الخادم من Firestore.
 *
 * ```
 * الطلب:  { doctorId, date: 'yyyy-MM-dd', time: 'HH:mm', reason? }
 * الرد:   { ok, appointmentId, slotId, appointmentDate, startTime,
 *           endTime, price, status, duplicate }
 * ```
 *
 * الأخطاء تُرجَع بأكواد HttpsError القياسية (وهي مجموعة مغلقة لا تقبل أسماء
 * مخصّصة)، مع `details.reason` رمزاً ثابتاً يترجمه التطبيق لرسالة عربية:
 *
 * | reason | code | المعنى |
 * |---|---|---|
 * | `unauthenticated` | unauthenticated | بلا تسجيل دخول |
 * | `permission-denied` | permission-denied | حجز نيابة عن غيره |
 * | `invalid-argument` | invalid-argument | مدخلات غير صالحة |
 * | `doctor-not-found` | not-found | لا طبيب بهذا المعرّف |
 * | `doctor-not-verified` | failed-precondition | طبيب غير موثَّق |
 * | `doctor-disabled` | failed-precondition | حساب موقوف |
 * | `doctor-not-working` | failed-precondition | ليس يوم عمل |
 * | `slot-not-found` | not-found | وقت خارج جدول الطبيب |
 * | `slot-expired` | failed-precondition | وقت مضى |
 * | `slot-out-of-range` | out-of-range | أبعد من أفق الحجز |
 * | `slot-closed` | failed-precondition | خانة مغلقة |
 * | `slot-unavailable` | aborted | امتلأت الخانة |
 * | `already-booked-same-day` | already-exists | موعد قائم نفس اليوم |
 * | `patient-not-found` | failed-precondition | ملف المريض ناقص |
 * | `internal` | internal | خطأ غير متوقع |
 *
 * الرسائل عربية وعامة عمداً: لا تكشف اسم مريض آخر ولا سبب رفض داخلياً.
 */
exports.bookAppointment = callable("bookAppointment", bookAppointmentCore);

/**
 * إلغاء موعد — نقطة الدخول الوحيدة لإلغائه من العميل.
 *
 * المريض صاحب الموعد وحده يستطيع الإلغاء، وحتى مهلة معيّنة قبل موعد
 * الكشف. الخانة تُحرَّر في نفس المعاملة التي تُغيّر حالة الموعد، فلا يبقى
 * عدّادها مرفوعاً بلا صاحب.
 *
 * ```
 * الطلب:  { appointmentId, reason? }
 * الرد:   { ok, appointmentId, status, alreadyCancelled }
 * ```
 *
 * إعادة إرسال نفس الطلب على موعد أُلغي بالفعل تُعيد نجاحاً هادئاً
 * (`alreadyCancelled: true`) بدل خطأ.
 *
 * | reason | code | المعنى |
 * |---|---|---|
 * | `unauthenticated` | unauthenticated | بلا تسجيل دخول |
 * | `invalid-argument` | invalid-argument | معرّف موعد غير صالح |
 * | `appointment-not-found` | not-found | لا موعد بهذا المعرّف |
 * | `permission-denied` | permission-denied | ليس موعدك |
 * | `appointment-completed` | failed-precondition | تم الكشف بالفعل |
 * | `appointment-not-cancellable` | failed-precondition | حالة الموعد لا تسمح بالإلغاء |
 * | `appointment-past` | failed-precondition | موعد فات وقته |
 * | `cancellation-deadline-passed` | failed-precondition | أقرب من مهلة الإلغاء |
 * | `internal` | internal | خطأ غير متوقع |
 */
exports.cancelAppointment = callable("cancelAppointment", cancelAppointmentCore);

/**
 * إعادة جدولة موعد إلى وقت آخر عند **نفس الطبيب** — نقطة الدخول الوحيدة.
 *
 * العملية ذرّية: تحرير الخانة القديمة، وحجز الجديدة، وربط المستندين
 * ببعضهما (`rescheduledTo` / `rescheduledFrom`)، كلها في معاملة واحدة —
 * إما تنجح كاملة أو لا يتغيّر شيء.
 *
 * ```
 * الطلب:  { appointmentId, newDate: 'yyyy-MM-dd', newTime: 'HH:mm', reason? }
 * الرد:   { ok, appointmentId, previousAppointmentId, slotId,
 *           appointmentDate, startTime, endTime, price, status,
 *           duplicate, unchanged }
 * ```
 *
 * `appointmentId` في الرد هو معرّف الموعد **الجديد** (يتغيّر مع الخانة)؛
 * `previousAppointmentId` يشير إلى القديم لمن يحتاج تتبّعه. طلب إلى نفس
 * الخانة الحالية يُعيد `unchanged: true` بلا أي تعديل.
 *
 * | reason | code | المعنى |
 * |---|---|---|
 * | `unauthenticated` | unauthenticated | بلا تسجيل دخول |
 * | `invalid-argument` | invalid-argument | مدخلات غير صالحة |
 * | `appointment-not-found` | not-found | لا موعد بهذا المعرّف |
 * | `permission-denied` | permission-denied | ليس موعدك |
 * | `appointment-completed` | failed-precondition | تم الكشف بالفعل |
 * | `appointment-not-reschedulable` | failed-precondition | حالة الموعد لا تسمح بالتعديل |
 * | `appointment-past` | failed-precondition | موعد فات وقته |
 * | `reschedule-deadline-passed` | failed-precondition | أقرب من مهلة التعديل |
 * | `doctor-not-verified` / `doctor-disabled` | failed-precondition | الطبيب غير متاح الآن |
 * | `doctor-not-working` | failed-precondition | الطبيب لا يعمل في التاريخ الجديد |
 * | `slot-not-found` | not-found | الوقت الجديد خارج جدول الطبيب |
 * | `slot-expired` / `slot-out-of-range` | failed-precondition / out-of-range | التاريخ الجديد غير صالح |
 * | `slot-unavailable` / `slot-closed` | aborted / failed-precondition | الخانة الجديدة ممتلئة أو مغلقة |
 * | `already-booked-same-day` | already-exists | موعد آخر عندك في اليوم الجديد |
 * | `internal` | internal | خطأ غير متوقع |
 */
exports.rescheduleAppointment = callable("rescheduleAppointment", rescheduleAppointmentCore);

/**
 * التوفّر — قراءة الخانات المتاحة عند طبيب ضمن مدى تاريخ.
 *
 * تستخدم **نفس** دوال الجدول التي يستخدمها `bookAppointment`، فلا تعرض
 * وقتاً يرفضه الحجز. الرد مع ذلك ليس مرجعاً نهائياً — قد يصبح قديماً قبل
 * لحظة الحجز، ومعاملة `bookAppointment` هي الحكم الأخير دائماً.
 *
 * ```
 * الطلب:  { doctorId, dateFrom: 'yyyy-MM-dd', dateTo?: 'yyyy-MM-dd' }
 * الرد:   { ok, doctorId, timezone, generatedAt, dateFrom, dateTo, slots: [
 *           { slotId, date, startTime, endTime, capacity, bookedCount,
 *             remainingCapacity, status } ] }
 * ```
 *
 * `status` لكل خانة: `available` | `full` | `past` | `closed`. لا سعة ولا
 * عدّادات تُرسَل من العميل — الرد وحده يحملها من Firestore.
 */
exports.getAvailability = callable("getAvailability", getAvailabilityCore);

// ===================== المرحلة 2: الإدارة وتوثيق الأطباء =====================
//
// الأربعة أدناه إدارية حصراً — تتحقق من `context.auth.token.admin` (راجع
// `admin.js`)، وهو Custom Claim لا يُكتب إلا بـ Admin SDK
// (`scripts/create_admin.js`). لا مسار عميل يمنح نفسه هذه الصلاحية.

/**
 * قبول طلب توثيق طبيب — يرقّي المتقدّم إلى طبيب نشط وقابل للحجز.
 *
 * ```
 * الطلب:  { uid: <معرّف المتقدّم> }
 * الرد:   { ok, doctorId, alreadyApproved }
 * ```
 *
 * يكتب على `users/{uid}`: `role: 'doctor'`, `isVerified: true`,
 * `disabled: false` — نفس الحقلين اللذين يفحصهما محرّك الحجز أصلاً منذ
 * المرحلة 1أ، فيصبح الطبيب قابلاً للحجز فوراً بلا أي تعديل على `booking.js`.
 * طلب مكرَّر على نفس المتقدّم بعد قبوله بنجاح يُعيد `alreadyApproved: true`
 * بدل خطأ أو قبول مضاعف.
 *
 * | reason | code | المعنى |
 * |---|---|---|
 * | `permission-denied` | permission-denied | ليس Admin |
 * | `invalid-argument` | invalid-argument | معرّف مستخدم غير صالح |
 * | `application-not-found` | not-found | لا طلب توثيق بهذا المعرّف |
 * | `user-not-found` | not-found | حساب المتقدّم غير موجود |
 * | `application-rejected` | failed-precondition | الطلب مرفوض — يحتاج إعادة تقديم |
 * | `application-not-pending` | failed-precondition | حالة الطلب لا تسمح بالقبول |
 */
exports.approveDoctor = callable("approveDoctor", approveDoctorCore);

/**
 * رفض طلب توثيق طبيب — لا يمسّ حساب المتقدّم، يبقى `role: 'patient'`.
 *
 * ```
 * الطلب:  { uid: <معرّف المتقدّم>, reason: <سبب الرفض، إلزامي> }
 * الرد:   { ok, doctorId, alreadyRejected }
 * ```
 *
 * السجل التاريخي للطلب يبقى (`doctorApplications/{uid}` لا يُحذف)، ويستطيع
 * المتقدّم إعادة التقديم لاحقاً فتعود حالته `pending` من جديد.
 */
exports.rejectDoctor = callable("rejectDoctor", rejectDoctorCore);

/**
 * إيقاف طبيب موثَّق مؤقتاً — لا يقبل حجوزات جديدة، دون فقدان توثيقه أو
 * تاريخه.
 *
 * ```
 * الطلب:  { uid: <معرّف الطبيب>, reason: <سبب الإيقاف، إلزامي> }
 * الرد:   { ok, doctorId, alreadySuspended }
 * ```
 *
 * `isVerified` يبقى `true` — تمييز متعمَّد بين «غير موثَّق» و«موثَّق لكن
 * موقوف». `disabled: true` وحده هو ما يمنع الحجز الجديد (`fetchBookableDoctor`
 * في `availability.js`)؛ المواعيد القائمة والمراجعات لا تُلمَس إطلاقاً.
 */
exports.suspendDoctor = callable("suspendDoctor", suspendDoctorCore);

/**
 * استعادة طبيب موقوف إلى النشاط — يعود قابلاً للحجز فوراً.
 *
 * ```
 * الطلب:  { uid: <معرّف الطبيب> }
 * الرد:   { ok, doctorId, alreadyActive }
 * ```
 */
exports.restoreDoctor = callable("restoreDoctor", restoreDoctorCore);

// ملاحظة أمنية (المرحلة صفر):
//
// حُذفت من هذا الملف الدالة `sendOTPEmail` التي كانت تراقب مجموعة `otps`
// وترسل بريداً إلى العنوان المأخوذ من **معرّف المستند**. مع قاعدة
// `allow create: if true` على تلك المجموعة كان أي شخص على الإنترنت يستطيع
// كتابة مستند بمعرّف = بريد أي ضحية، فيُرسل بريد من عنوان المشروع إلى من
// يشاء: مرحّل بريد مفتوح، وطريق سريع لحرق سمعة نطاق الإرسال وللتصيّد باسم
// العيادة. المسار لم يكن مستخدماً في التطبيق أصلاً — تسجيل الدخول يتم
// ببريد وكلمة مرور عبر Firebase Auth، وإعادة تعيين كلمة المرور تمر برسائل
// Firebase نفسها.
//
// مجموعة `otps` صارت مغلقة بالكامل في `firestore.rules`.

/**
 * تذكيرات المواعيد — مجدوَلة كل 5 دقائق. راجع `functions/reminders.js`.
 *
 * ## لماذا هذه ليست `checkAppointments` القديمة مُصلَحة
 *
 * النسخة القديمة كانت معطَّلة بالكامل: تستعلم `status == "Scheduled"`
 * (القيمة الحقيقية دائماً `Booked`) وتقرأ حقلي `date`/`time` (الحقلان
 * الحقيقيان `appointmentDate`/`startTime` منذ المرحلة 1أ) — أي أن
 * استعلامها لا يُرجع شيئاً أبداً منذ أن كُتبت. لم يكن هناك «سلوك حالي
 * تُبقي عليه» لتُعدَّل بأقل تغيير؛ لا شيء كان يعمل فعلياً، فأُعيد البناء
 * كاملاً على البيانات الحقيقية ومحرّك `availability.js`.
 *
 * كذلك أُسقطت خطوة «تحذير الغياب» (تحويل الحالة تلقائياً إلى
 * `PendingConfirmation` بعد 10 دقائق) عمداً: نطاق المرحلة 3 إشعارات
 * وتذكيرات الموعد، لا تحوّلات حالة جديدة في دورة حياته — وهي أصلاً لم تكن
 * تعمل قط لنفس السبب، فإسقاطها لا يُفقد سلوكاً حقيقياً قائماً.
 */
exports.sendAppointmentReminders = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async () => {
    const result = await sendAppointmentRemindersCore({
      db: admin.firestore(),
      messaging: admin.messaging(),
    });
    functions.logger.info('sendAppointmentReminders اكتملت', result);
    return null;
  });
