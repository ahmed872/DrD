/**
 * اختبارات محرّك الحجز على الخادم.
 *
 * تعمل على **محاكي Firestore الحقيقي** لا على تهيئة وهمية: المعاملات
 * والتزامن وإعادة المحاولة سلوك قاعدة بيانات، ولا يُثبته إلا تشغيلها فعلاً.
 *
 *   firebase emulators:exec --only firestore --project drd-functions-test \
 *     "npm --prefix functions test"
 */

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const admin = require('firebase-admin');
const {
  bookAppointmentCore,
  generateSlotTimes,
  isWorkingDay,
  normalizeReason,
  slotIdFor,
  appointmentIdFor,
} = require('../booking');

admin.initializeApp({ projectId: 'drd-functions-test' });
const db = admin.firestore();

const DOCTOR = 'doctorOne';
const GROUP_DOCTOR = 'doctorGrouped';
const PATIENT = 'patientOne';
const OTHER = 'patientTwo';

/**
 * الزمن مثبَّت في كل الاختبارات.
 *
 * بدونه تصبح النتيجة دالة في يوم التشغيل: تاريخ داخل أفق الحجز اليوم يخرج
 * منه بعد ثلاثة أشهر، واختبار «وقت مضى» ينقلب مع الساعة. التثبيت يجعل الفشل
 * دليلاً على انحدار حقيقي لا على مرور الوقت.
 *
 * NOW جمعة، وFUTURE_DATE الأحد الذي يليه.
 */
const NOW = new Date('2030-03-01T06:00:00Z');
const FUTURE_DATE = '2030-03-03';
const SLOT_TIME = '09:00';

const doctorDoc = (extra = {}) => ({
  role: 'doctor',
  isVerified: true,
  name: 'د. أحمد',
  nameEn: 'Dr. Ahmed',
  specialization: 'أسنان',
  phone: '201000000001',
  clinicLocation: 'المنصورة',
  price: 200,
  sessionDuration: 30,
  bookingSystemType: 'Individual',
  workingHours: '09:00 AM - 05:00 PM',
  ...extra,
});

async function clearFirestore() {
  for (const name of ['users', 'slots', 'appointments']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seed(extra = {}) {
  await db.collection('users').doc(DOCTOR).set(doctorDoc(extra.doctor));
  await db.collection('users').doc(GROUP_DOCTOR).set(doctorDoc({
    name: 'د. مجمّع',
    bookingSystemType: 'Grouped',
    maxPatientsPerSlot: 2,
    price: 150,
    ...extra.groupDoctor,
  }));
  await db.collection('users').doc(PATIENT).set({
    role: 'patient', name: 'مريض', phone: '201000000002',
    email: 'p@example.com',
  });
  await db.collection('users').doc(OTHER).set({
    role: 'patient', name: 'مريض ٢', phone: '201000000003',
  });
}

const book = (uid, data, now = NOW) =>
  bookAppointmentCore({ db, uid, data, now });

const request = (extra = {}) => ({
  doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME, ...extra,
});

/** يلتقط سبب الفشل بدل رمي الخطأ. */
async function reasonOf(promise) {
  try {
    await promise;
    return null;
  } catch (e) {
    return e.reason || e.code || e.message;
  }
}

beforeEach(async () => {
  await clearFirestore();
  await seed();
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app && app.delete()));
});

// ===================== دوال مساعدة خالصة =====================

