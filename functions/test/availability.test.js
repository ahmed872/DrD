/**
 * اختبارات محرّك التوفّر: منطق الجدول الخالص (بلا I/O)، واستعلام
 * `getAvailability` على المحاكي الحقيقي.
 *
 *   firebase emulators:exec --only firestore --project drd-functions-test \
 *     "npm --prefix functions test"
 */

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const admin = require('firebase-admin');
const {
  generateSlotTimes,
  isWorkingDay,
  isClosedDate,
  normalizedWorkingDays,
  getAvailabilityCore,
  slotIdFor,
} = require('../availability');
const { bookAppointmentCore } = require('../booking');

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'drd-functions-test' });
}
const db = admin.firestore();

const DOCTOR = 'doctorOne';
const PATIENT = 'patientOne';

const NOW = new Date('2030-03-01T06:00:00Z'); // جمعة 08:00 بتوقيت القاهرة.
const FUTURE_DATE = '2030-03-03'; // أحد.

const doctorDoc = (extra = {}) => ({
  role: 'doctor',
  isVerified: true,
  name: 'د. أحمد',
  nameEn: 'Dr. Ahmed',
  specialization: 'أسنان',
  phone: '201000000001',
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

beforeEach(async () => {
  await clearFirestore();
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app && app.delete()));
});

// ===================== منطق الجدول الخالص =====================

describe('generateSlotTimes — فترات عمل متعددة واستراحات', () => {
  test('استراحة واحدة تقسم يوماً متصلاً إلى فترتين', () => {
    const doctor = doctorDoc({
      workingHours: '09:00 AM - 10:00 PM',
      breaks: [{ start: '13:00', end: '17:00' }],
    });
    const slots = generateSlotTimes(doctor, '2030-03-03');
    expect(slots).toContain('09:00');
    expect(slots).toContain('12:30');
    expect(slots).not.toContain('13:00');
    expect(slots).not.toContain('16:30');
    expect(slots).toContain('17:00');
    expect(slots).toContain('21:30');
  });

  test('أكثر من استراحة في اليوم نفسه', () => {
    const doctor = doctorDoc({
      workingHours: '09:00 AM - 10:00 PM',
      breaks: [
        { start: '11:00', end: '12:00' },
        { start: '15:00', end: '16:00' },
      ],
    });
    const slots = generateSlotTimes(doctor, '2030-03-03');
    expect(slots).toContain('10:30');
    expect(slots).not.toContain('11:00');
    expect(slots).not.toContain('11:30');
    expect(slots).toContain('12:00');
    expect(slots).not.toContain('15:00');
    expect(slots).toContain('16:00');
  });

  test('فترات عمل متعددة صريحة (workingPeriods) بلا الاعتماد على workingHours', () => {
    const doctor = doctorDoc({
      workingPeriods: [
        { start: '09:00', end: '13:00' },
        { start: '17:00', end: '22:00' },
      ],
    });
    const slots = generateSlotTimes(doctor, '2030-03-03');
    expect(slots).toContain('09:00');
    expect(slots).toContain('12:30');
    expect(slots).not.toContain('13:00');
    expect(slots).not.toContain('16:30');
    expect(slots).toContain('17:00');
    expect(slots).toContain('21:30');
  });

  test('دوام يمتد بعد منتصف الليل مع استراحة داخله', () => {
    const doctor = doctorDoc({
      workingHours: '10:00 PM - 02:00 AM',
      breaks: [{ start: '00:00', end: '01:00' }],
    });
    const slots = generateSlotTimes(doctor, '2030-03-03');
    expect(slots).toContain('22:00');
    expect(slots).toContain('23:30');
    expect(slots).not.toContain('00:00');
    expect(slots).not.toContain('00:30');
    expect(slots).toContain('01:00');
    expect(slots).toContain('01:30');
  });

  test('بلا استراحات ولا فترات جديدة: نفس سلوك ما قبل المرحلة 1ب حرفياً', () => {
    const doctor = doctorDoc();
    const withDate = generateSlotTimes(doctor, '2030-03-03');
    const withoutDate = generateSlotTimes(doctor);
    expect(withDate).toEqual(withoutDate);
    expect(withDate[0]).toBe('09:00');
  });
});

