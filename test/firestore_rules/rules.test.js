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
const {
  setDoc, getDoc, updateDoc, doc, deleteDoc,
  collection, query, where, getDocs,
} = require('firebase/firestore');

let testEnv;

const DOCTOR = 'doctor_1';
const DOCTOR2 = 'doctor_2';
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
    await setDoc(doc(db, 'users', DOCTOR2), {
      role: 'doctor', name: 'د. سعيد', phone: '201000000003',
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
      // اسم المريض ورقمه منسوخان في مستند الموعد وقت الحجز — هذا ما تعتمد
      // عليه شاشة مرضى الطبيب بدل قراءة users/{patientId} المرفوضة.
      patientName: 'مريض', patientPhone: '201000000002',
    });
  });
});

const asPatient = () => testEnv.authenticatedContext(PATIENT).firestore();
const asOther = () => testEnv.authenticatedContext(OTHER).firestore();
const asDoctor = () => testEnv.authenticatedContext(DOCTOR).firestore();
const asOtherDoctor = () => testEnv.authenticatedContext(DOCTOR2).firestore();
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

// ===========================================================================
// اختبارات انحدار — المرحلة صفر
//
// كل حالة هنا كانت **تنجح فعلاً** على المحاكي قبل التعديل. المقصود منها أن
// تفشل بصوت عالٍ لو عادت القاعدة إلى صيغتها السابقة.
// ===========================================================================

describe('انحدار: منح صلاحية طبيب من العميل', () => {
  test('لا يمكن إنشاء حساب بدور "doctor"', async () => {
    // كانت القاعدة `role in ['doctor','patient']`، وشاشة التسجيل تعرض
    // زرّي اختيار. أي شخص كان يصبح طبيباً بضغطة.
    const newUser = testEnv.authenticatedContext('new_doctor').firestore();
    await assertFails(setDoc(doc(newUser, 'users', 'new_doctor'), {
      role: 'doctor', name: 'طبيب مزيّف', phone: '201999999999',
    }));
  });

  test('إنشاء حساب مريض ما زال مسموحاً', async () => {
    const newUser = testEnv.authenticatedContext('new_patient').firestore();
    await assertSucceeds(setDoc(doc(newUser, 'users', 'new_patient'), {
      role: 'patient', name: 'مريض جديد', phone: '201999999998',
    }));
  });

  test('لا يمكن إنشاء حساب بدور مخترع', async () => {
    const newUser = testEnv.authenticatedContext('new_admin').firestore();
    await assertFails(setDoc(doc(newUser, 'users', 'new_admin'), {
      role: 'admin', name: 'مشرف مزيّف', phone: '201999999997',
    }));
  });
});