describe('توليد الخانات — مطابقة الواجهة', () => {
  test('يحترم ساعات العمل ومدة الكشف', () => {
    const slots = generateSlotTimes(doctorDoc());
    expect(slots[0]).toBe('09:00');
    expect(slots[1]).toBe('09:30');
    expect(slots).toContain('16:30');
    expect(slots).not.toContain('17:00'); // النهاية غير مشمولة
    expect(slots).not.toContain('03:00');
  });

  test('نظام المجموعات خاناته ساعة كاملة', () => {
    const slots = generateSlotTimes(doctorDoc({
      bookingSystemType: 'Grouped', maxPatientsPerSlot: 4,
    }));
    expect(slots).toContain('09:00');
    expect(slots).toContain('10:00');
    expect(slots).not.toContain('09:30');
  });

  test('يسقط للخانات الافتراضية عند ساعات عمل غير مفهومة', () => {
    const slots = generateSlotTimes(doctorDoc({ workingHours: 'من الصبح للعصر' }));
    expect(slots).toContain('09:00');
    expect(slots).toContain('16:30');
  });

  test('مطابقة أيام العمل بنفس مفاتيح شاشة الإعدادات', () => {
    const workingDays = {
      'السبت (Saturday)': true,
      'الأحد (Sunday)': false,
      'الجمعة (Friday)': false,
    };
    // 2030-03-03 أحد، 2030-03-02 سبت، 2030-03-01 جمعة.
    expect(isWorkingDay({ workingDays }, '2030-03-02')).toBe(true);
    expect(isWorkingDay({ workingDays }, '2030-03-03')).toBe(false);
    expect(isWorkingDay({ workingDays }, '2030-03-01')).toBe(false);
    // يوم بلا مفتاح مطابق يُعامل كيوم عمل — تماماً كما تفعل الواجهة.
    expect(isWorkingDay({ workingDays }, '2030-03-04')).toBe(true);
  });

  test('سبب الزيارة يُقصّ ويُحدّ طوله', () => {
    expect(normalizeReason('  ألم   في الأسنان  ')).toBe('ألم في الأسنان');
    expect(normalizeReason(undefined)).toBe('');
    expect(() => normalizeReason('x'.repeat(501))).toThrow();
    expect(() => normalizeReason({ evil: true })).toThrow();
  });
});

// ===================== المصادقة =====================

describe('المصادقة', () => {
  test('طلب بلا هوية مرفوض', async () => {
    expect(await reasonOf(book(null, request()))).toBe('unauthenticated');
    expect(await reasonOf(book('', request()))).toBe('unauthenticated');
  });

  test('مريض مسجَّل يحجز بنجاح', async () => {
    const res = await book(PATIENT, request());
    expect(res.appointmentId)
      .toBe(appointmentIdFor(slotIdFor(DOCTOR, FUTURE_DATE, SLOT_TIME), PATIENT));
    expect(res.duplicate).toBe(false);
  });

  test('لا يمكن الحجز نيابة عن مريض آخر', async () => {
    // حتى لو أرسل العميل patientId صريحاً، صاحب الحجز هو صاحب رمز المصادقة.
    expect(await reasonOf(book(PATIENT, request({ patientId: OTHER }))))
      .toBe('permission-denied');
  });

  test('patientId المطابق للهوية مقبول (توافق مع العميل القديم)', async () => {
    const res = await book(PATIENT, request({ patientId: PATIENT }));
    expect(res.duplicate).toBe(false);
  });

  test('ملف مريض ناقص يمنع الحجز', async () => {
    await db.collection('users').doc(PATIENT).delete();
    expect(await reasonOf(book(PATIENT, request()))).toBe('patient-not-found');
  });
});

// ===================== الطبيب =====================

describe('الطبيب', () => {
  test('طبيب غير موجود', async () => {
    expect(await reasonOf(book(PATIENT, request({ doctorId: 'ghostDoctor' }))))
      .toBe('doctor-not-found');
  });

  test('حساب مريض لا يصلح طبيباً', async () => {
    expect(await reasonOf(book(PATIENT, request({ doctorId: OTHER }))))
      .toBe('doctor-not-found');
  });

  test('طبيب غير موثَّق', async () => {
    await db.collection('users').doc(DOCTOR).update({ isVerified: false });
    expect(await reasonOf(book(PATIENT, request())))
      .toBe('doctor-not-verified');
  });

  test('طبيب بلا حقل توثيق إطلاقاً', async () => {
    await db.collection('users').doc(DOCTOR).set(
      { ...doctorDoc(), isVerified: admin.firestore.FieldValue.delete() },
      { merge: true }
    );
    expect(await reasonOf(book(PATIENT, request())))
      .toBe('doctor-not-verified');
  });

  test('طبيب موقوف', async () => {
    await db.collection('users').doc(DOCTOR).update({ disabled: true });
    expect(await reasonOf(book(PATIENT, request())))
      .toBe('doctor-disabled');
  });

  test('التوثيق يؤخذ من الخادم لا من الطلب', async () => {
    await db.collection('users').doc(DOCTOR).update({ isVerified: false });
    expect(await reasonOf(book(PATIENT, request({ isVerified: true }))))
      .toBe('doctor-not-verified');
  });
});

