/**
 * اختبارات حذف الحساب — على محاكي Firestore الحقيقي.
 *
 * ما يُختبر هنا ليس «هل استُدعيت الدوال» بل أثر الحذف على قاعدة البيانات
 * نفسها: هل تحرّر المقعد؟ هل بقيت الزيارة في سجل العيادة بلا هوية؟ هل
 * اختفى مدخل الفهرس؟ وهل يستطيع مريض آخر حجز الوقت بعدها؟
 *
 *   firebase emulators:exec --only firestore --project drd-functions-test \
 *     "npm --prefix functions test"
 */

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const { bookAppointmentCore } = require('../booking');
const {
  deleteAccountCore,
  ANONYMOUS_NAME,
  RECENT_LOGIN_MAX_AGE_SECONDS,
} = require('../account');

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'drd-functions-test' });
}
const db = admin.firestore();

const DOCTOR = 'doctorOne';
const PATIENT = 'patientOne';
const OTHER = 'patientTwo';
const PATIENT_PHONE = '201000000002';

const NOW = new Date('2030-03-01T06:00:00Z');
const FUTURE_DATE = '2030-03-03';
const SLOT_TIME = '09:00';

/** رمز مصادقة بتسجيل دخول حديث — `auth_time` بالثواني كما في Firebase. */
const freshAuth = (now = NOW) => ({
  token: { auth_time: Math.floor(now.getTime() / 1000) - 30 },
});

/** رمز جلسة قديمة — تجاوزت السقف بدقيقة. */
const staleAuth = (now = NOW) => ({
  token: {
    auth_time: Math.floor(now.getTime() / 1000) - RECENT_LOGIN_MAX_AGE_SECONDS - 60,
  },
});

/** بريد وهمي: الاختبارات لا تلمس Firebase Auth الحقيقي. */
const fakeAuthAdmin = () => {
  const deleted = [];
  return {
    deleted,
    deleteUser: async (uid) => { deleted.push(uid); },
  };
};

/** لا إرسال Push في الاختبارات — الإشعار مستند في Firestore وهو ما يُفحص. */
const fakeMessaging = { sendEachForMulticast: async () => ({ responses: [] }) };

async function clearFirestore() {
  for (const name of [
    'users', 'slots', 'appointments', 'reviews', 'notifications',
    'phone_index', 'auditLogs',
  ]) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seed() {
  await db.collection('users').doc(DOCTOR).set({
    role: 'doctor', isVerified: true, name: 'د. أحمد', specialization: 'أسنان',
    phone: '201000000001', price: 200, sessionDuration: 30,
    bookingSystemType: 'Individual', workingHours: '09:00 AM - 05:00 PM',
  });
  await db.collection('users').doc(PATIENT).set({
    role: 'patient', name: 'مريض', phone: PATIENT_PHONE, email: 'p@example.com',
  });
  await db.collection('users').doc(OTHER).set({
    role: 'patient', name: 'مريض ٢', phone: '201000000003',
  });
  await db.collection('phone_index').doc(PATIENT_PHONE).set({
    uid: PATIENT, email: 'p@example.com',
  });
}

beforeEach(async () => {
  await clearFirestore();
  await seed();
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app && app.delete()));
});

const book = (uid, data, now = NOW) => bookAppointmentCore({ db, uid, data, now });

const remove = (uid, { auth, data = { confirm: true }, now = NOW, authAdmin } = {}) =>
  deleteAccountCore({
    db,
    uid,
    auth: auth === undefined ? freshAuth(now) : auth,
    data,
    now,
    authAdmin: authAdmin || fakeAuthAdmin(),
    messaging: fakeMessaging,
  });

async function reasonOf(promise) {
  try {
    await promise;
    return null;
  } catch (e) {
    return e.reason || e.code || e.message;
  }
}

const getDoc = async (path) => {
  const snap = await db.doc(path).get();
  return snap.exists ? snap.data() : null;
};

