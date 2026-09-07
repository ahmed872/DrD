/**
 * اختبارات أمان السجل السريري (المرحلة الثالثة).
 *
 * السؤال: هل يستطيع أحد أن يقرأ أو يكتب سجلاً طبياً لا يخصّه؟
 * تُشغَّل على المحاكي الحقيقي.
 *
 *   firebase emulators:exec --only firestore "npm --prefix test/firestore_rules test"
 */

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  setDoc, getDoc, updateDoc, doc, deleteDoc,
  collection, query, where, getDocs,
} = require('firebase/firestore');

let testEnv;

const DOCTOR = 'enc_doctor_1';
const DOCTOR2 = 'enc_doctor_2';
const PATIENT = 'enc_patient_1';
const OTHER = 'enc_patient_2';
const ADMIN = 'enc_admin_1';

// المواعيد المزروعة. معرّف السجل = معرّف الموعد دائماً.
const DONE = 'appt_done';        // مكتمل، للطبيب والمريض
const DONE2 = 'appt_done_2';     // مكتمل آخر، بلا سجل
const BOOKED = 'appt_booked';    // محجوز ولم يتم
const CANCELLED = 'appt_cancel'; // ملغى
const OTHERS = 'appt_other_doc'; // مكتمل لكن لطبيب آخر

const encounter = (overrides = {}) => ({
  appointmentId: DONE2,
  patientId: PATIENT,
  doctorId: DOCTOR,
  encounterDate: '2030-02-01',
  diagnosis: 'التهاب في الحلق',
  clinicalNotes: 'حرارة 38 ولا ضيق تنفس.',
  treatmentPlan: 'مضاد حيوي خمسة أيام.',
  ...overrides,
});

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'drd-rules-test',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
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
    await setDoc(doc(db, 'users', DOCTOR), { role: 'doctor', name: 'د. أحمد' });
    await setDoc(doc(db, 'users', DOCTOR2), { role: 'doctor', name: 'د. سعيد' });
    await setDoc(doc(db, 'users', PATIENT), { role: 'patient', name: 'مريض' });
    await setDoc(doc(db, 'users', OTHER), { role: 'patient', name: 'آخر' });
    await setDoc(doc(db, 'users', ADMIN), { role: 'patient', name: 'مشرف' });
    await setDoc(doc(db, 'admins', ADMIN), {});

    const appt = (id, extra) => setDoc(doc(db, 'appointments', id), {
      doctorId: DOCTOR, patientId: PATIENT,
      appointmentDate: '2030-02-01', startTime: '09:00', ...extra,
    });
    await appt(DONE, { status: 'Completed' });
    await appt(DONE2, { status: 'Completed' });
    await appt(BOOKED, { status: 'Booked' });
    await appt(CANCELLED, { status: 'Cancelled' });
    await appt(OTHERS, { status: 'Completed', doctorId: DOCTOR2 });

    // سجل قائم على DONE.
    await setDoc(doc(db, 'encounters', DONE), {
      ...encounter({ appointmentId: DONE }),
      createdAt: new Date(), updatedAt: new Date(),
    });
  });
});

const asDoctor = () => testEnv.authenticatedContext(DOCTOR).firestore();
const asDoctor2 = () => testEnv.authenticatedContext(DOCTOR2).firestore();
const asPatient = () => testEnv.authenticatedContext(PATIENT).firestore();
const asOther = () => testEnv.authenticatedContext(OTHER).firestore();
const asAdmin = () => testEnv.authenticatedContext(ADMIN).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

