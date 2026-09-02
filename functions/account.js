/**
 * حذف الحساب — على الخادم، بسلطة واحدة ومسار واحد.
 *
 * ## لماذا دالة سحابية لا زرّ في العميل
 *
 * `FirebaseAuth.currentUser.delete()` تحذف **حساب المصادقة وحده**. البيانات
 * تبقى كما هي: مستند المستخدم، ومدخل فهرس الهاتف الذي يحجز رقمه إلى الأبد،
 * ومواعيد قائمة تحجز مقاعد في خانات لن يحضرها أحد، ورموز أجهزة تستقبل
 * إشعارات لحساب لم يعد موجوداً. والقواعد لا تسمح للعميل بحذف مستنده أصلاً
 * (`users` → `allow delete: if false`) لأن الحذف يجب أن يجرّ خلفه هذا كلّه.
 *
 * ## ما يُحذف وما يبقى — وليس الفرق اعتباطياً
 *
 * | البيانات | القرار | لماذا |
 * |---|---|---|
 * | `users/{uid}` | تُحذف | ملف شخصي يخصّ صاحبه وحده |
 * | `phone_index/{phone}` | يُحذف | وإلا بقي الرقم محجوزاً بلا صاحب |
 * | `notifications` للمستلم | تُحذف | لا يقرأها غيره |
 * | `users/{uid}/devices` | تُحذف | رموز Push لأجهزته |
 * | حساب المصادقة | يُحذف | آخر خطوة، بعد أن تنتهي البيانات |
 * | مواعيد **قائمة** | تُلغى ويُحرَّر مقعدها | وإلا حجبت وقت طبيب عن مرضى آخرين |
 * | مواعيد **ماضية** | تبقى، وتُطمَس هويته فيها | سجل العيادة الطبي ليس ملكاً للمريض وحده |
 * | مراجعات كتبها | تبقى، ويُطمَس اسمه | حذفها يغيّر تقييم طبيب — سجل يخصّ غيره |
 * | `auditLogs` | يُكتب سجل بالحذف | أثر إداري لا يجوز أن يمحوه المستخدم |
 *
 * الطمس (`anonymize`) لا الحذف هو الفرق الجوهري: المطلوب ألا تبقى بيانات
 * **تعريفية** عن شخص حذف حسابه، لا أن يختفي أثر زيارة وقعت فعلاً من دفاتر
 * العيادة. يُبقى `patientId` كمفتاح فني لا يدلّ على أحد بعد زوال الحساب.
 *
 * ## إعادة المحاولة
 *
 * الحذف عملية متعدّدة الخطوات، وقد تنقطع في منتصفها. كل خطوة هنا مكتوبة
 * لتُعاد بلا ضرر: الحذف يتجاهل ما اختفى، والطمس يعيد كتابة نفس القيم،
 * وحذف حساب المصادقة يبتلع `user-not-found`. فاستدعاء ثانٍ بعد انقطاع
 * يُكمل ما بقي بدل أن يفشل.
 */

const admin = require('firebase-admin');
// `FieldValue` من الوحدة النمطية لا من `admin.firestore.FieldValue`.
//
// الثانية تعمل في اختبارات jest لكنها تنهار داخل محاكي الدوال: هناك
// `admin.firestore` كائن مُغلَّف لا يحمل الخاصية، فتفشل العملية في منتصفها
// بـ «Cannot read properties of undefined». اكتُشف هذا بتشغيل الحذف من
// الواجهة الحقيقية على المحاكي، لا من الاختبارات — ولذلك يوجد اختبار
// تعاقد أدناه يمنع عودته.
const { FieldValue } = require('firebase-admin/firestore');

const { AppError, fail, normalizeStatusKey, ACTIVE_STATUSES, planSlotRelease } =
  require('./availability');
const { NOTIFICATION_TYPES, queueNotification, deliverPendingPush } =
  require('./notifications');

