const functions = require("firebase-functions");
const admin = require("firebase-admin");
// الاستيراد الوسيطي لا الوصول عبر `admin.firestore.FieldValue`.
//
// وقت تشغيل محاكي الدوال يلفّ `firebase-admin` بوسيط لتوجيهه إلى المحاكيات،
// وتضيع في ذلك الخصائص الساكنة: `admin.firestore.FieldValue` تصبح
// `undefined` فتنهار الدالة عند أول طابع زمني. الاستيراد المباشر يعمل في
// الاثنين — المحاكي والإنتاج — فتصبح الدالة قابلة للاختبار فعلاً.
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

admin.initializeApp();

// كان هنا ناقل بريد (nodemailer + Gmail) تستخدمه دالة `sendOTPEmail` وحدها.
// أُزيلت الدالة (انظر أسفل الملف) فلم يبق له مستخدم، وأُزيل معه الاعتماد على
// nodemailer ومتغيّرات EMAIL_USER / EMAIL_PASSWORD.

// ─────────────────────────────────────────────────────────────────────────────
// أُزيلت: `checkAppointments` (تذكيرات المواعيد وتنبيهات الغياب)
//
// كانت `functions.pubsub.schedule("every 5 minutes")`، وكانت معطوبة بأربع
// طرق مستقلة — أي أنها لم تُنتج تذكيراً واحداً منذ كُتبت:
//
//   1. تُصفّي `status == "Scheduled"` — قيمة **لا يكتبها أي سطر** في التطبيق.
//      القيمة المعتمدة `"Booked"` (lib/core/constants/appointment_status.dart).
//   2. تقرأ `data.date` و`data.time` — والمخطّط الحالي `appointmentDate`
//      و`startTime`. فحتى لو طابقت الحالة، كان كل مستند يُتخطّى عند
//      `if (!data.date || !data.time) continue;`.
//   3. تكتب في `notifications` — مجموعة **لا يقرأها أي كود**: الخدمة الوحيدة
//      التي كانت تلمسها (`NotificationService`) غير مستدعاة من أي شاشة.
//   4. كانت تكتب `status: "PendingConfirmation"` على مواعيد لم تصل إليها.
//
// وكانت فوق ذلك المُشغِّل الوحيد لـCloud Scheduler في المشروع — أي التكلفة
// المتكرّرة الوحيدة (٨٬٦٤٠ تشغيلاً شهرياً بلا أثر).
//
// حُذفت بدل إصلاحها: التذكيرات ميزة منتج تحتاج قراراً (قناة الإرسال، التوقيت،
// من يقرأها)، لا ترقيعاً لكود لم يعمل قط. راجع docs/FUNCTIONS.md.
// ─────────────────────────────────────────────────────────────────────────────

// ============================================================================
// حساب متوسط تقييم الطبيب — على الخادم حصراً.
//
// كان هذا الحساب يجري في العميل: شاشة "مواعيدي" تقرأ `users/{doctorId}`
// وتكتب `rating` و`reviews` في معاملة. وكانت قاعدة الأمان تسمح لأي مستخدم
// مسجَّل بزيادة العدّاد بواحد وكتابة أي قيمة في المتوسط — أي أن رقم الثقة
// الوحيد في التطبيق كان تحت سيطرة العميل. حلقة بسيطة تُنزل منافساً إلى صفر.
//
// قاعدة أمان لا تستطيع التحقّق من صحة *حساب* متوسط، لذا لا حل إلا نقله إلى
// الخادم. الدالة تعيد الحساب من الصفر عند كل كتابة في `reviews` بدل التعديل
// التزايدي: أبطأ نظرياً، لكنه لا ينحرف أبداً ويصحّح نفسه لو اختلّت البيانات.
//
// التكلفة: قراءة واحدة لكل مراجعة قائمة للطبيب، مرة عند كل مراجعة جديدة.
// عند عشرات المراجعات لكل طبيب هذا لا يُذكر ضمن الحصة المجانية.
exports.syncDoctorRating = functions.firestore
  .document("reviews/{reviewId}")
  .onWrite(async (change, context) => {
    const after = change.after.exists ? change.after.data() : null;
    const before = change.before.exists ? change.before.data() : null;
    const doctorId = (after && after.doctorId) || (before && before.doctorId);
    if (!doctorId) return null;

    const db = admin.firestore();
    const snapshot = await db
      .collection("reviews")
      .where("doctorId", "==", doctorId)
      .get();

    let sum = 0;
    let count = 0;
    snapshot.forEach((doc) => {
      const value = doc.data().rating;
      // القيم خارج النطاق تُتجاهل بدل أن تُفسد المتوسط. القاعدة تمنعها عند
      // الكتابة، وهذا حارس ثانٍ للبيانات القديمة.
      if (typeof value === "number" && value >= 1 && value <= 5) {
        sum += value;
        count += 1;
      }
    });

    const rating = count === 0 ? 0 : Math.round((sum / count) * 10) / 10;

    await db
      .collection("users")
      .doc(doctorId)
      .set({ rating, reviews: count }, { merge: true });

    console.log(`Doctor ${doctorId}: rating=${rating} from ${count} review(s)`);
    return null;
  });

