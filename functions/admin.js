/**
 * سلطة الإدارة على الخادم: التحقق من صلاحية admin، ودورة حياة توثيق الطبيب
 * (طلب → مراجعة → قبول/رفض → نشط/موقوف)، وسجل تدقيق الإجراءات الإدارية.
 *
 * ## لماذا الصلاحية Custom Claim لا حقل Firestore
 *
 * حقل مثل `users/{uid}.role == 'admin'` يقرأه العميل ويكتبه العميل ما لم
 * تُقفَل القواعد بعناية — وحتى مع الإقفال، تبقى قراءته من داخل قاعدة بيانات
 * يستطيع أي عميل مصادَق عليه قراءتها جزئياً مصدر ثقة أضعف من توقيع Firebase
 * نفسه. الـ Custom Claim يُكتب حصراً بـ Admin SDK (`admin.auth()
 * .setCustomUserClaims`)، ويصل موقَّعاً داخل رمز JWT الذي يتحقق منه كلٌّ من
 * Cloud Functions (`context.auth.token.admin`) و Firestore Rules
 * (`request.auth.token.admin`) بمعزل عن أي قراءة قاعدة بيانات. لا مسار
 * عميل يستطيع أن يصل إليه إطلاقاً.
 *
 * ## دورة حياة توثيق الطبيب
 *
 * ```
 * تسجيل كمستخدم عادي (role: patient)
 *          │
 *          ▼
 *   doctorApplications/{uid}.status = 'pending'   (كتابة مباشرة من العميل،
 *          │                                        تحكمها القواعد وحدها)
 *          ├── approveDoctor ──► users/{uid}: role='doctor', isVerified=true,
 *          │                     disabled=false، والتطبيق pending='approved'
 *          │
 *          └── rejectDoctor ──► doctorApplications/{uid}.status='rejected'
 *                                (لا يُلمس users/{uid} إطلاقاً)
 *
 *   طبيب نشط (role=doctor, isVerified=true, disabled=false)
 *          │
 *          ├── suspendDoctor ──► disabled=true   (يبقى isVerified=true —
 *          │                     «موثَّق لكن موقوف» تمييز متعمَّد)
 *          │
 *          └── restoreDoctor ──► disabled=false
 * ```
 *
 * `isVerified` و`disabled` هما الحقلان الوحيدان اللذان تفحصهما
 * `fetchBookableDoctor` في `availability.js` — أي أن **الحجز يحترم هذه
 * الدورة تلقائياً بلا أي تعديل على محرّك الحجز نفسه**؛ `doctor.disabled`
 * كان مفحوصاً هناك منذ المرحلة 1أ ولم يكن أي كود يكتبه قط حتى الآن.
 *
 * `verificationStatus` حقل وصفي إضافي يعكس نفس الحالة بصيغة أوضح للوحة
 * التحكم (`pending` / `approved` / `rejected` / `suspended`) — لا يقرأه
 * أي مسار حجز، فلا خطر من اختلافه لحظياً عن `isVerified`/`disabled`.
 */

const {
  AppError,
  fail,
} = require('./availability');

/** الحد الأقصى لنص سبب الرفض أو الإيقاف. */
const MAX_REASON_LENGTH = 500;

/** يتحقق أن صاحب الطلب يحمل صلاحية admin — Custom Claim موقَّع لا حقل Firestore. */
function requireAdmin(auth) {
  if (!auth || !auth.token || auth.token.admin !== true) {
    fail('permission-denied', 'permission-denied',
      'هذا الإجراء متاح للإدارة فقط');
  }
}

function normalizeText(raw, label, { required = false } = {}) {
  if (raw === undefined || raw === null) {
    if (required) fail('invalid-argument', 'invalid-argument', `${label} مطلوب`);
    return '';
  }
  if (typeof raw !== 'string') {
    fail('invalid-argument', 'invalid-argument', `${label} يجب أن يكون نصاً`);
  }
  const trimmed = raw.trim().replace(/\s+/g, ' ');
  if (required && !trimmed) {
    fail('invalid-argument', 'invalid-argument', `${label} مطلوب`);
  }
  if (trimmed.length > MAX_REASON_LENGTH) {
    fail('invalid-argument', 'invalid-argument', `${label} أطول من ${MAX_REASON_LENGTH} حرفاً`);
  }
  return trimmed;
}

function assertValidUid(uid) {
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    fail('invalid-argument', 'invalid-argument', 'معرّف المستخدم غير صالح');
  }
}

