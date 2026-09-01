/**
 * اختبارات دورة حياة توثيق الطبيب والصلاحية الإدارية: قبول ورفض وإيقاف
 * واستعادة، وسجل التدقيق.
 *
 *   firebase emulators:exec --only firestore --project drd-functions-test \
 *     "npm --prefix functions test"
 */

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const admin = require('firebase-admin');
const {
  approveDoctorCore,
  rejectDoctorCore,
  suspendDoctorCore,
  restoreDoctorCore,
} = require('../admin');
const { bookAppointmentCore } = require('../booking');

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'drd-functions-test' });
}
const db = admin.firestore();

const ADMIN_UID = 'adminOne';
const APPLICANT = 'applicantOne';
const PATIENT = 'patientOne';

const NOW = new Date('2030-03-01T06:00:00Z');
const FUTURE_DATE = '2030-03-03';

/** سياق مصادقة إداري صحيح — نفس ما يمرّره `functions/index.js` الحقيقي. */
const asAdmin = () => ({ uid: ADMIN_UID, token: { admin: true } });
/** مستخدم موقّع بلا صلاحية إدارية — لتجربة الرفض. */
const asNonAdmin = (uid) => ({ uid, token: {} });

async function clearFirestore() {
  for (const name of ['users', 'doctorApplications', 'auditLogs', 'slots', 'appointments']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seedApplicant(extra = {}) {
  await db.collection('users').doc(APPLICANT).set({
    role: 'patient', name: 'متقدّم', phone: '201000000009',
    email: 'applicant@example.com',
  });
  await db.collection('doctorApplications').doc(APPLICANT).set({
    uid: APPLICANT, status: 'pending', specialization: 'أسنان',
    note: 'خبرة 5 سنوات', submittedAt: NOW,
    ...extra,
  });
}

async function seedActiveDoctor(extra = {}) {
  await db.collection('users').doc(APPLICANT).set({
    role: 'doctor', name: 'د. متقدّم', phone: '201000000009',
    email: 'applicant@example.com', isVerified: true, disabled: false,
    verificationStatus: 'approved', bookingSystemType: 'Individual',
    sessionDuration: 30, price: 200, workingHours: '09:00 AM - 05:00 PM',
    ...extra,
  });
}

beforeEach(async () => {
  await clearFirestore();
  await db.collection('users').doc(PATIENT).set({
    role: 'patient', name: 'مريض', phone: '201000000002',
    email: 'p@example.com',
  });
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app && app.delete()));
});

async function reasonOf(promise) {
  try {
    await promise;
    return null;
  } catch (e) {
    return e.reason || e.code || e.message;
  }
}

async function getUser(uid) {
  const snap = await db.collection('users').doc(uid).get();
  return snap.exists ? snap.data() : null;
}

async function getApplication(uid) {
  const snap = await db.collection('doctorApplications').doc(uid).get();
  return snap.exists ? snap.data() : null;
}

async function getAuditLogs(targetId) {
  const snap = await db.collection('auditLogs')
    .where('targetId', '==', targetId).get();
  return snap.docs.map((d) => d.data());
}

// ===================== approveDoctor =====================

describe('approveDoctor — التفويض والمدخلات', () => {
  test('غير مسجَّل الدخول مرفوض', async () => {
    await seedApplicant();
    expect(await reasonOf(approveDoctorCore({
      db, uid: '', auth: null, data: { uid: APPLICANT },
    }))).toBe('permission-denied');
  });

  test('مريض عادي مرفوض', async () => {
    await seedApplicant();
    expect(await reasonOf(approveDoctorCore({
      db, uid: PATIENT, auth: asNonAdmin(PATIENT), data: { uid: APPLICANT },
    }))).toBe('permission-denied');

    // ولم يتغيّر شيء.
    const app = await getApplication(APPLICANT);
    expect(app.status).toBe('pending');
  });

  test('claim مزيَّف من الطلب لا يمنح الصلاحية — auth.token هو المصدر الوحيد', async () => {
    await seedApplicant();
    expect(await reasonOf(approveDoctorCore({
      db, uid: PATIENT, auth: asNonAdmin(PATIENT),
      data: { uid: APPLICANT, admin: true, token: { admin: true } },
    }))).toBe('permission-denied');
  });

  test('معرّف مستخدم غير صالح مرفوض', async () => {
    expect(await reasonOf(approveDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: '../etc' },
    }))).toBe('invalid-argument');
  });

  test('لا يوجد طلب بهذا المعرّف', async () => {
    expect(await reasonOf(approveDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: 'no_such_uid' },
    }))).toBe('application-not-found');
  });
});