describe('generateSlotTimes / isWorkingDay — تجاوزات التاريخ', () => {
  test('تجاوز ساعات يوم واحد لا يمسّ باقي الأيام', () => {
    const doctor = doctorDoc({
      dateOverrides: {
        '2030-03-03': { workingHours: '10:00 AM - 12:00 PM' },
      },
    });
    expect(generateSlotTimes(doctor, '2030-03-03')).toEqual(['10:00', '10:30', '11:00', '11:30']);
    expect(generateSlotTimes(doctor, '2030-03-04')).toContain('09:00'); // يوم آخر لم يتأثر.
  });

  test('إغلاق طارئ ليوم واحد عبر dateOverrides.closed', () => {
    const doctor = doctorDoc({ dateOverrides: { '2030-03-03': { closed: true } } });
    expect(isWorkingDay(doctor, '2030-03-03')).toBe(false);
    expect(isClosedDate(doctor, '2030-03-03')).toBe(true);
    expect(isWorkingDay(doctor, '2030-03-04')).toBe(true);
  });

  test('عطلة رسمية عبر closedDates', () => {
    const doctor = doctorDoc({ closedDates: ['2030-03-03'] });
    expect(isWorkingDay(doctor, '2030-03-03')).toBe(false);
  });

  test('إجازة عبر مدى vacations شامل الطرفين', () => {
    const doctor = doctorDoc({ vacations: [{ start: '2030-03-05', end: '2030-03-10' }] });
    expect(isWorkingDay(doctor, '2030-03-04')).toBe(true);
    expect(isWorkingDay(doctor, '2030-03-05')).toBe(false);
    expect(isWorkingDay(doctor, '2030-03-08')).toBe(false);
    expect(isWorkingDay(doctor, '2030-03-10')).toBe(false);
    expect(isWorkingDay(doctor, '2030-03-11')).toBe(true);
  });

  test('workingDaysByWeekday الكانونية تُفضَّل على workingDays العربية إن وُجدت معاً', () => {
    const doctor = doctorDoc({
      // الجمعة (2030-03-01) عطلة بالصيغة العربية القديمة...
      workingDays: { 'الجمعة (Friday)': false },
      // ...لكن الصيغة الكانونية الجديدة تقول إنه يوم عمل — وهي الأولى.
      workingDaysByWeekday: { fri: true },
    });
    expect(isWorkingDay(doctor, '2030-03-01')).toBe(true);
  });

  test('normalizedWorkingDays يبني تمثيلاً كانونياً من الصيغة العربية القديمة', () => {
    const doctor = doctorDoc({
      workingDays: {
        'السبت (Saturday)': true,
        'الأحد (Sunday)': false,
        'الجمعة (Friday)': false,
      },
    });
    const norm = normalizedWorkingDays(doctor);
    expect(norm.sat).toBe(true);
    expect(norm.sun).toBe(false);
    expect(norm.fri).toBe(false);
    expect(norm.mon).toBe(true); // بلا مفتاح مطابق ← يوم عمل، كالواجهة تماماً.
  });
});

// ===================== getAvailability على المحاكي =====================