/**
 * أقصى عدد مستندات تُعالَج في استدعاء واحد لكل مجموعة.
 *
 * سقف لا هدف: حساب مريض عادي لا يقترب منه. وجوده يمنع استدعاءً واحداً من
 * أن يمسح عشرات الآلاف من المستندات في معاملة زمنها محدود، فيفشل بعد أن
 * غيّر نصف الحالة. ما يتجاوز السقف يُكمَل بإعادة الاستدعاء — والعملية
 * مبنية لتُعاد.
 */
const MAX_DOCS_PER_COLLECTION = 500;

/** حجم دفعة الكتابة — حدّ Firestore نفسه. */
const BATCH_SIZE = 400;

/**
 * أقصى عمر لتسجيل الدخول يُقبل عند طلب الحذف، بالثواني.
 *
 * الحذف لا رجعة فيه. جلسة قديمة على جهاز مفقود أو معار يجب ألا تكفي
 * لمحو حساب صاحبها، فيُطلب تسجيل دخول حديث — نفس ما تشترطه Firebase
 * نفسها على العمليات الحسّاسة في العميل (`requires-recent-login`).
 */
const RECENT_LOGIN_MAX_AGE_SECONDS = 10 * 60;

/** نص يحلّ محل الاسم بعد الحذف — لا فراغ، حتى تبقى الواجهات مقروءة. */
const ANONYMOUS_NAME = 'حساب محذوف';

/**
 * هل سجّل صاحب الطلب دخوله حديثاً؟
 *
 * `auth_time` مطالبة موقَّعة داخل الرمز نفسه — لا يملك العميل تزويرها.
 * غيابها (اختبارات، أو رمز بصيغة غير متوقعة) يُعامَل كعدم استيفاء لا
 * كاستيفاء: الافتراض الآمن في عملية لا رجعة فيها هو الرفض.
 */
function assertRecentLogin(auth, now) {
  const authTime = auth && auth.token && Number(auth.token.auth_time);
  if (!Number.isFinite(authTime)) {
    fail('recent-login-required', 'failed-precondition',
      'سجّل الدخول من جديد قبل حذف حسابك');
  }
  const ageSeconds = Math.floor(now.getTime() / 1000) - authTime;
  if (ageSeconds > RECENT_LOGIN_MAX_AGE_SECONDS) {
    fail('recent-login-required', 'failed-precondition',
      'سجّل الدخول من جديد قبل حذف حسابك');
  }
}