// ===========================================================================
describe('إنشاء السجل — سلطة الطبيب', () => {
  test('الطبيب يُنشئ سجلاً لزيارة تمّت عنده', async () => {
    await assertSucceeds(
      setDoc(doc(asDoctor(), 'encounters', DONE2), encounter())
    );
  });

  test('لا يُنشئ الطبيب سجلاً لموعد طبيب آخر', async () => {
    // هذا ما يمنع طبيباً من تأليف سجل لأي مريض يعرف معرّفه.
    await assertFails(
      setDoc(doc(asDoctor(), 'encounters', OTHERS),
             encounter({ appointmentId: OTHERS }))
    );
  });

  test('لا يُنشئ الطبيب سجلاً لمريض غير مريض الموعد', async () => {
    await assertFails(
      setDoc(doc(asDoctor(), 'encounters', DONE2),
             encounter({ patientId: OTHER }))
    );
  });

  test('لا يؤلّف الطبيب باسم طبيب آخر', async () => {
    await assertFails(
      setDoc(doc(asDoctor2(), 'encounters', DONE2),
             encounter({ doctorId: DOCTOR }))
    );
  });

  test('لا يُنشأ سجل لموعد لم يتم بعد', async () => {
    // السجل السريري يوثّق زيارة حدثت، لا حجزاً قد يُلغى.
    await assertFails(
      setDoc(doc(asDoctor(), 'encounters', BOOKED),
             encounter({ appointmentId: BOOKED }))
    );
  });

  test('لا يُنشأ سجل لموعد ملغى', async () => {
    await assertFails(
      setDoc(doc(asDoctor(), 'encounters', CANCELLED),
             encounter({ appointmentId: CANCELLED }))
    );
  });

  test('لا يُنشأ سجل لموعد غير موجود', async () => {
    await assertFails(
      setDoc(doc(asDoctor(), 'encounters', 'appt_ghost'),
             encounter({ appointmentId: 'appt_ghost' }))
    );
  });

  test('معرّف المستند يجب أن يطابق معرّف الموعد', async () => {
    // بدون هذا الشرط ينفصل السجل عن الزيارة التي تُجيزه: يشير إلى موعد
    // مشروع بينما يُكتب تحت معرّف آخر، فيسقط ضمان «سجل واحد لكل زيارة».
    await assertFails(
      setDoc(doc(asDoctor(), 'encounters', 'some_other_id'),
             encounter({ appointmentId: DONE2 }))
    );
  });

  test('من سُحبت صفة الطبيب عنه لا يُنشئ سجلاً', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', DOCTOR), {
        role: 'patient', name: 'د. أحمد',
      });
    });
    await assertFails(
      setDoc(doc(asDoctor(), 'encounters', DONE2), encounter())
    );
  });
});

// ===========================================================================
describe('سجل واحد لكل زيارة', () => {
  test('لا يكتب طبيب آخر فوق سجل قائم', async () => {
    await assertFails(
      setDoc(doc(asDoctor2(), 'encounters', DONE),
             encounter({ appointmentId: DONE, doctorId: DOCTOR2 }))
    );
  });

  test('محاولتان متزامنتان تنتهيان إلى مستند واحد', async () => {
    // الضمان بنيوي لا برمجي: المعرّف واحد، وFirestore لا يقبل مستندين
    // بنفس المعرّف. لا يعتمد على `if (exists)` في العميل.
    const a = setDoc(doc(asDoctor(), 'encounters', DONE2), encounter());
    const b = setDoc(doc(asDoctor(), 'encounters', DONE2),
                     encounter({ diagnosis: 'تشخيص ثانٍ' }));
    await Promise.allSettled([a, b]);

    let count;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDocs(query(
        collection(ctx.firestore(), 'encounters'),
        where('appointmentId', '==', DONE2),
      ));
      count = snap.size;
    });
    expect(count).toBe(1);
  });

  test('سباق بين طبيبين: الدخيل لا يفوز أبداً', async () => {
    const legit = setDoc(doc(asDoctor(), 'encounters', DONE2), encounter());
    const intruder = setDoc(doc(asDoctor2(), 'encounters', DONE2),
                            encounter({ doctorId: DOCTOR2 }));
    await Promise.allSettled([legit, intruder]);

    let data;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDoc(doc(ctx.firestore(), 'encounters', DONE2));
      data = snap.exists() ? snap.data() : null;
    });
    if (data) expect(data.doctorId).toBe(DOCTOR);
  });
});