// ===================== الجدول والخانة =====================

describe('الجدول والخانة', () => {
  test('وقت خارج جدول الطبيب مرفوض', async () => {
    // الحماية التي لم تكن موجودة: لا شيء كان يمنع حجز الثالثة فجراً.
    expect(await reasonOf(book(PATIENT, request({ time: '03:00' }))))
      .toBe('slot-not-found');
  });

  test('وقت لا يقع على بداية خانة مرفوض', async () => {
    expect(await reasonOf(book(PATIENT, request({ time: '09:17' }))))
      .toBe('slot-not-found');
  });

  test('تاريخ مضى مرفوض', async () => {
    expect(await reasonOf(book(PATIENT, request({ date: '2020-01-06' }))))
      .toBe('slot-expired');
  });

  test('اليوم نفسه قبل الوقت الحالي مرفوض', async () => {
    const now = new Date('2030-03-03T12:00:00Z'); // 14:00 بتوقيت القاهرة
    const early = bookAppointmentCore({
      db, uid: PATIENT, data: request({ time: '09:00' }), now,
    });
    expect(await reasonOf(early)).toBe('slot-expired');

    const later = await bookAppointmentCore({
      db, uid: PATIENT, data: request({ time: '16:00' }), now,
    });
    expect(later.duplicate).toBe(false);
  });

  test('أبعد من أفق الحجز مرفوض', async () => {
    expect(await reasonOf(book(PATIENT, request({ date: '2031-06-01' }))))
      .toBe('slot-out-of-range');
  });

  test('يوم عطلة الطبيب مرفوض', async () => {
    await db.collection('users').doc(DOCTOR).update({
      workingDays: { 'الأحد (Sunday)': false },
    });
    expect(await reasonOf(book(PATIENT, request())))
      .toBe('doctor-not-working');
  });

  test('تاريخ أو وقت بصيغة غير صالحة مرفوض', async () => {
    expect(await reasonOf(book(PATIENT, request({ date: '03/03/2030' }))))
      .toBe('invalid-argument');
    expect(await reasonOf(book(PATIENT, request({ date: '2030-02-31' }))))
      .toBe('invalid-argument');
    expect(await reasonOf(book(PATIENT, request({ time: '9:00' }))))
      .toBe('invalid-argument');
    expect(await reasonOf(book(PATIENT, request({ time: '25:00' }))))
      .toBe('invalid-argument');
    expect(await reasonOf(book(PATIENT, request({ doctorId: 'a/b' }))))
      .toBe('invalid-argument');
  });

  test('خانة تخصّ طبيباً آخر لا تُستعمل', async () => {
    // قفل بمعرّف هذا الطبيب لكن بحقول طبيب آخر — حالة بيانات فاسدة.
    const sid = slotIdFor(DOCTOR, FUTURE_DATE, SLOT_TIME);
    await db.collection('slots').doc(sid).set({
      doctorId: GROUP_DOCTOR, appointmentDate: FUTURE_DATE,
      startTime: SLOT_TIME, capacity: 1, bookedCount: 0, patientIds: [],
    });
    expect(await reasonOf(book(PATIENT, request()))).toBe('slot-conflict');
  });

  test('خانة مغلقة مرفوضة', async () => {
    const sid = slotIdFor(DOCTOR, FUTURE_DATE, SLOT_TIME);
    await db.collection('slots').doc(sid).set({
      doctorId: DOCTOR, appointmentDate: FUTURE_DATE, startTime: SLOT_TIME,
      capacity: 1, bookedCount: 0, patientIds: [], closed: true,
    });
    expect(await reasonOf(book(PATIENT, request()))).toBe('slot-closed');
  });

  test('خانة ممتلئة مرفوضة', async () => {
    await book(PATIENT, request());
    expect(await reasonOf(book(OTHER, request()))).toBe('slot-unavailable');
  });

  test('نظام المجموعات يقبل حتى السعة ثم يرفض', async () => {
    const groupReq = { doctorId: GROUP_DOCTOR, date: FUTURE_DATE, time: '10:00' };
    await book(PATIENT, groupReq);
    await book(OTHER, groupReq);

    await db.collection('users').doc('patientThree').set({
      role: 'patient', name: 'ثالث',
    });
    expect(await reasonOf(book('patientThree', groupReq)))
      .toBe('slot-unavailable');

    const sid = slotIdFor(GROUP_DOCTOR, FUTURE_DATE, '10:00');
    const slot = await db.collection('slots').doc(sid).get();
    expect(slot.data().bookedCount).toBe(2);
    expect(slot.data().capacity).toBe(2);
  });

  test('موعد آخر لنفس المريض في نفس اليوم مرفوض', async () => {
    await book(PATIENT, request());
    expect(await reasonOf(book(PATIENT, request({ time: '11:00' }))))
      .toBe('already-booked-same-day');
  });

  test('الإلغاء يتيح إعادة الحجز في نفس الخانة', async () => {
    const res = await book(PATIENT, request());
    const sid = slotIdFor(DOCTOR, FUTURE_DATE, SLOT_TIME);

    // إلغاء كما يفعله BookingService.cancel.
    await db.collection('appointments').doc(res.appointmentId)
      .update({ status: 'Cancelled' });
    await db.collection('slots').doc(sid)
      .update({ bookedCount: 0, patientIds: [] });

    const again = await book(PATIENT, request());
    expect(again.duplicate).toBe(false);
    const slot = await db.collection('slots').doc(sid).get();
    expect(slot.data().bookedCount).toBe(1);
  });
});

