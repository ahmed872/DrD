/**
 * تقييمات الطرفين (`ratings`) — الثغرات التي أُغلقت في `reviews` وبقيت هنا.
 *
 * ## لماذا مجموعة لا تستخدمها الواجهة تستحق كل هذا
 *
 * لا شاشة اليوم تكتب في `ratings`: الشاشتان المكتوبتان (`PatientRateDoctorScreen`
 * و`DoctorRatePatientScreen`) لا يصل إليهما أي تنقّل. لكن **القاعدة حيّة في
 * الإنتاج**، وما يمكن كتابته تحدّده القاعدة لا وجود زر. أي عميل يستطيع الكتابة
 * مباشرة عبر SDK.
 *
 * وقد كانت تحمل الثغرات الثلاث التي وصف قسم `reviews` إغلاقها بأنه لا يتجزّأ:
 * لا اشتراط زيارة، ولا منع لتقييم النفس، ولا فحص نطاق إطلاقاً — وزادت رابعة:
 * معرّف عشوائي، فلا تفرّد.
 *
 * وحقولها ليست تجميلية: `healthConditionRating` و`healthConditionComment`
 * تقييم طبيب لحالة مريض. أي أن الثغرة كانت تسمح بكتابة ملاحظة سريرية عن أي
 * شخص، خارج نموذج `encounters` وضماناته كلها.
 */

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { setDoc, updateDoc, getDoc, deleteDoc, doc } = require('firebase/firestore');

let testEnv;

const DOCTOR = 'doctor_1';
const DOCTOR2 = 'doctor_2';
const PATIENT = 'patient_1';
const STRANGER = 'patient_2';

const DONE = 'visit_done';      // زيارة مكتملة بين DOCTOR و PATIENT
const BOOKED = 'visit_booked';  // زيارة لم تتم بعد

const P2D = `${DONE}_patient_to_doctor`;
const D2P = `${DONE}_doctor_to_patient`;

const patientRating = (overrides = {}) => ({
  appointmentId: DONE,
  fromUserId: PATIENT,
  toUserId: DOCTOR,
  ratingType: 'patient_to_doctor',
  serviceRating: 5,
  serviceComment: 'خدمة ممتازة',
  createdAt: new Date(),
  ...overrides,
});

const doctorRating = (overrides = {}) => ({
  appointmentId: DONE,
  fromUserId: DOCTOR,
  toUserId: PATIENT,
  ratingType: 'doctor_to_patient',
  healthConditionRating: 4,
  healthConditionComment: 'تحسّن ملحوظ',
  createdAt: new Date(),
  ...overrides,
});

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'drd-ratings-test',
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
    await setDoc(doc(db, 'users', STRANGER), { role: 'patient', name: 'غريب' });

    await setDoc(doc(db, 'appointments', DONE), {
      doctorId: DOCTOR, patientId: PATIENT,
      appointmentDate: '2024-01-01', startTime: '09:00', status: 'Completed',
    });
    await setDoc(doc(db, 'appointments', BOOKED), {
      doctorId: DOCTOR, patientId: PATIENT,
      appointmentDate: '2030-01-01', startTime: '09:00', status: 'Booked',
    });
  });
});

const as = (uid) => testEnv.authenticatedContext(uid).firestore();

describe('ما يجوز', () => {
  test('المريض يقيّم طبيب زيارته المكتملة', async () => {
    await assertSucceeds(
      setDoc(doc(as(PATIENT), 'ratings', P2D), patientRating())
    );
  });

  test('الطبيب يسجّل ملاحظة عن مريض زيارته المكتملة', async () => {
    await assertSucceeds(
      setDoc(doc(as(DOCTOR), 'ratings', D2P), doctorRating())
    );
  });

  test('الطرفان يقرآن التقييم', async () => {
    await setDoc(doc(as(PATIENT), 'ratings', P2D), patientRating());
    await assertSucceeds(getDoc(doc(as(PATIENT), 'ratings', P2D)));
    await assertSucceeds(getDoc(doc(as(DOCTOR), 'ratings', P2D)));
  });

  test('صاحب التقييم يعدّل درجته داخل النطاق', async () => {
    await setDoc(doc(as(PATIENT), 'ratings', P2D), patientRating());
    await assertSucceeds(updateDoc(doc(as(PATIENT), 'ratings', P2D), {
      serviceRating: 3,
      serviceComment: 'مقبول',
    }));
  });

  test('صاحب التقييم يحذفه', async () => {
    await setDoc(doc(as(PATIENT), 'ratings', P2D), patientRating());
    await assertSucceeds(deleteDoc(doc(as(PATIENT), 'ratings', P2D)));
  });
});

