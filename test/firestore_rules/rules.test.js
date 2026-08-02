/**
 * اختبارات قواعد أمان Firestore.
 *
 * تعمل على محاكي Firestore الحقيقي، فتُثبت أن القواعد تمنع ما يجب منعه
 * فعلاً — لا بمجرد قراءة الملف.
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
const { setDoc, getDoc, updateDoc, doc, deleteDoc } = require('firebase/firestore');

let testEnv;

const DOCTOR = 'doctor_1';
const PATIENT = 'patient_1';
const OTHER = 'patient_2';

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'drd-rules-test',
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

  // بذور البيانات تُكتب بتجاوز القواعد، لتمثيل حالة قاعدة بيانات قائمة.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', DOCTOR), {
      role: 'doctor', name: 'د. أحمد', phone: '201000000001',
      rating: 4, reviews: 10,
    });
    await setDoc(doc(db, 'users', PATIENT), {
      role: 'patient', name: 'مريض', phone: '201000000002',
      birthDate: '1990-01-01',
    });
    await setDoc(doc(db, 'slots', `${DOCTOR}_2030-01-01_09-00`), {
      doctorId: DOCTOR, appointmentDate: '2030-01-01', startTime: '09:00',
      capacity: 1, bookedCount: 1, patientIds: [PATIENT],
    });
    await setDoc(doc(db, 'appointments', 'appt_1'), {
      doctorId: DOCTOR, patientId: PATIENT,
      appointmentDate: '2030-01-01', startTime: '09:00', status: 'Booked',
    });
  });
});

const asPatient = () => testEnv.authenticatedContext(PATIENT).firestore();
const asOther = () => testEnv.authenticatedContext(OTHER).firestore();
const asDoctor = () => testEnv.authenticatedContext(DOCTOR).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

describe('users', () => {
  test('زائر غير مسجَّل لا يقرأ بيانات أي مريض', async () => {
    // هذا هو الفرق الجوهري عن القاعدة القديمة `allow read: if true`،
    // التي كانت تكشف كل الأسماء والأرقام وتواريخ الميلاد للإنترنت كله.
    await assertFails(getDoc(doc(asAnon(), 'users', PATIENT)));
  });

  test('مريض لا يقرأ بيانات مريض آخر', async () => {
    await assertFails(getDoc(doc(asOther(), 'users', PATIENT)));
  });

  test('المريض يقرأ مستنده', async () => {
    await assertSucceeds(getDoc(doc(asPatient(), 'users', PATIENT)));
  });

  test('أي مستخدم مسجَّل يقرأ بيانات الأطباء (لازم للحجز)', async () => {
    await assertSucceeds(getDoc(doc(asPatient(), 'users', DOCTOR)));
  });

  test('المريض لا يستطيع ترقية نفسه إلى طبيب', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', PATIENT), {
      role: 'doctor',
    }));
  });

  test('المريض يعدّل اسمه', async () => {
    await assertSucceeds(updateDoc(doc(asPatient(), 'users', PATIENT), {
      name: 'اسم جديد',
    }));
  });
});

describe('تقييم الطبيب (الحقول المجمَّعة)', () => {
  test('مراجعة صحيحة: زيادة واحدة وقيمة ضمن النطاق', async () => {
    await assertSucceeds(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 4.2, reviews: 11,
    }));
  });

  test('لا يمكن تزوير عدد المراجعات', async () => {
    // القاعدة القديمة كانت تسمح بهذا.
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 5, reviews: 99999,
    }));
  });

  test('لا يمكن وضع تقييم خارج 0..5', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 99, reviews: 11,
    }));
  });

  test('الطبيب لا يرفع تقييم نفسه', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      rating: 5, reviews: 11,
    }));
  });

  test('لا يمكن تمرير حقول أخرى مع التقييم', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 4.2, reviews: 11, price: 0,
    }));
  });
});

describe('slots — منع الحجز المزدوج', () => {
  const SLOT = `${DOCTOR}_2030-01-01_09-00`;

  test('لا يمكن تجاوز سعة الخانة', async () => {
    // جوهر الضمان: الخانة سعتها 1 ومحجوزة بالفعل.
    await assertFails(updateDoc(doc(asOther(), 'slots', SLOT), {
      bookedCount: 2, patientIds: [PATIENT, OTHER],
    }));
  });

  test('لا يمكن توسيع السعة للتحايل', async () => {
    await assertFails(updateDoc(doc(asOther(), 'slots', SLOT), {
      capacity: 99, bookedCount: 2, patientIds: [PATIENT, OTHER],
    }));
  });

  test('الإلغاء ينقص العدّاد', async () => {
    await assertSucceeds(updateDoc(doc(asPatient(), 'slots', SLOT), {
      bookedCount: 0, patientIds: [],
    }));
  });

  test('إنشاء خانة جديدة يبدأ بحجز واحد باسم صاحب الطلب', async () => {
    await assertSucceeds(setDoc(doc(asPatient(), 'slots', `${DOCTOR}_2030-02-02_10-00`), {
      doctorId: DOCTOR, appointmentDate: '2030-02-02', startTime: '10:00',
      capacity: 1, bookedCount: 1, patientIds: [PATIENT],
    }));
  });

  test('لا يمكن إنشاء خانة محجوزة باسم شخص آخر', async () => {
    await assertFails(setDoc(doc(asOther(), 'slots', `${DOCTOR}_2030-03-03_10-00`), {
      doctorId: DOCTOR, appointmentDate: '2030-03-03', startTime: '10:00',
      capacity: 1, bookedCount: 1, patientIds: [PATIENT],
    }));
  });
});

describe('appointments', () => {
  test('طرف ثالث لا يقرأ موعد غيره', async () => {
    await assertFails(getDoc(doc(asOther(), 'appointments', 'appt_1')));
  });

  test('المريض والطبيب يقرآن الموعد', async () => {
    await assertSucceeds(getDoc(doc(asPatient(), 'appointments', 'appt_1')));
    await assertSucceeds(getDoc(doc(asDoctor(), 'appointments', 'appt_1')));
  });

  test('لا يمكن إنشاء موعد باسم مريض آخر', async () => {
    // القاعدة القديمة `allow create: if request.auth != null` كانت تسمح بهذا،
    // أي أن أي مستخدم يستطيع ملء جدول أي طبيب بمواعيد وهمية.
    await assertFails(setDoc(doc(asOther(), 'appointments', 'fake'), {
      doctorId: DOCTOR, patientId: PATIENT,
      appointmentDate: '2030-05-05', startTime: '11:00', status: 'Booked',
    }));
  });

  test('لا يمكن إنشاء موعد بحالة "مكتمل" مباشرة', async () => {
    await assertFails(setDoc(doc(asOther(), 'appointments', 'fake2'), {
      doctorId: DOCTOR, patientId: OTHER,
      appointmentDate: '2030-05-05', startTime: '11:00', status: 'Completed',
    }));
  });

  test('لا يمكن نقل الموعد لوقت آخر', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'appointments', 'appt_1'), {
      startTime: '08:00',
    }));
  });

  test('الإلغاء بتغيير الحالة مسموح', async () => {
    await assertSucceeds(updateDoc(doc(asPatient(), 'appointments', 'appt_1'), {
      status: 'Cancelled',
    }));
  });

  test('حذف الموعد ممنوع — يبقى السجل كاملاً', async () => {
    await assertFails(deleteDoc(doc(asPatient(), 'appointments', 'appt_1')));
  });
});

describe('phone_index', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'phone_index', '201000000002'), {
        uid: PATIENT, email: 'p@example.com',
      });
    });
  });

  test('قراءة مدخل واحد متاحة قبل تسجيل الدخول (يلزم للدخول بالرقم)', async () => {
    await assertSucceeds(getDoc(doc(asAnon(), 'phone_index', '201000000002')));
  });

  test('لا يمكن اختطاف مدخل رقم شخص آخر', async () => {
    // لو نجح هذا لاستطاع مهاجم توجيه رقم أي مريض إلى بريده هو، فيمنع صاحب
    // الرقم من تسجيل الدخول نهائياً.
    await assertFails(updateDoc(doc(asOther(), 'phone_index', '201000000002'), {
      uid: OTHER, email: 'attacker@example.com',
    }));
  });
});

describe('ratings — بيانات طبية', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'ratings', 'r1'), {
        appointmentId: 'appt_1', fromUserId: DOCTOR, toUserId: PATIENT,
        ratingType: 'doctor_to_patient', healthConditionRating: 3,
      });
    });
  });

  test('طرف ثالث لا يقرأ تقييم الحالة الصحية لمريض', async () => {
    await assertFails(getDoc(doc(asOther(), 'ratings', 'r1')));
  });

  test('المريض والطبيب يقرآن التقييم', async () => {
    await assertSucceeds(getDoc(doc(asPatient(), 'ratings', 'r1')));
    await assertSucceeds(getDoc(doc(asDoctor(), 'ratings', 'r1')));
  });

  test('لا يمكن كتابة تقييم باسم شخص آخر', async () => {
    await assertFails(setDoc(doc(asOther(), 'ratings', 'r2'), {
      appointmentId: 'appt_1', fromUserId: DOCTOR, toUserId: PATIENT,
      ratingType: 'doctor_to_patient', healthConditionRating: 5,
    }));
  });
});

describe('reviews — مراجعات علنية', () => {
  test('المريض يكتب مراجعة باسمه', async () => {
    await assertSucceeds(setDoc(doc(asPatient(), 'reviews', 'rev1'), {
      doctorId: DOCTOR, patientId: PATIENT, rating: 5, comment: 'ممتاز',
    }));
  });

  test('لا يمكن كتابة مراجعة باسم مريض آخر', async () => {
    await assertFails(setDoc(doc(asOther(), 'reviews', 'rev2'), {
      doctorId: DOCTOR, patientId: PATIENT, rating: 1, comment: 'سيء',
    }));
  });

  test('التقييم خارج 1..5 مرفوض', async () => {
    await assertFails(setDoc(doc(asPatient(), 'reviews', 'rev3'), {
      doctorId: DOCTOR, patientId: PATIENT, rating: 100, comment: '',
    }));
  });
});

describe('notifications', () => {
  test('العميل لا يستطيع إنشاء إشعار باسم العيادة', async () => {
    await assertFails(setDoc(doc(asOther(), 'notifications', 'n1'), {
      userId: PATIENT, title: 'رسالة مزيّفة', body: 'احضر الآن', read: false,
    }));
  });
});
