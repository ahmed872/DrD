/**
 * اختبارات أمان مشاركة السجلات الطبية (المرحلة الرابعة).
 *
 * السؤالان: هل يستطيع أحد أن يقرأ ما لم يُشارَك معه؟ وهل يستطيع المريض أن
 * يختلق محتوى طبياً ينسبه لطبيبه؟
 *
 *   firebase emulators:exec --only firestore "npm --prefix test/firestore_rules test"
 */

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertFails, assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  setDoc, getDoc, updateDoc, doc, deleteDoc, addDoc,
  collection, query, where, getDocs, serverTimestamp,
} = require('firebase/firestore');

let testEnv;

const PATIENT = 'sh_patient_1';
const OTHER = 'sh_patient_2';
const MY_DOCTOR = 'sh_doctor_author';   // الطبيب الذي كتب السجل
const RECIPIENT = 'sh_doctor_recipient'; // الطبيب المستقبِل
const STRANGER = 'sh_doctor_stranger';   // طبيب لا علاقة له
const ADMIN = 'sh_admin_1';

const ENC = 'sh_appt_1';   // معرّف السجل = معرّف الموعد
const ENC2 = 'sh_appt_2';

/** طلب مشاركة صالح الشكل — بلا محتوى سريري، كما يرسله المريض. */
const shareRequest = (overrides = {}) => ({
  patientId: PATIENT,
  patientName: 'أحمد يوسف',
  recipientDoctorId: RECIPIENT,
  recipientDoctorName: 'د. سعيد',
  recipientDoctorSpecialization: 'جلدية',
  encounterIds: [ENC],
  status: 'pending',
  createdAt: serverTimestamp(),
  ...overrides,
});

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'drd-rules-test',
    firestore: {
      host: '127.0.0.1', port: 8080,
      rules: fs.readFileSync(
        path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });
});

afterAll(async () => { if (testEnv) await testEnv.cleanup(); });

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', PATIENT), { role: 'patient', name: 'أحمد' });
    await setDoc(doc(db, 'users', OTHER), { role: 'patient', name: 'آخر' });
    await setDoc(doc(db, 'users', MY_DOCTOR), { role: 'doctor', name: 'د. أحمد' });
    await setDoc(doc(db, 'users', RECIPIENT), { role: 'doctor', name: 'د. سعيد' });
    await setDoc(doc(db, 'users', STRANGER), { role: 'doctor', name: 'د. غريب' });
    await setDoc(doc(db, 'users', ADMIN), { role: 'patient', name: 'مشرف' });
    await setDoc(doc(db, 'admins', ADMIN), {});

    for (const id of [ENC, ENC2]) {
      await setDoc(doc(db, 'appointments', id), {
        doctorId: MY_DOCTOR, patientId: PATIENT,
        appointmentDate: '2030-05-01', startTime: '09:00', status: 'Completed',
      });
      await setDoc(doc(db, 'encounters', id), {
        appointmentId: id, patientId: PATIENT, doctorId: MY_DOCTOR,
        doctorName: 'د. أحمد', doctorSpecialization: 'طب الأسرة',
        encounterDate: '2030-05-01', diagnosis: 'التهاب',
        clinicalNotes: 'حرارة 38.', treatmentPlan: 'مضاد حيوي.',
        createdAt: new Date(), updatedAt: new Date(),
      });
    }
  });
});

const asPatient = () => testEnv.authenticatedContext(PATIENT).firestore();
const asOther = () => testEnv.authenticatedContext(OTHER).firestore();
const asRecipient = () => testEnv.authenticatedContext(RECIPIENT).firestore();
const asStranger = () => testEnv.authenticatedContext(STRANGER).firestore();
const asAuthor = () => testEnv.authenticatedContext(MY_DOCTOR).firestore();
const asAdmin = () => testEnv.authenticatedContext(ADMIN).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

/** يزرع مشاركة بحالة معيّنة، كما تكتبها الدالة على الخادم. */
const seedShare = (id, extra = {}) =>
  testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'medical_shares', id), {
      ...shareRequest(),
      createdAt: new Date(),
      status: 'active',
      activatedAt: new Date(),
      snapshots: [{
        encounterId: ENC, encounterDate: '2030-05-01',
        doctorName: 'د. أحمد', doctorSpecialization: 'طب الأسرة',
        diagnosis: 'التهاب', clinicalNotes: 'حرارة 38.',
        treatmentPlan: 'مضاد حيوي.', followUpNotes: '', followUpDate: '',
      }],
      ...extra,
    });
  });