// ============================================================================
// أُزيلت دالة `sendOTPEmail`.
//
// كانت تستمع على `otps/{docId}` وترسل بريداً إلى **معرّف المستند نفسه**:
//
//     const email = context.params.docId;   // يختاره الطالب
//     await transporter.sendMail({ to: email, ... });
//
// وكانت قاعدة الأمان المقابلة `allow create: if true` — بلا مصادقة. أي أن أي
// شخص على الإنترنت كان يستطيع إنشاء مستند باسم أي بريد إلكتروني فيُرسل حساب
// Gmail الخاص بالمشروع رسالة إلى ذلك العنوان، بلا حد ولا تحقق. ذلك يكفي
// لإغراق شخص بالرسائل، ولاستنفاد حصة الإرسال، ولتعليق حساب Gmail نفسه.
//
// ولم يكن للدالة أي مستخدم: لا يوجد سطر واحد في lib/ يكتب في `otps`، وشاشة
// "نسيت كلمة المرور" تستدعي `FirebaseAuth.sendPasswordResetEmail` مباشرة،
// وشاشة التسجيل تنشئ الحساب بلا رمز تحقق. أُزيلت الدالة والقاعدة معاً.
// ============================================================================

// ============================================================================
// ترقية الطبيب بعد قبول طلبه — المرحلة الثانية.
//
// ## لماذا الترقية هنا وليست في القاعدة
//
// قواعد Firestore تستطيع أن تمنع كتابة `role`، لكنها لا تستطيع أن تكتبه.
// ولو فُتح لأي عميل — ولو للمشرف — مسارُ كتابةٍ إلى `users/{uid}.role`
// لصار الدور حقلاً يتحكم فيه العميل، وهو بالضبط ما أُغلق في المرحلة صفر.
//
// لذلك السلطة مقسومة قسمة صريحة:
//   - **القرار** يُسجَّل في `doctor_applications/{uid}` — يكتبه المشرف
//     بقاعدة أمان تفرض هويته وسبب الرفض والانتقال المسموح.
//   - **الصلاحية** تُكتب في `users/{uid}` — من هنا وحده.
//
// ## اتساق الحالتين
//
// بين القرار والصلاحية نافذة زمنية بالمللي ثانية. النافذة **تفشل مغلقة**:
// إن لم تُنفَّذ هذه الدالة بقي المستخدم مريضاً، فلا تُمنح صلاحية بغير قرار.
// العكس — صلاحية بلا قرار — مستحيل بنيوياً لأن لا مسار آخر يكتب `role`.
//
// والدالة **متوافقة مع التكرار** (idempotent): تشتقّ الحالة المطلوبة من
// حالة الطلب في كل مرة بدل أن تعدّل تزايدياً، فإعادة المحاولة بعد فشل
// جزئي تصل إلى النتيجة نفسها.
// ============================================================================

/** حالة الطلب التي تمنح صلاحية الطبيب. */
const APPROVED = "approved";