// ===================== التلاعب بالقيم =====================

describe('التلاعب — الخادم هو مصدر الحقيقة', () => {
  test('القيم المرسلة من العميل تُتجاهل بالكامل', async () => {
    const res = await book(PATIENT, request({
      // كل ما يلي كان يُكتب كما هو قبل هذه المرحلة.
      price: 1,
      capacity: 999,
      bookedCount: 0,
      status: 'Completed',
      endTime: '23:59',
      duration: 1,
      patientName: 'اسم مزيّف',
      patientPhone: '000',
      doctorName: 'طبيب مزيّف',
      doctorSpecialization: 'تخصص مزيّف',
      clinicLocation: 'عنوان مزيّف',
      slotId: 'evil_slot',
      appointmentDate: '2030-12-31',
      startTime: '23:00',
      createdAt: 'أمس',
      bookedVia: 'hack',
      reason: 'ألم',
    }));

    const appt = (await db.collection('appointments')
      .doc(res.appointmentId).get()).data();

    expect(appt.price).toBe(200);                 // من مستند الطبيب
    expect(appt.status).toBe('Booked');
    expect(appt.appointmentDate).toBe(FUTURE_DATE);
    expect(appt.startTime).toBe(SLOT_TIME);
    expect(appt.endTime).toBe('09:30');           // محسوب من مدة الكشف
    expect(appt.duration).toBe(30);
    expect(appt.slotId).toBe(slotIdFor(DOCTOR, FUTURE_DATE, SLOT_TIME));
    expect(appt.patientId).toBe(PATIENT);
    expect(appt.patientName).toBe('مريض');        // من مستند المريض
    expect(appt.patientPhone).toBe('201000000002');
    expect(appt.doctorName).toBe('د. أحمد');
    expect(appt.doctorSpecialization).toBe('أسنان');
    expect(appt.clinicLocation).toBe('المنصورة');
    expect(appt.bookedVia).toBe('callable');
    expect(appt.reason).toBe('ألم');              // المدخل الحر الوحيد
    expect(appt.createdAt.toDate()).toBeInstanceOf(Date);

    const slot = (await db.collection('slots').doc(appt.slotId).get()).data();
    expect(slot.capacity).toBe(1);                // لا 999
    expect(slot.bookedCount).toBe(1);
    expect(slot.patientIds).toEqual([PATIENT]);
  });

  test('السعر يتبع مستند الطبيب لا الطلب', async () => {
    await db.collection('users').doc(DOCTOR).update({ price: 350 });
    const res = await book(PATIENT, request({ price: 1 }));
    const appt = (await db.collection('appointments')
      .doc(res.appointmentId).get()).data();
    expect(appt.price).toBe(350);
    expect(res.price).toBe(350);
  });

  test('السعة تتبع إعدادات الطبيب لا الطلب', async () => {
    const res = await book(PATIENT, request({ capacity: 50 }));
    const slot = (await db.collection('slots')
      .doc(slotIdFor(DOCTOR, FUTURE_DATE, SLOT_TIME)).get()).data();
    expect(slot.capacity).toBe(1);
    expect(res.duplicate).toBe(false);
  });

  test('لا يمكن تضخيم عدّاد خانة قائمة', async () => {
    await book(PATIENT, request());
    const sid = slotIdFor(DOCTOR, FUTURE_DATE, SLOT_TIME);
    await reasonOf(book(OTHER, request({ bookedCount: 0, capacity: 99 })));
    const slot = (await db.collection('slots').doc(sid).get()).data();
    expect(slot.bookedCount).toBe(1);
    expect(slot.patientIds).toEqual([PATIENT]);
  });
});

