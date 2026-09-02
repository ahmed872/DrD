/**
 * اختبارات دورة حياة الموعد على الخادم: الإلغاء وإعادة الجدولة.
 *
 * تعمل على **محاكي Firestore الحقيقي** كاختبارات الحجز تماماً — المعاملات
 * والتزامن سلوك قاعدة بيانات، ولا يُثبته إلا تشغيله فعلاً.
 *
 *   firebase emulators:exec --only firestore --project drd-functions-test \
 *     "npm --prefix functions test"
 */

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const admin = require('firebase-admin');
const { bookAppointmentCore } = require('../booking');
const {
  cancelAppointmentCore,
  rescheduleAppointmentCore,
  CANCEL_DEADLINE_MINUTES,
  RESCHEDULE_DEADLINE_MINUTES,
} = require('../lifecycle');
const { slotIdFor, appointmentIdFor } = require('../availability');

// نفس اسم مشروع اختبارات الحجز — نفس محاكي واحد، وnamespace منفصل داخله
// عبر `clearFirestore` في `beforeEach`.
if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'drd-functions-test' });
}
const db = admin.firestore();

const DOCTOR = 'doctorOne';
const GROUP_DOCTOR = 'doctorGrouped';
const PATIENT = 'patientOne';
const OTHER = 'patientTwo';
const THIRD = 'patientThree';

/**
 * الجمعة 2030-03-01 الساعة 08:00 بتوقيت القاهرة (06:00Z، مصر UTC+2 في مارس
 * — لا توقيت صيفي في هذا الشهر). نفس لحظة "الآن" في `booking.test.js`.
 */
const NOW = new Date('2030-03-01T06:00:00Z');
const SAME_DAY_DATE = '2030-03-01';
const SAME_DAY_SLOT = '09:00'; // بعد "الآن" بساعة بالضبط — حد المهلة.
const FUTURE_DATE = '2030-03-03'; // أحد، بعد يومين — بعيد عن أي مهلة.
const FUTURE_DATE_2 = '2030-03-10'; // أحد آخر — لإعادة الجدولة إليه.
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
  await db.collection('users').doc(THIRD).set({
    role: 'patient', name: 'مريض ٣', phone: '201000000004',
  });
}

beforeEach(async () => {
  await clearFirestore();
  await seed();
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app && app.delete()));
});

const book = (uid, data, now = NOW) => bookAppointmentCore({ db, uid, data, now });
const cancel = (uid, data, now = NOW) => cancelAppointmentCore({ db, uid, data, now });
const reschedule = (uid, data, now = NOW) => rescheduleAppointmentCore({ db, uid, data, now });

/** يلتقط سبب الفشل بدل رمي الخطأ. */
async function reasonOf(promise) {
  try {
    await promise;
    return null;
  } catch (e) {
    return e.reason || e.code || e.message;
  }
}

async function getAppointment(id) {
  const snap = await db.collection('appointments').doc(id).get();
  return snap.exists ? snap.data() : null;
}

async function getSlot(id) {
  const snap = await db.collection('slots').doc(id).get();
  return snap.exists ? snap.data() : null;
}

// ===================== الإلغاء =====================

describe('cancelAppointment — المصادقة والملكية', () => {
  test('طلب بلا هوية مرفوض', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    expect(await reasonOf(cancel(null, { appointmentId: appt.appointmentId })))
      .toBe('unauthenticated');
  });

  test('معرّف موعد غير صالح مرفوض', async () => {
    expect(await reasonOf(cancel(PATIENT, { appointmentId: '../etc/passwd' })))
      .toBe('invalid-argument');
    expect(await reasonOf(cancel(PATIENT, { appointmentId: '' })))
      .toBe('invalid-argument');
  });

  test('موعد غير موجود', async () => {
    expect(await reasonOf(cancel(PATIENT, { appointmentId: 'no_such_appointment' })))
      .toBe('appointment-not-found');
  });

  test('المريض يلغي موعده بنجاح', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    const res = await cancel(PATIENT, { appointmentId: appt.appointmentId });
    expect(res.status).toBe('Cancelled');
    expect(res.alreadyCancelled).toBe(false);

    const doc = await getAppointment(appt.appointmentId);
    expect(doc.status).toBe('Cancelled');
    expect(doc.cancelledBy).toBe(PATIENT);
    expect(doc.cancelledAt).toBeTruthy();

    const slot = await getSlot(appt.slotId);
    expect(slot.bookedCount).toBe(0);
    expect(slot.patientIds).not.toContain(PATIENT);
  });

  test('سبب الإلغاء يُحفَظ ويُقصّ', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    await cancel(PATIENT, { appointmentId: appt.appointmentId, reason: '  سفر مفاجئ  ' });
    const doc = await getAppointment(appt.appointmentId);
    expect(doc.cancelReason).toBe('سفر مفاجئ');
  });

  test('مريض آخر لا يستطيع إلغاء موعد ليس له', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    expect(await reasonOf(cancel(OTHER, { appointmentId: appt.appointmentId })))
      .toBe('permission-denied');

    // ولم يتأثر الموعد ولا الخانة.
    const doc = await getAppointment(appt.appointmentId);
    expect(doc.status).toBe('Booked');
  });

  test('طبيب آخر لا يلغي موعداً ليس عنده', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    expect(await reasonOf(cancel(GROUP_DOCTOR, { appointmentId: appt.appointmentId })))
      .toBe('permission-denied');

    const doc = await getAppointment(appt.appointmentId);
    expect(doc.status).toBe('Booked');
  });
});

