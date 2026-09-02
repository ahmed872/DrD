/**
 * اختبارات التحليلات على الخادم.
 *
 * تعمل على محاكي Firestore الحقيقي — التجميع والتصنيف وحدود المدى لا
 * يُثبتها إلا تشغيلها على بيانات فعلية.
 *
 *   firebase emulators:exec --only firestore --project drd-functions-test \
 *     "npm --prefix functions test"
 */

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const admin = require('firebase-admin');
const {
  getPatientAnalyticsCore,
  getDoctorAnalyticsCore,
  getAdminAnalyticsCore,
  bucketKey,
  shiftDays,
  classify,
  RANGES,
  MAX_SCAN,
  TOP_N,
} = require('../analytics');

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'drd-functions-test' });
}
const db = admin.firestore();

const DOCTOR = 'anDoctor';
const OTHER_DOCTOR = 'anDoctorTwo';
const PATIENT = 'anPatient';
const OTHER_PATIENT = 'anPatientTwo';

const adminAuth = { token: { admin: true } };
const plainAuth = { token: {} };

/** اليوم بتوقيت العيادة — نفس ما تحسبه الوحدة نفسها. */
const today = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Africa/Cairo', year: 'numeric', month: '2-digit', day: '2-digit',
}).format(new Date());

async function clearAll() {
  for (const col of ['appointments', 'users', 'doctorApplications']) {
    const snap = await db.collection(col).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seedUsers() {
  await db.collection('users').doc(DOCTOR).set({
    role: 'doctor', name: 'د. تحليل', isVerified: true, disabled: false,
    rating: 4.5, reviews: 20, specialization: 'باطنة',
  });
  await db.collection('users').doc(OTHER_DOCTOR).set({
    role: 'doctor', name: 'د. آخر', isVerified: true, disabled: true,
    rating: 3, reviews: 2,
  });
  await db.collection('users').doc(PATIENT).set({
    role: 'patient', name: 'مريض',
  });
  await db.collection('users').doc(OTHER_PATIENT).set({
    role: 'patient', name: 'مريض آخر',
  });
}

let seq = 0;
async function seedAppointment({
  doctorId = DOCTOR, patientId = PATIENT, dayOffset = 0,
  status = 'Booked', specialization = 'باطنة', rescheduledFrom = null,
} = {}) {
  const date = shiftDays(today, dayOffset);
  const id = `an${seq++}`;
  await db.collection('appointments').doc(id).set({
    doctorId, patientId, appointmentDate: date, startTime: '09:00',
    status, price: 200, doctorSpecialization: specialization,
    ...(rescheduledFrom ? { rescheduledFrom } : {}),
  });
  return id;
}

beforeEach(async () => {
  await clearAll();
  await seedUsers();
});

afterAll(async () => {
  await clearAll();
});

// ===================== الصلاحيات =====================

describe('صلاحية الوصول', () => {
  test('غير المسجَّل لا يصل إلى أي تحليلات', async () => {
    for (const core of
      [getPatientAnalyticsCore, getDoctorAnalyticsCore, getAdminAnalyticsCore]) {
      await expect(core({ db, uid: null, auth: null, data: {} }))
        .rejects.toThrow();
    }
  });

  test('المريض لا يصل إلى تحليلات الأطباء', async () => {
    await expect(getDoctorAnalyticsCore({
      db, uid: PATIENT, auth: plainAuth, data: {},
    })).rejects.toThrow();
  });

  test('المريض لا يصل إلى تحليلات المنصّة', async () => {
    await expect(getAdminAnalyticsCore({
      db, uid: PATIENT, auth: plainAuth, data: {},
    })).rejects.toThrow();
  });

  test('الطبيب لا يصل إلى تحليلات المنصّة', async () => {
    await expect(getAdminAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: {},
    })).rejects.toThrow();
  });

  test('صلاحية الإدارة من الرمز الموقَّع لا من مستند', async () => {
    // كتابة `admin: true` في مستند المستخدم لا تمنح شيئاً.
    await db.collection('users').doc(PATIENT)
      .set({ role: 'patient', admin: true, isAdmin: true }, { merge: true });
    await expect(getAdminAnalyticsCore({
      db, uid: PATIENT, auth: plainAuth, data: {},
    })).rejects.toThrow();

    await expect(getAdminAnalyticsCore({
      db, uid: PATIENT, auth: adminAuth, data: {},
    })).resolves.toMatchObject({ ok: true, scope: 'admin' });
  });

  test('لا صيغة لطلب تحليلات مريض آخر', async () => {
    // النطاق مشتقّ من `uid` المصادَق عليه؛ أي معرّف في الحمولة يُتجاهَل.
    await seedAppointment({ patientId: OTHER_PATIENT });
    const res = await getPatientAnalyticsCore({
      db, uid: PATIENT, auth: plainAuth,
      data: { patientId: OTHER_PATIENT, uid: OTHER_PATIENT },
    });
    expect(res.counts.total).toBe(0);
  });

  test('لا صيغة لطلب تحليلات طبيب آخر', async () => {
    await seedAppointment({ doctorId: OTHER_DOCTOR });
    const res = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth,
      data: { doctorId: OTHER_DOCTOR },
    });
    expect(res.counts.total).toBe(0);
  });
});

