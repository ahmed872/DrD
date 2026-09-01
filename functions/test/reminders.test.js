/**
 * اختبارات تذكيرات المواعيد — `functions/reminders.js`.
 *
 * تستبدل اختبارات `checkAppointments` القديمة (لم تكن موجودة أصلاً، لأن
 * الدالة القديمة لم تكن تعمل مطلقاً — راجع تعليق `reminders.js`).
 *
 *   firebase emulators:exec --only firestore --project drd-functions-test \
 *     "npm --prefix functions test"
 */

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const admin = require('firebase-admin');
const {
  sendAppointmentRemindersCore, maybeSendReminder, REMINDER_WINDOWS,
  MAX_APPOINTMENTS_PER_RUN, REMINDER_CONCURRENCY,
} = require('../reminders');
const { NOTIFICATION_TYPES, notificationIdFor } = require('../notifications');

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'drd-functions-test' });
}
const db = admin.firestore();

const DOCTOR = 'doctorOne'; // بلا timezone — يسقط لتوقيت القاهرة الافتراضي.
const TOKYO_DOCTOR = 'doctorTokyo'; // timezone صريح مختلف — لاختبار حدود المنطقة الزمنية.
const PATIENT = 'patientOne';

function fakeMessaging() {
  return {
    calls: [],
    async sendEachForMulticast(payload) {
      this.calls.push(payload);
      return { successCount: 0, responses: payload.tokens.map(() => ({ success: false, error: { code: 'x' } })) };
    },
  };
}

async function clearFirestore() {
  for (const name of ['users', 'appointments', 'notifications']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seedDoctors() {
  await db.collection('users').doc(DOCTOR).set({
    role: 'doctor', isVerified: true, name: 'د. أحمد',
  });
  // طوكيو UTC+9 — فرق تسع ساعات عن القاهرة (UTC+2 شتاءً) يكفي لإثبات أن
  // الحساب يستخدم توقيت الطبيب لا القاهرة المُقفلة.
  await db.collection('users').doc(TOKYO_DOCTOR).set({
    role: 'doctor', isVerified: true, name: 'د. طوكيو', timezone: 'Asia/Tokyo',
  });
  await db.collection('users').doc(PATIENT).set({
    role: 'patient', name: 'مريض',
  });
}

async function seedAppointment(id, { doctorId = DOCTOR, date, time, status = 'Booked' }) {
  await db.collection('appointments').doc(id).set({
    doctorId, patientId: PATIENT, appointmentDate: date, startTime: time,
    status, doctorName: 'د. أحمد', patientName: 'مريض',
  });
}

beforeEach(async () => {
  await clearFirestore();
  await seedDoctors();
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app && app.delete()));
});

async function getNotification(appointmentId, type, role) {
  const snap = await db.collection('notifications')
    .doc(notificationIdFor(appointmentId, type, role)).get();
  return snap.exists ? snap.data() : null;
}

