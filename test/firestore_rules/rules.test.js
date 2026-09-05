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

describe('تقييم الطبيب — الحقول المجمَّعة صارت للخادم وحده', () => {
  // كانت هنا قاعدة `isReviewAggregateUpdate` تسمح لأي مستخدم مسجَّل بزيادة
  // `reviews` بواحد وكتابة أي قيمة في `rating`. أُزيلت: لا قاعدة أمان تستطيع
  // التحقّق من صحة *حساب* متوسط، فالحساب انتقل إلى `syncDoctorRating`.

  test('المريض لا يكتب في تقييم الطبيب إطلاقاً', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 4.2, reviews: 11,
    }));
  });

  test('ولا حتى بزيادة واحدة بقيمة سليمة (ما كان مسموحاً سابقاً)', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 4, reviews: 11,
    }));
  });

  test('الطبيب لا يرفع تقييم نفسه', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      rating: 5, reviews: 999,
    }));
  });
});

describe('slots — منع الحجز المزدوج', () => {
  const SLOT = `${DOCTOR}_2030-01-01_09-00`;

  test('لا يمكن تجاوز سعة الخانة', async () => {
    // جوهر الضمان: الخانة سعتها 1 ومحجوزة بالفعل.
    await assertFails(updateDoc(doc(asOther(), 'slots', SLOT), {
      bookedCount: 2,
    }));
  });

  test('لا يمكن توسيع السعة للتحايل', async () => {
    await assertFails(updateDoc(doc(asOther(), 'slots', SLOT), {
      capacity: 99, bookedCount: 2,
    }));
  });

  test('الإلغاء ينقص العدّاد', async () => {
    await assertSucceeds(updateDoc(doc(asPatient(), 'slots', SLOT), {
      bookedCount: 0,
    }));
  });

  test('إنشاء خانة جديدة يبدأ بحجز واحد', async () => {
    await assertSucceeds(setDoc(doc(asPatient(), 'slots', `${DOCTOR}_2030-02-02_10-00`), {
      doctorId: DOCTOR, appointmentDate: '2030-02-02', startTime: '10:00',
      capacity: 1, bookedCount: 1,
    }));
  });

  test('لا تُنشأ خانة تحمل هويّات المرضى', async () => {
    // `slots` مقروءة لكل مستخدم مسجَّل، فحمل الهويّات فيها يكشف مَن حجز
    // عند أي طبيب ومتى. العدّاد وحده هو ما يجوز أن يكون عاماً.
    await assertFails(setDoc(doc(asPatient(), 'slots', `${DOCTOR}_2030-03-03_10-00`), {
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

describe('reviews — مراجعات مربوطة بزيارة', () => {
  // معرّف المراجعة = معرّف الموعد، فالتفرّد مجاني والقاعدة تستطيع التحقّق
  // من الزيارة نفسها.
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'appointments', 'visit_done'), {
        doctorId: DOCTOR, patientId: PATIENT,
        appointmentDate: '2020-01-01', startTime: '09:00', status: 'Completed',
      });
      await setDoc(doc(db, 'appointments', 'visit_booked'), {
        doctorId: DOCTOR, patientId: PATIENT,
        appointmentDate: '2030-01-01', startTime: '11:00', status: 'Booked',
      });
      await setDoc(doc(db, 'reviews', 'visit_done'), {
        doctorId: DOCTOR, patientId: PATIENT,
        appointmentId: 'visit_done', rating: 5, comment: 'ممتاز',
      });
    });
  });

  test('المريض يراجع زيارة تمّت فعلاً', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), 'reviews', 'visit_done'));
    });
    await assertSucceeds(setDoc(doc(asPatient(), 'reviews', 'visit_done'), {
      doctorId: DOCTOR, patientId: PATIENT,
      appointmentId: 'visit_done', rating: 5, comment: 'شكراً',
    }));
  });

  test('لا مراجعة بلا زيارة', async () => {
    await assertFails(setDoc(doc(asOther(), 'reviews', 'ghost'), {
      doctorId: DOCTOR, patientId: OTHER, appointmentId: 'ghost', rating: 1,
    }));
  });

  test('لا مراجعة لزيارة لم تتم بعد', async () => {
    await assertFails(setDoc(doc(asPatient(), 'reviews', 'visit_booked'), {
      doctorId: DOCTOR, patientId: PATIENT,
      appointmentId: 'visit_booked', rating: 5,
    }));
  });

  test('لا مراجعة لزيارة شخص آخر', async () => {
    await assertFails(setDoc(doc(asOther(), 'reviews', 'visit_done'), {
      doctorId: DOCTOR, patientId: OTHER,
      appointmentId: 'visit_done', rating: 1,
    }));
  });

  test('الطبيب لا يراجع نفسه', async () => {
    // كان مسموحاً: القاعدة كانت تفحص `patientId == uid` فقط، فيمرّ
    // `doctorId == patientId == self`. تصبح ثغرة فعلية بمجرد نقل حساب
    // المتوسط إلى الخادم، لأن التقييم المزوّر سيُحتسب.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'appointments', 'self_visit'), {
        doctorId: DOCTOR, patientId: DOCTOR,
        appointmentDate: '2020-01-01', startTime: '09:00', status: 'Completed',
      });
    });
    await assertFails(setDoc(doc(asDoctor(), 'reviews', 'self_visit'), {
      doctorId: DOCTOR, patientId: DOCTOR,
      appointmentId: 'self_visit', rating: 5,
    }));
  });

  test('التقييم خارج 1..5 مرفوض عند الإنشاء', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), 'reviews', 'visit_done'));
    });
    await assertFails(setDoc(doc(asPatient(), 'reviews', 'visit_done'), {
      doctorId: DOCTOR, patientId: PATIENT,
      appointmentId: 'visit_done', rating: 100,
    }));
  });

  test('وخارج 1..5 مرفوض عند التعديل أيضاً', async () => {
    // كان النطاق مفحوصاً عند الإنشاء فقط: أنشئ بـ 5 ثم عدّل إلى 999.
    await assertFails(updateDoc(doc(asPatient(), 'reviews', 'visit_done'), {
      rating: 999,
    }));
  });

  test('تعديل التقييم ضمن النطاق مسموح لصاحبه', async () => {
    await assertSucceeds(updateDoc(doc(asPatient(), 'reviews', 'visit_done'), {
      rating: 3, comment: 'غيّرت رأيي',
    }));
  });

  test('لا يُغيَّر الطبيب أو المريض في مراجعة قائمة', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'reviews', 'visit_done'), {
      doctorId: DOCTOR2,
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

// ===========================================================================
// اختبارات انحدار — المرحلة صفر (الجولة الثانية)
// ===========================================================================

describe('انحدار: إعادة الحجز بعد الإلغاء', () => {
  // معرّف الموعد محسوب من (طبيب + تاريخ + وقت + مريض)، فإعادة الحجز تكتب فوق
  // نفس المستند — `update` لا `create`. قاعدة الإلغاء وحدها كانت ترفض ذلك،
  // فمن ألغى موعداً لم يكن يستطيع حجزه ثانية أبداً.
  const SLOT = `${DOCTOR}_2030-01-01_09-00`;
  const APPT = `${SLOT}__${PATIENT}`;

  const seedWith = (status, extra = {}) =>
    testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'appointments', APPT), {
        doctorId: DOCTOR, patientId: PATIENT,
        appointmentDate: '2030-01-01', startTime: '09:00', slotId: SLOT,
        status, patientName: 'مريض', patientPhone: '201000000002',
        reason: 'كشف', price: 200, ...extra,
      });
    });

  const rebook = (extra = {}) =>
    setDoc(doc(asPatient(), 'appointments', APPT), {
      doctorId: DOCTOR, patientId: PATIENT,
      appointmentDate: '2030-01-01', startTime: '09:00', slotId: SLOT,
      status: 'Booked', patientName: 'مريض', patientPhone: '201000000002',
      reason: 'كشف جديد', price: 200, createdAt: new Date(), ...extra,
    });

  test('المريض يعيد حجز خانة ألغاها', async () => {
    await seedWith('Cancelled');
    await assertSucceeds(rebook());
  });

  test('وتعمل مع الصيغ القديمة للإلغاء', async () => {
    await seedWith('canceled');
    await assertSucceeds(rebook());
  });

  test('لا إعادة حجز فوق زيارة مكتملة', async () => {
    await seedWith('Completed', { diagnosis: 'التهاب', notes: 'ملاحظة' });
    await assertFails(rebook());
  });

  test('لا إعادة حجز فوق موعد قائم', async () => {
    await seedWith('Booked');
    await assertFails(rebook());
  });

  test('إعادة الحجز لا تمحو تشخيصاً موجوداً', async () => {
    // `affectedKeys()` يشمل الحقول المحذوفة، فمحاولة الكتابة بدون التشخيص
    // تُرصد كتغيير عليه وتُرفض.
    await seedWith('Cancelled', { diagnosis: 'تشخيص سابق' });
    await assertFails(rebook());
  });

  test('إعادة الحجز لا تحقن تشخيصاً', async () => {
    await seedWith('Cancelled');
    await assertFails(rebook({ diagnosis: 'مزروع' }));
  });

  test('إعادة الحجز لا تنقل الموعد لوقت آخر', async () => {
    await seedWith('Cancelled');
    await assertFails(rebook({ startTime: '08:00' }));
  });
});