// ===================== الصحّة =====================

describe('صحّة الأرقام', () => {
  test('تصنيف الحالات يشمل الصيغ القديمة', () => {
    // قاعدة البيانات تحمل سبع صيغ؛ رقم لا يرى `done` مكتملاً رقم خاطئ.
    expect(classify('Completed')).toBe('completed');
    expect(classify('done')).toBe('completed');
    expect(classify('Cancelled')).toBe('cancelled');
    expect(classify('canceled')).toBe('cancelled');
    expect(classify('NoShow')).toBe('noShow');
    expect(classify('upcoming')).toBe('open');
    expect(classify('Booked')).toBe('open');
  });

  test('العدّ يفصل الحالات فصلاً صحيحاً', async () => {
    await seedAppointment({ status: 'Booked' });
    await seedAppointment({ status: 'Booked' });
    await seedAppointment({ status: 'Completed' });
    await seedAppointment({ status: 'done' });
    await seedAppointment({ status: 'Cancelled' });
    await seedAppointment({ status: 'NoShow' });

    const res = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: { range: '30d' },
    });
    expect(res.counts).toMatchObject({
      total: 6, open: 2, completed: 2, cancelled: 1, noShow: 1,
    });
  });

  test('المعاد جدولته يُعدّ من `rescheduledFrom`', async () => {
    await seedAppointment({ status: 'Booked' });
    await seedAppointment({ status: 'Booked', rescheduledFrom: 'old1' });
    const res = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: {},
    });
    expect(res.counts.rescheduled).toBe(1);
  });

  test('النِّسب تُحسب على المنتهية لا على الإجمالي', async () => {
    // موعد لم يحن بعد ليس فشلاً، فلا يدخل مقام نسبة الإلغاء.
    await seedAppointment({ status: 'Completed' });
    await seedAppointment({ status: 'Completed' });
    await seedAppointment({ status: 'Cancelled' });
    await seedAppointment({ status: 'Booked' });
    await seedAppointment({ status: 'Booked' });

    const res = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: {},
    });
    // 2 مكتمل من 3 منتهية = 66.7%
    expect(res.quality.completionRate).toBeCloseTo(66.7, 1);
    expect(res.quality.cancellationRate).toBeCloseTo(33.3, 1);
  });

  test('قسمة على صفر لا تنتج NaN', async () => {
    const res = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: {},
    });
    expect(res.quality.completionRate).toBe(0);
    expect(res.quality.cancellationRate).toBe(0);
    expect(res.counts.total).toBe(0);
  });

  test('مدى فارغ يُرجع هيكلاً كاملاً لا رداً ناقصاً', async () => {
    const res = await getPatientAnalyticsCore({
      db, uid: PATIENT, auth: plainAuth, data: {},
    });
    expect(res.series).toEqual([]);
    expect(res.counts).toMatchObject({
      total: 0, open: 0, completed: 0, cancelled: 0,
    });
  });

  test('التقييم من مُجمَّع الطبيب لا من حساب محلي', async () => {
    const res = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: {},
    });
    expect(res.quality.averageRating).toBe(4.5);
    expect(res.quality.reviewCount).toBe(20);
  });
});

// ===================== حدود المدى =====================

describe('حدود المدى', () => {
  test('ما قبل المدى لا يُحتسب', async () => {
    await seedAppointment({ dayOffset: -3, status: 'Completed' });
    await seedAppointment({ dayOffset: -20, status: 'Completed' });

    const week = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: { range: '7d' },
    });
    expect(week.counts.total).toBe(1);

    const month = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: { range: '30d' },
    });
    expect(month.counts.total).toBe(2);
  });

  test('حدّا المدى شاملان (اليوم وأول يوم فيه)', async () => {
    await seedAppointment({ dayOffset: 0 });
    await seedAppointment({ dayOffset: -6 });
    const res = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: { range: '7d' },
    });
    expect(res.counts.total).toBe(2);
  });

  test('مدى غير مدعوم يُرفض بدل أن يُفسَّر', async () => {
    for (const bad of ['10y', 'all', '', 0, { from: '2000-01-01' }]) {
      await expect(getDoctorAnalyticsCore({
        db, uid: DOCTOR, auth: plainAuth, data: { range: bad },
      })).rejects.toThrow();
    }
  });

  test('غياب المدى يسقط إلى الافتراضي لا إلى مسح مفتوح', async () => {
    const res = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: {},
    });
    expect(res.range.key).toBe('30d');
    expect(RANGES[res.range.key]).toBeDefined();
  });

  test('كل مدى مدعوم له دقّة تجميع معلنة', () => {
    for (const [key, cfg] of Object.entries(RANGES)) {
      expect(['day', 'week', 'month']).toContain(cfg.bucket);
      expect(cfg.days).toBeGreaterThan(0);
      expect(cfg.days).toBeLessThanOrEqual(365);
      void key;
    }
  });
});

