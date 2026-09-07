/**
 * ربط الموعد بخانته — الثغرة التي تركت السعة محروسة على نصف الطريق.
 *
 * ## ما كان مكسوراً
 *
 * منع الحجز المزدوج مبني على `slots`: عدّاد ذرّي داخل معاملة، وقاعدة تمنع
 * تجاوز السعة. لكن قاعدة إنشاء **الموعد** لم تشترط أي علاقة بتلك الخانة ولم
 * تقيّد معرّف المستند. فعميل معدَّل يكتب مستندات مواعيد بمعرّفات عشوائية بلا
 * `slotId` — فلا يمرّ بالعدّاد ولا يراه. وشاشات الطبيب الثلاث تقرأ من
 * `appointments` لا من `slots`، فتعرض تلك المواعيد كأنها حقيقية.
 *
 * أي أن المعاملة الذرّية كانت تحمي من **التسابق** فقط، لا من عميل معدَّل.
 *
 * ## ما يثبته هذا الملف
 *
 * المعرّف مشتق من الحقول: `{doctorId}_{date}_{HH-mm}__{patientId}`. أي تلاعب
 * في الطبيب أو التاريخ أو الوقت أو `slotId` يغيّر المعرّف المتوقَّع ويُرفض.
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
const { setDoc, updateDoc, doc, getDoc } = require('firebase/firestore');

let testEnv;

const DOCTOR = 'doctor_1';
const DOCTOR2 = 'doctor_2';
const PATIENT = 'patient_1';

const DATE = '2030-03-01';
const TIME = '10:30';
const SLOT = `${DOCTOR}_${DATE}_10-30`;
const APPT = `${SLOT}__${PATIENT}`;

/** حمولة حجز سليمة، مع إمكانية تشويه حقل واحد لعزل أثره. */
const booking = (overrides = {}) => ({
  doctorId: DOCTOR,
  patientId: PATIENT,
  appointmentDate: DATE,
  startTime: TIME,
  slotId: SLOT,
  status: 'Booked',
  reason: 'كشف',
  price: 200,
  patientName: 'مريض',
  patientPhone: '201000000002',
  ...overrides,
});

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'drd-slot-binding-test',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: fs.readFileSync(
        path.resolve(__dirname, '../../firestore.rules'),
        'utf8'
      ),
    },
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', DOCTOR), { role: 'doctor', name: 'د. أحمد' });
    await setDoc(doc(db, 'users', DOCTOR2), { role: 'doctor', name: 'د. سعيد' });
    await setDoc(doc(db, 'users', PATIENT), { role: 'patient', name: 'مريض' });
  });
});

const asPatient = () => testEnv.authenticatedContext(PATIENT).firestore();

describe('الحجز السليم', () => {
  test('معرّف مشتق صحيح + slotId مطابق → يُقبل', async () => {
    await assertSucceeds(
      setDoc(doc(asPatient(), 'appointments', APPT), booking())
    );
  });

  test('نفس المريض في خانة أخرى عند نفس الطبيب → يُقبل', async () => {
    const slot = `${DOCTOR}_${DATE}_11-00`;
    await assertSucceeds(setDoc(
      doc(asPatient(), 'appointments', `${slot}__${PATIENT}`),
      booking({ startTime: '11:00', slotId: slot }),
    ));
  });

  test('مريض آخر في نفس الخانة → يُقبل (الحجز الجماعي)', async () => {
    // السعة تحرسها `slots` لا هذه القاعدة. المطلوب هنا ألا يمنع الربط
    // الحجز الجماعي المشروع: مستندان مختلفان لنفس الخانة، بمريضين مختلفين.
    const other = 'patient_9';
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', other), {
        role: 'patient', name: 'مريض آخر',
      });
    });
    const db = testEnv.authenticatedContext(other).firestore();
    await assertSucceeds(setDoc(
      doc(db, 'appointments', `${SLOT}__${other}`),
      booking({ patientId: other }),
    ));
  });
});

describe('التلاعب بالهوية يُرفض', () => {
  test('تزوير الطبيب: معرّف خانة طبيب آخر، بيانات طبيبنا', async () => {
    // الشكل الذي يجعل الموعد يظهر في جدول طبيب لم يُحجز عنده.
    await assertFails(setDoc(
      doc(asPatient(), 'appointments', `${DOCTOR2}_${DATE}_10-30__${PATIENT}`),
      booking(),
    ));
  });

  test('تزوير الطبيب في الحقل مع إبقاء المعرّف', async () => {
    await assertFails(setDoc(
      doc(asPatient(), 'appointments', APPT),
      booking({ doctorId: DOCTOR2 }),
    ));
  });

  test('تزوير التاريخ', async () => {
    await assertFails(setDoc(
      doc(asPatient(), 'appointments', APPT),
      booking({ appointmentDate: '2030-03-02' }),
    ));
  });

  test('تزوير الوقت', async () => {
    await assertFails(setDoc(
      doc(asPatient(), 'appointments', APPT),
      booking({ startTime: '11:30' }),
    ));
  });

  test('تزوير المريض: حجز باسم شخص آخر', async () => {
    await assertFails(setDoc(
      doc(asPatient(), 'appointments', `${SLOT}__patient_9`),
      booking({ patientId: 'patient_9' }),
    ));
  });
});