// ===================== التزامن =====================

describe('التزامن', () => {
  // المعاملات المتنافسة تُعاد محاولتها، فتتجاوز أحياناً مهلة jest الافتراضية
  // (5 ثوانٍ) على أجهزة بطيئة. المهلة هنا سخيّة عمداً حتى يكون الفشل دليلاً
  // على خلل حقيقي لا على بطء.
  const CONCURRENCY_TIMEOUT = 60000;

  test('مريضان على آخر مكان: واحد ينجح والآخر يفشل بوضوح', async () => {
    const results = await Promise.allSettled([
      book(PATIENT, request()),
      book(OTHER, request()),
    ]);

    const ok = results.filter((r) => r.status === 'fulfilled');
    const failed = results.filter((r) => r.status === 'rejected');

    expect(ok).toHaveLength(1);
    expect(failed).toHaveLength(1);
    expect(failed[0].reason.reason).toBe('slot-unavailable');

    const sid = slotIdFor(DOCTOR, FUTURE_DATE, SLOT_TIME);
    const slot = (await db.collection('slots').doc(sid).get()).data();
    expect(slot.bookedCount).toBe(1);
    expect(slot.patientIds).toHaveLength(1);

    const appts = await db.collection('appointments')
      .where('slotId', '==', sid).get();
    expect(appts.size).toBe(1);
  }, CONCURRENCY_TIMEOUT);

  test('أربعة متزامنون على خانة مجموعة سعتها اثنان', async () => {
    for (const uid of ['c1', 'c2', 'c3', 'c4']) {
      await db.collection('users').doc(uid).set({ role: 'patient', name: uid });
    }
    const groupReq = { doctorId: GROUP_DOCTOR, date: FUTURE_DATE, time: '11:00' };

    const results = await Promise.allSettled(
      ['c1', 'c2', 'c3', 'c4'].map((uid) => book(uid, groupReq))
    );
    const ok = results.filter((r) => r.status === 'fulfilled');

    // **السلامة** مطلقة: لا تجاوز للسعة أبداً، والعدّاد ومستندات المواعيد
    // متطابقة مع من نجح فعلاً — لا حجز بلا مقعد ولا مقعد بلا حجز.
    //
    // أما **التقدّم** (أن يملأ أربعة متسابقين المقعدين في دفعة واحدة) فليس
    // مضموناً من Firestore: المعاملة المتنافسة قد تستنفد محاولاتها وتفشل رغم
    // وجود مكان، فيُعيد المريض المحاولة. تثبيت «اثنان بالضبط» هنا كان يجعل
    // الاختبار متذبذباً ويخفي فرقاً جوهرياً بين ضمان وسلوك.
    // امتلاء المقعدين بالكامل مُثبَت في اختبار متسلسل منفصل.
    expect(ok.length).toBeGreaterThanOrEqual(1);
    expect(ok.length).toBeLessThanOrEqual(2);

    for (const r of results.filter((x) => x.status === 'rejected')) {
      expect(['slot-unavailable', 'aborted', 'internal'])
        .toContain(r.reason.reason || r.reason.code);
    }

    const sid = slotIdFor(GROUP_DOCTOR, FUTURE_DATE, '11:00');
    const slot = (await db.collection('slots').doc(sid).get()).data();
    expect(slot.bookedCount).toBe(ok.length);
    expect(slot.bookedCount).toBeLessThanOrEqual(2);
    expect(new Set(slot.patientIds).size).toBe(ok.length);

    const appts = await db.collection('appointments')
      .where('slotId', '==', sid).get();
    expect(appts.size).toBe(ok.length);
  }, CONCURRENCY_TIMEOUT);
});

