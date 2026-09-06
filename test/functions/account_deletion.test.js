/**
 * حذف الحساب — ما يُمحى وما يبقى.
 *
 * القاعدة تُثبت أن أحداً لا يطلب حذف حساب غيره. هذا الملف يُثبت أن الحذف
 * **يفعل ما وعد به بالضبط**: لا أقل — فيبقى بيان شخصي حيّ — ولا أكثر — فيُمحى
 * سجل سريري يخصّ الطبيب والعيادة أيضاً.
 *
 * أخطر اختبار هنا هو `encounters`: مسار حذف يمحو السجل السريري يعطي المريض
 * سلطة أحادية على وثيقة طبية لطرفين.
 *
 *   firebase emulators:exec --only firestore,functions,auth \
 *     "npm --prefix test/functions test"
 */

const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';

if (!admin.apps.length) admin.initializeApp({ projectId: 'demo-drd' });
const db = admin.firestore();

const PATIENT = 'fn_del_patient';
const DOCTOR = 'fn_del_doctor';
const PHONE = '201000000091';

const FUTURE_SLOT = `${DOCTOR}_2030-09-09_10-00`;
const FUTURE_APPT = `${FUTURE_SLOT}__${PATIENT}`;
const PAST_APPT = `${DOCTOR}_2020-01-01_09-00__${PATIENT}`;

async function waitFor(ref, predicate, { timeoutMs = 30000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    const snap = await ref.get();
    last = snap.exists ? snap.data() : null;
    if (predicate(last)) return last;
    await new Promise((r) => setTimeout(r, 300));
  }
  return last;
}

async function seed() {
  await db.collection('users').doc(DOCTOR).set({
    role: 'doctor', name: 'د. سعيد', phone: '201000000092',
  });
  await db.collection('users').doc(PATIENT).set({
    role: 'patient',
    name: 'مريض للحذف',
    phone: PHONE,
    email: 'del@example.com',
    birthDate: '1990-01-01',
    gender: 'male',
    emailVerified: true,
  });
  await db.collection('phone_index').doc(PHONE).set({
    uid: PATIENT, email: 'del@example.com',
  });

  await db.collection('slots').doc(FUTURE_SLOT).set({
    doctorId: DOCTOR, appointmentDate: '2030-09-09', startTime: '10:00',
    capacity: 4, bookedCount: 2,
  });
  await db.collection('appointments').doc(FUTURE_APPT).set({
    doctorId: DOCTOR, patientId: PATIENT, slotId: FUTURE_SLOT,
    appointmentDate: '2030-09-09', startTime: '10:00', status: 'Booked',
  });
  await db.collection('appointments').doc(PAST_APPT).set({
    doctorId: DOCTOR, patientId: PATIENT,
    appointmentDate: '2020-01-01', startTime: '09:00', status: 'Completed',
  });

  // سجل سريري لزيارة تمّت — الوثيقة التي يجب ألا تُمحى.
  await db.collection('encounters').doc(PAST_APPT).set({
    appointmentId: PAST_APPT, patientId: PATIENT, doctorId: DOCTOR,
    doctorName: 'د. سعيد', encounterDate: '2020-01-01',
    diagnosis: 'التهاب حاد', clinicalNotes: 'راجع بعد أسبوع',
  });

  await db.collection('medical_shares').doc('fn_del_share').set({
    patientId: PATIENT, recipientDoctorId: DOCTOR,
    status: 'active', encounterIds: [PAST_APPT],
  });

  await db.collection('reviews').doc(PAST_APPT).set({
    doctorId: DOCTOR, patientId: PATIENT, patientName: 'مريض للحذف',
    appointmentId: PAST_APPT, rating: 5, comment: 'ممتاز',
  });

  try {
    await admin.auth().createUser({
      uid: PATIENT, email: 'del@example.com', password: 'password123',
    });
  } catch (e) {
    if (e.code !== 'auth/uid-already-exists') throw e;
  }
}