// ===========================================================================
describe('القراءة', () => {
  test('المريض يقرأ سجله', async () => {
    await assertSucceeds(getDoc(doc(asPatient(), 'encounters', DONE)));
  });

  test('الطبيب المؤلِّف يقرأ سجله', async () => {
    await assertSucceeds(getDoc(doc(asDoctor(), 'encounters', DONE)));
  });

  test('مريض آخر لا يقرأ السجل', async () => {
    await assertFails(getDoc(doc(asOther(), 'encounters', DONE)));
  });

  test('طبيب لم يعالج المريض لا يقرأ السجل', async () => {
    await assertFails(getDoc(doc(asDoctor2(), 'encounters', DONE)));
  });

  test('الزائر غير المسجَّل لا يقرأ أي سجل', async () => {
    await assertFails(getDoc(doc(asAnon(), 'encounters', DONE)));
  });

  test('المشرف لا يقرأ السجلات السريرية', async () => {
    // صفة المشرف تخصّ إدارة المنصّة لا محتوى العيادات. مراجعة طلبات
    // الأطباء لا تعني الاطّلاع على تشخيصات المرضى.
    await assertFails(getDoc(doc(asAdmin(), 'encounters', DONE)));
    await assertFails(getDocs(collection(asAdmin(), 'encounters')));
  });

  test('المريض يسرد سجلاته وحدها', async () => {
    await assertSucceeds(getDocs(query(
      collection(asPatient(), 'encounters'),
      where('patientId', '==', PATIENT))));
    // استعلام بلا قيد يُرفض كاملاً — القاعدة لا تُرشِّح، بل تقبل أو ترفض.
    await assertFails(getDocs(collection(asPatient(), 'encounters')));
    await assertFails(getDocs(query(
      collection(asPatient(), 'encounters'),
      where('patientId', '==', OTHER))));
  });

  test('الطبيب يسرد ما ألّفه وحده', async () => {
    await assertSucceeds(getDocs(query(
      collection(asDoctor(), 'encounters'),
      where('doctorId', '==', DOCTOR))));
    await assertFails(getDocs(query(
      collection(asDoctor(), 'encounters'),
      where('doctorId', '==', DOCTOR2))));
    // ولا يسرد سجلات مريض عالجه لكن ألّفها غيره.
    await assertFails(getDocs(query(
      collection(asDoctor(), 'encounters'),
      where('patientId', '==', PATIENT))));
  });
});

// ===========================================================================
describe('المريض قارئ لا كاتب', () => {
  test('لا يُنشئ المريض سجلاً', async () => {
    await assertFails(
      setDoc(doc(asPatient(), 'encounters', DONE2), encounter())
    );
  });

  test('لا يغيّر المريض التشخيص', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'encounters', DONE),
                                { diagnosis: 'تشخيص من عند المريض' }));
  });

  test('لا يغيّر المريض خطة العلاج', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'encounters', DONE),
                                { treatmentPlan: 'دواء اخترته' }));
  });

  test('لا يغيّر المريض ملاحظات الكشف', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'encounters', DONE),
                                { clinicalNotes: 'ملاحظة مزوّرة' }));
  });

  test('لا يغيّر المريض طرفَي السجل ولا موعده', async () => {
    for (const patch of [
      { doctorId: DOCTOR2 }, { patientId: OTHER },
      { appointmentId: DONE2 }, { createdAt: new Date() },
      { encounterDate: '2031-01-01' },
    ]) {
      await assertFails(
        updateDoc(doc(asPatient(), 'encounters', DONE), patch));
    }
  });

  test('لا يحذف المريض سجلاً', async () => {
    await assertFails(deleteDoc(doc(asPatient(), 'encounters', DONE)));
  });

  test('لا يحذف الطبيب سجلاً — السجل الطبي لا يُمحى', async () => {
    await assertFails(deleteDoc(doc(asDoctor(), 'encounters', DONE)));
  });
});