describe('getAvailability — المصادقة والمدخلات', () => {
  beforeEach(async () => {
    await db.collection('users').doc(DOCTOR).set(doctorDoc());
  });

  test('طلب بلا هوية مرفوض', async () => {
    await expect(getAvailabilityCore({
      db, uid: null, data: { doctorId: DOCTOR, dateFrom: FUTURE_DATE }, now: NOW,
    })).rejects.toMatchObject({ reason: 'unauthenticated' });
  });

  test('مدى أطول من الحد الأقصى مرفوض', async () => {
    await expect(getAvailabilityCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, dateFrom: '2030-03-01', dateTo: '2030-06-01' },
      now: NOW,
    })).rejects.toMatchObject({ reason: 'invalid-argument' });
  });

  test('طبيب غير موثَّق مرفوض', async () => {
    await db.collection('users').doc('unverified').set(doctorDoc({ isVerified: false }));
    await expect(getAvailabilityCore({
      db, uid: PATIENT, data: { doctorId: 'unverified', dateFrom: FUTURE_DATE }, now: NOW,
    })).rejects.toMatchObject({ reason: 'doctor-not-verified' });
  });

  test('dateTo تسقط افتراضياً إلى dateFrom (يوم واحد)', async () => {
    const res = await getAvailabilityCore({
      db, uid: PATIENT, data: { doctorId: DOCTOR, dateFrom: FUTURE_DATE }, now: NOW,
    });
    expect(res.slots.every((s) => s.date === FUTURE_DATE)).toBe(true);
  });
});