describe('انحدار: قائمة سماح حقول مستند المستخدم', () => {
  test('المستخدم لا يمنح نفسه حقل تحقّق', async () => {
    // القاعدة السابقة كانت قائمة منع تحمي `role`/`rating`/`reviews` فقط،
    // فأي حقل جديد كان مسموحاً. أول شاشة تعرض "طبيب موثّق" اعتماداً على حقل
    // كهذا كانت ستصبح قابلة للتزوير من العميل.
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      isVerified: true,
    }));
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      verificationStatus: 'approved',
    }));
    await assertFails(updateDoc(doc(asPatient(), 'users', PATIENT), {
      accountStatus: 'premium',
    }));
  });

  test('ولا يُهرّبه ضمن تعديل مشروع', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', PATIENT), {
      name: 'اسم جديد', isVerified: true,
    }));
  });

  test('ولا عند إنشاء الحساب', async () => {
    const fresh = testEnv.authenticatedContext('fresh_user').firestore();
    await assertFails(setDoc(doc(fresh, 'users', 'fresh_user'), {
      role: 'patient', name: 'جديد', phone: '201555555555',
      isVerified: true,
    }));
  });

  test('التعديلات المشروعة ما زالت تعمل', async () => {
    await assertSucceeds(updateDoc(doc(asPatient(), 'users', PATIENT), {
      name: 'اسم جديد', gender: 'female', birthDate: '1991-02-02',
    }));
    await assertSucceeds(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      clinicNameAr: 'عيادة النور', price: 250, specialization: 'أسنان',
      workingHours: '09:00 AM - 05:00 PM',
    }));
  });

  test('وإنشاء حساب مريض عادي ما زال يعمل', async () => {
    const fresh = testEnv.authenticatedContext('fresh_ok').firestore();
    await assertSucceeds(setDoc(doc(fresh, 'users', 'fresh_ok'), {
      role: 'patient', name: 'جديد', phone: '201555555556',
      email: 'n@e.com', birthDate: '1990-01-01', gender: 'male',
      emailVerified: true, createdAt: new Date(),
    }));
  });
});