describe('deleteAccount — عقد الاستيراد', () => {
  test('لا يُستعمل admin.firestore.FieldValue — ينهار في محاكي الدوال', () => {
    // ليس تفضيل أسلوب: `admin.firestore.FieldValue` يعمل هنا في jest
    // وينهار داخل محاكي الدوال («Cannot read properties of undefined»)،
    // فيتوقف الحذف في منتصفه بعد أن ألغى المواعيد. اكتُشف بتشغيل الحذف من
    // الواجهة الحقيقية، ولا يلتقطه أي اختبار سلوكي هنا لأن الفرق في
    // بيئة التشغيل لا في المنطق.
    const raw = fs.readFileSync(path.join(__dirname, '..', 'account.js'), 'utf8');
    // التعليقات تشرح الفخّ بالاسم، فلولا تجريدها لسقط الاختبار على شرحه.
    const src = raw
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).not.toMatch(/admin\.firestore\.FieldValue/);
    expect(src).toMatch(/require\('firebase-admin\/firestore'\)/);
  });
});

describe('deleteAccount — الحراسة قبل أي حذف', () => {
  test('بلا هوية مرفوض', async () => {
    expect(await reasonOf(remove(null))).toBe('unauthenticated');
  });

  test('بلا تأكيد صريح مرفوض — ولا تُمَسّ البيانات', async () => {
    expect(await reasonOf(remove(PATIENT, { data: {} })))
      .toBe('confirmation-required');
    expect(await reasonOf(remove(PATIENT, { data: { confirm: 'yes' } })))
      .toBe('confirmation-required');
    expect(await getDoc(`users/${PATIENT}`)).not.toBeNull();
  });

  test('جلسة قديمة مرفوضة — الحذف لا رجعة فيه', async () => {
    expect(await reasonOf(remove(PATIENT, { auth: staleAuth() })))
      .toBe('recent-login-required');
    expect(await getDoc(`users/${PATIENT}`)).not.toBeNull();
  });

  test('رمز بلا auth_time مرفوض — الافتراض الآمن هو الرفض', async () => {
    expect(await reasonOf(remove(PATIENT, { auth: { token: {} } })))
      .toBe('recent-login-required');
  });

  test('حساب الطبيب لا يُحذف ذاتياً', async () => {
    expect(await reasonOf(remove(DOCTOR))).toBe('doctor-account');
    expect(await getDoc(`users/${DOCTOR}`)).not.toBeNull();
  });
});

describe('deleteAccount — ما يُحذف فعلاً', () => {
  test('يحذف المستند والفهرس وحساب المصادقة', async () => {
    const authAdmin = fakeAuthAdmin();
    const res = await remove(PATIENT, { authAdmin });

    expect(res.deleted).toBe(true);
    expect(await getDoc(`users/${PATIENT}`)).toBeNull();
    expect(await getDoc(`phone_index/${PATIENT_PHONE}`)).toBeNull();
    expect(authAdmin.deleted).toEqual([PATIENT]);
  });

  test('لا يحذف مدخل فهرس صار لشخص آخر', async () => {
    // سيناريو حقيقي: أعاد شخص آخر تسجيل نفس الرقم بعد أن تركه صاحبه.
    // حذفه هنا كان سيقطع تسجيل دخول صاحبه الحالي.
    await db.collection('phone_index').doc(PATIENT_PHONE)
      .set({ uid: OTHER, email: 'o@example.com' });

    await remove(PATIENT);
    expect(await getDoc(`phone_index/${PATIENT_PHONE}`))
      .toMatchObject({ uid: OTHER });
  });

  test('يحذف إشعاراته وأجهزته دون إشعارات غيره', async () => {
    await db.collection('notifications').doc('mine').set({
      recipientId: PATIENT, type: 'booking_confirmed', isRead: false,
    });
    await db.collection('notifications').doc('theirs').set({
      recipientId: OTHER, type: 'booking_confirmed', isRead: false,
    });
    await db.collection('users').doc(PATIENT).collection('devices')
      .doc('token_1').set({ token: 'token_1', platform: 'android' });

    const res = await remove(PATIENT);
    expect(res.deletedNotifications).toBe(1);
    expect(res.deletedDevices).toBe(1);
    expect(await getDoc('notifications/mine')).toBeNull();
    expect(await getDoc('notifications/theirs')).not.toBeNull();
  });

  test('يكتب أثراً إدارياً قبل أن يزول المستند', async () => {
    await remove(PATIENT);
    const logs = await db.collection('auditLogs')
      .where('action', '==', 'account.deleted').get();
    expect(logs.size).toBe(1);
    expect(logs.docs[0].data().targetId).toBe(PATIENT);
  });
});

