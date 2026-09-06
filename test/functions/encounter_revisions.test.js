/**
 * اختبارات دالة نسخ تصحيح السجل السريري (المرحلة الثالثة).
 *
 * القاعدة تُثبت أن العميل لا يكتب في `revisions/`. هذا الملف يُثبت الشق
 * الآخر: أن الخادم يكتبها فعلاً عند التعديل. بلا الاثنين معاً يبقى وعد
 * «تاريخ السجل محفوظ» ادّعاءً.
 *
 *   firebase emulators:exec --only firestore,functions \
 *     "npm --prefix test/functions test"
 */

const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

if (!admin.apps.length) admin.initializeApp({ projectId: 'demo-drd' });
const db = admin.firestore();

const DOCTOR = 'rev_doctor_1';
const PATIENT = 'rev_patient_1';
const APPT = 'rev_appt_1';

const baseEncounter = () => ({
  appointmentId: APPT,
  patientId: PATIENT,
  doctorId: DOCTOR,
  encounterDate: '2030-03-01',
  diagnosis: 'التهاب في الحلق',
  clinicalNotes: 'حرارة 38.',
  treatmentPlan: 'مضاد حيوي.',
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
});

async function waitFor(fn, { timeoutMs = 20000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    last = await fn();
    if (last) return last;
    await new Promise((r) => setTimeout(r, 300));
  }
  return last;
}

const encounterRef = () => db.collection('encounters').doc(APPT);
const revisions = () => encounterRef().collection('revisions').get();

beforeEach(async () => {
  const revs = await revisions();
  await Promise.all(revs.docs.map((d) => d.ref.delete()));
  await encounterRef().delete();
  const logs = await db.collection('audit_logs').get();
  await Promise.all(logs.docs.map((d) => d.ref.delete()));
});

afterAll(async () => {
  await Promise.all(admin.apps.map((a) => a && a.delete()));
});

describe('نسخ تصحيح السجل السريري', () => {
  test('الإنشاء يترك أثراً في التدقيق ولا يُنشئ نسخة', async () => {
    await encounterRef().set(baseEncounter());

    const logs = await waitFor(async () => {
      const s = await db.collection('audit_logs')
        .where('action', '==', 'encounter.created')
        .where('subjectId', '==', APPT).get();
      return s.empty ? null : s;
    });
    expect(logs.empty).toBe(false);
    expect(logs.docs[0].data().subjectId).toBe(APPT);
    expect(logs.docs[0].data().actorId).toBe(DOCTOR);

    // لا نسخة عند الإنشاء: لا يوجد «ما قبل» لتُحفَظ.
    const revs = await revisions();
    expect(revs.size).toBe(0);
  }, 40000);

  test('التعديل يحفظ ما كان عليه السجل قبله', async () => {
    await encounterRef().set(baseEncounter());
    await waitFor(async () => {
      const s = await db.collection('audit_logs')
        .where('action', '==', 'encounter.created')
        .where('subjectId', '==', APPT).get();
      return s.empty ? null : s;
    });

    await encounterRef().update({
      diagnosis: 'التهاب لوزتين حاد',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const revs = await waitFor(async () => {
      const s = await revisions();
      return s.empty ? null : s;
    });

    expect(revs.size).toBe(1);
    const rev = revs.docs[0].data();
    // النسخة تحمل النص **السابق**، لا الجديد.
    expect(rev.diagnosis).toBe('التهاب في الحلق');
    // والهوية معها، فتبقى مفهومة بذاتها لو قُرئت وحدها — وهو ما تحتاجه
    // المرحلة الرابعة لتحديد ما شُورك ومتى.
    expect(rev.encounterId).toBe(APPT);
    expect(rev.patientId).toBe(PATIENT);
    expect(rev.doctorId).toBe(DOCTOR);
    expect(rev.appointmentId).toBe(APPT);
    expect(rev.supersededAt).toBeTruthy();

    // والسجل نفسه يحمل النص الجديد.
    const now = await encounterRef().get();
    expect(now.data().diagnosis).toBe('التهاب لوزتين حاد');
  }, 40000);

  test('التعديل يُسجَّل في التدقيق مع الحقول التي تغيّرت', async () => {
    await encounterRef().set(baseEncounter());
    await waitFor(async () => {
      const s = await db.collection('audit_logs')
        .where('action', '==', 'encounter.created')
        .where('subjectId', '==', APPT).get();
      return s.empty ? null : s;
    });

    await encounterRef().update({ treatmentPlan: 'مسكّن فقط.' });

    const logs = await waitFor(async () => {
      const s = await db.collection('audit_logs')
        .where('action', '==', 'encounter.updated')
        .where('subjectId', '==', APPT).get();
      return s.empty ? null : s;
    });
    const entry = logs.docs[0].data();
    expect(entry.subjectId).toBe(APPT);
    expect(entry.details.changed).toEqual(['treatmentPlan']);
    expect(entry.at).toBeTruthy();
  }, 40000);

  test('تعديل لا يمسّ المحتوى السريري لا يُنشئ نسخة', async () => {
    // طابع زمني متغيّر ليس تصحيحاً طبياً؛ نسخة له تملأ السجل بلا معنى.
    await encounterRef().set(baseEncounter());
    await waitFor(async () => {
      const s = await db.collection('audit_logs')
        .where('action', '==', 'encounter.created')
        .where('subjectId', '==', APPT).get();
      return s.empty ? null : s;
    });

    await encounterRef().update({
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await new Promise((r) => setTimeout(r, 3000));

    const revs = await revisions();
    expect(revs.size).toBe(0);
  }, 40000);

  test('تعديلان متتاليان يتركان نسختين مرتّبتين', async () => {
    await encounterRef().set(baseEncounter());
    await waitFor(async () => {
      const s = await db.collection('audit_logs')
        .where('action', '==', 'encounter.created')
        .where('subjectId', '==', APPT).get();
      return s.empty ? null : s;
    });

    await encounterRef().update({ diagnosis: 'تشخيص ثانٍ' });
    await waitFor(async () => {
      const s = await revisions();
      return s.size >= 1 ? s : null;
    });

    await encounterRef().update({ diagnosis: 'تشخيص ثالث' });
    const revs = await waitFor(async () => {
      const s = await revisions();
      return s.size >= 2 ? s : null;
    });

    expect(revs.size).toBe(2);
    const saved = revs.docs.map((d) => d.data().diagnosis).sort();
    expect(saved).toEqual(['التهاب في الحلق', 'تشخيص ثانٍ'].sort());
  }, 60000);
});