describe('encounters — السجل السريري', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'appointments', 'visit_1'), {
        doctorId: DOCTOR, patientId: PATIENT,
        appointmentDate: '2020-01-01', startTime: '09:00', status: 'Completed',
      });
      await setDoc(doc(db, 'encounters', 'enc_1'), {
        doctorId: DOCTOR, patientId: PATIENT, appointmentId: 'visit_1',
        encounterDate: '2020-01-01', diagnosis: 'التهاب',
        prescription: 'مضاد حيوي', clinicalNotes: 'يشكو من ألم',
      });
    });
  });

  test('المريض يقرأ سجله، والطبيب المؤلِّف كذلك', async () => {
    await assertSucceeds(getDoc(doc(asPatient(), 'encounters', 'enc_1')));
    await assertSucceeds(getDoc(doc(asDoctor(), 'encounters', 'enc_1')));
  });

  test('طبيب آخر لا يقرأ السجل', async () => {
    // الوصول لطرف ثالث يمرّ عبر مشاركة صريحة من المريض (المرحلة الرابعة)،
    // لا عبر توسيع هذه القاعدة.
    await assertFails(getDoc(doc(asOtherDoctor(), 'encounters', 'enc_1')));
  });

  test('مريض آخر لا يقرأ السجل', async () => {
    await assertFails(getDoc(doc(asOther(), 'encounters', 'enc_1')));
  });

  test('المريض لا يعدّل التشخيص ولا الوصفة ولا الملاحظات', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'encounters', 'enc_1'), {
      diagnosis: 'تشخيص من عند المريض',
    }));
    await assertFails(updateDoc(doc(asPatient(), 'encounters', 'enc_1'), {
      prescription: 'دواء',
    }));
    await assertFails(updateDoc(doc(asPatient(), 'encounters', 'enc_1'), {
      clinicalNotes: 'ملاحظة مزوّرة',
    }));
  });

  test('المريض لا يُنشئ سجلاً سريرياً', async () => {
    await assertFails(setDoc(doc(asPatient(), 'encounters', 'enc_fake'), {
      doctorId: DOCTOR, patientId: PATIENT, appointmentId: 'visit_1',
      encounterDate: '2020-01-01', diagnosis: 'مخترع',
    }));
  });

  test('المريض لا يحذف سجلاً', async () => {
    await assertFails(deleteDoc(doc(asPatient(), 'encounters', 'enc_1')));
  });

  test('الطبيب يُنشئ سجلاً لموعد عنده', async () => {
    await assertSucceeds(setDoc(doc(asDoctor(), 'encounters', 'enc_2'), {
      doctorId: DOCTOR, patientId: PATIENT, appointmentId: 'visit_1',
      encounterDate: '2020-01-01', diagnosis: 'تشخيص',
    }));
  });

  test('الطبيب لا يُنشئ سجلاً لمريض لا موعد له عنده', async () => {
    // هذا ما يمنع طبيباً من تأليف سجل لأي مريض يعرف معرّفه.
    await assertFails(setDoc(doc(asOtherDoctor(), 'encounters', 'enc_3'), {
      doctorId: DOCTOR2, patientId: PATIENT, appointmentId: 'visit_1',
      encounterDate: '2020-01-01', diagnosis: 'تدخّل',
    }));
  });

  test('الطبيب لا يؤلّف باسم طبيب آخر', async () => {
    await assertFails(setDoc(doc(asOtherDoctor(), 'encounters', 'enc_4'), {
      doctorId: DOCTOR, patientId: PATIENT, appointmentId: 'visit_1',
      encounterDate: '2020-01-01',
    }));
  });

  test('المؤلِّف يعدّل سجله، وغيره لا', async () => {
    await assertSucceeds(updateDoc(doc(asDoctor(), 'encounters', 'enc_1'), {
      diagnosis: 'تشخيص محدَّث',
    }));
    await assertFails(updateDoc(doc(asOtherDoctor(), 'encounters', 'enc_1'), {
      diagnosis: 'تدخّل',
    }));
  });

  test('لا يُنقل السجل إلى مريض أو طبيب آخر', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'encounters', 'enc_1'), {
      patientId: OTHER,
    }));
    await assertFails(updateDoc(doc(asDoctor(), 'encounters', 'enc_1'), {
      doctorId: DOCTOR2,
    }));
  });

  test('المريض يسرد سجلاته، ولا يسرد سجلات غيره', async () => {
    await assertSucceeds(getDocs(query(
      collection(asPatient(), 'encounters'),
      where('patientId', '==', PATIENT),
    )));
    await assertFails(getDocs(query(collection(asPatient(), 'encounters'))));
    await assertFails(getDocs(query(
      collection(asOther(), 'encounters'),
      where('patientId', '==', PATIENT),
    )));
  });

  test('نسخ التصحيح لا تُكتب من العميل', async () => {
    await assertFails(setDoc(
      doc(asDoctor(), 'encounters', 'enc_1', 'revisions', 'r1'),
      { diagnosis: 'قديم' },
    ));
  });
});