describe('deleteAccount — المواعيد', () => {
  test('يلغي الموعد القائم ويحرّر مقعده فيعود قابلاً للحجز', async () => {
    const appt = await book(PATIENT, {
      doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME,
    });

    const res = await remove(PATIENT);
    expect(res.cancelledAppointments).toBe(1);

    const slot = await getDoc(`slots/${appt.slotId}`);
    expect(slot.bookedCount).toBe(0);
    expect(slot.patientIds).not.toContain(PATIENT);

    // الإثبات الحقيقي: الوقت صار متاحاً لمريض آخر.
    const again = await book(OTHER, {
      doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME,
    });
    expect(again.status).toBe('Booked');
  });

  test('تبقى الزيارة في سجل العيادة بلا هوية', async () => {
    const appt = await book(PATIENT, {
      doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME,
    });

    await remove(PATIENT);

    const doc = await getDoc(`appointments/${appt.appointmentId}`);
    expect(doc).not.toBeNull();            // لم تُمحَ — سجل الطبيب ليس ملكه وحده
    expect(doc.status).toBe('Cancelled');
    expect(doc.patientName).toBe(ANONYMOUS_NAME);
    expect(doc.patientPhone).toBeUndefined();
    expect(doc.patientDeletedAt).toBeTruthy();
  });

  test('يُبلَّغ الطبيب بإلغاء موعده', async () => {
    const appt = await book(PATIENT, {
      doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME,
    });
    await remove(PATIENT);

    const snap = await db.collection('notifications')
      .where('recipientId', '==', DOCTOR)
      .where('appointmentId', '==', appt.appointmentId)
      .get();
    expect(snap.size).toBeGreaterThan(0);
  });

  test('لا يمسّ مواعيد مريض آخر', async () => {
    const mine = await book(PATIENT, {
      doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME,
    });
    const theirs = await book(OTHER, {
      doctorId: DOCTOR, date: FUTURE_DATE, time: '10:00',
    });

    await remove(PATIENT);

    expect((await getDoc(`appointments/${theirs.appointmentId}`)).status)
      .toBe('Booked');
    expect((await getDoc(`appointments/${theirs.appointmentId}`)).patientName)
      .not.toBe(ANONYMOUS_NAME);
    expect((await getDoc(`appointments/${mine.appointmentId}`)).status)
      .toBe('Cancelled');
  });
});

describe('deleteAccount — المراجعات', () => {
  test('تبقى المراجعة ويُطمس اسم كاتبها — تقييم الطبيب لا يتحرك', async () => {
    await db.collection('users').doc(DOCTOR)
      .update({ rating: 5, reviews: 1, ratingSum: 5 });
    await db.collection('reviews').doc('rev_1').set({
      appointmentId: 'a1', doctorId: DOCTOR, patientId: PATIENT,
      patientName: 'مريض', rating: 5, comment: 'ممتاز',
    });

    const res = await remove(PATIENT);
    expect(res.anonymizedReviews).toBe(1);

    const review = await getDoc('reviews/rev_1');
    expect(review).not.toBeNull();
    expect(review.patientName).toBe(ANONYMOUS_NAME);
    expect(review.rating).toBe(5);

    const doctor = await getDoc(`users/${DOCTOR}`);
    expect(doctor.ratingSum).toBe(5);
    expect(doctor.reviews).toBe(1);
  });
});

describe('deleteAccount — إعادة المحاولة', () => {
  test('استدعاء ثانٍ بعد نجاح لا يفشل ولا يغيّر شيئاً', async () => {
    const appt = await book(PATIENT, {
      doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME,
    });
    await remove(PATIENT);

    // المستند اختفى، فالاستدعاء الثاني يمرّ على حساب بلا بيانات.
    const second = await remove(PATIENT);
    expect(second.deleted).toBe(true);

    const slot = await getDoc(`slots/${appt.slotId}`);
    expect(slot.bookedCount).toBe(0);   // لم يُنقَص مرتين
  });

  test('حساب مصادقة محذوف سلفاً لا يُسقط العملية', async () => {
    const authAdmin = {
      deleteUser: async () => {
        const e = new Error('no user');
        e.code = 'auth/user-not-found';
        throw e;
      },
    };
    const res = await remove(PATIENT, { authAdmin });
    expect(res.deleted).toBe(true);
    expect(await getDoc(`users/${PATIENT}`)).toBeNull();
  });
});