describe('approveDoctor — القبول الفعلي', () => {
  test('مدير صحيح يقبل الطلب فيصبح المتقدّم طبيباً نشطاً', async () => {
    await seedApplicant();
    const res = await approveDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT },
    });
    expect(res.alreadyApproved).toBe(false);

    const user = await getUser(APPLICANT);
    expect(user.role).toBe('doctor');
    expect(user.isVerified).toBe(true);
    expect(user.disabled).toBe(false);
    expect(user.verificationStatus).toBe('approved');
    expect(user.verifiedBy).toBe(ADMIN_UID);
    expect(user.verifiedAt).toBeTruthy();

    const app = await getApplication(APPLICANT);
    expect(app.status).toBe('approved');
    expect(app.reviewedBy).toBe(ADMIN_UID);

    const logs = await getAuditLogs(APPLICANT);
    expect(logs.length).toBe(1);
    expect(logs[0].action).toBe('doctor.approved');
    expect(logs[0].actorAdminId).toBe(ADMIN_UID);
  });

  test('الطبيب المقبول أصبح قابلاً للحجز فوراً — بلا أي تعديل على bookAppointment', async () => {
    await seedApplicant();
    await approveDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT },
    });
    const result = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: APPLICANT, date: FUTURE_DATE, time: '09:00' },
      now: NOW,
    });
    expect(result.status).toBe('Booked');
  });

  test('طلب مكرَّر بعد القبول لا يُنتج قبولاً ثانياً ولا سجل تدقيق إضافي', async () => {
    await seedApplicant();
    await approveDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT },
    });
    const second = await approveDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT },
    });
    expect(second.alreadyApproved).toBe(true);

    const logs = await getAuditLogs(APPLICANT);
    expect(logs.length).toBe(1);
  });

  test('طلب مرفوض لا يُقبل مباشرة — يحتاج إعادة تقديم أولاً', async () => {
    await seedApplicant({ status: 'rejected', rejectionReason: 'ناقص' });
    expect(await reasonOf(approveDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT },
    }))).toBe('application-rejected');

    const user = await getUser(APPLICANT);
    expect(user.role).toBe('patient');
  });
});

// ===================== rejectDoctor =====================

describe('rejectDoctor', () => {
  test('غير مدير مرفوض', async () => {
    await seedApplicant();
    expect(await reasonOf(rejectDoctorCore({
      db, uid: PATIENT, auth: asNonAdmin(PATIENT),
      data: { uid: APPLICANT, reason: 'غير كافٍ' },
    }))).toBe('permission-denied');
  });

  test('السبب إلزامي', async () => {
    await seedApplicant();
    expect(await reasonOf(rejectDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT },
    }))).toBe('invalid-argument');
  });

  test('رفض صحيح يحفظ السبب ولا يمسّ حساب المتقدّم', async () => {
    await seedApplicant();
    const res = await rejectDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(),
      data: { uid: APPLICANT, reason: 'بيانات ناقصة' },
    });
    expect(res.alreadyRejected).toBe(false);

    const app = await getApplication(APPLICANT);
    expect(app.status).toBe('rejected');
    expect(app.rejectionReason).toBe('بيانات ناقصة');

    const user = await getUser(APPLICANT);
    expect(user.role).toBe('patient');
    expect(user.isVerified).toBeUndefined();

    const logs = await getAuditLogs(APPLICANT);
    expect(logs[0].action).toBe('doctor.rejected');
  });

  test('رفض مكرَّر لا يستبدل السبب الأصلي', async () => {
    await seedApplicant();
    await rejectDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(),
      data: { uid: APPLICANT, reason: 'السبب الأول' },
    });
    const second = await rejectDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(),
      data: { uid: APPLICANT, reason: 'سبب مختلف' },
    });
    expect(second.alreadyRejected).toBe(true);

    const app = await getApplication(APPLICANT);
    expect(app.rejectionReason).toBe('السبب الأول');
  });

  test('طلب مقبول بالفعل لا يُرفض مباشرة', async () => {
    await seedApplicant({ status: 'approved' });
    expect(await reasonOf(rejectDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(),
      data: { uid: APPLICANT, reason: 'سبب' },
    }))).toBe('application-approved');
  });
});

