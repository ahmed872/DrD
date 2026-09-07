/**
 * اختبار التزامن على الحجز — وعد المنتَج الأساسي.
 *
 *   firebase emulators:exec --only firestore "npm --prefix test/firestore_rules test"
 *
 * ## لماذا هذا الملف موجود
 *
 * التطبيق كله مبني على جملة واحدة: *لا يُحجز موعد واحد لمريضين*. الحماية
 * ثلاث طبقات — معرّف محسوب للخانة، معاملة ذرّية، وقاعدة أمان تحدّ السعة —
 * ومع ذلك **لم يكن هناك اختبار واحد يشغّل حجزين متزامنين**. الاختبارات
 * السابقة كانت تفحص القاعدة وحدها بطلب واحد، وهو ما لا يثبت شيئاً عن
 * التزامن.
 *
 * الاختبارات هنا تحاكي منطق `BookingService.book()` بالضبط: فحص تكرار مسبق
 * باستعلام مقيَّد بصاحب الطلب، ثم `runTransaction` تقرأ الخانة وتزيد العدّاد
 * وتكتب الموعد معاً.
 */

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, runTransaction,
  collection, query, where, getDocs,
} = require('firebase/firestore');

let testEnv;

const DOCTOR = 'doctor_1';
const A = 'patient_a';
const B = 'patient_b';
const DATE = '2030-01-01';
const TIME = '09:00';
const SLOT = `${DOCTOR}_${DATE}_09-00`;
const apptId = (uid) => `${SLOT}__${uid}`;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'drd-booking-concurrency',
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
    await setDoc(doc(db, 'users', A), { role: 'patient', name: 'مريض أ' });
    await setDoc(doc(db, 'users', B), { role: 'patient', name: 'مريض ب' });
  });
});

const as = (uid) => testEnv.authenticatedContext(uid).firestore();

/**
 * نفس منطق BookingService.book()، مترجَماً إلى JS.
 *
 * ملاحظة مهمة: كشف التكرار يجري **قبل** المعاملة باستعلام مقيَّد بصاحب
 * الطلب، لا بقراءة مستند الموعد داخلها. قراءة مستند غير موجود تُقيَّم على
 * `allow read: if isOwner()` و`resource` عندها `null`، فتُرفض القراءة —
 * أي أن الفحص داخل المعاملة كان سيكسر كل حجز أول. هذا الاختبار هو ما كشف
 * ذلك.
 */
async function book(db, uid, capacity) {
  const mine = await getDocs(query(
    collection(db, 'appointments'),
    where('doctorId', '==', DOCTOR),
    where('patientId', '==', uid),
    where('appointmentDate', '==', DATE),
  ));
  const duplicate = mine.docs.some(
    (d) => d.data().startTime === TIME && d.data().status === 'Booked'
  );
  if (duplicate) throw new Error('ALREADY_BOOKED');

  await runTransaction(db, async (tx) => {
    const slotRef = doc(db, 'slots', SLOT);
    const slotSnap = await tx.get(slotRef);

    if (!slotSnap.exists()) {
      tx.set(slotRef, {
        doctorId: DOCTOR, appointmentDate: DATE, startTime: TIME,
        capacity, bookedCount: 1,
      });
    } else {
      const data = slotSnap.data();
      const booked = data.bookedCount || 0;
      const cap = data.capacity != null ? data.capacity : capacity;
      if (booked >= cap) throw new Error('SLOT_TAKEN');
      tx.update(slotRef, { bookedCount: booked + 1 });
    }

    tx.set(doc(db, 'appointments', apptId(uid)), {
      doctorId: DOCTOR, patientId: uid, appointmentDate: DATE,
      startTime: TIME, slotId: SLOT, status: 'Booked',
      patientName: uid, patientPhone: '20100000000',
    });
  });
}

async function slotCount() {
  let count = null;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const snap = await getDoc(doc(ctx.firestore(), 'slots', SLOT));
    count = snap.exists() ? snap.data().bookedCount : null;
  });
  return count;
}

async function bookedAppointments() {
  let n = 0;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    for (const uid of [A, B]) {
      const snap = await getDoc(doc(ctx.firestore(), 'appointments', apptId(uid)));
      if (snap.exists() && snap.data().status === 'Booked') n += 1;
    }
  });
  return n;
}

describe('حجزان متزامنان على نفس الخانة', () => {
  test('خانة فردية: ينجح واحد فقط، والعدّاد يساوي 1', async () => {
    const results = await Promise.allSettled([
      book(as(A), A, 1),
      book(as(B), B, 1),
    ]);

    const ok = results.filter((r) => r.status === 'fulfilled').length;
    expect(ok).toBe(1);
    expect(await slotCount()).toBe(1);
    expect(await bookedAppointments()).toBe(1);
  });

  test('خانة مجموعات بسعة 2: ينجح الاثنان، والعدّاد يساوي 2', async () => {
    const results = await Promise.allSettled([
      book(as(A), A, 2),
      book(as(B), B, 2),
    ]);

    expect(results.filter((r) => r.status === 'fulfilled').length).toBe(2);
    expect(await slotCount()).toBe(2);
    expect(await bookedAppointments()).toBe(2);
  });

  test('خانة مجموعات ممتلئة لا تقبل ثالثاً', async () => {
    await book(as(A), A, 2);
    await book(as(B), B, 2);
    await expect(book(as('patient_c'), 'patient_c', 2)).rejects.toThrow();
    expect(await slotCount()).toBe(2);
  });
});

describe('الحماية بعد المعاملة', () => {
  test('العميل لا يستطيع تجاوز السعة بالكتابة المباشرة', async () => {
    // الطبقة الثالثة: حتى لو تجاوز عميل معدَّل المعاملة كلها، القاعدة تردّه.
    await book(as(A), A, 1);
    await assertFails(
      setDoc(doc(as(B), 'slots', SLOT), {
        doctorId: DOCTOR, appointmentDate: DATE, startTime: TIME,
        capacity: 1, bookedCount: 2,
      })
    );
    expect(await slotCount()).toBe(1);
  });

  test('نفس المريض لا يحجز الخانة مرتين', async () => {
    await book(as(A), A, 4);
    await expect(book(as(A), A, 4)).rejects.toThrow('ALREADY_BOOKED');
    expect(await slotCount()).toBe(1);
  });

  test('لكنه يعيد الحجز بعد الإلغاء، والعدّاد يعود إلى 1', async () => {
    // الحالة التي كانت مستحيلة قبل إصلاح دورة حياة الموعد.
    await book(as(A), A, 1);

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'appointments', apptId(A)), {
        doctorId: DOCTOR, patientId: A, appointmentDate: DATE,
        startTime: TIME, slotId: SLOT, status: 'Cancelled',
        patientName: A, patientPhone: '20100000000',
      });
      await setDoc(doc(db, 'slots', SLOT), {
        doctorId: DOCTOR, appointmentDate: DATE, startTime: TIME,
        capacity: 1, bookedCount: 0,
      });
    });

    await book(as(A), A, 1);
    expect(await slotCount()).toBe(1);
    expect(await bookedAppointments()).toBe(1);
  });
});