// ===========================================================================
describe('التعديل — للمؤلِّف وحده', () => {
  test('المؤلِّف يصحّح سجله', async () => {
    await assertSucceeds(updateDoc(doc(asDoctor(), 'encounters', DONE), {
      diagnosis: 'التهاب لوزتين',
      updatedAt: new Date(),
    }));
  });

  test('طبيب آخر لا يعدّل سجل غيره', async () => {
    await assertFails(updateDoc(doc(asDoctor2(), 'encounters', DONE),
                                { diagnosis: 'تدخّل' }));
  });

  test('لا يُنقل السجل إلى طبيب أو مريض آخر', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'encounters', DONE),
                                { doctorId: DOCTOR2 }));
    await assertFails(updateDoc(doc(asDoctor(), 'encounters', DONE),
                                { patientId: OTHER }));
  });

  test('لا يُعاد ربط السجل بموعد آخر', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'encounters', DONE),
                                { appointmentId: DONE2 }));
  });

  test('لا يُزوَّر تاريخ الزيارة ولا تاريخ التوثيق', async () => {
    // سجل كُتب متأخراً يجب ألّا يبدو معاصراً للزيارة.
    await assertFails(updateDoc(doc(asDoctor(), 'encounters', DONE),
                                { encounterDate: '2031-01-01' }));
    await assertFails(updateDoc(doc(asDoctor(), 'encounters', DONE),
                                { createdAt: new Date(2031, 0, 1) }));
  });
});

// ===========================================================================
describe('فحص الشكل', () => {
  test('تُرفض الحقول الزائدة', async () => {
    // قائمة سماح لا قائمة منع: كل حقل جديد ممنوع حتى يُضاف صراحةً، فلا
    // يُهرَّب حقل صلاحية أو مشاركة داخل سجل طبي.
    await assertFails(setDoc(doc(asDoctor(), 'encounters', DONE2),
      encounter({ sharedWith: [DOCTOR2] })));
    await assertFails(setDoc(doc(asDoctor(), 'encounters', DONE2),
      encounter({ isPublic: true })));
  });

  test('يُرفض التشخيص الفارغ أو الناقص', async () => {
    await assertFails(setDoc(doc(asDoctor(), 'encounters', DONE2),
      encounter({ diagnosis: '' })));
    const { diagnosis, ...without } = encounter();
    await assertFails(
      setDoc(doc(asDoctor(), 'encounters', DONE2), without));
  });

  test('تُرفض الأنواع الخاطئة', async () => {
    await assertFails(setDoc(doc(asDoctor(), 'encounters', DONE2),
      encounter({ diagnosis: 42 })));
    await assertFails(setDoc(doc(asDoctor(), 'encounters', DONE2),
      encounter({ clinicalNotes: ['a', 'b'] })));
    await assertFails(setDoc(doc(asDoctor(), 'encounters', DONE2),
      encounter({ encounterDate: 20300201 })));
  });

  test('يُرفض النص السريري الضخم — حماية الحصة', async () => {
    await assertFails(setDoc(doc(asDoctor(), 'encounters', DONE2),
      encounter({ diagnosis: 'ط'.repeat(301) })));
    await assertFails(setDoc(doc(asDoctor(), 'encounters', DONE2),
      encounter({ clinicalNotes: 'ط'.repeat(4001) })));
    await assertFails(setDoc(doc(asDoctor(), 'encounters', DONE2),
      encounter({ treatmentPlan: 'ط'.repeat(4001) })));
  });

  test('يُقبل السجل بحقوله الاختيارية فارغة', async () => {
    // ليست كل زيارة تنتهي بوصفة أو متابعة.
    await assertSucceeds(setDoc(doc(asDoctor(), 'encounters', DONE2), {
      appointmentId: DONE2, patientId: PATIENT, doctorId: DOCTOR,
      encounterDate: '2030-02-01', diagnosis: 'كشف عام — لا شكوى',
    }));
  });
});

// ===========================================================================
describe('نسخ التصحيح', () => {
  test('لا يكتب أحد في revisions من العميل', async () => {
    await assertFails(setDoc(
      doc(asDoctor(), 'encounters', DONE, 'revisions', 'r1'),
      { diagnosis: 'قديم' }));
    await assertFails(setDoc(
      doc(asPatient(), 'encounters', DONE, 'revisions', 'r1'),
      { diagnosis: 'قديم' }));
  });

  test('طرفا السجل يقرآن نسخه، وغيرهما لا', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'encounters', DONE, 'revisions', 'r1'),
        { diagnosis: 'التهاب', revisedAt: new Date() });
    });
    await assertSucceeds(getDoc(
      doc(asPatient(), 'encounters', DONE, 'revisions', 'r1')));
    await assertSucceeds(getDoc(
      doc(asDoctor(), 'encounters', DONE, 'revisions', 'r1')));
    await assertFails(getDoc(
      doc(asDoctor2(), 'encounters', DONE, 'revisions', 'r1')));
    await assertFails(getDoc(
      doc(asOther(), 'encounters', DONE, 'revisions', 'r1')));
  });
});

