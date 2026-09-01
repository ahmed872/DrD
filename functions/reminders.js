/**
 * تذكيرات المواعيد — نسخة صحيحة من `checkAppointments` القديمة.
 *
 * ## لماذا أُعيد بناؤها لا تصحيحها فقط
 *
 * النسخة القديمة كانت معطَّلة عملياً بالكامل: تستعلم عن
 * `status == "Scheduled"` بينما القيمة الحقيقية المكتوبة دائماً `Booked`،
 * وتقرأ `data.date`/`data.time` بينما الحقلان الحقيقيان
 * `appointmentDate`/`startTime` (`booking.js` منذ المرحلة 1أ). النتيجة:
 * الاستعلام لا يُرجع شيئاً أبداً — لا خطأ ظاهر، مجرّد صمت. هذا الملف يقرأ
 * الحقول الحقيقية ويستخدم نفس محرّك الحالة والتوقيت من `availability.js`
 * بدل نسخة موازية.
 *
 * ## الحتمية والتزامن
 *
 * معرّف كل تذكير حتمي (`appointmentId__reminderType__role`، عبر
 * `createReminderIfAbsent`)، والكتابة عبر `create()` لا `set()` — تشغيل
 * هذه الدالة مرتين على نفس الدفعة (إعادة محاولة Cloud Scheduler، أو تداخل
 * تنفيذين) لا يُنتج تذكيراً مضاعفاً؛ المحاولة الثانية تصطدم بـ
 * `ALREADY_EXISTS` وتُتجاهَل بهدوء.
 *
 * ## نافذة الرصد
 *
 * تعمل كل 5 دقائق. لكل موعد نشط، تُحسَب المدة المتبقية بتوقيت **طبيبه هو**
 * (`nowForDoctor` من `availability.js` — نفس التجريد الذي بُني في المرحلة
 * 1ب، لا نسخة جديدة). موعد تقع مدته المتبقية داخل نافذة 5 دقائق حول 24
 * ساعة يُرسَل له تذكير 24 ساعة؛ وحول ساعتين يُرسَل له تذكير الساعتين
 * (وتذكير مبسَّط للطبيب في نفس اللحظة). خارج النافذتين — لا شيء.
 *
 * ## السباق مع الإلغاء/إعادة الجدولة
 *
 * الاستعلام الأول يقرأ لقطة قد تُصبح قديمة خلال معالجة الدفعة. قبل إرسال
 * أي تذكير فعلياً تُعاد قراءة الموعد بذاته (قراءة مفردة رخيصة) والتحقق أن
 * حالته ما زالت نشطة — موعد أُلغي أو أُعيدت جدولته بين الاستعلام والإرسال
 * لا يصله تذكير.
 */

const {
  nowForDoctor,
  minutesBetween,
  normalizeStatusKey,
  ACTIVE_STATUSES,
  shiftDateStr,
} = require('./availability');
const {
  NOTIFICATION_TYPES,
  createReminderIfAbsent,
  deliverPendingPush,
} = require('./notifications');

/** طول نافذة الرصد بالدقائق — يطابق دورية التشغيل (كل 5 دقائق). */
const WINDOW_MINUTES = 5;

const REMINDER_WINDOWS = [
  { targetMinutes: 24 * 60, type: NOTIFICATION_TYPES.REMINDER_24H, recipient: 'patient' },
  { targetMinutes: 2 * 60, type: NOTIFICATION_TYPES.REMINDER_2H, recipient: 'patient' },
  { targetMinutes: 2 * 60, type: NOTIFICATION_TYPES.DOCTOR_REMINDER, recipient: 'doctor' },
];

function inWindow(minutesUntil, targetMinutes) {
  return minutesUntil <= targetMinutes && minutesUntil > targetMinutes - WINDOW_MINUTES;
}

/**
 * يعالج دفعة واحدة من التذكيرات. يُصدَّر منفصلاً عن `exports.sendAppointmentReminders`
 * في `index.js` ليكون قابلاً للاختبار المباشر بحقن `now` ومزوّد push وهمي.
 *
 * @param {object} args
 * @param {FirebaseFirestore.Firestore} args.db
 * @param {Date} [args.now]
 * @param {import('firebase-admin').messaging.Messaging} args.messaging
 * @returns {Promise<{checked: number, sent: number, skipped: number}>}
 */
