/**
 * Cloud Functions لتطبيق DrD.
 *
 * ## ما كان مكسوراً
 *
 * دالة التذكير السابقة لم ترسل تذكيراً واحداً منذ كتابتها، لثلاثة أسباب
 * مجتمعة — كل واحد منها كافٍ وحده:
 *
 *   1. كانت تستعلم عن `status == "Scheduled"` بينما التطبيق يكتب `"Booked"`،
 *      فيعود الاستعلام فارغاً دائماً.
 *   2. كانت تقرأ `data.date` والتطبيق يكتب `appointmentDate`.
 *   3. كانت تقرأ `data.time` والتطبيق يكتب `startTime`.
 *
 * والسطر `if (!data.date || !data.time) continue;` كان يبتلع الخطأ بصمت،
 * فلم يظهر في السجلات ما يشير إلى وجود مشكلة.
 *
 * ## التوقيت
 *
 * الدوال تعمل بتوقيت UTC والمواعيد بتوقيت مصر المحلي. بدل حساب الفارق
 * وتتبّع التوقيت الصيفي داخل الخادم (مصدر شائع لتذكيرات تصل قبل موعدها
 * بساعتين)، صار العميل يكتب `startsAt` كطابع زمني مطلق وقت الحجز، والدالة
 * تقارن الطوابع مباشرة.
 *
 * المواعيد القديمة لا تحمل `startsAt`، فتُحسب من النصّين مع منطقة
 * [CLINIC_TIMEZONE] كحل احتياطي.
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
// المسار الفرعي مقصود: `require("firebase-functions")` يُحمّل فهرس v2 كاملاً،
// ومعه مزوّد Realtime Database الذي يسحب `@firebase/database-compat` ويطلب
// `@firebase/app` — وهي تبعية نظيرة غير مثبَّتة، فينهار التحميل. الاستيراد
// المباشر يتفادى ذلك ويقلّل زمن الإقلاع البارد أيضاً.
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

/** المنطقة الزمنية للعيادة — تُستخدم للمواعيد القديمة فقط. */
const CLINIC_TIMEZONE = "Africa/Cairo";

/**
 * كل الصيغ التي تعني "موعد قائم" في قاعدة البيانات.
 *
 * مطابقة لـ `AppointmentStatus` في `lib/core/constants/appointment_status.dart`.
 * البيانات تراكمت عبر إصدارات مختلفة من التطبيق، فالتسامح هنا ضروري وإلا
 * سقطت مواعيد حقيقية من التذكير.
 */
const ACTIVE_STATUSES = [
  "Booked", "booked",
  "Scheduled", "scheduled",
  "upcoming", "Upcoming",
  "pending", "Pending",
  "confirmed", "Confirmed",
];

/**
 * إزاحة منطقة زمنية بالدقائق عند لحظة معيّنة، مع مراعاة التوقيت الصيفي.
 *
 * تُحسب بمقارنة نفس اللحظة مُنسَّقة بالمنطقتين — أدق من ثابت مكتوب يدوياً،
 * لأن مصر تعمل بالتوقيت الصيفي منذ 2023.
 */
function timezoneOffsetMinutes(date, timeZone) {
  const asUtc = new Date(date.toLocaleString("en-US", { timeZone: "UTC" }));
  const asZone = new Date(date.toLocaleString("en-US", { timeZone }));
  return (asZone.getTime() - asUtc.getTime()) / 60000;
}

/** لحظة بدء الموعد، من `startsAt` أو من النصّين للمواعيد القديمة. */
function appointmentStart(data) {
  if (data.startsAt && typeof data.startsAt.toDate === "function") {
    return data.startsAt.toDate();
  }

  const dateStr = data.appointmentDate || data.date;
  const timeStr = data.startTime || data.time;
  if (!dateStr || !timeStr) return null;

  const dateParts = String(dateStr).split("T")[0].split("-");
  if (dateParts.length < 3) return null;

  const raw = String(timeStr).trim().toUpperCase();
  const timeParts = raw.replace(/[^0-9:]/g, "").split(":");
  if (!timeParts[0]) return null;

  let hour = parseInt(timeParts[0], 10);
  const minute = parseInt(timeParts[1] || "0", 10);
  if (Number.isNaN(hour) || Number.isNaN(minute)) return null;

  if (raw.includes("PM") && hour !== 12) hour += 12;
  if (raw.includes("AM") && hour === 12) hour = 0;

  // نبني اللحظة كأنها UTC ثم نطرح إزاحة المنطقة للحصول على اللحظة الحقيقية.
  const naive = Date.UTC(
    parseInt(dateParts[0], 10),
    parseInt(dateParts[1], 10) - 1,
    parseInt(dateParts[2], 10),
    hour,
    minute
  );
  const offset = timezoneOffsetMinutes(new Date(naive), CLINIC_TIMEZONE);
  return new Date(naive - offset * 60000);
}