describe('١ — لا تقييم بلا زيارة حقيقية', () => {
  test('غريب لم تكن له زيارة أصلاً', async () => {
    await assertFails(setDoc(
      doc(as(STRANGER), 'ratings', `${DONE}_patient_to_doctor`),
      patientRating({ fromUserId: STRANGER }),
    ));
  });

  test('زيارة لم تتم بعد', async () => {
    await assertFails(setDoc(
      doc(as(PATIENT), 'ratings', `${BOOKED}_patient_to_doctor`),
      patientRating({ appointmentId: BOOKED }),
    ));
  });

  test('موعد غير موجود إطلاقاً', async () => {
    await assertFails(setDoc(
      doc(as(PATIENT), 'ratings', 'ghost_patient_to_doctor'),
      patientRating({ appointmentId: 'ghost' }),
    ));
  });

  test('طبيب آخر لم يحضر الزيارة', async () => {
    await assertFails(setDoc(
      doc(as(DOCTOR2), 'ratings', D2P),
      doctorRating({ fromUserId: DOCTOR2 }),
    ));
  });

  test('انتحال: الكتابة باسم شخص آخر', async () => {
    await assertFails(setDoc(
      doc(as(STRANGER), 'ratings', P2D),
      patientRating(),
    ));
  });

  test('عكس الاتجاه: المريض يكتب تقييماً من نوع الطبيب', async () => {
    // بدون فحص الاتجاه يستطيع المريض كتابة `healthConditionComment` —
    // ملاحظة سريرية عن نفسه تبدو كأن الطبيب كتبها.
    await assertFails(setDoc(
      doc(as(PATIENT), 'ratings', D2P),
      doctorRating({ fromUserId: PATIENT, toUserId: DOCTOR }),
    ));
  });
});

describe('٢ — لا تقييم للنفس', () => {
  test('الطبيب يقيّم نفسه في زيارة حجزها عند نفسه', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'appointments', 'self_visit'), {
        doctorId: DOCTOR, patientId: DOCTOR,
        appointmentDate: '2024-01-01', startTime: '09:00', status: 'Completed',
      });
    });
    await assertFails(setDoc(
      doc(as(DOCTOR), 'ratings', 'self_visit_patient_to_doctor'),
      patientRating({
        appointmentId: 'self_visit', fromUserId: DOCTOR, toUserId: DOCTOR,
      }),
    ));
  });
});

describe('٣ — النطاق ١..٥ عند الإنشاء وعند التعديل', () => {
  test('درجة فوق النطاق عند الإنشاء', async () => {
    await assertFails(setDoc(
      doc(as(PATIENT), 'ratings', P2D),
      patientRating({ serviceRating: 999 }),
    ));
  });

  test('درجة صفر عند الإنشاء', async () => {
    await assertFails(setDoc(
      doc(as(PATIENT), 'ratings', P2D),
      patientRating({ serviceRating: 0 }),
    ));
  });

  test('درجة سالبة عند الإنشاء', async () => {
    await assertFails(setDoc(
      doc(as(PATIENT), 'ratings', P2D),
      patientRating({ serviceRating: -5 }),
    ));
  });

  test('الالتفاف: إنشاء بـ٥ ثم تعديل إلى ٩٩٩', async () => {
    // هذا بالضبط ما كان مفتوحاً: الفحص عند الإنشاء وحده لا يحمي شيئاً.
    await setDoc(doc(as(PATIENT), 'ratings', P2D), patientRating());
    await assertFails(updateDoc(doc(as(PATIENT), 'ratings', P2D), {
      serviceRating: 999,
    }));
  });

  test('الالتفاف عبر الحقل السريري', async () => {
    await setDoc(doc(as(DOCTOR), 'ratings', D2P), doctorRating());
    await assertFails(updateDoc(doc(as(DOCTOR), 'ratings', D2P), {
      healthConditionRating: 100,
    }));
  });

  test('درجة نصّية بدل رقم', async () => {
    await assertFails(setDoc(
      doc(as(PATIENT), 'ratings', P2D),
      patientRating({ serviceRating: '5' }),
    ));
  });
});