describe('sendAppointmentReminders — النوافذ الزمنية', () => {
  test('موعد على حافة نافذة 24 ساعة يحصل على تذكير 24 ساعة للمريض', async () => {
    // "الآن" 2030-03-01T06:00:00Z (08:00 بتوقيت القاهرة). موعد بعد 23:57
    // دقيقة بالضبط يقع داخل نافذة الرصد (24 ساعة إلى 24 ساعة - 5 دقائق).
    const now = new Date('2030-03-01T06:00:00Z');
    await seedAppointment('appt1', { date: '2030-03-02', time: '07:57' });

    const result = await sendAppointmentRemindersCore({ db, now, messaging: fakeMessaging() });
    expect(result.sent).toBe(1);

    const notif = await getNotification('appt1', NOTIFICATION_TYPES.REMINDER_24H, 'patient');
    expect(notif).toBeTruthy();
    expect(notif.recipientId).toBe(PATIENT);
  });

  test('موعد على حافة نافذة الساعتين يحصل على تذكيرين: مريض وطبيب', async () => {
    const now = new Date('2030-03-01T06:00:00Z'); // 08:00 قاهرة.
    await seedAppointment('appt2', { date: '2030-03-01', time: '09:57' }); // بعد 1:57.

    const result = await sendAppointmentRemindersCore({ db, now, messaging: fakeMessaging() });
    expect(result.sent).toBe(2);

    const patientNotif = await getNotification('appt2', NOTIFICATION_TYPES.REMINDER_2H, 'patient');
    expect(patientNotif).toBeTruthy();
    const doctorNotif = await getNotification('appt2', NOTIFICATION_TYPES.DOCTOR_REMINDER, 'doctor');
    expect(doctorNotif).toBeTruthy();
  });

  test('موعد خارج كلتا النافذتين لا يحصل على أي تذكير', async () => {
    const now = new Date('2030-03-01T06:00:00Z');
    await seedAppointment('appt3', { date: '2030-03-01', time: '15:00' }); // بعد 7 ساعات.

    const result = await sendAppointmentRemindersCore({ db, now, messaging: fakeMessaging() });
    expect(result.sent).toBe(0);
    expect(await getNotification('appt3', NOTIFICATION_TYPES.REMINDER_24H, 'patient')).toBeNull();
    expect(await getNotification('appt3', NOTIFICATION_TYPES.REMINDER_2H, 'patient')).toBeNull();
  });

  test('موعد فات وقته لا يحصل على تذكير', async () => {
    const now = new Date('2030-03-01T06:00:00Z');
    await seedAppointment('appt4', { date: '2030-02-28', time: '09:00' });

    const result = await sendAppointmentRemindersCore({ db, now, messaging: fakeMessaging() });
    expect(result.sent).toBe(0);
  });
});

describe('sendAppointmentReminders — الحالة والسباق', () => {
  test('موعد ملغى لا يحصل على تذكير رغم وقوعه داخل النافذة', async () => {
    const now = new Date('2030-03-01T06:00:00Z');
    await seedAppointment('appt5', { date: '2030-03-01', time: '09:57', status: 'Cancelled' });

    const result = await sendAppointmentRemindersCore({ db, now, messaging: fakeMessaging() });
    expect(result.sent).toBe(0);
  });

  test('موعد مكتمل لا يحصل على تذكير', async () => {
    const now = new Date('2030-03-01T06:00:00Z');
    await seedAppointment('appt6', { date: '2030-03-01', time: '09:57', status: 'Completed' });

    const result = await sendAppointmentRemindersCore({ db, now, messaging: fakeMessaging() });
    expect(result.sent).toBe(0);
  });

  test('إلغاء الموعد بعد الاستعلام الأول وقبل الإرسال يمنع التذكير (سباق)', async () => {
    // إثبات مباشر لإغلاق السباق: نستدعي `maybeSendReminder` بلقطة `appt`
    // **قديمة عمداً** تصف حالة نشطة (تماماً كما لو كانت من استعلام الدفعة
    // الأولي)، بينما المستند الفعلي في القاعدة أصبح ملغياً بالفعل. الدالة
    // يجب أن تُعيد قراءة الموعد فعلياً قبل الإرسال وترفض بناءً على الحالة
    // الحقيقية، لا اللقطة القديمة الممرَّرة إليها.
    await seedAppointment('appt7', { date: '2030-03-01', time: '09:57' });
    const staleApptSnapshot = {
      doctorId: DOCTOR, patientId: PATIENT, appointmentDate: '2030-03-01',
      startTime: '09:57', status: 'Booked', // نشط — لكنه قديم.
      doctorName: 'د. أحمد', patientName: 'مريض',
    };
    await db.collection('appointments').doc('appt7').update({ status: 'Cancelled' });

    const sentDespiteStaleSnapshot = await maybeSendReminder({
      db, messaging: fakeMessaging(), appointmentId: 'appt7',
      appt: staleApptSnapshot, window: REMINDER_WINDOWS[1], // نافذة الساعتين.
    });
    expect(sentDespiteStaleSnapshot).toBe(false);
    expect(await getNotification('appt7', NOTIFICATION_TYPES.REMINDER_2H, 'patient')).toBeNull();
  });
});