describe('getAvailability — نفس قواعد الحجز بالضبط', () => {
  beforeEach(async () => {
    await db.collection('users').doc(DOCTOR).set(doctorDoc());
    await db.collection('users').doc(PATIENT).set({
      role: 'patient', name: 'مريض', phone: '201000000002',
    });
  });

  test('يوم عمل عادي: كل الخانات متاحة بسعة كاملة', async () => {
    const res = await getAvailabilityCore({
      db, uid: PATIENT, data: { doctorId: DOCTOR, dateFrom: FUTURE_DATE }, now: NOW,
    });
    const nineAm = res.slots.find((s) => s.startTime === '09:00');
    expect(nineAm).toBeTruthy();
    expect(nineAm.status).toBe('available');
    expect(nineAm.remainingCapacity).toBe(1);
    expect(nineAm.capacity).toBe(1);
  });

  test('يوم عطلة الطبيب: لا خانات إطلاقاً', async () => {
    await db.collection('users').doc(DOCTOR).update({
      workingDays: { 'الأحد (Sunday)': false },
    });
    const res = await getAvailabilityCore({
      db, uid: PATIENT, data: { doctorId: DOCTOR, dateFrom: FUTURE_DATE }, now: NOW,
    });
    expect(res.slots.length).toBe(0);
  });

  test('خانة محجوزة فعلياً تظهر ممتلئة، ونفس الوقت متاح في الحجز يطابق ذلك', async () => {
    await bookAppointmentCore({
      db, uid: PATIENT, data: { doctorId: DOCTOR, date: FUTURE_DATE, time: '09:00' }, now: NOW,
    });
    const res = await getAvailabilityCore({
      db, uid: PATIENT, data: { doctorId: DOCTOR, dateFrom: FUTURE_DATE }, now: NOW,
    });
    const nineAm = res.slots.find((s) => s.startTime === '09:00');
    expect(nineAm.status).toBe('full');
    expect(nineAm.remainingCapacity).toBe(0);
    expect(nineAm.bookedCount).toBe(1);

    const other = res.slots.find((s) => s.startTime === '09:30');
    expect(other.status).toBe('available');
  });

  test('خانة مجموعة جزئياً: السعة المتبقية صحيحة', async () => {
    await db.collection('users').doc(DOCTOR).update({
      bookingSystemType: 'Grouped', maxPatientsPerSlot: 4,
    });
    await bookAppointmentCore({
      db, uid: PATIENT, data: { doctorId: DOCTOR, date: FUTURE_DATE, time: '09:00' }, now: NOW,
    });
    const res = await getAvailabilityCore({
      db, uid: PATIENT, data: { doctorId: DOCTOR, dateFrom: FUTURE_DATE }, now: NOW,
    });
    const nineAm = res.slots.find((s) => s.startTime === '09:00');
    expect(nineAm.capacity).toBe(4);
    expect(nineAm.bookedCount).toBe(1);
    expect(nineAm.remainingCapacity).toBe(3);
    expect(nineAm.status).toBe('available');
  });

  test('خانة مغلقة يدوياً على مستند القفل تظهر closed', async () => {
    const sid = slotIdFor(DOCTOR, FUTURE_DATE, '10:00');
    await db.collection('slots').doc(sid).set({
      doctorId: DOCTOR, appointmentDate: FUTURE_DATE, startTime: '10:00',
      capacity: 1, bookedCount: 0, patientIds: [], closed: true,
    });
    const res = await getAvailabilityCore({
      db, uid: PATIENT, data: { doctorId: DOCTOR, dateFrom: FUTURE_DATE }, now: NOW,
    });
    const tenAm = res.slots.find((s) => s.startTime === '10:00');
    expect(tenAm.status).toBe('closed');
  });

  test('موعد قديم بلا مستند خانة (توافق قديم) يُحتسَب في العدّاد', async () => {
    await db.collection('appointments').doc('legacy_appt').set({
      doctorId: DOCTOR, patientId: PATIENT, appointmentDate: FUTURE_DATE,
      startTime: '11:00', status: 'Booked',
    });
    const res = await getAvailabilityCore({
      db, uid: PATIENT, data: { doctorId: DOCTOR, dateFrom: FUTURE_DATE }, now: NOW,
    });
    const elevenAm = res.slots.find((s) => s.startTime === '11:00');
    expect(elevenAm.bookedCount).toBe(1);
    expect(elevenAm.status).toBe('full');
  });

  test('خانة اليوم قبل الوقت الحالي حالتها past، وما بعده available', async () => {
    // "الآن" 10:30 بتوقيت القاهرة (08:30Z) يوم 2030-03-01 — بعد بداية الدوام.
    const midMorning = new Date('2030-03-01T08:30:00Z');
    const res = await getAvailabilityCore({
      db, uid: PATIENT, data: { doctorId: DOCTOR, dateFrom: '2030-03-01' }, now: midMorning,
    });

    const passed = res.slots.filter((s) => s.startTime <= '10:30');
    expect(passed.length).toBeGreaterThan(0);
    expect(passed.every((s) => s.status === 'past')).toBe(true);

    const upcoming = res.slots.find((s) => s.startTime === '11:00');
    expect(upcoming.status).toBe('available');
  });

  test('خانة منتهية الصلاحية (يوم مضى بالكامل) لا تظهر في المدى', async () => {
    const res = await getAvailabilityCore({
      db, uid: PATIENT,
      data: { doctorId: DOCTOR, dateFrom: '2030-02-01', dateTo: '2030-03-03' },
      now: NOW,
    });
    expect(res.slots.every((s) => s.date >= '2030-03-01')).toBe(true);
  });

  test('حدود منتصف الليل: دوام يمتد لليوم التالي يظهر بشكل صحيح', async () => {
    await db.collection('users').doc(DOCTOR).update({ workingHours: '10:00 PM - 02:00 AM' });
    const res = await getAvailabilityCore({
      db, uid: PATIENT, data: { doctorId: DOCTOR, dateFrom: FUTURE_DATE }, now: NOW,
    });
    const late = res.slots.find((s) => s.startTime === '23:30');
    expect(late).toBeTruthy();
    expect(late.endTime).toBe('00:00'); // نهاية الخانة تعبر منتصف الليل بصيغة الساعة نفسها.
  });

  test('مدة الخانة تنعكس على startTime/endTime بدقة', async () => {
    await db.collection('users').doc(DOCTOR).update({ sessionDuration: 45 });
    const res = await getAvailabilityCore({
      db, uid: PATIENT, data: { doctorId: DOCTOR, dateFrom: FUTURE_DATE }, now: NOW,
    });
    const first = res.slots.find((s) => s.startTime === '09:00');
    expect(first.endTime).toBe('09:45');
  });
});
