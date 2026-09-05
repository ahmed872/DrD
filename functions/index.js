const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// كان هنا ناقل بريد (nodemailer + Gmail) تستخدمه دالة `sendOTPEmail` وحدها.
// أُزيلت الدالة (انظر أسفل الملف) فلم يبق له مستخدم، وأُزيل معه الاعتماد على
// nodemailer ومتغيّرات EMAIL_USER / EMAIL_PASSWORD.

// إرسال الإشعارات بناءً على مواعيد الحضور وغيرها
exports.checkAppointments = functions.pubsub.schedule("every 5 minutes").onRun(async (context) => {
  const now = admin.firestore.Timestamp.now();
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
         createdAt: admin.firestore.FieldValue.serverTimestamp()
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
         createdAt: admin.firestore.FieldValue.serverTimestamp()
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