/**
 * يكتب سطراً في سجل التدقيق. لا يقرأه أي عميل — القاعدة تمنع ذلك.
 *
 * `subjectId` هو ما يخصّه الإجراء: معرّف الطلب في قرارات الأطباء، ومعرّف
 * السجل في السجلات السريرية. `action` هو ما يميّز النوع.
 */
function auditEntry(batch, db, { action, subjectId, actorId, details }) {
  batch.set(db.collection("audit_logs").doc(), {
    action,
    subjectId,
    actorId: actorId || null,
    details: details || null,
    at: FieldValue.serverTimestamp(),
  });
}

exports.onDoctorApplicationDecision = functions.firestore
  .document("doctor_applications/{uid}")
  .onWrite(async (change, context) => {
    const uid = context.params.uid;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    // الحذف ممنوع بالقاعدة؛ هذا حارس ثانٍ لا أكثر.
    if (!after) return null;

    const beforeStatus = before ? before.status : null;
    const afterStatus = after.status;
    if (beforeStatus === afterStatus) return null;

    const db = admin.firestore();
    const batch = db.batch();
    const userRef = db.collection("users").doc(uid);

    if (afterStatus === APPROVED) {
      // الترقية. `merge` لا `set` — لئلا تُمحى بيانات المستخدم القائمة.
      //
      // التخصص يُنسخ من الطلب ليبدأ ملف الطبيب مملوءاً بما راجعه المشرف
      // فعلاً، بدل أن يظهر في بحث المرضى بتخصص فارغ.
      batch.set(
        userRef,
        {
          role: "doctor",
          isVerified: true,
          verificationStatus: APPROVED,
          specialization: after.specialty || "",
          doctorApprovedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      auditEntry(batch, db, {
        action: "doctor_application_approved",
        subjectId: uid,
        actorId: after.reviewedBy,
        details: { specialty: after.specialty || null },
      });
    } else if (beforeStatus === APPROVED) {
      // مسار الخادم وحده: القاعدة لا تسمح بالخروج من `approved` من أي عميل.
      // موجود هنا حتى يبقى مستند المستخدم متسقاً لو تدخّل الخادم يوماً.
      batch.set(
        userRef,
        {
          role: "patient",
          isVerified: false,
          verificationStatus: afterStatus,
        },
        { merge: true }
      );
      auditEntry(batch, db, {
        action: "doctor_access_revoked",
        subjectId: uid,
        actorId: after.reviewedBy,
        details: { newStatus: afterStatus },
      });
    } else if (afterStatus === "rejected") {
      // الرفض لا يغيّر الدور — المستخدم كان مريضاً ويبقى مريضاً.
      auditEntry(batch, db, {
        action: "doctor_application_rejected",
        subjectId: uid,
        actorId: after.reviewedBy,
        details: { reason: after.rejectionReason || null },
      });
    } else if (afterStatus === "pending") {
      auditEntry(batch, db, {
        action: before
          ? "doctor_application_resubmitted"
          : "doctor_application_submitted",
        subjectId: uid,
        actorId: uid,
        details: { specialty: after.specialty || null },
      });
    }

    await batch.commit();
    console.log(
      `doctor_application ${uid}: ${beforeStatus || "none"} -> ${afterStatus}`
    );
    return null;
  });

// ============================================================================
// نسخ تصحيح السجل السريري وتدقيقه — المرحلة الثالثة.
//
// ## لماذا نحفظ النسخة السابقة
//
// السجل الطبي قابل للتصحيح من مؤلِّفه — وهذا صحيح منتَجياً: طبيب أخطأ في
// كتابة تشخيص يجب أن يصحّحه. لكن التصحيح بلا أثر يعني أن ما قرأه المريض
// أمس قد لا يكون ما يقرأه اليوم، بلا ما يدلّ على ذلك.
//
// وهذا شرط للمرحلة الرابعة تحديداً: حين يشارك المريض سجلاً مع طبيب ثانٍ،
// يجب أن يبقى ممكناً تحديد **ما شُورك ومتى** حتى لو عُدِّل السجل بعدها.
// نسخة ما قبل التعديل هي ما يجعل ذلك ممكناً دون إعادة تصميم النموذج.
//
// النسخ تُكتب من هنا وحده: القاعدة `allow write: if false` على
// `revisions/`، والدوال تتجاوز القواعد.
// ============================================================================

/** الحقول السريرية التي يُحفَظ تغيّرها. الهوية ثابتة أصلاً بحكم القاعدة. */
const CLINICAL_FIELDS = [
  "diagnosis",
  "clinicalNotes",
  "treatmentPlan",
  "followUpNotes",
  "followUpDate",
];

/** هل تغيّر شيء سريري فعلاً؟ */
function clinicalContentChanged(before, after) {
  return CLINICAL_FIELDS.some(
    (f) => (before[f] || "") !== (after[f] || "")
  );
}

exports.onEncounterWritten = functions.firestore
  .document("encounters/{encounterId}")
  .onWrite(async (change, context) => {
    const encounterId = context.params.encounterId;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    // الحذف ممنوع بالقاعدة؛ هذا حارس ثانٍ.
    if (!after) return null;

    const db = admin.firestore();
    const batch = db.batch();

    if (!before) {
      auditEntry(batch, db, {
        action: "encounter.created",
        subjectId: encounterId,
        actorId: after.doctorId,
        details: { patientId: after.patientId, appointmentId: after.appointmentId },
      });
    } else {
      // تعديل لا يمسّ المحتوى السريري (طابع زمني مثلاً) لا يستحق نسخة.
      if (!clinicalContentChanged(before, after)) return null;

      // النسخة تحمل ما كان عليه السجل **قبل** هذا التعديل.
      const revisionRef = db
        .collection("encounters")
        .doc(encounterId)
        .collection("revisions")
        .doc();
      batch.set(revisionRef, {
        ...CLINICAL_FIELDS.reduce((acc, f) => {
          acc[f] = before[f] === undefined ? null : before[f];
          return acc;
        }, {}),
        // الهوية تُنسخ معها حتى تبقى النسخة مفهومة بذاتها لو قُرئت وحدها.
        encounterId,
        patientId: before.patientId,
        doctorId: before.doctorId,
        appointmentId: before.appointmentId,
        encounterDate: before.encounterDate,
        supersededAt: FieldValue.serverTimestamp(),
      });

      auditEntry(batch, db, {
        action: "encounter.updated",
        subjectId: encounterId,
        actorId: after.doctorId,
        details: {
          patientId: after.patientId,
          revisionId: revisionRef.id,
          changed: CLINICAL_FIELDS.filter(
            (f) => (before[f] || "") !== (after[f] || "")
          ),
        },
      });
    }

    await batch.commit();
    console.log(`encounter ${encounterId}: ${before ? "updated" : "created"}`);
    return null;
  });

// ============================================================================
// بناء لقطة المشاركة الطبية — المرحلة الرابعة.
//
// ## لماذا يكتب الخادمُ اللقطة
//
// هذا هو الشرط الأمني المحوري في هذه الميزة. لو كتب المريض المحتوى السريري
// بنفسه لاستطاع **اختلاق تشخيص** ونسبته إلى طبيبه ثم عرضه على طبيب آخر —
// تزوير طبي بعواقب علاجية حقيقية، لا مجرد خلل بيانات. لذلك المريض يرسل
// معرّفات سجلاته فقط، والدالة تقرأها بصلاحية الخادم وتتحقّق أنه يملكها.
//
// ## لماذا لقطة لا وصول حيّ
//
// المريض وافق على نصّ بعينه رآه لحظة المشاركة. لو قرأ الطبيب السجل الحيّ
// لتغيّر ما يراه كلما عدّله الطبيب المؤلِّف — أي أن الموافقة تنسحب على محتوى
// لم يوافق عليه أحد. اللقطة تربط الموافقة بالمحتوى لا بالموقع.
//
// `sourceUpdatedAt` يثبّت أي نسخة من السجل التُقطت، ويتقاطع مع نسخ
// `revisions/` من المرحلة الثالثة.
// ============================================================================

/** الحقول السريرية التي تُنسخ إلى اللقطة. */
function buildSnapshot(encounterId, e) {
  return {
    encounterId,
    encounterDate: e.encounterDate || "",
    // اسم الطبيب المؤلِّف وتخصصه — يحتاجهما المستقبِل ليفهم السياق.
    // معرّفه الخام لا يُنسخ: ليس ضرورياً للاستشارة.
    doctorName: e.doctorName || "",
    doctorSpecialization: e.doctorSpecialization || "",
    diagnosis: e.diagnosis || "",
    clinicalNotes: e.clinicalNotes || "",
    treatmentPlan: e.treatmentPlan || "",
    followUpNotes: e.followUpNotes || "",
    followUpDate: e.followUpDate || "",
    // أي نسخة من السجل التُقطت — يبقى معروفاً حتى لو عُدِّل السجل لاحقاً.
    sourceUpdatedAt: e.updatedAt || null,
  };
}

exports.onMedicalShareWritten = functions.firestore
  .document("medical_shares/{shareId}")
  .onWrite(async (change, context) => {
    const shareId = context.params.shareId;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    // الحذف ممنوع بالقاعدة؛ حارس ثانٍ.
    if (!after) return null;

    const db = admin.firestore();

    // الإلغاء: تدوين فقط. الوصول انقطع بالقاعدة نفسها لحظة تغيّر الحالة.
    if (before && before.status !== after.status) {
      if (after.status === "revoked") {
        const batch = db.batch();
        auditEntry(batch, db, {
          action: "medical_share.revoked",
          subjectId: shareId,
          actorId: after.patientId,
          details: {
            recipientDoctorId: after.recipientDoctorId,
            encounterIds: after.encounterIds || [],
          },
        });
        await batch.commit();
      }
      return null;
    }

    // ما عدا الإنشاء المعلّق لا يعني الدالة شيئاً. والشرط يجعلها متوافقة
    // مع التكرار: إعادة تشغيلها على مشاركة نشطة لا تعيد بناء اللقطة.
    if (before || after.status !== "pending") return null;

    const patientId = after.patientId;
    const requested = Array.from(new Set(after.encounterIds || []));

    const reject = async (reason) => {
      await change.after.ref.update({
        status: "rejected",
        rejectionReason: reason,
        rejectedAt: FieldValue.serverTimestamp(),
      });
      console.log(`medical_share ${shareId}: rejected — ${reason}`);
    };

    if (requested.length === 0) {
      return reject("لم تُحدَّد أي سجلات للمشاركة.");
    }

    // قراءة السجلات دفعةً واحدة بدل قراءة لكل معرّف.
    const refs = requested.map((id) => db.collection("encounters").doc(id));
    const docs = await db.getAll(...refs);

    const snapshots = [];
    for (const snap of docs) {
      if (!snap.exists) {
        return reject("أحد السجلات المختارة لم يعد موجوداً.");
      }
      const e = snap.data();
      // **الفحص الحاسم**: المريض يملك هذا السجل فعلاً.
      //
      // القاعدة لا تستطيع فحص قائمة معرّفات، فالسلطة هنا. بدونه يستطيع
      // مريض أن يشارك سجل مريض آخر بمجرد معرفة معرّفه.
      if (e.patientId !== patientId) {
        return reject("لا يمكن مشاركة سجل لا يخصّك.");
      }
      snapshots.push(buildSnapshot(snap.id, e));
    }

    const batch = db.batch();
    batch.update(change.after.ref, {
      snapshots,
      status: "active",
      activatedAt: FieldValue.serverTimestamp(),
    });
    auditEntry(batch, db, {
      action: "medical_share.created",
      subjectId: shareId,
      actorId: patientId,
      details: {
        recipientDoctorId: after.recipientDoctorId,
        encounterIds: requested,
        snapshotCount: snapshots.length,
      },
    });
    await batch.commit();

    console.log(
      `medical_share ${shareId}: active with ${snapshots.length} snapshot(s)`
    );
    return null;
  });

// ============================================================================
// الملف العام للطبيب — إسقاط يكتبه الخادم وحده.
//
// كانت قاعدة `users` تسمح لأي مستخدم مسجَّل بقراءة مستند أي طبيب، لأن دليل
// الأطباء يحتاج الاسم والتخصّص والسعر. لكن قواعد Firestore لا تُرشِّح الحقول:
// السماح بقراءة المستند يمنحه كاملاً — الهاتف والبريد وتاريخ الميلاد والنوع.
//
// الحل هو الفصل على مستوى المستند لا الحقل، وهو نفس ما طُبِّق على `slots`
// حين نُزع منها `patientIds`. هذه الدالة تحافظ على الإسقاط متزامناً.
//
// لماذا يكتبه الخادم ولا يكتبه الطبيب نفسه؟ لأن ملفاً عاماً يكتبه صاحبه
// يستطيع أن يخالف مستنده الأصلي — تخصّص أو سعر معلن غير المسجَّل — وأن يبقى
// منشوراً بعد خفض دوره. الاشتقاق من مصدر واحد يجعل ذلك مستحيلاً بنيوياً.
// ============================================================================

/// الحقول التي يراها المريض في الدليل وشاشة الحجز — ولا شيء غيرها.
///
/// كل ما ليس في هذه القائمة يبقى داخل `users` ولا يخرج منه: `phone`, `email`,
/// `birthDate`, `gender`, `emailVerified`, `role`, `createdAt`.
/// يحرس ذلك اختبار في test/firestore_rules/rules.test.js.
const PUBLIC_DOCTOR_FIELDS = [
  "name",
  "nameEn",
  "clinicNameAr",
  "clinicNameEn",
  "clinicLocation",
  "specialization",
  "specializationEn",
  "bio",
  "bioEn",
  "price",
  "sessionDuration",
  "maxPatientsPerSlot",
  "bookingSystemType",
  "workingHours",
  "workingDays",
  "rating",
  "reviews",
];

exports.syncDoctorPublicProfile = functions.firestore
  .document("users/{userId}")
  .onWrite(async (change, context) => {
    const userId = context.params.userId;
    const after = change.after.exists ? change.after.data() : null;
    const db = admin.firestore();
    const profileRef = db.collection("doctor_profiles").doc(userId);

    // ثلاث حالات تُخرج المستخدم من الدليل: لم يعد طبيباً، أو حُذف مستنده،
    // أو حُذف حسابه. الحذف هنا غير مشروط عمداً — حذف مستند غير موجود لا
    // يفشل، ومحاولة قراءته أولاً تضيف قراءة بلا فائدة.
    const isPublishable =
      after && after.role === "doctor" && after.deleted !== true;

    if (!isPublishable) {
      await profileRef.delete();
      console.log(`doctor_profiles/${userId}: removed`);
      return null;
    }

    const profile = {
      doctorId: userId,
      updatedAt: FieldValue.serverTimestamp(),
    };
    for (const field of PUBLIC_DOCTOR_FIELDS) {
      if (after[field] !== undefined) profile[field] = after[field];
    }

    // `set` بلا `merge` عمداً: لو أفرغ الطبيب نبذته، يجب أن تختفي من الملف
    // العام أيضاً. الدمج كان سيُبقي القيمة القديمة منشورة إلى الأبد.
    await profileRef.set(profile);
    console.log(`doctor_profiles/${userId}: synced`);
    return null;
  });

// ============================================================================
// حذف الحساب — الدالة التي كانت قاعدة `users` تَعِد بها ولم تكن موجودة.
//
// المتطلّب ليس «امسح كل شيء»: السجل السريري وثيقة طبية، ومحوه بضغطة من
// المريض يمحو أيضاً ما يحتاجه الطبيب والعيادة. لذلك التقسيم هنا صريح:
//
//   يُمحى     — بيانات التعريف الشخصية، وفهرس الجوال، والملف العام، وحساب
//               المصادقة نفسه (فلا يمكن تسجيل الدخول بعدها).
//   يُلغى     — المواعيد القائمة (مع تحرير عدّاد الخانة)، وكل مشاركة طبية
//               نشطة أو معلّقة، صادرة كانت أم واردة.
//   يُجهَّل    — الاسم في المراجعات العلنية، فيبقى التقييم صادقاً بلا صاحب.
//   يبقى     — `encounters` كما هي: سجل الزيارة يخصّ الطبيب والعيادة أيضاً،
//               ولا يملك أحد طرفيه محوه من جانب واحد.
//
// وترتيب الخطوات ليس اعتباطياً: المصادقة تُحذف **أخيراً**. لو حُذفت أولاً
// وفشلت خطوة لاحقة، لبقي المستخدم بلا وسيلة دخول وببيانات حيّة — أسوأ
// النتيجتين. وحالة الطلب لا تصبح `completed` إلا بعد نجاح كل خطوة.
// ============================================================================

exports.onDeletionRequested = functions.firestore
  .document("deletion_requests/{userId}")
  .onCreate(async (snap, context) => {
    const userId = context.params.userId;
    const db = admin.firestore();
    const requestRef = snap.ref;
    const steps = [];

    try {
      const userSnap = await db.collection("users").doc(userId).get();
      const user = userSnap.exists ? userSnap.data() : null;

      // ── 1. المواعيد القائمة: إلغاء وتحرير الخانة ──────────────────────
      // العدّاد يُنقَص هنا كما ينقصه الإلغاء العادي، وإلا بقيت خانات تبدو
      // ممتلئة للأبد بحجوزات صاحبها لم يعد موجوداً.
      const activeAppointments = await db
        .collection("appointments")
        .where("patientId", "==", userId)
        .where("status", "==", "Booked")
        .get();

      for (const doc of activeAppointments.docs) {
        const slotId = doc.data().slotId;
        await db.runTransaction(async (tx) => {
          if (slotId) {
            const slotRef = db.collection("slots").doc(slotId);
            const slotSnap = await tx.get(slotRef);
            if (slotSnap.exists) {
              const booked = Number(slotSnap.data().bookedCount) || 0;
              tx.update(slotRef, {
                bookedCount: Math.max(0, booked - 1),
                updatedAt: FieldValue.serverTimestamp(),
              });
            }
          }
          tx.update(doc.ref, {
            status: "Cancelled",
            cancelledAt: FieldValue.serverTimestamp(),
          });
        });
      }
      steps.push(`appointments_cancelled:${activeAppointments.size}`);

      // ── 2. المشاركات الطبية: إلغاء الصادر والوارد ────────────────────
      // الطرفان معاً: مريض يحذف حسابه يسحب ما شاركه، وطبيب يحذف حسابه لا
      // يجوز أن يبقى في صندوقه سجل مريض حيّ.
      let revoked = 0;
      for (const field of ["patientId", "recipientDoctorId"]) {
        const shares = await db
          .collection("medical_shares")
          .where(field, "==", userId)
          .where("status", "in", ["pending", "active"])
          .get();
        for (const doc of shares.docs) {
          await doc.ref.update({
            status: "revoked",
            revokedAt: FieldValue.serverTimestamp(),
          });
          revoked += 1;
        }
      }
      steps.push(`shares_revoked:${revoked}`);

      // ── 3. المراجعات العلنية: تجهيل بلا حذف ──────────────────────────
      // حذف المراجعة يغيّر متوسط الطبيب بأثر رجعي بسبب مغادرة مريض، وهو
      // تشويه للتقييم لا حماية للخصوصية. الاسم وحده هو البيان الشخصي.
      const reviews = await db
        .collection("reviews")
        .where("patientId", "==", userId)
        .get();
      for (const doc of reviews.docs) {
        await doc.ref.update({ patientName: "مريض محذوف" });
      }
      steps.push(`reviews_anonymised:${reviews.size}`);

      // ── 4. فهرس الجوال: حذف ليعود الرقم قابلاً للتسجيل ───────────────
      if (user && user.phone) {
        await db.collection("phone_index").doc(String(user.phone)).delete();
        steps.push("phone_index_deleted");
      }

      // ── 5. مستند المستخدم: تجهيل لا حذف ──────────────────────────────
      // الحذف الكامل يترك `encounters` و`appointments` تشير إلى معرّف بلا
      // مستند، فتنكسر كل شاشة تعرض اسماً. التجهيل يحفظ سلامة الإشارات
      // ويمحو البيان الشخصي في آن.
      //
      // `deleted: true` هو ما يمنع `syncDoctorPublicProfile` من إعادة نشر
      // ملف عام لطبيب حذف حسابه.
      if (userSnap.exists) {
        await userSnap.ref.set(
          {
            name: "حساب محذوف",
            phone: FieldValue.delete(),
            email: FieldValue.delete(),
            birthDate: FieldValue.delete(),
            gender: FieldValue.delete(),
            emailVerified: FieldValue.delete(),
            deleted: true,
            deletedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        steps.push("user_anonymised");
      }

      // ── 5‑ب. طلب الانضمام: تجهيل لا حذف ──────────────────────────────
      //
      // مستند `doctor_applications/{uid}` يحمل اسم المتقدّم ونبذته المهنية
      // وتخصّصه — بيان شخصي يبقى مقروءاً للمشرف بعد حذف الحساب.
      //
      // ولا يُحذف كاملاً: هو سجل قرار إداري (مَن وافق ومتى ولماذا رُفض)،
      // وحذفه يمحو أثر الترقية من التاريخ. فيُجهَّل البيان الشخصي ويبقى القرار.
      const applicationRef = db.collection("doctor_applications").doc(userId);
      const applicationSnap = await applicationRef.get();
      if (applicationSnap.exists) {
        await applicationRef.set(
          {
            applicantName: "حساب محذوف",
            professionalBio: FieldValue.delete(),
            applicantNotes: FieldValue.delete(),
            anonymisedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        steps.push("application_anonymised");
      }

      // ── 5‑ج. صلاحية الإشراف ──────────────────────────────────────────
      //
      // معرّفات Firebase لا يُعاد استخدامها، فبقاء `admins/{uid}` بعد حذف
      // الحساب لا يمنح أحداً شيئاً عملياً. لكن قائمة المشرفين هي **تعريف
      // الصلاحية** في هذا النظام (`exists()` وحده)، وتركها تحمل مداخل
      // لحسابات غير موجودة يجعل مراجعتها أصعب — وهي أول ما يُراجَع عند أي
      // شكّ أمني.
      const adminRef = db.collection("admins").doc(userId);
      if ((await adminRef.get()).exists) {
        await adminRef.delete();
        steps.push("admin_revoked");
      }

      // ── 6. الملف العام ───────────────────────────────────────────────
      // المحفّز في الخطوة السابقة يحذفه، لكن الاعتماد على تسلسل محفّزات
      // غير مضمون الترتيب. الحذف الصريح يجعل النتيجة مؤكدة.
      await db.collection("doctor_profiles").doc(userId).delete();
      steps.push("public_profile_deleted");

      // ── 7. حساب المصادقة — أخيراً ────────────────────────────────────
      // بعد هذه الخطوة لا يمكن تسجيل الدخول. تنفيذها آخراً يضمن أنه لو فشلت
      // خطوة قبلها، بقي للمستخدم حساب يستطيع طلب الحذف به مرة أخرى.
      try {
        await admin.auth().deleteUser(userId);
        steps.push("auth_deleted");
      } catch (e) {
        // `user-not-found` نتيجة صحيحة لا عطل: الحساب محذوف بالفعل.
        if (e && e.code === "auth/user-not-found") {
          steps.push("auth_already_absent");
        } else {
          throw e;
        }
      }

      const batch = db.batch();
      batch.update(requestRef, {
        status: "completed",
        completedAt: FieldValue.serverTimestamp(),
        steps,
      });
      auditEntry(batch, db, {
        action: "account_deleted",
        subjectId: userId,
        actorId: userId,
        details: { steps },
      });
      await batch.commit();

      console.log(`account ${userId} deleted: ${steps.join(", ")}`);
      return null;
    } catch (error) {
      // الفشل يُسجَّل ولا يُدَّعى اكتماله. المستخدم يرى «لم يكتمل» لا «تم».
      console.error(`account deletion failed for ${userId}`, error);
      const batch = db.batch();
      batch.update(requestRef, {
        status: "failed",
        failedAt: FieldValue.serverTimestamp(),
        error: String((error && error.message) || error),
        steps,
      });
      auditEntry(batch, db, {
        action: "account_deletion_failed",
        subjectId: userId,
        actorId: userId,
        details: { steps, error: String((error && error.message) || error) },
      });
      await batch.commit();
      return null;
    }
  });