// ===================== إلغاء الطبيب (المرحلة 10) =====================

describe('cancelAppointment — إلغاء الطبيب', () => {
  // كان الطبيب يلغي بكتابة مباشرة من العميل (`BookingService.cancelAsDoctor`):
  // معاملة تُنقص العدّاد وتحذف المريض من `patientIds` وتضع الحالة `Cancelled`.
  // المرحلة 10 نقلت ذلك إلى هنا، فصارت سلطة الإلغاء واحدة للطرفين.

  test('طبيب الموعد يلغيه ويُحرَّر مقعد المريض', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    const res = await cancel(DOCTOR, { appointmentId: appt.appointmentId });
    expect(res.status).toBe('Cancelled');

    const doc = await getAppointment(appt.appointmentId);
    expect(doc.status).toBe('Cancelled');
    expect(doc.cancelledBy).toBe(DOCTOR);
    expect(doc.cancelledByRole).toBe('doctor');

    // الجوهري: المقعد المُحرَّر هو مقعد **المريض** لا مقعد الطبيب.
    // تمرير معرّف الطبيب إلى `planSlotRelease` كان سيجعل التحرير لا يفعل
    // شيئاً، فيبقى العدّاد مرفوعاً على موعد ملغى وتُحجب الخانة عن غيره.
    const slot = await getSlot(appt.slotId);
    expect(slot.bookedCount).toBe(0);
    expect(slot.patientIds).not.toContain(PATIENT);
  });

  test('الخانة تعود قابلة للحجز بعد إلغاء الطبيب', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    await cancel(DOCTOR, { appointmentId: appt.appointmentId });

    const again = await book(OTHER, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    expect(again.status).toBe('Booked');
  });

  test('الطبيب لا تُفرض عليه مهلة المريض', async () => {
    // نفس الموعد الذي يرفض المريض إلغاءه لقرب وقته (`SAME_DAY_SLOT` بعد
    // ساعة بالضبط من `NOW`) — الطبيب يلغيه: طارئ أو إغلاق يوم. المسار
    // المباشر الذي حلّت هذه الدالة محلّه لم يكن يفحص وقتاً إطلاقاً.
    const appt = await book(
      PATIENT, { doctorId: DOCTOR, date: SAME_DAY_DATE, time: SAME_DAY_SLOT });
    const late = new Date('2030-03-01T06:30:00Z'); // نصف ساعة قبل الموعد.

    expect(await reasonOf(cancel(PATIENT, { appointmentId: appt.appointmentId }, late)))
      .toBe('cancellation-deadline-passed');

    const res = await cancel(DOCTOR, { appointmentId: appt.appointmentId }, late);
    expect(res.status).toBe('Cancelled');
  });

  test('إلغاء الطبيب المكرَّر لا يُنقص العدّاد مرتين', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    await cancel(DOCTOR, { appointmentId: appt.appointmentId });
    const second = await cancel(DOCTOR, { appointmentId: appt.appointmentId });
    expect(second.alreadyCancelled).toBe(true);

    const slot = await getSlot(appt.slotId);
    expect(slot.bookedCount).toBe(0);
  });

  test('الطبيب لا يلغي موعداً تم الكشف فيه', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    await db.collection('appointments').doc(appt.appointmentId)
      .update({ status: 'Completed' });
    expect(await reasonOf(cancel(DOCTOR, { appointmentId: appt.appointmentId })))
      .toBe('appointment-completed');
  });

  test('الطرفان يُبلَّغان حين يلغي الطبيب', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    await cancel(DOCTOR, { appointmentId: appt.appointmentId });

    const snap = await db.collection('notifications')
      .where('appointmentId', '==', appt.appointmentId).get();
    const recipients = snap.docs.map((d) => d.data().recipientId);
    // المريض تحديداً: هو الطرف الذي لم يُلغِ، ويحتاج الإبلاغ أكثر لا أقل.
    expect(recipients).toContain(PATIENT);
    expect(recipients).toContain(DOCTOR);
  });

  test('الطبيب لا يلغي في خانة مجموعة إلا مقعد المريض المعني', async () => {
    const first = await book(
      OTHER, { doctorId: GROUP_DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    const second = await book(
      THIRD, { doctorId: GROUP_DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    expect(first.slotId).toBe(second.slotId);

    await cancel(GROUP_DOCTOR, { appointmentId: first.appointmentId });

    const slot = await getSlot(first.slotId);
    expect(slot.bookedCount).toBe(1);
    expect(slot.patientIds).not.toContain(OTHER);
    expect(slot.patientIds).toContain(THIRD);

    // وموعد المريض الآخر لم يُمَسّ.
    const untouched = await getAppointment(second.appointmentId);
    expect(untouched.status).toBe('Booked');
  });
});

describe('cancelAppointment — الحالة والمهلة', () => {
  test('موعد ملغى بالفعل — نجاح هادئ لا خطأ (تكرار الطلب)', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    const first = await cancel(PATIENT, { appointmentId: appt.appointmentId });
    expect(first.alreadyCancelled).toBe(false);

    const second = await cancel(PATIENT, { appointmentId: appt.appointmentId });
    expect(second.alreadyCancelled).toBe(true);
    expect(second.status).toBe('Cancelled');

    // لم يُنقَص العدّاد مرتين.
    const slot = await getSlot(appt.slotId);
    expect(slot.bookedCount).toBe(0);
  });

  test('موعد مكتمل لا يُلغى', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    await db.collection('appointments').doc(appt.appointmentId).update({ status: 'Completed' });
    expect(await reasonOf(cancel(PATIENT, { appointmentId: appt.appointmentId })))
      .toBe('appointment-completed');
  });

  test('موعد فات وقته لا يُلغى', async () => {
    const appt = await book(PATIENT, {
      doctorId: DOCTOR, date: SAME_DAY_DATE, time: SAME_DAY_SLOT,
    });
    // "الآن" بعد بداية الموعد بنصف ساعة.
    const later = new Date('2030-03-01T07:30:00Z');
    expect(await reasonOf(cancel(PATIENT, { appointmentId: appt.appointmentId }, later)))
      .toBe('appointment-past');
  });

  test('الإلغاء أقرب من مهلة الإلغاء مرفوض', async () => {
    const appt = await book(PATIENT, {
      doctorId: DOCTOR, date: SAME_DAY_DATE, time: SAME_DAY_SLOT,
    });
    // "الآن" قبل الموعد بربع ساعة فقط — أقل من المهلة (ساعة).
    const soon = new Date('2030-03-01T06:45:00Z');
    expect(await reasonOf(cancel(PATIENT, { appointmentId: appt.appointmentId }, soon)))
      .toBe('cancellation-deadline-passed');

    // والموعد ما زال قائماً.
    const doc = await getAppointment(appt.appointmentId);
    expect(doc.status).toBe('Booked');
  });

  test('الإلغاء عند حد المهلة بالضبط مقبول', async () => {
    const appt = await book(PATIENT, {
      doctorId: DOCTOR, date: SAME_DAY_DATE, time: SAME_DAY_SLOT,
    });
    // فرق الدقائق = المهلة بالضبط (ساعة).
    const atDeadline = new Date(
      NOW.getTime() + (60 - CANCEL_DEADLINE_MINUTES) * 60000
    );
    const res = await cancel(PATIENT, { appointmentId: appt.appointmentId }, atDeadline);
    expect(res.status).toBe('Cancelled');
  });
});