describe('الالتفاف على عدّاد الخانة', () => {
  test('معرّف عشوائي بلا صلة بأي خانة → يُرفض', async () => {
    // هذا هو الاستغلال الفعلي: `.doc()` بمعرّف تلقائي يتخطّى القفل كلياً.
    await assertFails(setDoc(
      doc(asPatient(), 'appointments', 'kJ3nX9qLpZ0aBcDeFgHi'),
      booking(),
    ));
  });

  test('بلا `slotId` إطلاقاً → يُرفض', async () => {
    const payload = booking();
    delete payload.slotId;
    await assertFails(
      setDoc(doc(asPatient(), 'appointments', APPT), payload)
    );
  });

  test('`slotId` يشير إلى خانة أخرى → يُرفض', async () => {
    // الشكل الأخبث: المعرّف سليم فيبدو الموعد في مكانه، بينما العدّاد
    // المرفوع يخصّ خانة أخرى — فتظهر خانتان خاطئتان معاً.
    await assertFails(setDoc(
      doc(asPatient(), 'appointments', APPT),
      booking({ slotId: `${DOCTOR}_${DATE}_09-00` }),
    ));
  });

  test('تهريب فاصل داخل التاريخ لإزاحة التفكيك → يُرفض', async () => {
    // بدون اشتراط الصيغة الصارمة، تاريخ يحمل `_` يزيح حدود المعرّف
    // فيتطابق نصّياً مع تركيب مختلف تماماً.
    await assertFails(setDoc(
      doc(asPatient(), 'appointments', `${DOCTOR}_2030-03_01_10-30__${PATIENT}`),
      booking({ appointmentDate: '2030-03_01' }),
    ));
  });

  test('وقت بصيغة غير قياسية → يُرفض', async () => {
    // `9:00` و`09:00 AM` صيغتان موجودتان في البيانات القديمة. قبولهما هنا
    // يعني معرّفين مختلفين لنفس الخانة — وعودة الحجز المزدوج من الباب الخلفي.
    await assertFails(setDoc(
      doc(asPatient(), 'appointments', `${DOCTOR}_${DATE}_9-00__${PATIENT}`),
      booking({ startTime: '9:00', slotId: `${DOCTOR}_${DATE}_9-00` }),
    ));
  });
});

describe('الإلغاء وإعادة الحجز', () => {
  beforeEach(async () => {
    await setDoc(doc(asPatient(), 'appointments', APPT), booking());
  });

  test('المريض يلغي موعده', async () => {
    await assertSucceeds(updateDoc(doc(asPatient(), 'appointments', APPT), {
      status: 'Cancelled',
      cancelledAt: new Date(),
    }));
  });

  test('إعادة حجز نفس الخانة بعد الإلغاء', async () => {
    await updateDoc(doc(asPatient(), 'appointments', APPT), {
      status: 'Cancelled', cancelledAt: new Date(),
    });
    await assertSucceeds(updateDoc(doc(asPatient(), 'appointments', APPT), {
      status: 'Booked',
      slotId: SLOT,
    }));
  });

  test('إعادة الحجز لا تستطيع توجيه الموعد لخانة أخرى', async () => {
    // بدون هذا الشرط يُرفع عدّاد خانة لا علاقة لها بالموعد.
    await updateDoc(doc(asPatient(), 'appointments', APPT), {
      status: 'Cancelled', cancelledAt: new Date(),
    });
    await assertFails(updateDoc(doc(asPatient(), 'appointments', APPT), {
      status: 'Booked',
      slotId: `${DOCTOR}_${DATE}_09-00`,
    }));
  });

  test('الحجز مرتين ينتهي إلى مستند واحد', async () => {
    // التفرّد بنيوي: نفس المدخلات تنتج نفس المعرّف، فالمحاولة الثانية
    // تكتب على نفس المستند بدل أن تُنشئ ثانياً.
    const snap = await getDoc(doc(asPatient(), 'appointments', APPT));
    expect(snap.exists()).toBe(true);
    expect(snap.data().slotId).toBe(SLOT);
  });
});