/**
 * فحص المواعيد كل خمس دقائق: تذكير قبل ساعة، وتنبيه غياب بعد عشر دقائق.
 */
exports.checkAppointments = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: CLINIC_TIMEZONE,
    memory: "256MiB",
  },
  async () => {
    const now = Date.now();

    // نطاق ضيّق حول الوقت الحالي بدل قراءة كل المواعيد القائمة — الاستعلام
    // السابق كان يجلب المجموعة كاملة في كل تشغيل، وهو ما يصبح مكلفاً ثم
    // يتجاوز حدود القراءة مع نمو العيادة.
    const windowStart = new Date(now - 2 * 60 * 60 * 1000); // ساعتان للخلف
    const windowEnd = new Date(now + 2 * 60 * 60 * 1000);   // ساعتان للأمام

    const snapshot = await db
      .collection("appointments")
      .where("status", "in", ACTIVE_STATUSES)
      .where("startsAt", ">=", admin.firestore.Timestamp.fromDate(windowStart))
      .where("startsAt", "<=", admin.firestore.Timestamp.fromDate(windowEnd))
      .get();

    if (snapshot.empty) {
      logger.info("لا توجد مواعيد ضمن النطاق الحالي");
      return;
    }

    const batch = db.batch();
    let reminders = 0;
    let noShows = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const start = appointmentStart(data);
      if (!start) {
        logger.warn(`موعد بلا وقت صالح: ${doc.id}`);
        continue;
      }

      const minutesUntil = (start.getTime() - now) / 60000;

      // تذكير قبل الموعد بساعة (نافذة 55–60 دقيقة تغطي دورة الخمس دقائق).
      if (minutesUntil <= 60 && minutesUntil > 55 && !data.reminderSent) {
        batch.set(db.collection("notifications").doc(), {
          userId: data.patientId,
          type: "appointment_reminder",
          title: "تذكير بموعدك 🏥",
          body: `موعدك مع ${data.doctorName || "الطبيب"} بعد أقل من ساعة `
            + `(${data.startTime || ""}).`,
          appointmentId: doc.id,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        batch.update(doc.ref, { reminderSent: true });
        reminders++;
      }

      // مرّت عشر دقائق على الموعد ولم يسجّل الطبيب حضوراً.
      if (minutesUntil < -10 && !data.noShowWarningSent) {
        batch.set(db.collection("notifications").doc(), {
          userId: data.patientId,
          type: "appointment_missed",
          title: "تنبيه غياب ⚠️",
          body: `يبدو أنك لم تحضر موعدك مع ${data.doctorName || "الطبيب"} `
            + `الساعة ${data.startTime || ""}. يرجى التواصل مع العيادة.`,
          appointmentId: doc.id,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        batch.update(doc.ref, {
          noShowWarningSent: true,
          status: "PendingConfirmation",
        });
        noShows++;
      }
    }

    if (reminders || noShows) {
      await batch.commit();
    }
    logger.info(`تذكيرات: ${reminders} · تنبيهات غياب: ${noShows}`);
  }
);

// ملاحظة: دالة `sendOTPEmail` حُذفت.
//
// كانت تراقب مجموعة `otps` وترسل رمزاً بالبريد عبر nodemailer، لكن الشاشة
// التي كانت تكتب في تلك المجموعة (`firebase_phone_auth.dart`) أُزيلت — فلم
// يعد أي شيء في التطبيق يكتب فيها. حذفها يلغي أيضاً الحاجة إلى إعداد
// `EMAIL_USER` و`EMAIL_PASSWORD` وإلى تبعية nodemailer، فيصبح النشر أبسط.
