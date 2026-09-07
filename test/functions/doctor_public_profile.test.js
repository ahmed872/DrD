/**
 * الإسقاط العام للطبيب — الشق الخادمي من إغلاق `users`.
 *
 * القاعدة تُثبت أن العميل لم يعد يقرأ مستند الطبيب. هذا الملف يُثبت الشق
 * الآخر: أن الخادم **ينشئ البديل فعلاً وبالحقول الصحيحة**. بلا الاثنين معاً
 * يكون ما بُني إغلاقاً لدليل الأطباء لا حمايةً لخصوصيتهم.
 *
 * وأهم اختبار هنا ليس أن الحقول العامة تصل، بل أن **الخاصة لا تصل**: فصل
 * المستندين بلا فصل الحقول يعيد التسريب كاملاً بينما تبدو القاعدة مغلقة.
 *
 *   firebase emulators:exec --only firestore,functions,auth \
 *     "npm --prefix test/functions test"
 */

const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

if (!admin.apps.length) admin.initializeApp({ projectId: 'demo-drd' });
const db = admin.firestore();

const DOCTOR = 'fn_profile_doctor';
const PATIENT = 'fn_profile_patient';

async function waitFor(ref, predicate, { timeoutMs = 20000 } = {}) {
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

const doctorDoc = (overrides = {}) => ({
  role: 'doctor',
  name: 'د. أحمد يوسف',
  phone: '201000000077',
  email: 'doctor@example.com',
  birthDate: '1980-05-05',
  gender: 'male',
  emailVerified: true,
  clinicNameAr: 'عيادة النور',
  clinicLocation: 'المنصورة',
  specialization: 'باطنة',
  bio: 'استشاري باطنة',
  price: 250,
  sessionDuration: 30,
  maxPatientsPerSlot: 4,
  bookingSystemType: 'Individual',
  workingHours: '09:00 - 17:00',
  workingDays: { sat: true, sun: true },
  rating: 4.5,
  reviews: 12,
  ...overrides,
});

beforeEach(async () => {
  await db.collection('doctor_profiles').doc(DOCTOR).delete();
  await db.collection('doctor_profiles').doc(PATIENT).delete();
  await db.collection('users').doc(DOCTOR).delete();
  await db.collection('users').doc(PATIENT).delete();
});

test('كتابة مستند طبيب تُنشئ ملفاً عاماً', async () => {
  await db.collection('users').doc(DOCTOR).set(doctorDoc());

  const profile = await waitFor(
    db.collection('doctor_profiles').doc(DOCTOR),
    (d) => d !== null
  );

  expect(profile).not.toBeNull();
  expect(profile.name).toBe('د. أحمد يوسف');
  expect(profile.specialization).toBe('باطنة');
  expect(profile.price).toBe(250);
  expect(profile.rating).toBe(4.5);
  expect(profile.doctorId).toBe(DOCTOR);
});

test('الملف العام لا يحمل أي بيان شخصي', async () => {
  // الاختبار الذي يجعل بقية العمل ذا معنى.
  await db.collection('users').doc(DOCTOR).set(doctorDoc());

  const profile = await waitFor(
    db.collection('doctor_profiles').doc(DOCTOR),
    (d) => d !== null
  );

  for (const field of [
    'phone', 'email', 'birthDate', 'gender', 'emailVerified', 'role',
  ]) {
    expect(profile).not.toHaveProperty(field);
  }
});

test('المريض لا يُنشأ له ملف عام', async () => {
  await db.collection('users').doc(PATIENT).set({
    role: 'patient', name: 'مريض', phone: '201000000078',
  });

  // انتظار قصير مقصود: لا يوجد شرط إيجابي ننتظره، والمطلوب إثبات أن شيئاً
  // **لم** يحدث. المهلة الطويلة هنا تُبطئ الحزمة بلا فائدة.
  await new Promise((r) => setTimeout(r, 3000));
  const snap = await db.collection('doctor_profiles').doc(PATIENT).get();
  expect(snap.exists).toBe(false);
});

test('خفض الدور يحذف الملف العام', async () => {
  await db.collection('users').doc(DOCTOR).set(doctorDoc());
  await waitFor(db.collection('doctor_profiles').doc(DOCTOR), (d) => d !== null);

  await db.collection('users').doc(DOCTOR).update({ role: 'patient' });

  const gone = await waitFor(
    db.collection('doctor_profiles').doc(DOCTOR),
    (d) => d === null
  );
  expect(gone).toBeNull();
});

test('تعليم الحساب محذوفاً يزيل الملف العام', async () => {
  await db.collection('users').doc(DOCTOR).set(doctorDoc());
  await waitFor(db.collection('doctor_profiles').doc(DOCTOR), (d) => d !== null);

  await db.collection('users').doc(DOCTOR).update({ deleted: true });

  const gone = await waitFor(
    db.collection('doctor_profiles').doc(DOCTOR),
    (d) => d === null
  );
  expect(gone).toBeNull();
});

test('إفراغ حقل يُزيله من الملف العام ولا يُبقي القديم منشوراً', async () => {
  // `set` بلا `merge`: لو دُمج، لبقيت نبذة حذفها الطبيب معروضة إلى الأبد.
  await db.collection('users').doc(DOCTOR).set(doctorDoc());
  await waitFor(
    db.collection('doctor_profiles').doc(DOCTOR),
    (d) => d !== null && d.bio === 'استشاري باطنة'
  );

  await db.collection('users').doc(DOCTOR).update({
    bio: admin.firestore.FieldValue.delete(),
  });

  const updated = await waitFor(
    db.collection('doctor_profiles').doc(DOCTOR),
    (d) => d !== null && d.bio === undefined
  );
  expect(updated.bio).toBeUndefined();
  expect(updated.name).toBe('د. أحمد يوسف');
});
