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

/**
 * أقصى عدد مواعيد تُفحص في استدعاء واحد.
 *
 * حاجز أمان لا هدف: الدفعة الواقعية أصغر من هذا بكثير لأن المدى أربعة
 * تواريخ فقط. وجوده يمنع أن تتحوّل قفزة في الحجم إلى استدعاء يتجاوز مهلته.
 */
const MAX_APPOINTMENTS_PER_RUN = 2000;

/**
 * عدد المواعيد التي تُعالَج معاً.
 *
 * المعالجة كانت متسلسلة تماماً: `await` لكل موعد، وداخله `await` لكل نافذة
 * تذكير. دفعة من ألف موعد كانت ألف رحلة متعاقبة إلى Firestore.
 *
 * والتوازي محدود عمداً: إطلاق آلاف الكتابات دفعةً واحدة يستهلك اتصالات
 * Firestore ويستدعي تقييد المعدّل، فيصير أبطأ لا أسرع.
 */
const REMINDER_CONCURRENCY = 10;

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

  // ===== المرحلة 7: عمل محدود في الاستدعاء الواحد =====
  //
  // المدى التقويمي كان ضيّقاً أصلاً (أربعة تواريخ)، لكن بلا سقف: الاستعلام
  // يسحب **كل** مواعيد المنصّة في تلك التواريخ. على منصّة بمئات الأطباء
  // تصير الدفعة عشرات الآلاف من المستندات في استدعاء واحد، ثم تُعالَج
  // بحلقة متسلسلة فيها `await` لكل موعد — وهو ما ينتهي بانتهاء مهلة الدالة
  // قبل إرسال التذكيرات الأخيرة، فتضيع بلا أثر ظاهر.
  //
  // السقف يجعل الدفعة محدودة، والمعالجة تجري على دفعات صغيرة متوازية.
  // الدالة تعمل كل خمس دقائق ونافذة الرصد خمس دقائق، فما يتجاوز السقف في
  // دورة يلتقطه ترتيب `appointmentDate` في الدورة التالية ما دام ضمن
  // نافذته. والحدّ مرفوع بما يكفي ليكون ذلك نظرياً على المدى المنظور.
  const snap = await db.collection('appointments')
    .where('appointmentDate', 'in', dateCandidates)
    .orderBy('appointmentDate')
    .limit(MAX_APPOINTMENTS_PER_RUN)
    .get();

  const candidates = snap.docs.filter((doc) => {
    const status = normalizeStatusKey(doc.data().status);
    return ACTIVE_STATUSES.has(status);
  });

  if (snap.size === MAX_APPOINTMENTS_PER_RUN) {
    // إشارة تشغيلية: بلغت الدفعة سقفها، فقد تكون هناك مواعيد لم تُفحص.
    console.warn('sendAppointmentReminders: بلغت الدفعة سقفها', {
      cap: MAX_APPOINTMENTS_PER_RUN,
    });
  }

  // كاش أطباء الدفعة — لا قراءة الطبيب نفسه أكثر من مرة واحدة مهما تكرّر
  // في مواعيد كثيرة.
  //
  // المرحلة 7: يُخزَّن **الوعد** لا القيمة. بعد أن صارت المعالجة متوازية،
  // كان فحصُ الوجود ثم الانتظار يترك ثغرة: عشرة مواعيد لنفس الطبيب تنطلق
  // معاً، فتجد الكاش فارغاً كلها وتقرأ المستند عشر مرات. تخزين الوعد فور
  // إطلاقه يجعل التالين ينتظرون القراءة الجارية بدل بدء أخرى.
  const doctorCache = new Map();
  function getDoctor(doctorId) {
    if (doctorCache.has(doctorId)) return doctorCache.get(doctorId);
    const pending = db.collection('users').doc(doctorId).get()
      .then((doctorSnap) => (doctorSnap.exists ? doctorSnap.data() : null))
      .catch((e) => {
        // قراءة فاشلة لا تُخزَّن: المحاولة التالية تعيدها بدل أن ترث الفشل.
        doctorCache.delete(doctorId);
        throw e;
      });
    doctorCache.set(doctorId, pending);
    return pending;
  }

  let sent = 0;
  let skipped = 0;

  /** يعالج موعداً واحداً ويُرجع ما أُرسل وما تُخطّي. */
  async function processOne(doc) {
    const appt = doc.data();
    const appointmentId = doc.id;
    let localSent = 0;
    let localSkipped = 0;

    try {
      const doctor = await getDoctor(appt.doctorId);
      if (!doctor) return { sent: 0, skipped: 1 };

      const nowInfo = nowForDoctor(doctor, now);
      const minutesUntil = minutesBetween(
        nowInfo.date, nowInfo.time, appt.appointmentDate, appt.startTime);
      if (minutesUntil <= 0) return { sent: 0, skipped: 1 };

      // النوافذ تبقى متسلسلة داخل الموعد الواحد: ثلاث نوافذ على الأكثر،
      // وتسلسلها يحفظ ترتيب الكتابة على نفس الموعد.
      for (const window of REMINDER_WINDOWS) {
        if (!inWindow(minutesUntil, window.targetMinutes)) continue;

        const didSend = await maybeSendReminder({
          db, messaging, appointmentId, appt, window,
        });
        if (didSend) localSent++; else localSkipped++;
      }
    } catch (e) {
      // موعد واحد فاسد أو طبيبه غير موجود لا يوقف بقية الدفعة.
      console.error('sendAppointmentReminders: فشل معالجة موعد', {
        appointmentId, error: e && e.message,
      });
      localSkipped++;
    }
    return { sent: localSent, skipped: localSkipped };
  }

  // معالجة على دفعات محدودة التوازي بدل حلقة متسلسلة.
  //
  // لا أثر على منع التكرار: `maybeSendReminder` تعيد قراءة الموعد ثم تكتب
  // علامة التذكير عبر `createReminderIfAbsent` بمعرّف مشتقّ من
  // (الموعد + النوع)، أي أن الحماية على مستوى المستند لا على ترتيب الحلقة.
  // وكل موعد هنا مستند مستقلّ، فلا تتسابق دفعتان على نفس العلامة.
  for (let i = 0; i < candidates.length; i += REMINDER_CONCURRENCY) {
    const chunk = candidates.slice(i, i + REMINDER_CONCURRENCY);
    const results = await Promise.all(chunk.map(processOne));
    for (const r of results) {
      sent += r.sent;
      skipped += r.skipped;
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
  // مُصدَّران للاختبارات: إثبات أن الدفعة محدودة وأن التوازي مقيَّد يحتاج
  // معرفة القيمتين لا تخمينهما.
  MAX_APPOINTMENTS_PER_RUN,
  REMINDER_CONCURRENCY,
};