// ===========================================================================
describe('إنشاء المشاركة — الموافقة بيد المريض', () => {
  test('المريض يشارك سجله مع طبيب معتمَد', async () => {
    await assertSucceeds(
      addDoc(collection(asPatient(), 'medical_shares'), shareRequest()));
  });

  test('لا يشارك المريض باسم مريض آخر', async () => {
    await assertFails(
      addDoc(collection(asPatient(), 'medical_shares'),
             shareRequest({ patientId: OTHER })));
  });

  test('لا ينشئ الطبيب مشاركة نيابةً عن المريض', async () => {
    // الموافقة قرار المريض وحده — لا يمنحها الطبيب لنفسه.
    await assertFails(
      addDoc(collection(asRecipient(), 'medical_shares'), shareRequest()));
    await assertFails(
      addDoc(collection(asRecipient(), 'medical_shares'),
             shareRequest({ patientId: RECIPIENT })));
  });

  test('لا يمنح الطبيب نفسه وصولاً لسجل مريض', async () => {
    await assertFails(
      addDoc(collection(asStranger(), 'medical_shares'),
             shareRequest({ patientId: PATIENT,
                            recipientDoctorId: STRANGER })));
  });

  test('المستقبِل يجب أن يكون طبيباً معتمَداً', async () => {
    // آلية واحدة للاعتماد: `role == 'doctor'` يكتبه الخادم بعد موافقة
    // المشرف. لا آلية ثانية.
    await assertFails(
      addDoc(collection(asPatient(), 'medical_shares'),
             shareRequest({ recipientDoctorId: OTHER })));
    await assertFails(
      addDoc(collection(asPatient(), 'medical_shares'),
             shareRequest({ recipientDoctorId: 'ghost_doctor' })));
  });

  test('لا تُنشأ مشاركة نشطة مباشرةً — تخطّي الخادم', async () => {
    // هذا هو الهجوم المحوري: لو مرّ لأصبح المريض قادراً على كتابة اللقطة.
    await assertFails(
      addDoc(collection(asPatient(), 'medical_shares'),
             shareRequest({ status: 'active' })));
  });

  test('لا يكتب المريض محتوى سريرياً في المشاركة', async () => {
    // اختلاق تشخيص ونسبته لطبيب هو تزوير طبي بعواقب علاجية.
    await assertFails(
      addDoc(collection(asPatient(), 'medical_shares'),
             shareRequest({
               snapshots: [{ encounterId: ENC, diagnosis: 'يحتاج مورفين' }],
             })));
  });

  test('لا يكتب المريض حقول الخادم', async () => {
    for (const extra of [
      { activatedAt: new Date() },
      { rejectionReason: 'لا شيء' },
      { revokedAt: new Date() },
    ]) {
      await assertFails(
        addDoc(collection(asPatient(), 'medical_shares'),
               shareRequest(extra)));
    }
  });

  test('تُرفض قائمة السجلات الفارغة أو الضخمة', async () => {
    await assertFails(
      addDoc(collection(asPatient(), 'medical_shares'),
             shareRequest({ encounterIds: [] })));
    await assertFails(
      addDoc(collection(asPatient(), 'medical_shares'),
             shareRequest({ encounterIds: Array(21).fill(ENC) })));
  });

  test('الزائر غير المسجَّل لا ينشئ مشاركة', async () => {
    await assertFails(
      addDoc(collection(asAnon(), 'medical_shares'), shareRequest()));
  });
});

// ===========================================================================
describe('القراءة — من يرى ماذا', () => {
  beforeEach(() => seedShare('share_1'));

  test('المريض يقرأ مشاركته', async () => {
    await assertSucceeds(getDoc(doc(asPatient(), 'medical_shares', 'share_1')));
  });

  test('الطبيب المستقبِل يقرأ ما وُجّه إليه', async () => {
    await assertSucceeds(
      getDoc(doc(asRecipient(), 'medical_shares', 'share_1')));
  });

  test('طبيب آخر لا يقرأ المشاركة', async () => {
    await assertFails(getDoc(doc(asStranger(), 'medical_shares', 'share_1')));
  });

  test('حتى الطبيب المؤلِّف لا يقرأ مشاركة لم تُوجَّه إليه', async () => {
    // كتابته للسجل لا تمنحه اطّلاعاً على مع مَن شاركه المريض.
    await assertFails(getDoc(doc(asAuthor(), 'medical_shares', 'share_1')));
  });

  test('مريض آخر لا يقرأ المشاركة', async () => {
    await assertFails(getDoc(doc(asOther(), 'medical_shares', 'share_1')));
  });

  test('المشرف لا يقرأ المشاركات السريرية', async () => {
    await assertFails(getDoc(doc(asAdmin(), 'medical_shares', 'share_1')));
    await assertFails(getDocs(collection(asAdmin(), 'medical_shares')));
  });

  test('الزائر غير المسجَّل لا يقرأ شيئاً', async () => {
    await assertFails(getDoc(doc(asAnon(), 'medical_shares', 'share_1')));
  });

  test('المشاركة المعلّقة لا يقرأها الطبيب بعد', async () => {
    // النافذة تفشل مغلقة: لا محتوى قبل أن يوثّقه الخادم.
    await seedShare('share_pending', { status: 'pending', snapshots: null });
    await assertFails(
      getDoc(doc(asRecipient(), 'medical_shares', 'share_pending')));
    await assertSucceeds(
      getDoc(doc(asPatient(), 'medical_shares', 'share_pending')));
  });

  test('المشاركة المرفوضة لا يقرأها الطبيب', async () => {
    await seedShare('share_rejected', {
      status: 'rejected', rejectionReason: 'سجل غير مملوك',
    });
    await assertFails(
      getDoc(doc(asRecipient(), 'medical_shares', 'share_rejected')));
  });
});