/**
 * سجل تدقيق — append-only، Admin SDK فقط. `actorAdminId` من `auth.uid`
 * الموقَّع لا من الطلب، فلا يستطيع أي إجراء أن ينتحل هوية مدير آخر.
 */
function writeAuditLog(tx, db, { actorAdminId, action, targetType, targetId, metadata = {} }) {
  const ref = db.collection('auditLogs').doc();
  tx.set(ref, {
    actorAdminId,
    action,
    targetType,
    targetId,
    metadata,
    createdAt: new Date(),
  });
}

// ===================== قبول طلب توثيق طبيب =====================

/**
 * @param {object} args
 * @param {FirebaseFirestore.Firestore} args.db
 * @param {string} args.uid   معرّف المدير المستدعي (من رمز المصادقة).
 * @param {object} args.auth  `context.auth` كاملاً — لقراءة `token.admin`.
 * @param {object} args.data  `{ uid: <معرّف الطبيب المتقدّم> }`.
 */
async function approveDoctorCore({ db, uid, auth, data }) {
  requireAdmin(auth);

  const payload = data && typeof data === 'object' ? data : {};
  const applicantUid = payload.uid;
  assertValidUid(applicantUid);

  const appRef = db.collection('doctorApplications').doc(applicantUid);
  const userRef = db.collection('users').doc(applicantUid);

  const outcome = await db.runTransaction(async (tx) => {
    const [appSnap, userSnap] = await Promise.all([tx.get(appRef), tx.get(userRef)]);

    if (!appSnap.exists) {
      fail('application-not-found', 'not-found', 'لا يوجد طلب توثيق بهذا المعرّف');
    }
    if (!userSnap.exists) {
      fail('user-not-found', 'not-found', 'حساب المتقدّم غير موجود');
    }

    const app = appSnap.data();
    if (app.status === 'approved') {
      // طلب مكرَّر — القبول سبق أن تم، لا تكرار للأثر ولا لسجل التدقيق.
      return { alreadyApproved: true };
    }
    if (app.status === 'rejected') {
      fail('application-rejected', 'failed-precondition',
        'هذا الطلب مرفوض — على المتقدّم إعادة التقديم أولاً');
    }
    if (app.status !== 'pending') {
      fail('application-not-pending', 'failed-precondition',
        'حالة الطلب لا تسمح بالقبول الآن');
    }

    const now = new Date();

    tx.update(appRef, {
      status: 'approved',
      reviewedAt: now,
      reviewedBy: uid,
    });

    // دمج لا استبدال: يحافظ على أي بيانات عيادة سبق للمستخدم كتابتها
    // (لا يوجد عادة، لكن لا حاجة للافتراض).
    // ===== المرحلة 9: تصفير المُجمَّع عند الاعتماد =====
    //
    // دفاع ثانٍ خلف قاعدة الإنشاء: الحساب الذي وُثِّق للتوّ لم يستقبل
    // مراجعة واحدة بصفته طبيباً، فمُجمَّعه صفر بحكم التعريف. تثبيت ذلك هنا
    // يغلق أي قيمة سبقت إحكام القاعدة — حساباً أُنشئ قبل هذا الإصلاح
    // ببذرة تقييم، أو مستنداً كُتب بمسار إداري سابق.
    //
    // ولا يمسّ طبيباً قائماً: `approveDoctor` لا تعمل إلا على طلب معلَّق،
    // وطبيب نشط أُوقف ثم استُعيد يمرّ بـ `restoreDoctor` لا بهذه.
    tx.update(userRef, {
      role: 'doctor',
      isVerified: true,
      disabled: false,
      rating: 0,
      reviews: 0,
      ratingSum: 0,
      verificationStatus: 'approved',
      verificationSubmittedAt: app.submittedAt || now,
      verifiedAt: now,
      verifiedBy: uid,
    });

    writeAuditLog(tx, db, {
      actorAdminId: uid,
      action: 'doctor.approved',
      targetType: 'doctor',
      targetId: applicantUid,
      metadata: { applicationId: applicantUid },
    });

    return { alreadyApproved: false };
  });

  return { doctorId: applicantUid, alreadyApproved: outcome.alreadyApproved };
}

// ===================== رفض طلب توثيق طبيب =====================

