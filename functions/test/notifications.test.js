/**
 * اختبارات إشعارات دورة حياة الموعد: الحجز، الإلغاء، إعادة الجدولة، وتسليم
 * Push (رموز صحيحة وفاسدة وفشل الشبكة).
 *
 *   firebase emulators:exec --only firestore --project drd-functions-test \
 *     "npm --prefix functions test"
 */

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const admin = require('firebase-admin');
const { bookAppointmentCore } = require('../booking');
const { cancelAppointmentCore, rescheduleAppointmentCore } = require('../lifecycle');
const { NOTIFICATION_TYPES, notificationIdFor } = require('../notifications');

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'drd-functions-test' });
}
const db = admin.firestore();

const DOCTOR = 'doctorOne';
const PATIENT = 'patientOne';
const OTHER = 'patientTwo';

const NOW = new Date('2030-03-01T06:00:00Z');
const FUTURE_DATE = '2030-03-03';
const SLOT_TIME = '09:00';

const doctorDoc = (extra = {}) => ({
  role: 'doctor', isVerified: true, name: 'د. أحمد', nameEn: 'Dr. Ahmed',
  specialization: 'أسنان', phone: '201000000001', price: 200,
  sessionDuration: 30, bookingSystemType: 'Individual',
  workingHours: '09:00 AM - 05:00 PM', ...extra,
});

/** مزوّد Push وهمي — لا نداء شبكة حقيقياً أبداً في هذه الاختبارات. */
function fakeMessaging({ succeed = true, errorCode = null, throwError = null } = {}) {
  return {
    calls: [],
    async sendEachForMulticast(payload) {
      this.calls.push(payload);
      if (throwError) throw throwError;
      if (succeed) {
        return {
          successCount: payload.tokens.length,
          responses: payload.tokens.map(() => ({ success: true })),
        };
      }
      return {
        successCount: 0,
        responses: payload.tokens.map(() => ({
          success: false,
          error: { code: errorCode || 'messaging/internal-error', message: 'فشل وهمي' },
        })),
      };
    },
  };
}

async function clearFirestore() {
  for (const name of ['users', 'slots', 'appointments', 'notifications']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seed() {
  await db.collection('users').doc(DOCTOR).set(doctorDoc());
  await db.collection('users').doc(PATIENT).set({
    role: 'patient', name: 'مريض', phone: '201000000002', email: 'p@example.com',
  });
  await db.collection('users').doc(OTHER).set({
    role: 'patient', name: 'مريض ٢', phone: '201000000003',
  });
}

beforeEach(async () => {
  await clearFirestore();
  await seed();
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app && app.delete()));
});

async function getNotification(id) {
  const snap = await db.collection('notifications').doc(id).get();
  return snap.exists ? snap.data() : null;
}

async function countNotifications() {
  const snap = await db.collection('notifications').get();
  return snap.size;
}

// ===================== الحجز =====================

describe('إشعارات الحجز', () => {
  test('حجز ناجح ينتج إشعارين: تأكيد للمريض وحجز جديد للطبيب', async () => {
    const messaging = fakeMessaging();
    const res = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME },
      now: NOW, messaging,
    });

    const patientNotif = await getNotification(
      notificationIdFor(res.appointmentId, NOTIFICATION_TYPES.BOOKING_CONFIRMED, 'patient'));
    expect(patientNotif).toBeTruthy();
    expect(patientNotif.recipientId).toBe(PATIENT);
    expect(patientNotif.appointmentId).toBe(res.appointmentId);
    expect(patientNotif.isRead).toBe(false);

    const doctorNotif = await getNotification(
      notificationIdFor(res.appointmentId, NOTIFICATION_TYPES.NEW_APPOINTMENT, 'doctor'));
    expect(doctorNotif).toBeTruthy();
    expect(doctorNotif.recipientId).toBe(DOCTOR);

    expect(await countNotifications()).toBe(2);
  });

  test('حجز فاشل لا ينتج أي إشعار', async () => {
    await db.collection('users').doc(DOCTOR).update({ isVerified: false });
    await expect(bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME },
      now: NOW, messaging: fakeMessaging(),
    })).rejects.toThrow();

    expect(await countNotifications()).toBe(0);
  });

  test('طلب حجز مكرَّر لا يُنتج إشعاراً إضافياً', async () => {
    const request = { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME };
    await bookAppointmentCore({ db, uid: PATIENT, data: request, now: NOW, messaging: fakeMessaging() });
    expect(await countNotifications()).toBe(2);

    const second = await bookAppointmentCore({
      db, uid: PATIENT, data: request, now: NOW, messaging: fakeMessaging(),
    });
    expect(second.duplicate).toBe(true);
    expect(await countNotifications()).toBe(2); // لا زيادة.
  });
});