describe('انحدار: سلطة البيانات السريرية على الموعد', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      // موعد قائم، عليه ملاحظة سريرية كتبها الطبيب.
      await setDoc(doc(db, 'appointments', 'clinical_1'), {
        doctorId: DOCTOR, patientId: PATIENT,
        appointmentDate: '2030-01-01', startTime: '09:00',
        status: 'Booked', notes: 'ملاحظة الطبيب السريرية', price: 200,
        patientName: 'مريض', patientPhone: '201000000002',
      });
      // زيارة انتهت بالفعل — سجل طبي حقيقي.
      await setDoc(doc(db, 'appointments', 'clinical_done'), {
        doctorId: DOCTOR, patientId: PATIENT,
        appointmentDate: '2020-01-01', startTime: '09:00',
        status: 'Completed', notes: 'تم الكشف', diagnosis: 'التهاب',
      });
    });
  });

  // ---- ما لا يجوز للمريض ----

  test('المريض لا يمسح ملاحظة الطبيب السريرية', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'appointments', 'clinical_1'), {
      notes: 'ملاحظة زوّرها المريض',
    }));
  });

  test('المريض لا يكتب تشخيصاً', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'appointments', 'clinical_1'), {
      diagnosis: 'تشخيص من عند المريض',
    }));
  });

  test('المريض لا يكتب وصفة أو علاجاً', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'appointments', 'clinical_1'), {
      prescription: 'دواء',
    }));
    await assertFails(updateDoc(doc(asPatient(), 'appointments', 'clinical_1'), {
      treatment: 'خطة علاج',
    }));
  });

  test('المريض لا يعلّم موعده "مكتمل" — لا يصنع زيارة لم تحدث', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'appointments', 'clinical_1'), {
      status: 'Completed',
    }));
  });

  test('المريض لا يمرّر حقلاً سريرياً مع الإلغاء', async () => {
    // `hasOnly` هو ما يمنع هذا: الإلغاء وحده مسموح، لا الإلغاء + إضافة.
    await assertFails(updateDoc(doc(asPatient(), 'appointments', 'clinical_1'), {
      status: 'Cancelled', diagnosis: 'تشخيص مهرَّب',
    }));
  });

  test('المريض لا يلغي زيارة مكتملة — لا يمحو سجلاً طبياً', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'appointments', 'clinical_done'), {
      status: 'Cancelled',
    }));
  });

  test('المريض لا يغيّر سعر الموعد', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'appointments', 'clinical_1'), {
      price: 0,
    }));
  });

  test('المريض لا ينشئ موعداً ومعه تشخيص جاهز', async () => {
    // الباب الخلفي: حقل سريري وقت الإنشاء يظهر في السجل الطبي بمجرد أن
    // يعلّم الطبيب الزيارة مكتملة.
    await assertFails(setDoc(doc(asPatient(), 'appointments', 'backdoor'), {
      doctorId: DOCTOR, patientId: PATIENT,
      appointmentDate: '2030-06-06', startTime: '11:00',
      status: 'Booked', diagnosis: 'تشخيص مزروع',
    }));
  });

  // ---- ما يجب أن يبقى مسموحاً ----

  test('المريض يلغي موعده القائم', async () => {
    await assertSucceeds(updateDoc(doc(asPatient(), 'appointments', 'clinical_1'), {
      status: 'Cancelled', cancelledAt: new Date(),
    }));
  });

  test('المريض يحجز موعداً عادياً', async () => {
    await assertSucceeds(setDoc(doc(asPatient(), 'appointments', 'ok_booking'), {
      doctorId: DOCTOR, patientId: PATIENT,
      appointmentDate: '2030-06-06', startTime: '12:00',
      status: 'Booked', reason: 'كشف', price: 200,
      patientName: 'مريض', patientPhone: '201000000002',
    }));
  });

  // ---- ما يجوز للطبيب ----

  test('الطبيب يكتب ملاحظة سريرية على موعده', async () => {
    await assertSucceeds(updateDoc(doc(asDoctor(), 'appointments', 'clinical_1'), {
      notes: 'المريض يشكو من صداع متكرر',
    }));
  });

  test('الطبيب يكتب تشخيصاً وعلاجاً', async () => {
    await assertSucceeds(updateDoc(doc(asDoctor(), 'appointments', 'clinical_1'), {
      diagnosis: 'صداع نصفي', prescription: 'مسكّن', completedAt: new Date(),
    }));
  });

  test('الطبيب يُنهي الكشف', async () => {
    await assertSucceeds(updateDoc(doc(asDoctor(), 'appointments', 'clinical_1'), {
      status: 'Completed',
    }));
  });

  test('الطبيب يلغي موعداً عنده', async () => {
    await assertSucceeds(updateDoc(doc(asDoctor(), 'appointments', 'clinical_1'), {
      status: 'Cancelled', cancelledAt: new Date(),
    }));
  });

  // ---- ما لا يجوز للطبيب ----

  test('طبيب آخر لا يعدّل سجل عيادة غيره', async () => {
    await assertFails(updateDoc(doc(asOtherDoctor(), 'appointments', 'clinical_1'), {
      notes: 'تدخّل من طبيب آخر',
    }));
    await assertFails(updateDoc(doc(asOtherDoctor(), 'appointments', 'clinical_1'), {
      diagnosis: 'تشخيص من طبيب آخر',
    }));
  });

  test('طبيب آخر لا ينقل الموعد إلى نفسه', async () => {
    await assertFails(updateDoc(doc(asOtherDoctor(), 'appointments', 'clinical_1'), {
      doctorId: DOCTOR2,
    }));
  });

  test('الطبيب لا يغيّر سعر الموعد ولا اسم المريض', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'appointments', 'clinical_1'), {
      price: 9999,
    }));
    await assertFails(updateDoc(doc(asDoctor(), 'appointments', 'clinical_1'), {
      patientName: 'اسم آخر',
    }));
  });

  test('لا أحد ينقل الموعد إلى وقت آخر', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'appointments', 'clinical_1'), {
      startTime: '08:00',
    }));
    await assertFails(updateDoc(doc(asPatient(), 'appointments', 'clinical_1'), {
      appointmentDate: '2030-02-02',
    }));
  });

  test('طرف ثالث لا يلمس الموعد إطلاقاً', async () => {
    await assertFails(updateDoc(doc(asOther(), 'appointments', 'clinical_1'), {
      status: 'Cancelled',
    }));
  });
});

