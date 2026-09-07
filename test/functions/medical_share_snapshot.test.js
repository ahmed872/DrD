/**
 * اختبارات دالة بناء لقطة المشاركة (المرحلة الرابعة).
 *
 * القاعدة تُثبت أن المريض لا يكتب محتوى سريرياً. هذا الملف يُثبت الشق
 * الآخر: أن الخادم يبنيه بأمانة، ويرفض ما لا يملكه المريض، وأن اللقطة لا
 * تتغيّر بعد ذلك مهما عُدِّل السجل الأصلي.
 *
 *   firebase emulators:exec --only firestore,functions \
 *     "npm --prefix test/functions test"
 */

const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

if (!admin.apps.length) admin.initializeApp({ projectId: 'demo-drd' });
const db = admin.firestore();

const PATIENT = 'snap_patient_1';
const OTHER = 'snap_patient_2';
const AUTHOR = 'snap_doctor_author';
const RECIPIENT = 'snap_doctor_recipient';
const ENC = 'snap_enc_1';
const ENC2 = 'snap_enc_2';
const FOREIGN = 'snap_enc_foreign';

const shares = () => db.collection('medical_shares');

async function waitForShare(id, predicate, { timeoutMs = 25000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    const snap = await shares().doc(id).get();
    last = snap.exists ? snap.data() : null;
    if (last && predicate(last)) return last;
    await new Promise((r) => setTimeout(r, 300));
  }
  return last;
}

const encounter = (id, patientId, extra = {}) => ({
  appointmentId: id,
  patientId,
  doctorId: AUTHOR,
  doctorName: 'د. أحمد',
  doctorSpecialization: 'طب الأسرة',
  encounterDate: '2030-05-01',
  diagnosis: 'التهاب في الحلق',
  clinicalNotes: 'حرارة 38.',
  treatmentPlan: 'مضاد حيوي خمسة أيام.',
  followUpNotes: '',
  followUpDate: '',
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  ...extra,
});

const request = (overrides = {}) => ({
  patientId: PATIENT,
  patientName: 'أحمد يوسف',
  recipientDoctorId: RECIPIENT,
  recipientDoctorName: 'د. سعيد',
  recipientDoctorSpecialization: 'جلدية',
  encounterIds: [ENC],
  status: 'pending',
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  ...overrides,
});

beforeEach(async () => {
  const old = await shares().get();
  await Promise.all(old.docs.map((d) => d.ref.delete()));
  const logs = await db.collection('audit_logs').get();
  await Promise.all(logs.docs.map((d) => d.ref.delete()));

  await db.collection('encounters').doc(ENC).set(encounter(ENC, PATIENT));
  await db.collection('encounters').doc(ENC2).set(
    encounter(ENC2, PATIENT, { diagnosis: 'حساسية جلدية' }));
  await db.collection('encounters').doc(FOREIGN).set(
    encounter(FOREIGN, OTHER, { diagnosis: 'سجل مريض آخر' }));
});

afterAll(async () => {
  await Promise.all(admin.apps.map((a) => a && a.delete()));
});

describe('بناء اللقطة', () => {
  test('المشاركة تُفعَّل ومعها المحتوى السريري كاملاً', async () => {
    const ref = await shares().add(request());
    const data = await waitForShare(ref.id, (d) => d.status === 'active');

    expect(data.status).toBe('active');
    expect(data.snapshots).toHaveLength(1);

    const s = data.snapshots[0];
    expect(s.encounterId).toBe(ENC);
    expect(s.diagnosis).toBe('التهاب في الحلق');
    expect(s.clinicalNotes).toBe('حرارة 38.');
    expect(s.treatmentPlan).toBe('مضاد حيوي خمسة أيام.');
    // اسم الطبيب المؤلِّف يُنسخ ليفهم المستقبِل السياق.
    expect(s.doctorName).toBe('د. أحمد');
    expect(s.encounterDate).toBe('2030-05-01');
    // أي نسخة التُقطت.
    expect(s.sourceUpdatedAt).toBeTruthy();
    // ولا يُنسخ معرّف الطبيب الخام: ليس ضرورياً للاستشارة.
    expect(s.doctorId).toBeUndefined();
    expect(s.patientId).toBeUndefined();
  }, 45000);

  test('مشاركة عدة سجلات في موافقة واحدة', async () => {
    const ref = await shares().add(request({ encounterIds: [ENC, ENC2] }));
    const data = await waitForShare(ref.id, (d) => d.status === 'active');

    expect(data.snapshots).toHaveLength(2);
    const diagnoses = data.snapshots.map((s) => s.diagnosis).sort();
    expect(diagnoses).toEqual(['التهاب في الحلق', 'حساسية جلدية'].sort());
  }, 45000);

  test('مشاركة سجل لا يملكه المريض تُرفض', async () => {
    // القاعدة لا تستطيع فحص قائمة معرّفات، فهذا هو الحارس.
    const ref = await shares().add(request({ encounterIds: [FOREIGN] }));
    const data = await waitForShare(ref.id, (d) => d.status === 'rejected');

    expect(data.status).toBe('rejected');
    expect(data.rejectionReason).toContain('لا يخصّك');
    expect(data.snapshots).toBeUndefined();
  }, 45000);

  test('سجل واحد غير مملوك يُسقط المشاركة كلها', async () => {
    // لا تمرير جزئي: مشاركة نصفها مشروع تظل تسريباً.
    const ref = await shares().add(request({ encounterIds: [ENC, FOREIGN] }));
    const data = await waitForShare(ref.id, (d) => d.status === 'rejected');
    expect(data.status).toBe('rejected');
    expect(data.snapshots).toBeUndefined();
  }, 45000);

  test('سجل غير موجود يُرفض بسبب مفهوم', async () => {
    const ref = await shares().add(request({ encounterIds: ['ghost'] }));
    const data = await waitForShare(ref.id, (d) => d.status === 'rejected');
    expect(data.rejectionReason).toContain('لم يعد موجوداً');
  }, 45000);
});