/** يحذف مستندات استعلام على دفعات. يُرجع عدد ما حُذف. */
async function deleteQuery(db, query) {
  const snap = await query.limit(MAX_DOCS_PER_COLLECTION).get();
  if (snap.empty) return 0;

  for (let i = 0; i < snap.docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    snap.docs.slice(i, i + BATCH_SIZE).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  return snap.size;
}

/**
 * يلغي موعداً قائماً ويحرّر مقعده — بنفس ذرّية `cancelAppointment`.
 *
 * لا يُعاد استخدام `cancelAppointmentCore` هنا عمداً: تلك تفرض مهلة على
 * المريض وترفض ما قرب وقته، وحذف الحساب حقّ لا يصحّ أن تعطّله مهلة
 * تجارية. المشترك بينهما — تحرير المقعد — مستخرَج أصلاً في
 * `planSlotRelease`، فلا منطق مكرَّر.
 */
async function cancelForDeletion(db, apptSnap, uid, now) {
  const appt = apptSnap.data();
  const slotRef = appt.slotId
    ? db.collection('slots').doc(appt.slotId)
    : null;

  return db.runTransaction(async (tx) => {
    const [freshAppt, slotSnap] = await Promise.all([
      tx.get(apptSnap.ref),
      slotRef ? tx.get(slotRef) : Promise.resolve(null),
    ]);
    if (!freshAppt.exists) return null;

    const data = freshAppt.data();
    if (!ACTIVE_STATUSES.has(normalizeStatusKey(data.status))) return null;

    if (slotRef && slotSnap) {
      const plan = planSlotRelease(slotSnap, uid);
      if (plan.action === 'update') {
        tx.update(slotRef, { ...plan.data, updatedAt: now });
      }
    }

    tx.update(apptSnap.ref, {
      status: 'Cancelled',
      cancelledAt: now,
      cancelledBy: uid,
      cancelledByRole: 'patient',
      cancelReason: 'account-deleted',
      updatedAt: now,
    });

    // الطبيب يُبلَّغ: وقته صار متاحاً، وقد يكون رتّب يومه عليه.
    return queueNotification(tx, db, {
      recipientId: data.doctorId,
      recipientRole: 'doctor',
      type: NOTIFICATION_TYPES.APPOINTMENT_CANCELLED,
      appointmentId: apptSnap.id,
      metadata: {
        doctorName: data.doctorName,
        patientName: ANONYMOUS_NAME,
        date: data.appointmentDate,
        startTime: data.startTime,
      },
    });
  });
}

/**
 * حذف حساب صاحب الطلب.
 *
 * ```
 * الطلب:  { confirm: true }
 * الرد:   { ok, deleted, cancelledAppointments, anonymizedAppointments,
 *           anonymizedReviews, deletedNotifications, deletedDevices }
 * ```
 *
 * @param {object} args
 * @param {FirebaseFirestore.Firestore} args.db
 * @param {string} args.uid
 * @param {object} args.auth  `context.auth` كاملاً — لقراءة `auth_time`.
 * @param {object} args.data
 * @param {Date}   [args.now]
 */
async function deleteAccountCore({
  db, uid, auth, data, now = new Date(),
  authAdmin = admin.auth(), messaging = admin.messaging(),
}) {
  if (!uid || typeof uid !== 'string') {
    fail('unauthenticated', 'unauthenticated', 'يجب تسجيل الدخول أولاً');
  }

  const payload = data && typeof data === 'object' ? data : {};
  // تأكيد صريح: الحذف لا يقع كأثر جانبي لطلب أُرسل بالخطأ.
  if (payload.confirm !== true) {
    fail('confirmation-required', 'invalid-argument',
      'حذف الحساب يحتاج تأكيداً صريحاً');
  }

  assertRecentLogin(auth, now);

  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  const user = userSnap.exists ? userSnap.data() : {};

  // حساب الطبيب لا يُحذف ذاتياً.
  //
  // ليس تمييزاً بل تبعية: مستند الطبيب مرجع حيٌّ لكل موعد ومراجعة عنده،
  // ومحوّه يترك مرضى بمواعيد بلا طبيب وتقييمات بلا صاحب. وحسابات الأطباء
  // تُنشأ إدارياً أصلاً (`scripts/promote_to_doctor.js`)، فمن أنشأها
  // يُنهيها — بعد تصفية مواعيدها. راجع `docs/RUNBOOK.md`.
  if (user.role === 'doctor') {
    fail('doctor-account', 'failed-precondition',
      'حسابات الأطباء تُغلق من إدارة التطبيق — تواصل معنا');
  }

  const appointments = db.collection('appointments');

  // (1) المواعيد القائمة: إلغاء وتحرير المقعد، موعداً موعداً.
  //
  // بالتسلسل لا بالتوازي: كل إلغاء معاملة تلمس خانة قد تشترك مع غيرها،
  // والتوازي هنا يعني تنازعاً على نفس المستند بلا فائدة تُذكر — العدد
  // في حساب واحد صغير بطبيعته.
  const activeSnap = await appointments
    .where('patientId', '==', uid)
    .where('status', 'in', ['Booked', 'PendingConfirmation'])
    .limit(MAX_DOCS_PER_COLLECTION)
    .get();

  const notificationRefs = [];
  for (const apptSnap of activeSnap.docs) {
    const ref = await cancelForDeletion(db, apptSnap, uid, now);
    if (ref) notificationRefs.push(ref);
  }
  if (notificationRefs.length) {
    await deliverPendingPush({ db, messaging, refs: notificationRefs });
  }

  // (2) كل مواعيده — بما فيها ما أُلغي للتوّ: تُطمس الهوية وتبقى الزيارة.
  const allSnap = await appointments
    .where('patientId', '==', uid)
    .limit(MAX_DOCS_PER_COLLECTION)
    .get();

  let anonymizedAppointments = 0;
  for (let i = 0; i < allSnap.docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const d of allSnap.docs.slice(i, i + BATCH_SIZE)) {
      batch.update(d.ref, {
        patientName: ANONYMOUS_NAME,
        patientPhone: FieldValue.delete(),
        patientEmail: FieldValue.delete(),
        patientDeletedAt: now,
      });
      anonymizedAppointments += 1;
    }
    await batch.commit();
  }

  // (3) المراجعات: تبقى — حذفها يحرّك تقييم طبيب — ويُطمس اسم كاتبها.
  const reviewsSnap = await db.collection('reviews')
    .where('patientId', '==', uid)
    .limit(MAX_DOCS_PER_COLLECTION)
    .get();

  let anonymizedReviews = 0;
  for (let i = 0; i < reviewsSnap.docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const d of reviewsSnap.docs.slice(i, i + BATCH_SIZE)) {
      batch.update(d.ref, { patientName: ANONYMOUS_NAME, patientDeletedAt: now });
      anonymizedReviews += 1;
    }
    await batch.commit();
  }

  // (4) ما يخصّه وحده: الإشعارات، والأجهزة، وفهرس الهاتف، والمستند نفسه.
  const deletedNotifications = await deleteQuery(
    db, db.collection('notifications').where('recipientId', '==', uid));
  const deletedDevices = await deleteQuery(db, userRef.collection('devices'));

  const phone = typeof user.phone === 'string' ? user.phone.trim() : '';
  if (phone) {
    const phoneRef = db.collection('phone_index').doc(phone);
    const phoneSnap = await phoneRef.get();
    // الشرط ليس شكلياً: مدخل الفهرس قد يكون صار لشخص آخر (أعاد الرقم
    // تسجيله)، فحذفه حينها يقطع دخول صاحبه الحالي.
    if (phoneSnap.exists && phoneSnap.data().uid === uid) {
      await phoneRef.delete();
    }
  }

  // (5) أثر إداري قبل زوال المستند — يكتبه الخادم، ولا يقرأه إلا الإدارة.
  await db.collection('auditLogs').add({
    actorAdminId: uid,
    action: 'account.deleted',
    targetType: 'user',
    targetId: uid,
    metadata: {
      role: user.role || 'unknown',
      cancelledAppointments: notificationRefs.length,
      anonymizedAppointments,
      anonymizedReviews,
      deletedNotifications,
      deletedDevices,
    },
    createdAt: now,
  });

  await userRef.delete();

  // (6) وأخيراً حساب المصادقة — بعد أن انتهت البيانات، لا قبلها: لو سقط
  // الاستدعاء بينهما لبقي حساب بلا بيانات (غير ضار، ويُصلحه استدعاء ثانٍ)
  // بدل بيانات بلا صاحب يستطيع طلب حذفها.
  try {
    await authAdmin.deleteUser(uid);
  } catch (error) {
    if (!error || error.code !== 'auth/user-not-found') throw error;
  }

  return {
    deleted: true,
    cancelledAppointments: notificationRefs.length,
    anonymizedAppointments,
    anonymizedReviews,
    deletedNotifications,
    deletedDevices,
  };
}

module.exports = {
  AppError,
  deleteAccountCore,
  ANONYMOUS_NAME,
  MAX_DOCS_PER_COLLECTION,
  RECENT_LOGIN_MAX_AGE_SECONDS,
};