describe('٤ — التفرّد بمعرّف المستند', () => {
  test('معرّف عشوائي يُرفض', async () => {
    // `.doc()` بمعرّف تلقائي كان يسمح بعدد غير محدود من التقييمات لنفس
    // الزيارة — أي إغراق متوسط بلا حدّ لو رُبط الحساب بالخادم لاحقاً.
    await assertFails(setDoc(
      doc(as(PATIENT), 'ratings', 'aRandomAutoId123456'),
      patientRating(),
    ));
  });

  test('معرّف لا يطابق الموعد المُشار إليه', async () => {
    await assertFails(setDoc(
      doc(as(PATIENT), 'ratings', `${BOOKED}_patient_to_doctor`),
      patientRating({ appointmentId: DONE }),
    ));
  });

  test('معرّف لا يطابق نوع التقييم', async () => {
    await assertFails(setDoc(
      doc(as(PATIENT), 'ratings', D2P),
      patientRating(),
    ));
  });

  test('إعادة الإرسال تكتب على نفس المستند', async () => {
    await setDoc(doc(as(PATIENT), 'ratings', P2D), patientRating());
    await assertSucceeds(updateDoc(doc(as(PATIENT), 'ratings', P2D), {
      serviceRating: 4,
    }));
    const snap = await getDoc(doc(as(PATIENT), 'ratings', P2D));
    expect(snap.data().serviceRating).toBe(4);
  });
});

describe('حدود أخرى', () => {
  test('حقل خارج قائمة السماح يُرفض', async () => {
    // بدون `hasOnly` يمكن تهريب حقل صلاحية أو مشاركة داخل تقييم.
    await assertFails(setDoc(
      doc(as(PATIENT), 'ratings', P2D),
      patientRating({ isVerified: true }),
    ));
  });

  test('لا يمكن تغيير طرفَي التقييم بالتعديل', async () => {
    await setDoc(doc(as(PATIENT), 'ratings', P2D), patientRating());
    await assertFails(updateDoc(doc(as(PATIENT), 'ratings', P2D), {
      toUserId: DOCTOR2,
    }));
  });

  test('غريب لا يقرأ تقييماً ليس طرفاً فيه', async () => {
    // `healthConditionComment` ملاحظة سريرية — لذلك القراءة ليست عامة
    // كـ`reviews`.
    await setDoc(doc(as(DOCTOR), 'ratings', D2P), doctorRating());
    await assertFails(getDoc(doc(as(STRANGER), 'ratings', D2P)));
  });

  test('غريب لا يعدّل ولا يحذف تقييم غيره', async () => {
    await setDoc(doc(as(PATIENT), 'ratings', P2D), patientRating());
    await assertFails(updateDoc(doc(as(STRANGER), 'ratings', P2D), {
      serviceRating: 1,
    }));
    await assertFails(deleteDoc(doc(as(STRANGER), 'ratings', P2D)));
  });

  test('التقييم لا يمنح كاتبه أي أثر على متوسط الطبيب', async () => {
    // المتوسط يحسبه `syncDoctorRating` من `reviews` وحدها، و`users` لا
    // تقبل `rating` من أي عميل. هذا حارس على الحدّ بين المسارين.
    await assertFails(updateDoc(doc(as(PATIENT), 'users', DOCTOR), {
      rating: 5,
    }));
  });
});