describe('sendAppointmentReminders — الحتمية والتزامن', () => {
  test('تشغيل الدالة مرتين على نفس الدفعة لا يُنتج تذكيراً مضاعفاً', async () => {
    const now = new Date('2030-03-01T06:00:00Z');
    await seedAppointment('appt8', { date: '2030-03-02', time: '07:57' });

    const first = await sendAppointmentRemindersCore({ db, now, messaging: fakeMessaging() });
    expect(first.sent).toBe(1);

    const second = await sendAppointmentRemindersCore({ db, now, messaging: fakeMessaging() });
    expect(second.sent).toBe(0); // كله تكرار — أُنشئ بالفعل.
    expect(second.skipped).toBeGreaterThan(0);

    const snap = await db.collection('notifications')
      .where('appointmentId', '==', 'appt8').get();
    expect(snap.size).toBe(1); // تذكير واحد فقط رغم تشغيلين.
  });

  test('تشغيلان متزامنان على نفس الدفعة لا ينتجان تذكيرين', async () => {
    const now = new Date('2030-03-01T06:00:00Z');
    await seedAppointment('appt9', { date: '2030-03-02', time: '07:57' });

    const [r1, r2] = await Promise.all([
      sendAppointmentRemindersCore({ db, now, messaging: fakeMessaging() }),
      sendAppointmentRemindersCore({ db, now, messaging: fakeMessaging() }),
    ]);
    expect(r1.sent + r2.sent).toBe(1); // واحد فقط ينجح، والآخر يصطدم بـ ALREADY_EXISTS.

    const snap = await db.collection('notifications')
      .where('appointmentId', '==', 'appt9').get();
    expect(snap.size).toBe(1);
  });
});

describe('sendAppointmentReminders — حدود المنطقة الزمنية', () => {
  test('طبيب بمنطقة زمنية مختلفة (طوكيو UTC+9) يُحسَب بتوقيته هو لا القاهرة', async () => {
    // "الآن" 2030-03-01T06:00:00Z = 15:00 بتوقيت طوكيو (UTC+9)، = 08:00
    // بتوقيت القاهرة (UTC+2). موعد الساعة 17:00 بتوقيت طوكيو (بعد ساعتين
    // بالضبط بتوقيت الطبيب) يجب أن يقع داخل نافذة الساعتين محسوباً بتوقيت
    // طوكيو — لا بتوقيت القاهرة الذي كان سيُنتج فرقاً مختلفاً تماماً لو
    // استُخدم خطأً.
    const now = new Date('2030-03-01T06:00:00Z');
    await seedAppointment('apptTokyo', {
      doctorId: TOKYO_DOCTOR, date: '2030-03-01', time: '16:57',
    });

    const result = await sendAppointmentRemindersCore({ db, now, messaging: fakeMessaging() });
    expect(result.sent).toBe(2); // تذكير المريض + تذكير الطبيب.

    const notif = await getNotification('apptTokyo', NOTIFICATION_TYPES.REMINDER_2H, 'patient');
    expect(notif).toBeTruthy();
  });
});

