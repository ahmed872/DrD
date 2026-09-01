/**
 * إشعارات دورة حياة الموعد — مصدر حقيقة واحد لمحتوى الإشعار، ومعرّفه
 * الحتمي، وتسليمه عبر Push.
 *
 * ## لماذا هنا لا في العميل
 *
 * `lib/core/services/notification_service.dart` كان يكتب مباشرة على
 * `notifications` من التطبيق — مسار كانت `firestore.rules` تغلقه أصلاً
 * (`allow create: if false`)، فكل استدعاء له كان يفشل بصمت ويُسجَّل خطأً
 * محلياً لا أكثر؛ لم يكن يعمل قط. هذا الملف هو الكاتب الوحيد الفعلي، من
 * Admin SDK داخل نفس معاملة الحجز/الإلغاء/إعادة الجدولة — فلا يوجد إشعار
 * بلا حدث خادم حقيقي وراءه.
 *
 * ## الشكل: مستند إشعار واحد يخدم القناتين
 *
 * لا حاجة لمجموعة `notificationEvents` أو نمط outbox منفصل — مستند
 * `notifications/{id}` نفسه هو الـ outbox: يُكتب داخل معاملة الحدث
 * (فيصبح in-app فوراً، مضموناً بنفس ذرّية الحدث)، ثم `deliverPendingPush`
 * تُستدعى **بعد** انتهاء المعاملة (لا نداء شبكة FCM داخل معاملة Firestore
 * أبداً) لتحديث حقل `push` الفرعي على نفس المستند بنتيجة محاولة التسليم.
 * فشل الدفع لا يمسّ صحة الموعد ولا يحذف الإشعار — يبقى ظاهراً داخل
 * التطبيق دائماً.
 *
 * ## الحتمية والتكرار
 *
 * معرّف كل إشعار حدث (لا تذكير) دالة في (`appointmentId`, `type`,
 * `recipientRole`) — نفس فلسفة `SlotId`. الكود المستدعي (`booking.js`,
 * `lifecycle.js`) لا يستدعي `queueNotification` إلا على المسار غير
 * المكرَّر أصلاً (`duplicate === false`)، فلا داعٍ لفحص وجود مسبق هنا.
 * التذكيرات مختلفة: `sendAppointmentReminders` تستدعيها دورياً على نفس
 * المواعيد، فتستخدم `create()` صراحة (يفشل لو existed) بدل `set()`.
 */

const admin = require('firebase-admin');

const NOTIFICATION_TYPES = Object.freeze({
  BOOKING_CONFIRMED: 'booking_confirmed',
  NEW_APPOINTMENT: 'new_appointment',
  BOOKING_CANCELLED: 'booking_cancelled',
  APPOINTMENT_CANCELLED: 'appointment_cancelled',
  BOOKING_RESCHEDULED: 'booking_rescheduled',
  APPOINTMENT_RESCHEDULED: 'appointment_rescheduled',
  REMINDER_24H: 'reminder_24h',
  REMINDER_2H: 'reminder_2h',
  DOCTOR_REMINDER: 'doctor_reminder',
});

/** معرّف حتمي لإشعار حدث واحد — يمنع التكرار بمعزل عن أي حالة إضافية. */
function notificationIdFor(appointmentId, type, recipientRole) {
  return `${appointmentId}__${type}__${recipientRole}`;
}

const pad = (n) => String(n).padStart(2, '0');

/** يهيّئ HH:mm إلى نص عربي مبسَّط دون مكتبة تاريخ خارجية. */
function formatArabicTime(time) {
  const [hStr, mStr] = String(time).split(':');
  let h = parseInt(hStr, 10);
  const m = mStr || '00';
  const period = h >= 12 ? 'م' : 'ص';
  h = h % 12;
  if (h === 0) h = 12;
  return `${h}:${m} ${period}`;
}

/**
 * محتوى الإشعار — جدول ثابت واحد لكل نوع، بدل نصوص مبعثرة في كل ملف.
 *
 * `lang` اختياري ويسقط افتراضياً إلى العربية، مطابقةً لبقية التطبيق
 * (لا توجد بيانات تفضيل لغة للمستخدم في المخطط الحالي بعد). بنية الجدول
 * (`ar`/`en` لكل نوع) جاهزة لإضافة الإنجليزية لاحقاً بلا تغيير هيكلي —
 * يكفي ملء مفتاح `en` عند توفر لغة المستخدم فعلياً.
 */
