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

// إرسال الإشعارات بناءً على مواعيد الحضور وغيرها
exports.checkAppointments = functions.pubsub.schedule("every 5 minutes").onRun(async (context) => {
  const now = Timestamp.now();
  const nowMillis = now.toMillis();
  const db = admin.firestore();
  const appointmentsSnapshot = await db.collection("appointments").where("status", "==", "Scheduled").get();

  const batch = db.batch();

  for (const doc of appointmentsSnapshot.docs) {
    const data = doc.data();
    if (!data.date || !data.time) continue;
    
    // تجميع تاريخ ووقت الموعد
    const parts = data.date.split("T")[0].split("-");
    const hms = data.time.split(":");
    let hour = parseInt(hms[0]);
    const minute = parseInt(hms[1].split(" ")[0]);
    if (data.time.includes("PM") && hour !== 12) hour += 12;
    if (data.time.includes("AM") && hour === 12) hour = 0;
    
    const appointmentDate = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]), hour, minute);
    const appointmentMillis = appointmentDate.getTime();
    
    const diffMins = (appointmentMillis - nowMillis) / 60000;

    // 1-hour prior reminder (تذكير قبلها بساعة)
    if (diffMins <= 60 && diffMins > 55 && !data.reminderSent) {
       // Save notification in firestore for the patient
       const notifRef = db.collection("notifications").doc();
       batch.set(notifRef, {
         userId: data.patientId,
         title: "تذكير بموعدك 🏥",
         body: `موعدك مع ${data.doctorName} بعد أقل من ساعة (${data.time}).`,
         read: false,
         createdAt: FieldValue.serverTimestamp()
       });
       batch.update(doc.ref, { reminderSent: true });
    }

    // 10-minutes after appointment logic (تحذير إذا لم يحضر المريض)
    // وهنا يجب على الطبيب أن يغيّر حالة الموعد لـ "Completed" أو "NoShow"
    // فلو مر 10 دقائق بعد الموعد ولسا Status بتاعه "Scheduled" معناه الطبيب معملوش Completed
    if (diffMins < -10 && !data.noShowWarningSent) {
      // إرسال تنبيه للمريض، وتغيير الحالة لـ Needs Confirmation من الطبيب مثلاً
       const notifRef = db.collection("notifications").doc();
       batch.set(notifRef, {
         userId: data.patientId,
         title: "تنبيه غياب ⚠️",
         body: `عذراً، يبدو أنك لم تحضر موعدك مع ${data.doctorName} الساعة ${data.time}. يرجى تأكيد حضورك مع الطبيب.`,
         read: false,
         createdAt: FieldValue.serverTimestamp()
       });
       batch.update(doc.ref, { noShowWarningSent: true, status: "PendingConfirmation" });
    }
  }

  await batch.commit();
  console.log("Appointment checks completed.");
  return null;
});

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