describe('انحدار: مجموعة otps المحذوفة', () => {
  test('زائر غير مسجَّل لا ينشئ otps — لا إرسال بريد بلا مصادقة', async () => {
    // كانت `allow create: if true`، ودالة sendOTPEmail ترسل إلى معرّف
    // المستند. أي شخص كان يستطيع إرسال بريد من حساب المشروع لأي عنوان.
    await assertFails(setDoc(doc(asAnon(), 'otps', 'victim@example.com'), {
      code: '123456', expiryTime: 0,
    }));
  });

  test('حتى المستخدم المسجَّل لا ينشئ otps', async () => {
    await assertFails(setDoc(doc(asPatient(), 'otps', 'victim@example.com'), {
      code: '123456', expiryTime: 0,
    }));
  });
});

// ===========================================================================
// مطابقة الاستعلامات بالقواعد.
//
// اختبار صلاحية مستند واحد لا يكفي: Firestore يرفض **الاستعلام كاملاً** إن
// كان أي مستند في نتيجته يخالف القاعدة. هذا بالضبط ما كسر شاشتين في
// الإنتاج دون أن يلاحظ أحد — لأن الاختبارات كانت تثبت منع المهاجم فقط، ولا
// تثبت أن استعلامات المستخدم الشرعي تنجح.
//
// كل اختبار هنا يستخدم **نفس شكل الاستعلام الموجود في التطبيق**، مع ذكر
// الملف والسطر.
// ===========================================================================