// ===================== suspendDoctor =====================

describe('suspendDoctor', () => {
  test('غير مدير مرفوض', async () => {
    await seedActiveDoctor();
    expect(await reasonOf(suspendDoctorCore({
      db, uid: PATIENT, auth: asNonAdmin(PATIENT),
      data: { uid: APPLICANT, reason: 'شكوى' },
    }))).toBe('permission-denied');
  });

  test('السبب إلزامي', async () => {
    await seedActiveDoctor();
    expect(await reasonOf(suspendDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT },
    }))).toBe('invalid-argument');
  });

  test('لا يمكن إيقاف حساب لم يُوثَّق كطبيب بعد', async () => {
    await db.collection('users').doc(APPLICANT).set({ role: 'patient' });
    expect(await reasonOf(suspendDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(),
      data: { uid: APPLICANT, reason: 'سبب' },
    }))).toBe('doctor-not-active');
  });

  test('إيقاف طبيب نشط ينجح ويحافظ على isVerified', async () => {
    await seedActiveDoctor();
    const res = await suspendDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(),
      data: { uid: APPLICANT, reason: 'شكاوى متكررة' },
    });
    expect(res.alreadySuspended).toBe(false);

    const user = await getUser(APPLICANT);
    expect(user.disabled).toBe(true);
    expect(user.isVerified).toBe(true); // موثَّق لكن موقوف — تمييز متعمَّد.
    expect(user.verificationStatus).toBe('suspended');
    expect(user.suspensionReason).toBe('شكاوى متكررة');

    const logs = await getAuditLogs(APPLICANT);
    expect(logs[0].action).toBe('doctor.suspended');
  });

  test('طبيب موقوف لا يقبل حجوزات جديدة', async () => {
    await seedActiveDoctor();
    await suspendDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(),
      data: { uid: APPLICANT, reason: 'إيقاف' },
    });
    expect(await reasonOf(bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: APPLICANT, date: FUTURE_DATE, time: '09:00' },
      now: NOW,
    }))).toBe('doctor-disabled');
  });

  test('إيقاف مكرَّر لا يُنتج سجل تدقيق إضافي', async () => {
    await seedActiveDoctor();
    await suspendDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT, reason: 'أ' },
    });
    const second = await suspendDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT, reason: 'ب' },
    });
    expect(second.alreadySuspended).toBe(true);

    const logs = await getAuditLogs(APPLICANT);
    expect(logs.length).toBe(1);
  });
});

// ===================== restoreDoctor =====================

describe('restoreDoctor', () => {
  test('غير مدير مرفوض', async () => {
    await seedActiveDoctor({ disabled: true });
    expect(await reasonOf(restoreDoctorCore({
      db, uid: PATIENT, auth: asNonAdmin(PATIENT), data: { uid: APPLICANT },
    }))).toBe('permission-denied');
  });

  test('استعادة طبيب موقوف تعيده قابلاً للحجز', async () => {
    await seedActiveDoctor({
      disabled: true, verificationStatus: 'suspended',
      suspendedAt: NOW, suspendedBy: ADMIN_UID, suspensionReason: 'سبب سابق',
    });
    const res = await restoreDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT },
    });
    expect(res.alreadyActive).toBe(false);

    const user = await getUser(APPLICANT);
    expect(user.disabled).toBe(false);
    expect(user.verificationStatus).toBe('approved');
    // السجل التاريخي للإيقاف يبقى — لا يُحذف.
    expect(user.suspensionReason).toBe('سبب سابق');

    const result = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: APPLICANT, date: FUTURE_DATE, time: '09:00' },
      now: NOW,
    });
    expect(result.status).toBe('Booked');

    const logs = await getAuditLogs(APPLICANT);
    expect(logs.some((l) => l.action === 'doctor.unsuspended')).toBe(true);
  });

  test('استعادة طبيب نشط بالفعل — نجاح هادئ بلا سجل إضافي', async () => {
    await seedActiveDoctor();
    const res = await restoreDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT },
    });
    expect(res.alreadyActive).toBe(true);

    const logs = await getAuditLogs(APPLICANT);
    expect(logs.length).toBe(0);
  });

  test('حساب ليس طبيباً لا يُستعاد', async () => {
    await db.collection('users').doc(APPLICANT).set({ role: 'patient' });
    expect(await reasonOf(restoreDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT },
    }))).toBe('not-a-doctor');
  });
});

