const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

// إعدادات البريد (استخدم Gmail مع App Password)
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: process.env.EMAIL_USER, // بريد Gmail
    pass: process.env.EMAIL_PASSWORD, // App Password من Gmail
  },
});

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

// مراقبة collection 'otps' وإرسال إيميل عند إضافة OTP جديد
exports.sendOTPEmail = functions.firestore
  .document("otps/{docId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const email = context.params.docId;
    const otpCode = data.code;
    const expiryTime = data.expiryTime;

    const mailOptions = {
      from: process.env.EMAIL_USER,
      to: email,
      subject: "🔐 رمز التحقق الخاص بك - Medical Appointment App",
      html: `
        <div style="font-family: 'Arial', sans-serif; direction: rtl; text-align: right; background-color: #f5f5f5; padding: 20px;">
          <div style="background-color: white; border-radius: 10px; padding: 30px; max-width: 500px; margin: 0 auto;">
            <h2 style="color: #2c3e50; margin-bottom: 20px;">مرحباً بك!</h2>
            
            <p style="color: #555; font-size: 16px; margin-bottom: 20px;">
              تم طلب رمز التحقق الخاص بك لتطبيق الحجز الطبي.
            </p>
            
            <div style="background-color: #e8f4f8; border-left: 4px solid #3498db; padding: 20px; margin: 20px 0; border-radius: 5px;">
              <p style="color: #999; margin: 0; font-size: 14px;">رمز التحقق:</p>
              <h1 style="color: #3498db; font-size: 40px; letter-spacing: 5px; margin: 10px 0; font-family: 'Courier New', monospace;">
                ${otpCode}
              </h1>
              <p style="color: #999; margin: 10px 0; font-size: 12px;">
                ⏱️ ينتهي الصلاحية في 10 دقائق
              </p>
            </div>
            
            <p style="color: #e74c3c; background-color: #fadbd8; padding: 15px; border-radius: 5px; margin: 20px 0;">
              ⚠️ لا تشارك هذا الرمز مع أحد. نحن لن نطلبه منك عبر البريد الإلكتروني.
            </p>
            
            <p style="color: #555; font-size: 14px; margin-top: 20px;">
              إذا لم تطلب هذا الرمز، يرجى تجاهل هذا البريد الإلكتروني.
            </p>
            
            <hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;">
            
            <p style="color: #999; font-size: 12px; text-align: center;">
              © 2026 Medical Appointment App | جميع الحقوق محفوظة
            </p>
          </div>
        </div>
      `,
    };

    try {
      await transporter.sendMail(mailOptions);
      console.log(`✅ Email sent to: ${email}`);
      
      // تحديث الـ Firestore لتسجيل أن الإيميل تم إرساله
      await admin.firestore().collection("otps").doc(email).update({
        emailSent: true,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return { success: true, message: "Email sent successfully" };
    } catch (error) {
      console.error(`❌ Error sending email to ${email}:`, error);
      return { success: false, error: error.message };
    }
  });