// ===========================================================================
describe('الاستعلامات تطابق القاعدة', () => {
  beforeEach(() => seedShare('share_1'));

  test('المريض يسرد مشاركاته وحدها', async () => {
    await assertSucceeds(getDocs(query(
      collection(asPatient(), 'medical_shares'),
      where('patientId', '==', PATIENT))));
    // بلا قيد: يُرفض كاملاً — القاعدة لا تُرشِّح.
    await assertFails(getDocs(collection(asPatient(), 'medical_shares')));
    await assertFails(getDocs(query(
      collection(asPatient(), 'medical_shares'),
      where('patientId', '==', OTHER))));
  });

  test('صندوق الطبيب يشترط قيد الحالة', async () => {
    await assertSucceeds(getDocs(query(
      collection(asRecipient(), 'medical_shares'),
      where('recipientDoctorId', '==', RECIPIENT),
      where('status', '==', 'active'))));
    // بلا قيد الحالة يُرفض: وإلا لقرأ الطبيب مشاركات ملغاة.
    await assertFails(getDocs(query(
      collection(asRecipient(), 'medical_shares'),
      where('recipientDoctorId', '==', RECIPIENT))));
  });

  test('لا يعدّ الطبيب مشاركات مريض بعينه', async () => {
    await assertFails(getDocs(query(
      collection(asRecipient(), 'medical_shares'),
      where('patientId', '==', PATIENT))));
    await assertFails(getDocs(query(
      collection(asStranger(), 'medical_shares'),
      where('recipientDoctorId', '==', RECIPIENT),
      where('status', '==', 'active'))));
  });
});

// ===========================================================================
describe('ثبات اللقطة والبيانات', () => {
  beforeEach(() => seedShare('share_1'));

  test('المريض لا يعدّل اللقطة بعد المشاركة', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'medical_shares', 'share_1'),
      { snapshots: [{ encounterId: ENC, diagnosis: 'تشخيص مختلق' }] }));
  });

  test('المريض لا يغيّر المستقبِل بعد الإنشاء', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'medical_shares', 'share_1'),
      { recipientDoctorId: STRANGER }));
  });

  test('المريض لا يغيّر السجلات المشمولة ولا تاريخ الإنشاء', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'medical_shares', 'share_1'),
      { encounterIds: [ENC, ENC2] }));
    await assertFails(updateDoc(doc(asPatient(), 'medical_shares', 'share_1'),
      { createdAt: new Date(2031, 0, 1) }));
  });

  test('الطبيب المستقبِل لا يعدّل المشاركة', async () => {
    await assertFails(updateDoc(doc(asRecipient(), 'medical_shares', 'share_1'),
      { snapshots: [] }));
    await assertFails(updateDoc(doc(asRecipient(), 'medical_shares', 'share_1'),
      { status: 'revoked', revokedAt: serverTimestamp() }));
  });

  test('لا يحذف أحد سجل الموافقة', async () => {
    await assertFails(deleteDoc(doc(asPatient(), 'medical_shares', 'share_1')));
    await assertFails(
      deleteDoc(doc(asRecipient(), 'medical_shares', 'share_1')));
  });

  test('الطبيب المستقبِل لا يقرأ السجل الأصلي مباشرةً', async () => {
    // المشاركة لا تفتح `encounters` — وهو الفرق بين لقطة ووصول حيّ.
    await assertFails(getDoc(doc(asRecipient(), 'encounters', ENC)));
    await assertFails(getDocs(query(
      collection(asRecipient(), 'encounters'),
      where('patientId', '==', PATIENT))));
  });

  test('ولا يقرأ موعد المريض ولا ملفه الشخصي', async () => {
    await assertFails(getDoc(doc(asRecipient(), 'appointments', ENC)));
    await assertFails(getDoc(doc(asRecipient(), 'users', PATIENT)));
  });
});