// ===================== الإلغاء =====================

describe('إشعارات الإلغاء', () => {
  test('إلغاء ناجح ينتج إشعارين: تأكيد للمريض وإبلاغ للطبيب', async () => {
    const booked = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME },
      now: NOW, messaging: fakeMessaging(),
    });

    await cancelAppointmentCore({
      db, uid: PATIENT, data: { appointmentId: booked.appointmentId },
      now: NOW, messaging: fakeMessaging(),
    });

    const patientNotif = await getNotification(
      notificationIdFor(booked.appointmentId, NOTIFICATION_TYPES.BOOKING_CANCELLED, 'patient'));
    expect(patientNotif).toBeTruthy();

    const doctorNotif = await getNotification(
      notificationIdFor(booked.appointmentId, NOTIFICATION_TYPES.APPOINTMENT_CANCELLED, 'doctor'));
    expect(doctorNotif).toBeTruthy();

    expect(await countNotifications()).toBe(4); // 2 حجز + 2 إلغاء.
  });

  test('إلغاء مكرَّر لا يُنتج إشعاراً إضافياً', async () => {
    const booked = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME },
      now: NOW, messaging: fakeMessaging(),
    });
    const cancelData = { appointmentId: booked.appointmentId };
    await cancelAppointmentCore({ db, uid: PATIENT, data: cancelData, now: NOW, messaging: fakeMessaging() });
    const afterFirst = await countNotifications();

    const second = await cancelAppointmentCore({
      db, uid: PATIENT, data: cancelData, now: NOW, messaging: fakeMessaging(),
    });
    expect(second.alreadyCancelled).toBe(true);
    expect(await countNotifications()).toBe(afterFirst); // لا زيادة.
  });
});

// ===================== إعادة الجدولة =====================

describe('إشعارات إعادة الجدولة', () => {
  test('نقل ناجح ينتج إشعارين على معرّف الموعد الجديد', async () => {
    const booked = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME },
      now: NOW, messaging: fakeMessaging(),
    });

    const res = await rescheduleAppointmentCore({
      db, uid: PATIENT,
      data: { appointmentId: booked.appointmentId, newDate: '2030-03-10', newTime: '11:00' },
      now: NOW, messaging: fakeMessaging(),
    });

    const patientNotif = await getNotification(
      notificationIdFor(res.appointmentId, NOTIFICATION_TYPES.BOOKING_RESCHEDULED, 'patient'));
    expect(patientNotif).toBeTruthy();
    expect(patientNotif.metadata.oldDate).toBe(FUTURE_DATE);
    expect(patientNotif.metadata.date).toBe('2030-03-10');

    const doctorNotif = await getNotification(
      notificationIdFor(res.appointmentId, NOTIFICATION_TYPES.APPOINTMENT_RESCHEDULED, 'doctor'));
    expect(doctorNotif).toBeTruthy();

    expect(await countNotifications()).toBe(4); // 2 حجز + 2 إعادة جدولة.
  });

  test('إعادة جدولة إلى نفس الخانة (unchanged) لا تُنتج إشعاراً', async () => {
    const booked = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME },
      now: NOW, messaging: fakeMessaging(),
    });
    const before = await countNotifications();

    const res = await rescheduleAppointmentCore({
      db, uid: PATIENT,
      data: { appointmentId: booked.appointmentId, newDate: FUTURE_DATE, newTime: SLOT_TIME },
      now: NOW, messaging: fakeMessaging(),
    });
    expect(res.unchanged).toBe(true);
    expect(await countNotifications()).toBe(before);
  });

  test('طلب إعادة جدولة مكرَّر لا يُنتج إشعاراً إضافياً', async () => {
    const booked = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME },
      now: NOW, messaging: fakeMessaging(),
    });
    const rescheduleData = {
      appointmentId: booked.appointmentId, newDate: '2030-03-10', newTime: '11:00',
    };
    await rescheduleAppointmentCore({ db, uid: PATIENT, data: rescheduleData, now: NOW, messaging: fakeMessaging() });
    const afterFirst = await countNotifications();

    const second = await rescheduleAppointmentCore({
      db, uid: PATIENT, data: rescheduleData, now: NOW, messaging: fakeMessaging(),
    });
    expect(second.duplicate).toBe(true);
    expect(await countNotifications()).toBe(afterFirst);
  });
});