describe('cancelAppointment — الخانات المجموعة والتزامن', () => {
  test('مريض لا يمكنه شطب مريض آخر من نفس الخانة', async () => {
    const a = await book(PATIENT, { doctorId: GROUP_DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    const b = await book(OTHER, { doctorId: GROUP_DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });

    await cancel(PATIENT, { appointmentId: a.appointmentId });

    const slot = await getSlot(a.slotId);
    expect(slot.bookedCount).toBe(1);
    expect(slot.patientIds).not.toContain(PATIENT);
    expect(slot.patientIds).toContain(OTHER);

    const bDoc = await getAppointment(b.appointmentId);
    expect(bDoc.status).toBe('Booked');
  });

  test('آخر مريض يغادر يُعيد الخانة متاحة بالكامل', async () => {
    const a = await book(PATIENT, { doctorId: GROUP_DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    const b = await book(OTHER, { doctorId: GROUP_DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });

    await cancel(PATIENT, { appointmentId: a.appointmentId });
    await cancel(OTHER, { appointmentId: b.appointmentId });

    const slot = await getSlot(a.slotId);
    expect(slot.bookedCount).toBe(0);
    expect(slot.patientIds).toEqual([]);

    // ويمكن حجزها من جديد بكامل سعتها.
    const c = await book(THIRD, { doctorId: GROUP_DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    expect(c.duplicate).toBe(false);
  });

  test('العدّاد لا يصبح سالباً مهما تكرّر الإلغاء بالتزامن', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });

    const results = await Promise.allSettled([
      cancel(PATIENT, { appointmentId: appt.appointmentId }),
      cancel(PATIENT, { appointmentId: appt.appointmentId }),
      cancel(PATIENT, { appointmentId: appt.appointmentId }),
    ]);
    // لا فشل غير متوقع: إما إلغاء فعلي أو نجاح هادئ لطلب مكرَّر.
    expect(results.every((r) => r.status === 'fulfilled')).toBe(true);

    const slot = await getSlot(appt.slotId);
    expect(slot.bookedCount).toBe(0);
    expect(slot.bookedCount).toBeGreaterThanOrEqual(0);
  });

  test('إلغاء متزامن مع حجز مريض آخر لنفس الخانة الفردية لا يزيد السعة', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });

    const [cancelResult, bookResult] = await Promise.allSettled([
      cancel(PATIENT, { appointmentId: appt.appointmentId }),
      book(OTHER, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME }),
    ]);

    const slot = await getSlot(appt.slotId);
    // إما أن الحجز الثاني نجح بعد تحرير الخانة (سعة 1)، أو فشل لأنه سبق
    // الإلغاء — كلاهما نتيجة صحيحة، والممنوع الوحيد هو تجاوز السعة.
    expect(slot.bookedCount).toBeLessThanOrEqual(1);
    expect(cancelResult.status).toBe('fulfilled');
    if (bookResult.status === 'fulfilled') {
      expect(slot.patientIds).toContain(OTHER);
    }
  });
});