describe('ثبات اللقطة', () => {
  test('تعديل السجل الأصلي لا يغيّر ما شُورك', async () => {
    // جوهر النموذج: الموافقة على محتوى، لا على موقع متغيّر.
    const ref = await shares().add(request());
    await waitForShare(ref.id, (d) => d.status === 'active');

    await db.collection('encounters').doc(ENC).update({
      diagnosis: 'تشخيص جديد تماماً',
      treatmentPlan: 'علاج مختلف',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await new Promise((r) => setTimeout(r, 3000));

    const after = (await shares().doc(ref.id).get()).data();
    expect(after.snapshots[0].diagnosis).toBe('التهاب في الحلق');
    expect(after.snapshots[0].treatmentPlan).toBe('مضاد حيوي خمسة أيام.');
  }, 45000);

  test('مشاركة جديدة بعد التعديل تلتقط النسخة الحالية', async () => {
    const first = await shares().add(request());
    await waitForShare(first.id, (d) => d.status === 'active');

    await db.collection('encounters').doc(ENC).update({
      diagnosis: 'تشخيص محدَّث',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const second = await shares().add(request());
    const data = await waitForShare(second.id, (d) => d.status === 'active');

    expect(data.snapshots[0].diagnosis).toBe('تشخيص محدَّث');
    // والقديمة كما هي — موافقتان على محتويين مختلفين.
    const old = (await shares().doc(first.id).get()).data();
    expect(old.snapshots[0].diagnosis).toBe('التهاب في الحلق');
  }, 60000);

  test('إعادة التشغيل على مشاركة نشطة لا تعيد البناء', async () => {
    const ref = await shares().add(request());
    await waitForShare(ref.id, (d) => d.status === 'active');

    await db.collection('encounters').doc(ENC).update({
      diagnosis: 'تغيير بعد التفعيل',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // كتابة لا تغيّر الحالة.
    await shares().doc(ref.id).update({ patientName: 'أحمد ي.' });
    await new Promise((r) => setTimeout(r, 3000));

    const after = (await shares().doc(ref.id).get()).data();
    expect(after.snapshots[0].diagnosis).toBe('التهاب في الحلق');
  }, 45000);
});

describe('التدقيق', () => {
  test('الإنشاء والإلغاء يتركان أثراً', async () => {
    const ref = await shares().add(request());
    await waitForShare(ref.id, (d) => d.status === 'active');

    let created = await db.collection('audit_logs')
      .where('action', '==', 'medical_share.created')
      .where('subjectId', '==', ref.id).get();
    expect(created.empty).toBe(false);
    expect(created.docs[0].data().actorId).toBe(PATIENT);
    expect(created.docs[0].data().details.recipientDoctorId).toBe(RECIPIENT);

    await shares().doc(ref.id).update({
      status: 'revoked',
      revokedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const deadline = Date.now() + 20000;
    let revoked;
    while (Date.now() < deadline) {
      revoked = await db.collection('audit_logs')
        .where('action', '==', 'medical_share.revoked')
        .where('subjectId', '==', ref.id).get();
      if (!revoked.empty) break;
      await new Promise((r) => setTimeout(r, 300));
    }
    expect(revoked.empty).toBe(false);
    expect(revoked.docs[0].data().actorId).toBe(PATIENT);
  }, 60000);
});