async function rejectDoctorCore({ db, uid, auth, data }) {
  requireAdmin(auth);

  const payload = data && typeof data === 'object' ? data : {};
  const applicantUid = payload.uid;
  assertValidUid(applicantUid);
  const reason = normalizeText(payload.reason, 'سبب الرفض', { required: true });

  const appRef = db.collection('doctorApplications').doc(applicantUid);

  const outcome = await db.runTransaction(async (tx) => {
    const appSnap = await tx.get(appRef);
    if (!appSnap.exists) {
      fail('application-not-found', 'not-found', 'لا يوجد طلب توثيق بهذا المعرّف');
    }

    const app = appSnap.data();
    if (app.status === 'rejected') {
      // طلب مكرَّر — لا تُستبدَل سبب الرفض الأصلي بسبب جديد عن طريق الخطأ.
      return { alreadyRejected: true };
    }
    if (app.status === 'approved') {
      fail('application-approved', 'failed-precondition',
        'هذا الطلب مقبول بالفعل — استخدم الإيقاف لا الرفض');
    }
    if (app.status !== 'pending') {
      fail('application-not-pending', 'failed-precondition',
        'حالة الطلب لا تسمح بالرفض الآن');
    }

    tx.update(appRef, {
      status: 'rejected',
      reviewedAt: new Date(),
      reviewedBy: uid,
      rejectionReason: reason,
    });

    writeAuditLog(tx, db, {
      actorAdminId: uid,
      action: 'doctor.rejected',
      targetType: 'doctor',
      targetId: applicantUid,
      metadata: { applicationId: applicantUid, reason },
    });

    return { alreadyRejected: false };
  });

  return { doctorId: applicantUid, alreadyRejected: outcome.alreadyRejected };
}

// ===================== إيقاف طبيب موثَّق =====================

async function suspendDoctorCore({ db, uid, auth, data }) {
  requireAdmin(auth);

  const payload = data && typeof data === 'object' ? data : {};
  const targetUid = payload.uid;
  assertValidUid(targetUid);
  const reason = normalizeText(payload.reason, 'سبب الإيقاف', { required: true });

  const userRef = db.collection('users').doc(targetUid);

  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) {
      fail('user-not-found', 'not-found', 'لا يوجد مستخدم بهذا المعرّف');
    }
    const user = snap.data();

    if (user.role !== 'doctor' || user.isVerified !== true) {
      fail('doctor-not-active', 'failed-precondition',
        'لا يمكن إيقاف حساب لم يُوثَّق كطبيب بعد');
    }
    if (user.disabled === true) {
      // طلب مكرَّر — إيقاف بالفعل، لا حاجة لسجل تدقيق مكرَّر.
      return { alreadySuspended: true };
    }

    const now = new Date();
    tx.update(userRef, {
      disabled: true,
      verificationStatus: 'suspended',
      suspendedAt: now,
      suspendedBy: uid,
      suspensionReason: reason,
    });

    writeAuditLog(tx, db, {
      actorAdminId: uid,
      action: 'doctor.suspended',
      targetType: 'doctor',
      targetId: targetUid,
      metadata: { reason },
    });

    return { alreadySuspended: false };
  });

  return { doctorId: targetUid, alreadySuspended: outcome.alreadySuspended };
}

// ===================== استعادة طبيب موقوف =====================

async function restoreDoctorCore({ db, uid, auth, data }) {
  requireAdmin(auth);

  const payload = data && typeof data === 'object' ? data : {};
  const targetUid = payload.uid;
  assertValidUid(targetUid);

  const userRef = db.collection('users').doc(targetUid);

  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) {
      fail('user-not-found', 'not-found', 'لا يوجد مستخدم بهذا المعرّف');
    }
    const user = snap.data();

    if (user.role !== 'doctor') {
      fail('not-a-doctor', 'failed-precondition', 'هذا الحساب ليس حساب طبيب');
    }
    if (user.disabled !== true) {
      // طلب مكرَّر — نشط بالفعل.
      return { alreadyActive: true };
    }

    const now = new Date();
    tx.update(userRef, {
      disabled: false,
      verificationStatus: 'approved',
      restoredAt: now,
      restoredBy: uid,
    });

    writeAuditLog(tx, db, {
      actorAdminId: uid,
      action: 'doctor.unsuspended',
      targetType: 'doctor',
      targetId: targetUid,
      metadata: {},
    });

    return { alreadyActive: false };
  });

  return { doctorId: targetUid, alreadyActive: outcome.alreadyActive };
}

module.exports = {
  AppError,
  requireAdmin,
  approveDoctorCore,
  rejectDoctorCore,
  suspendDoctorCore,
  restoreDoctorCore,
};