async function cleanup() {
  await db.collection('deletion_requests').doc(PATIENT).delete();
  for (const [coll, id] of [
    ['appointments', FUTURE_APPT], ['appointments', PAST_APPT],
    ['encounters', PAST_APPT], ['medical_shares', 'fn_del_share'],
    ['reviews', PAST_APPT], ['slots', FUTURE_SLOT],
    ['phone_index', PHONE], ['users', PATIENT], ['users', DOCTOR],
    ['doctor_profiles', DOCTOR],
  ]) {
    await db.collection(coll).doc(id).delete();
  }
  try {
    await admin.auth().deleteUser(PATIENT);
  } catch (_) {
    // غير موجود — نتيجة صحيحة.
  }
}

describe('حذف الحساب', () => {
  let request;

  beforeAll(async () => {
    await cleanup();
    await seed();
    await db.collection('deletion_requests').doc(PATIENT).set({
      status: 'requested',
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    request = await waitFor(
      db.collection('deletion_requests').doc(PATIENT),
      (d) => d !== null && d.status !== 'requested'
    );
  }, 60000);

  afterAll(async () => {
    await cleanup();
  });

  test('الطلب ينتهي مكتملاً لا فاشلاً', () => {
    // الحالة `failed` نتيجة مشروعة يجب أن يراها المستخدم بدل ادّعاء كاذب،
    // لكنها هنا تعني أن خطوة تعثّرت فعلاً.
    expect(request).not.toBeNull();
    expect(request.status).toBe('completed');
  });

  test('البيان الشخصي مُحي والمستند مُجهَّل', async () => {
    const user = (await db.collection('users').doc(PATIENT).get()).data();
    expect(user.name).toBe('حساب محذوف');
    expect(user.deleted).toBe(true);
    for (const field of ['phone', 'email', 'birthDate', 'gender']) {
      expect(user[field]).toBeUndefined();
    }
  });

  test('المستند يبقى موجوداً — لا يُحذف', () => {
    // الحذف الكامل يترك `encounters` و`appointments` تشير إلى معرّف بلا
    // مستند، فتنكسر كل شاشة تعرض اسماً.
    return db.collection('users').doc(PATIENT).get().then((snap) => {
      expect(snap.exists).toBe(true);
    });
  });

  test('السجل السريري يبقى كما هو', async () => {
    const enc = await db.collection('encounters').doc(PAST_APPT).get();
    expect(enc.exists).toBe(true);
    expect(enc.data().diagnosis).toBe('التهاب حاد');
  });

  test('الموعد القادم أُلغي وحُرِّر مكانه في الخانة', async () => {
    const appt = (await db.collection('appointments').doc(FUTURE_APPT).get())
      .data();
    expect(appt.status).toBe('Cancelled');

    const slot = (await db.collection('slots').doc(FUTURE_SLOT).get()).data();
    expect(slot.bookedCount).toBe(1);
  });

  test('الموعد المكتمل لم يُمَس', async () => {
    const appt = (await db.collection('appointments').doc(PAST_APPT).get())
      .data();
    expect(appt.status).toBe('Completed');
  });

  test('المشاركة الطبية أُلغيت', async () => {
    const share = (await db.collection('medical_shares').doc('fn_del_share')
      .get()).data();
    expect(share.status).toBe('revoked');
  });

  test('المراجعة بقيت وتقييمها لم يتغيّر، والاسم جُهِّل', async () => {
    // حذف المراجعة يغيّر متوسط الطبيب بأثر رجعي بسبب مغادرة مريض.
    const review = (await db.collection('reviews').doc(PAST_APPT).get()).data();
    expect(review.rating).toBe(5);
    expect(review.patientName).toBe('مريض محذوف');
  });

  test('مدخل فهرس الجوال حُذف فعاد الرقم قابلاً للتسجيل', async () => {
    const idx = await db.collection('phone_index').doc(PHONE).get();
    expect(idx.exists).toBe(false);
  });

  test('حساب المصادقة حُذف فلا يمكن تسجيل الدخول', async () => {
    await expect(admin.auth().getUser(PATIENT)).rejects.toThrow();
  });

  test('العملية مسجَّلة في سجل التدقيق', async () => {
    const logs = await db.collection('audit_logs')
      .where('subjectId', '==', PATIENT).get();
    const actions = logs.docs.map((d) => d.data().action);
    expect(actions).toContain('account_deleted');
  });
});