// ===================== التجميع =====================

describe('دقّة التجميع', () => {
  test('اليومي يحتفظ بالتاريخ كاملاً', () => {
    expect(bucketKey('2030-03-05', 'day')).toBe('2030-03-05');
  });

  test('الشهري يجمع على الشهر', () => {
    expect(bucketKey('2030-03-05', 'month')).toBe('2030-03');
    expect(bucketKey('2030-03-28', 'month')).toBe('2030-03');
  });

  test('الأسبوعي ينسب اليوم إلى الأحد الذي يسبقه', () => {
    // 2030-03-05 ثلاثاء؛ الأحد قبله 2030-03-03.
    expect(bucketKey('2030-03-05', 'week')).toBe('2030-03-03');
    expect(bucketKey('2030-03-03', 'week')).toBe('2030-03-03');
  });

  test('السلسلة مرتَّبة زمنياً ومجمَّعة بالدقّة الصحيحة', async () => {
    await seedAppointment({ dayOffset: -2 });
    await seedAppointment({ dayOffset: -2 });
    await seedAppointment({ dayOffset: 0 });

    const res = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: { range: '7d' },
    });
    expect(res.series).toHaveLength(2);
    expect(res.series[0].bucket < res.series[1].bucket).toBe(true);
    expect(res.series[0].booked).toBe(2);
    expect(res.series[1].booked).toBe(1);
  });

  test('لا مستند خام يعبر الشبكة — أرقام فقط', async () => {
    await seedAppointment({ status: 'Booked' });
    const res = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: {},
    });
    const asText = JSON.stringify(res);
    expect(asText).not.toContain(PATIENT);
    expect(asText).not.toContain('09:00');
    expect(asText).not.toContain('price');
  });
});

// ===================== المنصّة =====================

describe('تحليلات المنصّة', () => {
  test('الأعداد من تجميع خادمي لا من مسح', async () => {
    const res = await getAdminAnalyticsCore({
      db, uid: 'someAdmin', auth: adminAuth, data: {},
    });
    expect(res.platform).toMatchObject({
      patients: 2, doctors: 2, verifiedDoctors: 2, suspendedDoctors: 1,
    });
  });

  test('التخصصات مرتَّبة تنازلياً ومحدودة العدد', async () => {
    for (let i = 0; i < 3; i++) await seedAppointment({ specialization: 'أسنان' });
    await seedAppointment({ specialization: 'جلدية' });

    const res = await getAdminAnalyticsCore({
      db, uid: 'someAdmin', auth: adminAuth, data: {},
    });
    expect(res.specialties[0]).toEqual({ name: 'أسنان', count: 3 });
    expect(res.specialties.length).toBeLessThanOrEqual(TOP_N);
  });

  test('رد المنصّة تجميعي بلا أي معرّف أو اسم شخص', async () => {
    await seedAppointment();
    const res = await getAdminAnalyticsCore({
      db, uid: 'someAdmin', auth: adminAuth, data: {},
    });
    const asText = JSON.stringify(res);
    expect(asText).not.toContain(PATIENT);
    expect(asText).not.toContain(DOCTOR);
    expect(asText).not.toContain('مريض');
  });

  test('المنصّة ترى مواعيد كل الأطباء لا طبيباً واحداً', async () => {
    await seedAppointment({ doctorId: DOCTOR });
    await seedAppointment({ doctorId: OTHER_DOCTOR });
    const res = await getAdminAnalyticsCore({
      db, uid: 'someAdmin', auth: adminAuth, data: {},
    });
    expect(res.counts.total).toBe(2);
  });
});

// ===================== الأداء =====================

describe('حدود القراءة', () => {
  test('السقف معلن ومعقول', () => {
    expect(Number.isInteger(MAX_SCAN)).toBe(true);
    expect(MAX_SCAN).toBeGreaterThan(0);
    expect(MAX_SCAN).toBeLessThanOrEqual(10000);
  });

  test('الرد يعلن البتر بدل إخفائه', async () => {
    // لا نبذر 3000 مستنداً؛ نتحقّق أن العلم موجود وصريح في الرد.
    const res = await getDoctorAnalyticsCore({
      db, uid: DOCTOR, auth: plainAuth, data: {},
    });
    expect(res).toHaveProperty('truncated');
    expect(typeof res.truncated).toBe('boolean');
    expect(res.truncated).toBe(false);
  });

  test('الرد يحمل وقت توليده ومنطقته الزمنية', async () => {
    // رقم بلا وقت توليد يُقرأ كأنه لحظي.
    const res = await getPatientAnalyticsCore({
      db, uid: PATIENT, auth: plainAuth, data: {},
    });
    expect(res.timezone).toBe('Africa/Cairo');
    expect(new Date(res.generatedAt).toString()).not.toBe('Invalid Date');
  });
});