function buildContent(type, ctx, lang = 'ar') {
  const time = ctx.startTime ? formatArabicTime(ctx.startTime) : '';
  const table = {
    [NOTIFICATION_TYPES.BOOKING_CONFIRMED]: {
      ar: {
        title: 'تم تأكيد حجزك ✅',
        body: `موعدك مع ${ctx.doctorName || 'الطبيب'} يوم ${ctx.date} الساعة ${time}.`,
      },
    },
    [NOTIFICATION_TYPES.NEW_APPOINTMENT]: {
      ar: {
        title: 'حجز جديد 📅',
        body: `حجز ${ctx.patientName || 'مريض'} موعداً يوم ${ctx.date} الساعة ${time}.`,
      },
    },
    [NOTIFICATION_TYPES.BOOKING_CANCELLED]: {
      ar: {
        title: 'أُلغي موعدك',
        body: `موعدك مع ${ctx.doctorName || 'الطبيب'} يوم ${ctx.date} الساعة ${time} أُلغي.`,
      },
    },
    [NOTIFICATION_TYPES.APPOINTMENT_CANCELLED]: {
      ar: {
        title: 'إلغاء موعد',
        body: `ألغى ${ctx.patientName || 'المريض'} موعده يوم ${ctx.date} الساعة ${time}.`,
      },
    },
    [NOTIFICATION_TYPES.BOOKING_RESCHEDULED]: {
      ar: {
        title: 'تم تعديل موعدك 🔄',
        body: `انتقل موعدك مع ${ctx.doctorName || 'الطبيب'} إلى ${ctx.date} الساعة ${time}.`,
      },
    },
    [NOTIFICATION_TYPES.APPOINTMENT_RESCHEDULED]: {
      ar: {
        title: 'تعديل موعد',
        body: `نقل ${ctx.patientName || 'المريض'} موعده إلى ${ctx.date} الساعة ${time}.`,
      },
    },
    [NOTIFICATION_TYPES.REMINDER_24H]: {
      ar: {
        title: 'تذكير بموعدك غداً ⏰',
        body: `موعدك مع ${ctx.doctorName || 'الطبيب'} غداً ${ctx.date} الساعة ${time}.`,
      },
    },
    [NOTIFICATION_TYPES.REMINDER_2H]: {
      ar: {
        title: 'موعدك بعد ساعتين ⏰',
        body: `موعدك مع ${ctx.doctorName || 'الطبيب'} اليوم الساعة ${time}.`,
      },
    },
    [NOTIFICATION_TYPES.DOCTOR_REMINDER]: {
      ar: {
        title: 'موعد قريب 🏥',
        body: `لديك موعد مع ${ctx.patientName || 'مريض'} اليوم الساعة ${time}.`,
      },
    },
  };

  const entry = table[type];
  if (!entry) return { title: 'إشعار', body: '' };
  return entry[lang] || entry.ar;
}

/**
 * يُدرج مستند إشعار داخل معاملة قائمة — لا قراءة إضافية، ولا نداء شبكة.
 * المستدعي مسؤول عن عدم استدعائها إلا على مسار غير مكرَّر.
 *
 * @returns {FirebaseFirestore.DocumentReference} مرجع الإشعار — يُجمَع مع
 *   بقية المراجع لتسليمها إلى `deliverPendingPush` بعد نجاح المعاملة.
 */
function queueNotification(tx, db, {
  recipientId, recipientRole, type, appointmentId, metadata = {}, lang = 'ar',
}) {
  const id = notificationIdFor(appointmentId, type, recipientRole);
  const ref = db.collection('notifications').doc(id);
  const { title, body } = buildContent(type, metadata, lang);

  tx.set(ref, {
    recipientId,
    recipientRole,
    type,
    title,
    body,
    appointmentId,
    metadata,
    isRead: false,
    createdAt: new Date(),
    readAt: null,
    push: { status: 'pending', attempts: 0, lastAttemptAt: null, lastError: null },
  });

  return ref;
}

/**
 * تذكير — معرّف حتمي أيضاً، لكن الكتابة عبر `create()` صراحة: تُنفَّذ من
 * خارج أي معاملة موعد (المجدوِلة الدورية)، فالحماية من التكرار تحتاج فشلاً
 * صريحاً عند الوجود المسبق، لا مجرّد الاعتماد على معرّف ثابت.
 *
 * @returns {Promise<boolean>} `true` لو أُنشئ الإشعار فعلاً، `false` لو
 *   كان موجوداً بالفعل (تكرار تشغيل المجدوِلة — لا خطأ، ولا إرسال ثانٍ).
 */