// ===================== تكرار الطلب =====================

describe('تكرار الطلب', () => {
  test('نفس الطلب مرتين لا ينتج حجزين', async () => {
    const first = await book(PATIENT, request());
    const second = await book(PATIENT, request());

    expect(second.appointmentId).toBe(first.appointmentId);
    expect(first.duplicate).toBe(false);
    expect(second.duplicate).toBe(true);

    const sid = slotIdFor(DOCTOR, FUTURE_DATE, SLOT_TIME);
    const slot = (await db.collection('slots').doc(sid).get()).data();
    expect(slot.bookedCount).toBe(1);

    const appts = await db.collection('appointments')
      .where('patientId', '==', PATIENT).get();
    expect(appts.size).toBe(1);
  });

  test('ضغطتان متزامنتان لا تنتجان حجزين', async () => {
    // نفس سبب المهلة السخيّة في اختبارات التزامن أعلاه.
    const results = await Promise.allSettled([
      book(PATIENT, request()),
      book(PATIENT, request()),
    ]);
    expect(results.filter((r) => r.status === 'fulfilled').length)
      .toBeGreaterThanOrEqual(1);

    const sid = slotIdFor(DOCTOR, FUTURE_DATE, SLOT_TIME);
    const slot = (await db.collection('slots').doc(sid).get()).data();
    expect(slot.bookedCount).toBe(1);
    expect(slot.patientIds).toEqual([PATIENT]);

    const appts = await db.collection('appointments')
      .where('slotId', '==', sid).get();
    expect(appts.size).toBe(1);
  }, 60000);
});

// ===================== المواعيد القديمة =====================

describe('التوافق مع المواعيد القائمة', () => {
  test('موعد قديم بلا slotId يبقى كما هو ويحجز مكانه', async () => {
    // مواعيد ما قبل نظام الأقفال: بحقل `time` وحالة `Scheduled` وبلا قفل.
    await db.collection('appointments').doc('legacy_1').set({
      doctorId: DOCTOR, patientId: OTHER,
      appointmentDate: FUTURE_DATE, time: SLOT_TIME, status: 'Scheduled',
    });

    expect(await reasonOf(book(PATIENT, request()))).toBe('slot-unavailable');

    const legacy = await db.collection('appointments').doc('legacy_1').get();
    expect(legacy.data().status).toBe('Scheduled');
    expect(legacy.data().time).toBe(SLOT_TIME);
    expect(legacy.data().slotId).toBeUndefined();
  });

  test('موعد قديم ملغى لا يشغل الخانة', async () => {
    await db.collection('appointments').doc('legacy_2').set({
      doctorId: DOCTOR, patientId: OTHER,
      appointmentDate: FUTURE_DATE, time: SLOT_TIME, status: 'Cancelled',
    });
    const res = await book(PATIENT, request());
    expect(res.duplicate).toBe(false);
  });

  test('موعد قديم لنفس المريض في نفس اليوم يمنع حجزاً ثانياً', async () => {
    await db.collection('appointments').doc('legacy_3').set({
      doctorId: DOCTOR, patientId: PATIENT,
      appointmentDate: FUTURE_DATE, time: '10:00', status: 'upcoming',
    });
    expect(await reasonOf(book(PATIENT, request())))
      .toBe('already-booked-same-day');
  });

  test('المستند المكتوب يحمل كل الحقول التي تقرأها الشاشات', async () => {
    const res = await book(PATIENT, request({ reason: 'كشف دوري' }));
    const appt = (await db.collection('appointments')
      .doc(res.appointmentId).get()).data();

    for (const field of [
      'doctorId', 'patientId', 'slotId', 'appointmentDate', 'startTime',
      'endTime', 'duration', 'status', 'price', 'reason',
      'patientName', 'patientPhone', 'doctorName', 'doctorNameEn',
      'doctorSpecialization', 'clinicLocation', 'clinicPhone', 'createdAt',
    ]) {
      expect(appt[field]).toBeDefined();
    }
  });
});