// ===========================================================================
// السيناريو الكامل — كما يحدث في الواقع.
//
// الاختبارات أعلاه تفحص كل شرط على حدة. هذا يمشي الطريق من أوله إلى آخره
// بالترتيب، فيُثبت أن القطع تتركّب: كلٌّ منها قد يكون صحيحاً وحده والمسار
// مكسوراً.
// ===========================================================================
describe('السيناريو الكامل: حجز ← زيارة ← سجل ← قراءة المريض', () => {
  test('الطريق كله، بحُرّاسه', async () => {
    const APPT = 'journey_appt';

    // 1) موعد محجوز عند الطبيب.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'appointments', APPT), {
        doctorId: DOCTOR, patientId: PATIENT,
        appointmentDate: '2030-04-01', startTime: '11:00', status: 'Booked',
      });
    });

    const clinical = {
      appointmentId: APPT,
      patientId: PATIENT,
      doctorId: DOCTOR,
      doctorName: 'د. أحمد',
      doctorSpecialization: 'طب الأسرة',
      encounterDate: '2030-04-01',
      diagnosis: 'التهاب في الحلق',
      clinicalNotes: 'حرارة 38، بلا ضيق تنفس.',
      treatmentPlan: 'مضاد حيوي خمسة أيام.',
      followUpNotes: 'راجع إن استمرت الحرارة.',
      followUpDate: '2030-04-08',
    };

    // 2) قبل إتمام الزيارة: لا سجل. الحجز ليس زيارة.
    await assertFails(
      setDoc(doc(asDoctor(), 'encounters', APPT), clinical));

    // 3) الطبيب يُنهي الموعد.
    await assertSucceeds(updateDoc(
      doc(asDoctor(), 'appointments', APPT), { status: 'Completed' }));

    // 4) الآن يوثّق الزيارة.
    await assertSucceeds(
      setDoc(doc(asDoctor(), 'encounters', APPT), clinical));

    // 5) المريض يقرأ سجله ويجد ما كُتب.
    const seen = await getDoc(doc(asPatient(), 'encounters', APPT));
    expect(seen.data().diagnosis).toBe('التهاب في الحلق');
    expect(seen.data().treatmentPlan).toBe('مضاد حيوي خمسة أيام.');

    // 6) ولا يستطيع تعديله.
    await assertFails(updateDoc(doc(asPatient(), 'encounters', APPT),
      { diagnosis: 'شيء آخر' }));

    // 7) طبيب لم يعالجه لا يقرأ ولا يكتب.
    await assertFails(getDoc(doc(asDoctor2(), 'encounters', APPT)));
    await assertFails(updateDoc(doc(asDoctor2(), 'encounters', APPT),
      { diagnosis: 'تدخّل' }));

    // 8) ولا مريض آخر.
    await assertFails(getDoc(doc(asOther(), 'encounters', APPT)));

    // 9) ولا المشرف.
    await assertFails(getDoc(doc(asAdmin(), 'encounters', APPT)));

    // 10) ولا زائر غير مسجَّل.
    await assertFails(getDoc(doc(asAnon(), 'encounters', APPT)));

    // 11) لا سجل ثانٍ لنفس الزيارة — المعرّف واحد.
    let count;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDocs(query(
        collection(ctx.firestore(), 'encounters'),
        where('appointmentId', '==', APPT)));
      count = snap.size;
    });
    expect(count).toBe(1);

    // 12) والنظام يعرف أي موعد أنتج السجل — وهو ما تبني عليه المرحلة
    //     الرابعة نسخة المشاركة.
    expect(seen.data().appointmentId).toBe(APPT);
    expect(seen.id).toBe(APPT);
  });
});