async function sendAppointmentRemindersCore({ db, now = new Date(), messaging }) {
  // مدى تواريخ استعلام ضيّق ومحدود — لا مسح للمجموعة كاملة. ثلاثة تواريخ
  // تقويمية بتوقيت UTC كافية لتغطية أي إزاحة منطقة زمنية واقعية لنافذتي
  // 24 ساعة وساعتين معاً.
  const todayUtc = _utcDateStr(now);
  const dateCandidates = [
    shiftDateStr(todayUtc, -1),
    todayUtc,
    shiftDateStr(todayUtc, 1),
    shiftDateStr(todayUtc, 2),
  ];

  const snap = await db.collection('appointments')
    .where('appointmentDate', 'in', dateCandidates)
    .get();

  const candidates = snap.docs.filter((doc) => {
    const status = normalizeStatusKey(doc.data().status);
    return ACTIVE_STATUSES.has(status);
  });

  // كاش أطباء الدفعة — لا قراءة الطبيب نفسه أكثر من مرة واحدة مهما تكرّر
  // في مواعيد كثيرة.
  const doctorCache = new Map();
  async function getDoctor(doctorId) {
    if (doctorCache.has(doctorId)) return doctorCache.get(doctorId);
    const doctorSnap = await db.collection('users').doc(doctorId).get();
    const data = doctorSnap.exists ? doctorSnap.data() : null;
    doctorCache.set(doctorId, data);
    return data;
  }

  let sent = 0;
  let skipped = 0;

  for (const doc of candidates) {
    const appt = doc.data();
    const appointmentId = doc.id;

    try {
      const doctor = await getDoctor(appt.doctorId);
      if (!doctor) { skipped++; continue; }

      const nowInfo = nowForDoctor(doctor, now);
      const minutesUntil = minutesBetween(
        nowInfo.date, nowInfo.time, appt.appointmentDate, appt.startTime);
      if (minutesUntil <= 0) { skipped++; continue; }

      for (const window of REMINDER_WINDOWS) {
        if (!inWindow(minutesUntil, window.targetMinutes)) continue;

        const didSend = await maybeSendReminder({
          db, messaging, appointmentId, appt, window,
        });
        if (didSend) sent++; else skipped++;
      }
    } catch (e) {
      // موعد واحد فاسد أو طبيبه غير موجود لا يوقف بقية الدفعة.
      console.error('sendAppointmentReminders: فشل معالجة موعد', {
        appointmentId, error: e && e.message,
      });
      skipped++;
    }
  }

  return { checked: candidates.length, sent, skipped };
}

/**
 * يُرسل تذكيراً واحداً بعد إعادة قراءة الموعد فعلياً — يقفل نافذة السباق
 * مع إلغاء/إعادة جدولة وقعت بعد الاستعلام الأول.
 */
async function maybeSendReminder({ db, messaging, appointmentId, appt, window }) {
  const freshSnap = await db.collection('appointments').doc(appointmentId).get();
  if (!freshSnap.exists) return false;
  const fresh = freshSnap.data();
  if (!ACTIVE_STATUSES.has(normalizeStatusKey(fresh.status))) return false;

  const recipientId = window.recipient === 'patient' ? fresh.patientId : fresh.doctorId;
  if (!recipientId) return false;

  const ref = await createReminderIfAbsent(db, {
    recipientId, recipientRole: window.recipient,
    type: window.type, appointmentId,
    metadata: {
      doctorName: fresh.doctorName, patientName: fresh.patientName,
      date: fresh.appointmentDate, startTime: fresh.startTime,
    },
  });
  if (!ref) return false; // كان موجوداً بالفعل — تكرار تشغيل، لا إرسال ثانٍ.

  await deliverPendingPush({ db, messaging, refs: [ref] });
  return true;
}

/** تاريخ اليوم بصيغة yyyy-MM-dd بتوقيت UTC — مرجع محايد لبناء مدى الاستعلام. */
function _utcDateStr(now) {
  return now.toISOString().slice(0, 10);
}

module.exports = {
  sendAppointmentRemindersCore,
  // مُصدَّرة للاختبارات: إثبات إغلاق السباق مع الإلغاء/إعادة الجدولة يحتاج
  // استدعاء هذه الدالة مباشرة بلقطة أولية قديمة عمداً — راجع
  // `test/reminders.test.js`.
  maybeSendReminder,
  WINDOW_MINUTES,
  REMINDER_WINDOWS,
};