// ===================== تسليم Push =====================

describe('تسليم Push', () => {
  async function registerDevice(uid, token) {
    await db.collection('users').doc(uid).collection('devices').doc(token).set({
      token, platform: 'android', updatedAt: new Date(),
    });
  }

  test('لا رمز مسجَّل — الإشعار in-app يبقى، وحالة push تصبح skipped_no_token', async () => {
    const res = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME },
      now: NOW, messaging: fakeMessaging(),
    });
    const notif = await getNotification(
      notificationIdFor(res.appointmentId, NOTIFICATION_TYPES.BOOKING_CONFIRMED, 'patient'));
    expect(notif.push.status).toBe('skipped_no_token');
  });

  test('رمز صحيح — يُرسَل والحالة sent', async () => {
    await registerDevice(PATIENT, 'valid_token_123');
    const messaging = fakeMessaging({ succeed: true });

    const res = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME },
      now: NOW, messaging,
    });

    const notif = await getNotification(
      notificationIdFor(res.appointmentId, NOTIFICATION_TYPES.BOOKING_CONFIRMED, 'patient'));
    expect(notif.push.status).toBe('sent');
    expect(messaging.calls.length).toBe(1);
  });

  test('رمز فاسد — يُحذَف من devices والحالة failed', async () => {
    await registerDevice(PATIENT, 'dead_token_456');
    const messaging = fakeMessaging({
      succeed: false, errorCode: 'messaging/registration-token-not-registered',
    });

    const res = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME },
      now: NOW, messaging,
    });

    const notif = await getNotification(
      notificationIdFor(res.appointmentId, NOTIFICATION_TYPES.BOOKING_CONFIRMED, 'patient'));
    expect(notif.push.status).toBe('failed');

    const deviceSnap = await db.collection('users').doc(PATIENT)
      .collection('devices').doc('dead_token_456').get();
    expect(deviceSnap.exists).toBe(false);
  });

  test('فشل شبكة أثناء الإرسال لا يُسقط نجاح الحجز', async () => {
    await registerDevice(PATIENT, 'some_token');
    const messaging = fakeMessaging({ throwError: new Error('انقطاع شبكة وهمي') });

    const res = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME },
      now: NOW, messaging,
    });
    // الحجز نفسه نجح رغم فشل push تماماً.
    expect(res.status).toBe('Booked');

    const appt = await db.collection('appointments').doc(res.appointmentId).get();
    expect(appt.data().status).toBe('Booked');

    const notif = await getNotification(
      notificationIdFor(res.appointmentId, NOTIFICATION_TYPES.BOOKING_CONFIRMED, 'patient'));
    expect(notif.push.status).toBe('failed');
    expect(notif.push.lastError).toContain('انقطاع شبكة وهمي');
  });
});