// ===========================================================================
describe('الإلغاء', () => {
  beforeEach(() => seedShare('share_1'));

  test('المريض يلغي مشاركته النشطة', async () => {
    await assertSucceeds(
      updateDoc(doc(asPatient(), 'medical_shares', 'share_1'),
                { status: 'revoked', revokedAt: serverTimestamp() }));
  });

  test('الإلغاء يقطع وصول الطبيب فوراً', async () => {
    // النموذج الأكثر حفظاً للخصوصية: لا نسخة تاريخية تبقى مقروءة.
    await updateDoc(doc(asPatient(), 'medical_shares', 'share_1'),
                    { status: 'revoked', revokedAt: serverTimestamp() });
    await assertFails(getDoc(doc(asRecipient(), 'medical_shares', 'share_1')));
    // والمريض يظل يرى سجل موافقته وأنه ألغاها.
    await assertSucceeds(getDoc(doc(asPatient(), 'medical_shares', 'share_1')));
  });

  test('مريض آخر لا يلغي مشاركة ليست له', async () => {
    await assertFails(updateDoc(doc(asOther(), 'medical_shares', 'share_1'),
      { status: 'revoked', revokedAt: serverTimestamp() }));
  });

  test('لا يُمرَّر تعديل آخر مع الإلغاء', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'medical_shares', 'share_1'),
      { status: 'revoked', revokedAt: serverTimestamp(),
        recipientDoctorId: STRANGER }));
    await assertFails(updateDoc(doc(asPatient(), 'medical_shares', 'share_1'),
      { status: 'revoked', revokedAt: serverTimestamp(),
        snapshots: [{ encounterId: ENC, diagnosis: 'مختلق' }] }));
  });

  test('لا يُعاد تنشيط ما أُلغي — الموافقة حدث جديد', async () => {
    await updateDoc(doc(asPatient(), 'medical_shares', 'share_1'),
                    { status: 'revoked', revokedAt: serverTimestamp() });
    await assertFails(updateDoc(doc(asPatient(), 'medical_shares', 'share_1'),
      { status: 'active', revokedAt: serverTimestamp() }));
  });

  test('إعادة المشاركة تُنشئ حدث موافقة مستقلاً', async () => {
    await updateDoc(doc(asPatient(), 'medical_shares', 'share_1'),
                    { status: 'revoked', revokedAt: serverTimestamp() });
    // مستند جديد بمعرّف جديد — لا يُعاد كتابة سجل الموافقة القديم.
    await assertSucceeds(
      addDoc(collection(asPatient(), 'medical_shares'), shareRequest()));

    let count;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDocs(query(
        collection(ctx.firestore(), 'medical_shares'),
        where('patientId', '==', PATIENT)));
      count = snap.size;
    });
    expect(count).toBe(2);
  });

  test('مشاركتان متزامنتان تبقيان حدثين منفصلين', async () => {
    const a = addDoc(collection(asPatient(), 'medical_shares'), shareRequest());
    const b = addDoc(collection(asPatient(), 'medical_shares'), shareRequest());
    await Promise.allSettled([a, b]);

    let statuses;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDocs(query(
        collection(ctx.firestore(), 'medical_shares'),
        where('patientId', '==', PATIENT)));
      statuses = snap.docs.map((d) => d.data().status);
    });
    // لا مستند نصف مكتوب: كلٌّ منها موافقة قائمة بذاتها.
    expect(statuses.filter((s) => s === 'pending').length).toBe(2);
  });
});

// ===========================================================================
describe('لا تصعيد صلاحيات عبر المشاركة', () => {
  test('المشاركة لا تجعل المريض طبيباً', async () => {
    await assertFails(
      updateDoc(doc(asPatient(), 'users', PATIENT), { role: 'doctor' }));
    await assertFails(
      updateDoc(doc(asPatient(), 'users', PATIENT), { isVerified: true }));
  });

  test('المشاركة لا تفتح سجلات مريض آخر للمستقبِل', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'encounters', 'other_enc'), {
        appointmentId: 'other_enc', patientId: OTHER, doctorId: MY_DOCTOR,
        encounterDate: '2030-05-02', diagnosis: 'خاص',
        createdAt: new Date(), updatedAt: new Date(),
      });
    });
    await seedShare('share_1');
    await assertFails(getDoc(doc(asRecipient(), 'encounters', 'other_enc')));
  });

  test('المستقبِل لا يعدّل السجل الأصلي', async () => {
    await seedShare('share_1');
    await assertFails(updateDoc(doc(asRecipient(), 'encounters', ENC),
      { diagnosis: 'تعديل من طبيب لم يؤلّفه' }));
  });
});