// ===================== دورة حياة كاملة =====================

describe('دورة حياة كاملة: تقديم → قبول → إيقاف → استعادة', () => {
  test('كل انتقال يعكس نفسه في users والتدقيق، والحجز يتبع الحالة دائماً', async () => {
    await seedApplicant();

    // pending → لا يمكن الحجز أصلاً (ليس طبيباً بعد).
    expect(await reasonOf(bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: APPLICANT, date: FUTURE_DATE, time: '09:00' },
      now: NOW,
    }))).toBe('doctor-not-found');

    // approve → نشط وقابل للحجز.
    await approveDoctorCore({ db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT } });
    await db.collection('users').doc(APPLICANT).update({
      bookingSystemType: 'Individual', sessionDuration: 30, price: 200,
      workingHours: '09:00 AM - 05:00 PM',
    });
    const booked = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: APPLICANT, date: FUTURE_DATE, time: '09:00' },
      now: NOW,
    });
    expect(booked.status).toBe('Booked');

    // suspend → لا حجوزات جديدة، لكن الموعد القائم يبقى.
    await suspendDoctorCore({
      db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT, reason: 'مراجعة' },
    });
    expect(await reasonOf(bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: APPLICANT, date: FUTURE_DATE, time: '09:30' },
      now: NOW,
    }))).toBe('doctor-disabled');
    const stillThere = await db.collection('appointments').doc(booked.appointmentId).get();
    expect(stillThere.exists).toBe(true);
    expect(stillThere.data().status).toBe('Booked');

    // restore → الحجز يعمل من جديد. تاريخ مختلف لأن المريض له بالفعل موعد
    // قائم مع هذا الطبيب في FUTURE_DATE — قاعدة «لا موعدين لنفس اليوم» تعمل
    // كما هي، وليست ما يُختبر هنا.
    await restoreDoctorCore({ db, uid: ADMIN_UID, auth: asAdmin(), data: { uid: APPLICANT } });
    const rebooked = await bookAppointmentCore({
      db, uid: PATIENT,
      data: { doctorId: APPLICANT, date: '2030-03-10', time: '09:30' },
      now: NOW,
    });
    expect(rebooked.status).toBe('Booked');

    const logs = await getAuditLogs(APPLICANT);
    const actions = logs.map((l) => l.action).sort();
    expect(actions).toEqual(['doctor.approved', 'doctor.suspended', 'doctor.unsuspended']);
  });
});

describe('اعتماد الطبيب يصفّر المُجمَّع (المرحلة 9)', () => {
  test('قيمة تقييم سابقة على الحساب لا تنجو من الاعتماد', async () => {
    // دفاع ثانٍ خلف قاعدة الإنشاء: حساب أُنشئ قبل إحكام القاعدة ببذرة
    // تقييم كان سيظهر في البحث بخمس نجوم بلا زيارة واحدة.
    await db.collection('users').doc('seededDoc').set({
      role: 'patient', name: 'مهاجم', email: 's@e.com',
      rating: 5, reviews: 500, ratingSum: 2500,
    });
    await db.collection('doctorApplications').doc('seededDoc').set({
      uid: 'seededDoc', status: 'pending', submittedAt: new Date(),
    });

    await approveDoctorCore({
      db, uid: 'adminUid', auth: { token: { admin: true } },
      data: { uid: 'seededDoc' },
    });

    const after = (await db.collection('users').doc('seededDoc').get()).data();
    expect(after.role).toBe('doctor');
    expect(after.rating).toBe(0);
    expect(after.reviews).toBe(0);
    expect(after.ratingSum).toBe(0);
  });
});
