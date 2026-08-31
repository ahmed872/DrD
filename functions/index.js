const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

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