async function createReminderIfAbsent(db, {
  recipientId, recipientRole, type, appointmentId, metadata = {}, lang = 'ar',
}) {
  const id = notificationIdFor(appointmentId, type, recipientRole);
  const ref = db.collection('notifications').doc(id);
  const { title, body } = buildContent(type, metadata, lang);

  try {
    await ref.create({
      recipientId,
      recipientRole,
      type,
      title,
      body,
      appointmentId,
      metadata,
      isRead: false,
      createdAt: new Date(),
      readAt: null,
      push: { status: 'pending', attempts: 0, lastAttemptAt: null, lastError: null },
    });
    return ref;
  } catch (e) {
    // ALREADY_EXISTS (رمز 6) هو المسار المتوقَّع عند تكرار التشغيل — أي
    // خطأ آخر يُرفَع فعلاً، فلا يُبتلَع عطل حقيقي بصمت.
    if (e && (e.code === 6 || e.code === 'already-exists')) return null;
    throw e;
  }
}

/** رموز أخطاء FCM التي تعني أن الرمز لن يعمل أبداً — تُنظَّف من `devices`. */
const DEAD_TOKEN_ERROR_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

/**
 * تسليم Push لإشعارات سبق كتابتها — تُستدعى دائماً **بعد** اكتمال أي
 * معاملة Firestore، أبداً داخلها. تحدّث حقل `push` على كل مستند بنتيجة
 * المحاولة، ولا ترمي أبداً: فشل التسليم لا يجوز أن يُسقط استجابة الدالة
 * القابلة للاستدعاء التي تصف نجاح الحجز/الإلغاء/إعادة الجدولة.
 *
 * @param {object} args
 * @param {FirebaseFirestore.Firestore} args.db
 * @param {import('firebase-admin').messaging.Messaging} args.messaging
 * @param {FirebaseFirestore.DocumentReference[]} args.refs
 */
async function deliverPendingPush({ db, messaging, refs }) {
  await Promise.all(refs.map((ref) => deliverOne({ db, messaging, ref })));
}

async function deliverOne({ db, messaging, ref }) {
  try {
    const snap = await ref.get();
    if (!snap.exists) return;
    const notif = snap.data();

    const devicesSnap = await db
      .collection('users').doc(notif.recipientId)
      .collection('devices')
      .limit(10)
      .get();

    const tokens = devicesSnap.docs.map((d) => d.id);
    if (!tokens.length) {
      await ref.update({
        'push.status': 'skipped_no_token',
        'push.attempts': (notif.push?.attempts || 0) + 1,
        'push.lastAttemptAt': new Date(),
        'push.lastError': null,
      });
      return;
    }

    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: { title: notif.title, body: notif.body },
      data: {
        type: notif.type,
        appointmentId: notif.appointmentId || '',
      },
    });

    const deadTokens = [];
    response.responses.forEach((r, i) => {
      if (!r.success && r.error && DEAD_TOKEN_ERROR_CODES.has(r.error.code)) {
        deadTokens.push(tokens[i]);
      }
    });
    await Promise.all(deadTokens.map((t) =>
      db.collection('users').doc(notif.recipientId)
        .collection('devices').doc(t).delete().catch(() => {})
    ));

    const anySuccess = response.successCount > 0;
    await ref.update({
      'push.status': anySuccess ? 'sent' : 'failed',
      'push.attempts': (notif.push?.attempts || 0) + 1,
      'push.lastAttemptAt': new Date(),
      'push.lastError': anySuccess
        ? null
        : (response.responses.find((r) => !r.success)?.error?.message || 'unknown'),
    });
  } catch (e) {
    // تسجيل فقط — لا رمي أبداً. راجع تعليق الدالة.
    console.error('deliverPendingPush فشل', { ref: ref.path, error: e && e.message });
    try {
      await ref.update({
        'push.status': 'failed',
        'push.attempts': admin.firestore.FieldValue.increment(1),
        'push.lastAttemptAt': new Date(),
        'push.lastError': (e && e.message) || 'unknown',
      });
    } catch (_e2) {
      // حتى تحديث حالة الفشل قد يفشل (مستند حُذف مثلاً) — لا مزيد من المحاولة.
    }
  }
}

module.exports = {
  NOTIFICATION_TYPES,
  notificationIdFor,
  buildContent,
  queueNotification,
  createReminderIfAbsent,
  deliverPendingPush,
};