// ===================== إعادة الجدولة =====================

describe('rescheduleAppointment — المصادقة والملكية والمدخلات', () => {
  test('طلب بلا هوية مرفوض', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    expect(await reasonOf(reschedule(null, {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '10:00',
    }))).toBe('unauthenticated');
  });

  test('تاريخ أو وقت جديد بصيغة غير صالحة مرفوض', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    expect(await reasonOf(reschedule(PATIENT, {
      appointmentId: appt.appointmentId, newDate: '2030/03/10', newTime: '10:00',
    }))).toBe('invalid-argument');
    expect(await reasonOf(reschedule(PATIENT, {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '25:00',
    }))).toBe('invalid-argument');
  });

  test('موعد غير موجود', async () => {
    expect(await reasonOf(reschedule(PATIENT, {
      appointmentId: 'nope', newDate: FUTURE_DATE_2, newTime: '10:00',
    }))).toBe('appointment-not-found');
  });

  test('مريض آخر لا يعدّل موعداً ليس له', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    expect(await reasonOf(reschedule(OTHER, {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '10:00',
    }))).toBe('permission-denied');
  });
});

describe('rescheduleAppointment — النقل الفعلي', () => {
  test('نقل ناجح: الخانة القديمة تُحرَّر والجديدة تُحجَز', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    const res = await reschedule(PATIENT, {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '11:00',
    });

    expect(res.unchanged).toBe(false);
    expect(res.duplicate).toBe(false);
    expect(res.status).toBe('Booked');
    expect(res.appointmentId).toBe(
      appointmentIdFor(slotIdFor(DOCTOR, FUTURE_DATE_2, '11:00'), PATIENT)
    );
    expect(res.previousAppointmentId).toBe(appt.appointmentId);

    const oldDoc = await getAppointment(appt.appointmentId);
    expect(oldDoc.status).toBe('Cancelled');
    expect(oldDoc.cancelReason).toBe('rescheduled');
    expect(oldDoc.rescheduledTo).toBe(res.appointmentId);

    const newDoc = await getAppointment(res.appointmentId);
    expect(newDoc.status).toBe('Booked');
    expect(newDoc.rescheduledFrom).toBe(appt.appointmentId);
    expect(newDoc.appointmentDate).toBe(FUTURE_DATE_2);
    expect(newDoc.startTime).toBe('11:00');
    expect(newDoc.price).toBe(200); // من مستند الطبيب، لا من الطلب.

    const oldSlot = await getSlot(appt.slotId);
    expect(oldSlot.bookedCount).toBe(0);

    const newSlot = await getSlot(slotIdFor(DOCTOR, FUTURE_DATE_2, '11:00'));
    expect(newSlot.bookedCount).toBe(1);
    expect(newSlot.patientIds).toEqual([PATIENT]);
  });

  test('النقل لنفس الخانة الحالية لا يغيّر شيئاً', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    const res = await reschedule(PATIENT, {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE, newTime: SLOT_TIME,
    });
    expect(res.unchanged).toBe(true);
    expect(res.appointmentId).toBe(appt.appointmentId);

    const doc = await getAppointment(appt.appointmentId);
    expect(doc.status).toBe('Booked'); // لم يُلغَ.

    const slot = await getSlot(appt.slotId);
    expect(slot.bookedCount).toBe(1);
  });

  test('خانة جديدة ممتلئة مرفوضة، ويبقى القديم قائماً بلا أي تغيير (ذرّية العملية)', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    // خانة أخرى عند نفس الطبيب تمتلئ بمريض آخر.
    await book(OTHER, { doctorId: DOCTOR, date: FUTURE_DATE_2, time: '11:00' });

    expect(await reasonOf(reschedule(PATIENT, {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '11:00',
    }))).toBe('slot-unavailable');

    // لا شيء تغيّر: القديم قائم، خانته سليمة.
    const oldDoc = await getAppointment(appt.appointmentId);
    expect(oldDoc.status).toBe('Booked');
    const oldSlot = await getSlot(appt.slotId);
    expect(oldSlot.bookedCount).toBe(1);
    expect(oldSlot.patientIds).toEqual([PATIENT]);
  });

  test('وقت جديد خارج جدول الطبيب مرفوض', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    expect(await reasonOf(reschedule(PATIENT, {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '03:00',
    }))).toBe('slot-not-found');

    const oldDoc = await getAppointment(appt.appointmentId);
    expect(oldDoc.status).toBe('Booked');
  });

  test('تاريخ جديد مضى مرفوض', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    expect(await reasonOf(reschedule(PATIENT, {
      appointmentId: appt.appointmentId, newDate: '2030-01-01', newTime: '09:00',
    }))).toBe('slot-expired');
  });

  test('موعد مكتمل لا يُعاد جدولته', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    await db.collection('appointments').doc(appt.appointmentId).update({ status: 'Completed' });
    expect(await reasonOf(reschedule(PATIENT, {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '10:00',
    }))).toBe('appointment-completed');
  });

  test('موعد ملغى لا يُعاد جدولته', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    await cancel(PATIENT, { appointmentId: appt.appointmentId });
    expect(await reasonOf(reschedule(PATIENT, {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '10:00',
    }))).toBe('appointment-not-reschedulable');
  });

  test('موعد فات وقته لا يُعاد جدولته', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: SAME_DAY_DATE, time: SAME_DAY_SLOT });
    const later = new Date('2030-03-01T07:30:00Z');
    expect(await reasonOf(reschedule(PATIENT, {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '10:00',
    }, later))).toBe('appointment-past');
  });

  test('إعادة الجدولة أقرب من مهلتها مرفوضة', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: SAME_DAY_DATE, time: SAME_DAY_SLOT });
    const soon = new Date('2030-03-01T06:45:00Z');
    expect(await reasonOf(reschedule(PATIENT, {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '10:00',
    }, soon))).toBe('reschedule-deadline-passed');

    const oldDoc = await getAppointment(appt.appointmentId);
    expect(oldDoc.status).toBe('Booked');
  });

  test('طبيب أصبح غير موثَّق يمنع إعادة الجدولة', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    await db.collection('users').doc(DOCTOR).update({ isVerified: false });
    expect(await reasonOf(reschedule(PATIENT, {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '10:00',
    }))).toBe('doctor-not-verified');
  });

  test('طلب مكرَّر لا يُنتج نقلاً ثانياً', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    const request = {
      appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '11:00',
    };
    const first = await reschedule(PATIENT, request);
    expect(first.duplicate).toBe(false);

    const second = await reschedule(PATIENT, request);
    expect(second.duplicate).toBe(true);
    expect(second.appointmentId).toBe(first.appointmentId);

    const newSlot = await getSlot(slotIdFor(DOCTOR, FUTURE_DATE_2, '11:00'));
    expect(newSlot.bookedCount).toBe(1); // لا حجز مضاعف للخانة الجديدة.
  });

  test('إعادة جدولة مريض في خانة مجموعة لا تمسّ مريضاً آخر فيها', async () => {
    const a = await book(PATIENT, { doctorId: GROUP_DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });
    const b = await book(OTHER, { doctorId: GROUP_DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });

    const res = await reschedule(PATIENT, {
      appointmentId: a.appointmentId, newDate: FUTURE_DATE_2, newTime: '10:00',
    });
    expect(res.status).toBe('Booked');

    const oldSlot = await getSlot(a.slotId);
    expect(oldSlot.bookedCount).toBe(1);
    expect(oldSlot.patientIds).toEqual([OTHER]);

    const bDoc = await getAppointment(b.appointmentId);
    expect(bDoc.status).toBe('Booked');
  });
});