describe('مطابقة الاستعلامات بالقواعد', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      // موعد لمريض آخر عند نفس الطبيب في نفس اليوم: هو ما يجعل استعلام
      // "كل مواعيد الطبيب" مرفوضاً لحساب المريض.
      await setDoc(doc(db, 'appointments', 'other_same_day'), {
        doctorId: DOCTOR, patientId: OTHER,
        appointmentDate: '2030-01-01', startTime: '10:00', status: 'Booked',
      });
      await setDoc(doc(db, 'slots', `${DOCTOR}_2030-01-01_10-00`), {
        doctorId: DOCTOR, appointmentDate: '2030-01-01', startTime: '10:00',
        capacity: 1, bookedCount: 1, patientIds: [OTHER],
      });
    });
  });

  test('المريض يقرأ الأوقات المتاحة من slots — BookingService.availabilityFor', async () => {
    // المسار الجديد. لو فشل هذا، تعود شاشة الحجز لعرض كل الأوقات متاحة.
    await assertSucceeds(getDocs(query(
      collection(asPatient(), 'slots'),
      where('doctorId', '==', DOCTOR),
      where('appointmentDate', '==', '2030-01-01'),
    )));
  });

  test('المريض لا يستطيع سرد مواعيد الطبيب — المسار القديم المكسور', async () => {
    // هذا هو الاستعلام الذي كان في BookingService.bookedCountsFor. يبقى
    // مرفوضاً عن قصد: نتيجته تحتوي مواعيد مرضى آخرين.
    await assertFails(getDocs(query(
      collection(asPatient(), 'appointments'),
      where('doctorId', '==', DOCTOR),
      where('appointmentDate', '==', '2030-01-01'),
    )));
  });

  test('المريض يتحقق من موعده هو في نفس اليوم — hasAppointmentOnDate', async () => {
    await assertSucceeds(getDocs(query(
      collection(asPatient(), 'appointments'),
      where('doctorId', '==', DOCTOR),
      where('patientId', '==', PATIENT),
      where('appointmentDate', '==', '2030-01-01'),
    )));
  });

  test('المريض يسرد مواعيده — patient_my_appointments_screen', async () => {
    await assertSucceeds(getDocs(query(
      collection(asPatient(), 'appointments'),
      where('patientId', '==', PATIENT),
    )));
  });

  test('المريض يقرأ سجله الطبي — patient_medical_history_screen', async () => {
    await assertSucceeds(getDocs(query(
      collection(asPatient(), 'appointments'),
      where('patientId', '==', PATIENT),
    )));
  });

  test('المريض يسرد الأطباء — patient_search_doctor_screen:44', async () => {
    await assertSucceeds(getDocs(query(
      collection(asPatient(), 'users'),
      where('role', '==', 'doctor'),
    )));
  });

  test('الطبيب يسرد جدوله — doctor_schedule_screen:49', async () => {
    await assertSucceeds(getDocs(query(
      collection(asDoctor(), 'appointments'),
      where('doctorId', '==', DOCTOR),
    )));
  });

  test('الطبيب يبني قائمة مرضاه من المواعيد — doctor_patients_screen', async () => {
    // بعد الإصلاح لم تعد الشاشة تقرأ users/{patientId}؛ هذا الاستعلام وحده
    // يكفيها، وفيه patientName و patientPhone.
    const snap = await getDocs(query(
      collection(asDoctor(), 'appointments'),
      where('doctorId', '==', DOCTOR),
    ));
    const withPatient = snap.docs.find((d) => d.data().patientName);
    expect(withPatient).toBeDefined();
    expect(withPatient.data().patientPhone).toBeTruthy();
  });

  test('الطبيب ما زال ممنوعاً من قراءة مستند مريضه', async () => {
    // الإصلاح كان في الشاشة، لا في القاعدة: خصوصية المرضى لم تُفتح.
    await assertFails(getDoc(doc(asDoctor(), 'users', PATIENT)));
  });

  test('الطبيب يقرأ إحصاءاته — doctor_analytics_screen:70', async () => {
    await assertSucceeds(getDocs(query(
      collection(asDoctor(), 'appointments'),
      where('doctorId', '==', DOCTOR),
    )));
  });

  test('الطبيب يسرد إشعاراته — NotificationService.getUserNotifications', async () => {
    await assertSucceeds(getDocs(query(
      collection(asDoctor(), 'notifications'),
      where('doctorId', '==', DOCTOR),
    )));
  });

  // ---- ما يجب أن يبقى مرفوضاً ----

  test('لا سرد لمجموعة المستخدمين كاملة', async () => {
    await assertFails(getDocs(query(collection(asPatient(), 'users'))));
  });

  test('لا سرد لمجموعة المواعيد كاملة', async () => {
    await assertFails(getDocs(query(collection(asPatient(), 'appointments'))));
  });

  test('لا سرد لمواعيد طبيب من حساب طبيب آخر', async () => {
    await assertFails(getDocs(query(
      collection(asOtherDoctor(), 'appointments'),
      where('doctorId', '==', DOCTOR),
    )));
  });

  test('لا سرد لفهرس أرقام الجوال', async () => {
    await assertFails(getDocs(query(collection(asAnon(), 'phone_index'))));
  });
});