describe('sendAppointmentReminders — الأداء وحدود الاستعلام', () => {
  // ===== المرحلة 7: حدود الدفعة والتوازي =====

  test('الدفعة محدودة بسقف صريح ولا تُترك مفتوحة', () => {
    // بلا سقف يسحب الاستعلام كل مواعيد المنصّة في مدى التواريخ، وهو ما
    // يتحوّل على منصّة كبيرة إلى استدعاء يتجاوز مهلته قبل إتمام الإرسال.
    expect(Number.isInteger(MAX_APPOINTMENTS_PER_RUN)).toBe(true);
    expect(MAX_APPOINTMENTS_PER_RUN).toBeGreaterThan(0);
    expect(MAX_APPOINTMENTS_PER_RUN).toBeLessThanOrEqual(5000);
  });

  test('التوازي مقيَّد ولا يُطلق الدفعة كاملة دفعةً واحدة', () => {
    expect(REMINDER_CONCURRENCY).toBeGreaterThan(1);
    expect(REMINDER_CONCURRENCY).toBeLessThanOrEqual(50);
  });

  test('دفعة أكبر من حدّ التوازي تُعالَج كاملة بلا تكرار', async () => {
    // الانتقال من حلقة متسلسلة إلى دفعات متوازية هو التغيير الجوهري في
    // هذه المرحلة؛ هذا الاختبار يثبت أنه لم يُسقط موعداً ولم يضاعف تذكيراً.
    const count = REMINDER_CONCURRENCY * 2 + 3;
    const now = new Date('2030-03-01T06:00:00Z');
    for (let i = 0; i < count; i++) {
      await seedAppointment(`bulk${i}`, { date: '2030-03-02', time: '07:57' });
    }

    const first = await sendAppointmentRemindersCore({
      db, now, messaging: fakeMessaging(),
    });
    expect(first.sent).toBe(count);

    // التشغيل الثاني على نفس الدفعة لا يُرسل شيئاً — الحماية على مستوى
    // المستند لا على ترتيب الحلقة.
    const second = await sendAppointmentRemindersCore({
      db, now, messaging: fakeMessaging(),
    });
    expect(second.sent).toBe(0);

    for (let i = 0; i < count; i++) {
      const note = await getNotification(
        `bulk${i}`, NOTIFICATION_TYPES.REMINDER_24H, 'patient');
      expect(note).not.toBeNull();
    }
  }, 60000);

  test('طبيب واحد لمواعيد كثيرة يُقرأ مرّة واحدة رغم التوازي', async () => {
    // كاش الأطباء كان يخزّن القيمة **بعد** الانتظار: عشرة مواعيد متوازية
    // لنفس الطبيب تجد الكاش فارغاً كلها فتقرأ المستند عشر مرات. تخزين
    // الوعد فور إطلاقه يجعل التالين ينتظرون القراءة الجارية.
    //
    // العدّ هنا حقيقي: غلاف رفيع حول `db` يحصي قراءات `users` فعلياً بدل
    // افتراض أن الكاش يعمل.
    const now = new Date('2030-03-01T06:00:00Z');
    const count = REMINDER_CONCURRENCY * 2;
    for (let i = 0; i < count; i++) {
      await seedAppointment(`same${i}`, { date: '2030-03-02', time: '07:57' });
    }

    let userDocReads = 0;
    const countingDb = {
      collection(name) {
        const col = db.collection(name);
        if (name !== 'users') return col;
        return {
          ...col,
          doc(id) {
            const ref = col.doc(id);
            return {
              ...ref,
              get: (...args) => {
                userDocReads++;
                return ref.get(...args);
              },
            };
          },
        };
      },
    };

    const result = await sendAppointmentRemindersCore({
      db: countingDb, now, messaging: fakeMessaging(),
    });

    expect(result.sent).toBe(count);
    // طبيب واحد في البذور، فقراءة واحدة تكفي مهما بلغ عدد المواعيد.
    expect(userDocReads).toBe(1);
  }, 60000);

  test('لا تقرأ مواعيد بعيدة تماماً خارج مدى الاستعلام', async () => {
    const now = new Date('2030-03-01T06:00:00Z');
    // موعد بعد شهر كامل — خارج أي نافذة استعلام منطقية.
    await seedAppointment('apptFar', { date: '2030-04-01', time: '09:00' });
    await seedAppointment('apptNear', { date: '2030-03-02', time: '07:57' });

    const result = await sendAppointmentRemindersCore({ db, now, messaging: fakeMessaging() });
    // فقط الموعد القريب دخل نطاق الفحص أصلاً.
    expect(result.checked).toBe(1);
    expect(result.sent).toBe(1);
  });
});