describe('rescheduleAppointment — التزامن', () => {
  // معاملتان متنافستان على نفس المستند: المحاكي يعيد المحاولة داخلياً،
  // فيتجاوز زمنُها أحياناً مهلة jest الافتراضية (5 ثوانٍ) تحت الحِمل.
  // مهلة صريحة أوسع تمنع فشلاً لا علاقة له بما يختبره الاختبار.
  const CONCURRENCY_TIMEOUT_MS = 30000;

  test('مريضان يعيدان الجدولة إلى نفس الخانة الفردية الأخيرة: واحد فقط ينجح', async () => {
    const a = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: '09:00' });
    const b = await book(OTHER, { doctorId: DOCTOR, date: FUTURE_DATE, time: '09:30' });

    const results = await Promise.allSettled([
      reschedule(PATIENT, { appointmentId: a.appointmentId, newDate: FUTURE_DATE_2, newTime: '12:00' }),
      reschedule(OTHER, { appointmentId: b.appointmentId, newDate: FUTURE_DATE_2, newTime: '12:00' }),
    ]);

    const succeeded = results.filter((r) => r.status === 'fulfilled');
    const failed = results.filter((r) => r.status === 'rejected');
    expect(succeeded.length).toBe(1);
    expect(failed.length).toBe(1);
    expect(failed[0].reason.reason).toBe('slot-unavailable');

    const newSlot = await getSlot(slotIdFor(DOCTOR, FUTURE_DATE_2, '12:00'));
    expect(newSlot.bookedCount).toBe(1);
    expect(newSlot.capacity).toBe(1);
  }, CONCURRENCY_TIMEOUT_MS);

  test('إعادة جدولة وحجز مباشر يتنافسان على نفس الخانة: لا حجز مضاعف أبداً', async () => {
    const appt = await book(PATIENT, { doctorId: DOCTOR, date: FUTURE_DATE, time: SLOT_TIME });

    const results = await Promise.allSettled([
      reschedule(PATIENT, { appointmentId: appt.appointmentId, newDate: FUTURE_DATE_2, newTime: '13:00' }),
      book(OTHER, { doctorId: DOCTOR, date: FUTURE_DATE_2, time: '13:00' }),
    ]);

    expect(results.every((r) => r.status === 'fulfilled' || r.status === 'rejected')).toBe(true);

    const newSlot = await getSlot(slotIdFor(DOCTOR, FUTURE_DATE_2, '13:00'));
    // السعة فردية: مهما نجح، لا يمكن أن يشغلها أكثر من مريض واحد أبداً.
    expect(newSlot.bookedCount).toBe(1);
    expect(newSlot.patientIds.length).toBe(1);
  }, CONCURRENCY_TIMEOUT_MS);
});
