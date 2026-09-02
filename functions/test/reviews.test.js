/**
 * اختبارات المراجعات والتقييمات على الخادم.
 *
 * تعمل على **محاكي Firestore الحقيقي**: الذرّية والتزامن وإعادة المحاولة
 * سلوك قاعدة بيانات لا يُثبته إلا تشغيلها فعلاً.
 *
 *   firebase emulators:exec --only firestore --project drd-functions-test \
 *     "npm --prefix functions test"
 */

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const admin = require('firebase-admin');
const {
  createReviewCore,
  getReviewEligibilityCore,
  readAggregate,
  nextAggregate,
  normalizeRating,
  normalizeComment,
  MAX_COMMENT_LENGTH,
} = require('../reviews');

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'drd-functions-test' });
}
const db = admin.firestore();

const DOCTOR = 'reviewDoctor';
const OTHER_DOCTOR = 'reviewDoctorTwo';
const PATIENT = 'reviewPatient';
const OTHER = 'reviewPatientTwo';

const APPT = 'reviewDoctor_2030-03-03_09-00__reviewPatient';

const doctorDoc = (extra = {}) => ({
  role: 'doctor',
  isVerified: true,
  name: 'د. أحمد',
  specialization: 'أسنان',
  price: 200,
  ...extra,
});

const appointmentDoc = (extra = {}) => ({
  doctorId: DOCTOR,
  patientId: PATIENT,
  appointmentDate: '2030-03-03',
  startTime: '09:00',
  status: 'Completed',
  price: 200,
  ...extra,
});

async function clearFirestore() {
  for (const name of ['users', 'appointments', 'reviews']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seed() {
  await db.collection('users').doc(DOCTOR).set(doctorDoc());
  await db.collection('users').doc(OTHER_DOCTOR).set(doctorDoc({ name: 'د. سعاد' }));
  await db.collection('users').doc(PATIENT).set({
    role: 'patient', name: 'مريض', phone: '201000000002',
    email: 'p@example.com',
  });
  await db.collection('users').doc(OTHER).set({
    role: 'patient', name: 'مريض ٢', phone: '201000000003',
  });
  await db.collection('appointments').doc(APPT).set(appointmentDoc());
}

const review = (uid, data) => createReviewCore({ db, uid, data });
const eligibility = (uid, data) => getReviewEligibilityCore({ db, uid, data });

const request = (extra = {}) => ({
  appointmentId: APPT, rating: 5, comment: 'طبيب ممتاز', ...extra,
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

const doctorAggregate = async (id = DOCTOR) => {
  const snap = await db.collection('users').doc(id).get();
  const d = snap.data();
  return {
    rating: d.rating, reviews: d.reviews, ratingSum: d.ratingSum,
  };
};

beforeEach(async () => {
  await clearFirestore();
  await seed();
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app && app.delete()));
});

// ===================== دوال حسابية خالصة =====================

describe('حساب المُجمَّع', () => {
  test('التقييم عدد صحيح بين 1 و5', () => {
    expect(normalizeRating(1)).toBe(1);
    expect(normalizeRating(5)).toBe(5);
    expect(() => normalizeRating(0)).toThrow();
    expect(() => normalizeRating(6)).toThrow();
    expect(() => normalizeRating(4.5)).toThrow();
    expect(() => normalizeRating('5')).toThrow();
    expect(() => normalizeRating(NaN)).toThrow();
  });

  test('التعليق يُقصّ ويُحدّ طوله', () => {
    expect(normalizeComment('  ممتاز   جداً ')).toBe('ممتاز جداً');
    expect(normalizeComment(undefined)).toBe('');
    expect(() => normalizeComment('x'.repeat(MAX_COMMENT_LENGTH + 1))).toThrow();
    expect(() => normalizeComment({ evil: true })).toThrow();
  });

  test('المتوسط يُشتق من مجموع صحيح لا من متوسط سابق', () => {
    let agg = { count: 0, sum: 0 };
    for (const r of [5, 4, 3]) {
      const next = nextAggregate(agg, r);
      agg = { count: next.reviews, sum: next.ratingSum };
    }
    expect(agg.count).toBe(3);
    expect(agg.sum).toBe(12);
    expect(agg.sum / agg.count).toBe(4);

    const next = nextAggregate(agg, 1);
    expect(next.reviews).toBe(4);
    expect(next.ratingSum).toBe(13);
    expect(next.rating).toBe(3.25);
  });

  test('المجموع يُعاد بناؤه من الحقول القديمة عند غيابه', () => {
    // طبيب سابق للمرحلة 4: عنده متوسط وعدد، بلا `ratingSum`.
    const agg = readAggregate({ rating: 4, reviews: 3 });
    expect(agg.sum).toBe(12);
    expect(agg.count).toBe(3);
    expect(agg.reconstructed).toBe(true);
  });

  test('المجموع المخزَّن أولى من إعادة البناء', () => {
    const agg = readAggregate({ rating: 4, reviews: 3, ratingSum: 11 });
    expect(agg.sum).toBe(11);
    expect(agg.reconstructed).toBe(false);
  });

  test('طبيب بلا أي مراجعات يبدأ من الصفر', () => {
    expect(readAggregate({})).toEqual({ count: 0, sum: 0, reconstructed: false });
    expect(readAggregate(undefined))
      .toEqual({ count: 0, sum: 0, reconstructed: false });
  });
});

// ===================== المصادقة والملكية =====================

describe('المصادقة والملكية', () => {
  test('طلب بلا هوية مرفوض', async () => {
    // `callable` في index.js يرفض قبل الوصول هنا؛ هذا خط الدفاع الثاني.
    expect(await reasonOf(review(null, request()))).toBeTruthy();
    expect(await reasonOf(review('', request()))).toBeTruthy();
  });

  test('لا يمكن تقييم موعد مريض آخر', async () => {
    expect(await reasonOf(review(OTHER, request()))).toBe('permission-denied');
  });

  test('موعد غير موجود', async () => {
    expect(await reasonOf(review(PATIENT, request({ appointmentId: 'ghost' }))))
      .toBe('appointment-not-found');
  });

  test('معرّف موعد غير صالح', async () => {
    expect(await reasonOf(review(PATIENT, request({ appointmentId: 'a/b' }))))
      .toBe('invalid-argument');
    expect(await reasonOf(review(PATIENT, request({ appointmentId: '' }))))
      .toBe('invalid-argument');
    expect(await reasonOf(review(PATIENT, request({ appointmentId: 42 }))))
      .toBe('invalid-argument');
  });
});

// ===================== شرط الزيارة المكتملة =====================

describe('لا مراجعة بلا زيارة مكتملة', () => {
  const withStatus = async (status) => {
    await db.collection('appointments').doc(APPT).update({ status });
    return reasonOf(review(PATIENT, request()));
  };

  test('موعد محجوز لم يحضر بعد', async () => {
    expect(await withStatus('Booked')).toBe('appointment-not-completed');
  });

  test('موعد ملغى', async () => {
    expect(await withStatus('Cancelled')).toBe('appointment-not-completed');
  });

  test('موعد بانتظار التأكيد', async () => {
    expect(await withStatus('PendingConfirmation'))
      .toBe('appointment-not-completed');
  });

  test('موعد لم يحضره المريض', async () => {
    expect(await withStatus('NoShow')).toBe('appointment-not-completed');
  });

  test('حالة قديمة `Scheduled` لا تكفي', async () => {
    expect(await withStatus('Scheduled')).toBe('appointment-not-completed');
  });

  test('موعد أُعيدت جدولته ولم يكتمل', async () => {
    await db.collection('appointments').doc(APPT).update({
      status: 'Cancelled', rescheduledTo: 'someOtherAppointment',
    });
    expect(await reasonOf(review(PATIENT, request())))
      .toBe('appointment-not-completed');
  });

  test('موعد مكتمل يُقبل', async () => {
    const res = await review(PATIENT, request());
    expect(res.duplicate).toBe(false);
    expect(res.verifiedVisit).toBe(true);
  });

  test('الحالة القديمة `done` تُقبل — توافق', async () => {
    await db.collection('appointments').doc(APPT).update({ status: 'done' });
    const res = await review(PATIENT, request());
    expect(res.duplicate).toBe(false);
  });

  test('الحالة `completed` بحروف صغيرة تُقبل', async () => {
    await db.collection('appointments').doc(APPT).update({ status: 'completed' });
    expect((await review(PATIENT, request())).duplicate).toBe(false);
  });
});

// ===================== التحقق من المدخلات =====================

describe('التحقق من المدخلات', () => {
  test('تقييم خارج النطاق مرفوض', async () => {
    expect(await reasonOf(review(PATIENT, request({ rating: 0 }))))
      .toBe('invalid-argument');
    expect(await reasonOf(review(PATIENT, request({ rating: 6 }))))
      .toBe('invalid-argument');
    expect(await reasonOf(review(PATIENT, request({ rating: -3 }))))
      .toBe('invalid-argument');
  });

  test('تقييم كسري مرفوض', async () => {
    expect(await reasonOf(review(PATIENT, request({ rating: 4.5 }))))
      .toBe('invalid-argument');
  });

  test('تعليق ضخم مرفوض', async () => {
    const huge = 'ا'.repeat(MAX_COMMENT_LENGTH + 1);
    expect(await reasonOf(review(PATIENT, request({ comment: huge }))))
      .toBe('invalid-argument');
  });

  test('تعليق اختياري — الغياب مقبول', async () => {
    const res = await review(PATIENT, { appointmentId: APPT, rating: 4 });
    expect(res.comment).toBe('');
  });

  test('لا مراجعة تُكتب عند فشل التحقق', async () => {
    await reasonOf(review(PATIENT, request({ rating: 99 })));
    const snap = await db.collection('reviews').doc(APPT).get();
    expect(snap.exists).toBe(false);
    expect((await doctorAggregate()).reviews).toBeUndefined();
  });
});

// ===================== التلاعب =====================

describe('التلاعب — الخادم هو مصدر الحقيقة', () => {
  test('كل الحقول المرسلة من العميل تُتجاهل', async () => {
    const res = await review(PATIENT, {
      appointmentId: APPT,
      rating: 5,
      comment: 'ممتاز',
      // ما يلي كان يُكتب كما هو قبل هذه المرحلة:
      patientId: OTHER,
      doctorId: OTHER_DOCTOR,
      patientName: 'اسم مزيّف',
      verifiedVisit: false,
      createdAt: 'أمس',
      reviewId: 'forged',
      appointmentDate: '1999-01-01',
      doctorRating: 5,
      doctorReviews: 9999,
      ratingSum: 9999,
    });

    const stored = (await db.collection('reviews').doc(APPT).get()).data();
    expect(stored.patientId).toBe(PATIENT);       // من الموعد لا الطلب
    expect(stored.doctorId).toBe(DOCTOR);          // من الموعد لا الطلب
    expect(stored.patientName).toBe('مريض');       // من مستند المريض
    expect(stored.verifiedVisit).toBe(true);       // شهادة الخادم
    expect(stored.appointmentId).toBe(APPT);
    expect(stored.appointmentDate).toBe('2030-03-03');
    expect(stored.createdAt.toDate()).toBeInstanceOf(Date);
    expect(stored.ratingSum).toBeUndefined();
    expect(res.reviewId).toBe(APPT);

    // الطبيب الحقيقي هو من تأثّر مُجمَّعه، لا الطبيب المزيّف.
    expect(await doctorAggregate(DOCTOR))
      .toEqual({ rating: 5, reviews: 1, ratingSum: 5 });
    const forged = await doctorAggregate(OTHER_DOCTOR);
    expect(forged.reviews).toBeUndefined();
  });

  test('لا يمكن حقن مُجمَّع عبر الطلب', async () => {
    await review(PATIENT, request({ rating: 1, doctorReviews: 500 }));
    expect(await doctorAggregate())
      .toEqual({ rating: 1, reviews: 1, ratingSum: 1 });
  });
});

// ===================== التكرار والذرّية =====================

describe('مراجعة واحدة لكل زيارة', () => {
  test('نفس الطلب مرتين لا ينتج مراجعتين ولا يرفع العدّاد مرتين', async () => {
    const first = await review(PATIENT, request({ rating: 4 }));
    const second = await review(PATIENT, request({ rating: 1 }));

    expect(first.duplicate).toBe(false);
    expect(second.duplicate).toBe(true);
    expect(second.reviewId).toBe(first.reviewId);

    // التقييم الثاني (1) لم يُكتب ولم يؤثر في المتوسط.
    const stored = (await db.collection('reviews').doc(APPT).get()).data();
    expect(stored.rating).toBe(4);
    expect(await doctorAggregate())
      .toEqual({ rating: 4, reviews: 1, ratingSum: 4 });
  });

  test('طلبان متزامنان ينتجان مراجعة واحدة', async () => {
    const results = await Promise.allSettled([
      review(PATIENT, request({ rating: 5 })),
      review(PATIENT, request({ rating: 5 })),
    ]);

    expect(results.filter((r) => r.status === 'fulfilled').length)
      .toBeGreaterThanOrEqual(1);

    const all = await db.collection('reviews')
      .where('appointmentId', '==', APPT).get();
    expect(all.size).toBe(1);
    expect(await doctorAggregate())
      .toEqual({ rating: 5, reviews: 1, ratingSum: 5 });
  }, 60000);

  test('إعادة المحاولة بعد انقطاع تُعيد نفس المراجعة', async () => {
    const first = await review(PATIENT, request({ rating: 3 }));
    const retry = await review(PATIENT, request({ rating: 3 }));

    expect(retry.duplicate).toBe(true);
    expect(retry.rating).toBe(first.rating);
    expect(await doctorAggregate())
      .toEqual({ rating: 3, reviews: 1, ratingSum: 3 });
  });
});

describe('الذرّية', () => {
  test('فشل تحديث المُجمَّع لا يترك مراجعة يتيمة', async () => {
    // طبيب الموعد محذوف: تحديث المُجمَّع مستحيل، فيجب ألا تُكتب المراجعة.
    await db.collection('users').doc(DOCTOR).delete();

    expect(await reasonOf(review(PATIENT, request()))).toBe('doctor-not-found');

    const snap = await db.collection('reviews').doc(APPT).get();
    expect(snap.exists).toBe(false);
  });

  test('موعد بلا طبيب لا ينتج مراجعة', async () => {
    await db.collection('appointments').doc(APPT).update({
      doctorId: admin.firestore.FieldValue.delete(),
    });
    expect(await reasonOf(review(PATIENT, request()))).toBe('doctor-not-found');
    expect((await db.collection('reviews').doc(APPT).get()).exists).toBe(false);
  });

  test('المراجعة والمُجمَّع يظهران معاً', async () => {
    await review(PATIENT, request({ rating: 5 }));
    const [reviewSnap, agg] = await Promise.all([
      db.collection('reviews').doc(APPT).get(),
      doctorAggregate(),
    ]);
    expect(reviewSnap.exists).toBe(true);
    expect(agg.reviews).toBe(1);
    expect(agg.ratingSum).toBe(5);
  });
});

// ===================== صحة المُجمَّع =====================

describe('صحة المُجمَّع عبر عدة مرضى', () => {
  /** ينشئ موعداً مكتملاً لمريض ثم يقيّمه. */
  async function reviewAs(uid, rating, index) {
    const id = `${DOCTOR}_2030-03-0${index}_09-00__${uid}`;
    await db.collection('users').doc(uid)
      .set({ role: 'patient', name: uid }, { merge: true });
    await db.collection('appointments').doc(id).set(appointmentDoc({
      patientId: uid, appointmentDate: `2030-03-0${index}`,
    }));
    return createReviewCore({ db, uid, data: { appointmentId: id, rating } });
  }

  test('5 ثم 4 ثم 3 → العدد 3 والمجموع 12 والمتوسط 4', async () => {
    await reviewAs('agg1', 5, 1);
    await reviewAs('agg2', 4, 2);
    await reviewAs('agg3', 3, 3);

    expect(await doctorAggregate())
      .toEqual({ rating: 4, reviews: 3, ratingSum: 12 });
  });

  test('ثم 1 → العدد 4 والمجموع 13 والمتوسط 3.25', async () => {
    await reviewAs('agg1', 5, 1);
    await reviewAs('agg2', 4, 2);
    await reviewAs('agg3', 3, 3);
    await reviewAs('agg4', 1, 4);

    expect(await doctorAggregate())
      .toEqual({ rating: 3.25, reviews: 4, ratingSum: 13 });
  });

  test('مراجعات متزامنة من مرضى مختلفين لا تفقد أياً منها', async () => {
    const patients = ['con1', 'con2', 'con3', 'con4', 'con5'];
    await Promise.all(patients.map(async (uid, i) => {
      const id = `${DOCTOR}_2030-04-0${i + 1}_09-00__${uid}`;
      await db.collection('users').doc(uid).set({ role: 'patient', name: uid });
      await db.collection('appointments').doc(id).set(appointmentDoc({
        patientId: uid, appointmentDate: `2030-04-0${i + 1}`,
      }));
    }));

    const results = await Promise.allSettled(patients.map((uid, i) =>
      createReviewCore({
        db, uid,
        data: {
          appointmentId: `${DOCTOR}_2030-04-0${i + 1}_09-00__${uid}`,
          rating: 5,
        },
      })
    ));

    const ok = results.filter((r) => r.status === 'fulfilled').length;
    expect(ok).toBe(5);

    // لا فقدان تحديث: المجموع والعدّاد يطابقان عدد المراجعات المكتوبة فعلاً.
    const written = await db.collection('reviews')
      .where('doctorId', '==', DOCTOR).get();
    expect(written.size).toBe(5);

    const agg = await doctorAggregate();
    expect(agg.reviews).toBe(5);
    expect(agg.ratingSum).toBe(25);
    expect(agg.rating).toBe(5);
  }, 60000);

  test('طبيب سابق للمرحلة 4 يكمل من مجموعه المُعاد بناؤه', async () => {
    // متوسط 4 على 3 مراجعات = مجموع 12، ثم تصل مراجعة بـ5.
    await db.collection('users').doc(DOCTOR)
      .update({ rating: 4, reviews: 3 });

    await review(PATIENT, request({ rating: 5 }));

    expect(await doctorAggregate())
      .toEqual({ rating: 4.25, reviews: 4, ratingSum: 17 });
  });

  test('المتوسط لا ينجرف عبر مراجعات كثيرة', async () => {
    // ثلاثات متتالية: المتوسط يجب أن يبقى 3 بالضبط لا 2.9999999999999996.
    for (let i = 1; i <= 12; i++) {
      const uid = `drift${i}`;
      const id = `${DOCTOR}_2030-05-${String(i).padStart(2, '0')}_09-00__${uid}`;
      await db.collection('users').doc(uid).set({ role: 'patient', name: uid });
      await db.collection('appointments').doc(id).set(appointmentDoc({
        patientId: uid, appointmentDate: `2030-05-${String(i).padStart(2, '0')}`,
      }));
      await createReviewCore({ db, uid, data: { appointmentId: id, rating: 3 } });
    }

    const agg = await doctorAggregate();
    expect(agg.reviews).toBe(12);
    expect(agg.ratingSum).toBe(36);
    expect(agg.rating).toBe(3);
  }, 60000);
});

// ===================== الأهلية =====================

describe('أهلية التقييم', () => {
  test('موعد مكتمل غير مُقيَّم → مؤهَّل', async () => {
    const res = await eligibility(PATIENT, { appointmentId: APPT });
    expect(res.eligible).toBe(true);
    expect(res.alreadyReviewed).toBe(false);
    expect(res.doctorId).toBe(DOCTOR);
  });

  test('موعد غير مكتمل → غير مؤهَّل بسبب واضح', async () => {
    await db.collection('appointments').doc(APPT).update({ status: 'Booked' });
    const res = await eligibility(PATIENT, { appointmentId: APPT });
    expect(res.eligible).toBe(false);
    expect(res.reason).toBe('appointment-not-completed');
  });

  test('بعد التقييم → غير مؤهَّل، وتُعاد المراجعة القائمة', async () => {
    await review(PATIENT, request({ rating: 4, comment: 'جيد' }));
    const res = await eligibility(PATIENT, { appointmentId: APPT });
    expect(res.eligible).toBe(false);
    expect(res.alreadyReviewed).toBe(true);
    expect(res.reason).toBe('already-reviewed');
    expect(res.rating).toBe(4);
    expect(res.comment).toBe('جيد');
  });

  test('موعد شخص آخر لا تُكشف حالته', async () => {
    expect(await reasonOf(eligibility(OTHER, { appointmentId: APPT })))
      .toBe('permission-denied');
  });

  test('موعد غير موجود', async () => {
    expect(await reasonOf(eligibility(PATIENT, { appointmentId: 'ghost' })))
      .toBe('appointment-not-found');
  });

  test('الأهلية تطابق ما يقبله الإنشاء فعلاً', async () => {
    // لا يجوز أن تقول الواجهة «يمكنك التقييم» ثم يرفض الخادم.
    for (const status of ['Booked', 'Cancelled', 'NoShow', 'PendingConfirmation']) {
      await db.collection('appointments').doc(APPT).update({ status });
      const elig = await eligibility(PATIENT, { appointmentId: APPT });
      const createReason = await reasonOf(review(PATIENT, request()));
      expect(elig.eligible).toBe(false);
      expect(createReason).toBe('appointment-not-completed');
    }
  });
});

// ===================== المراجعات القائمة =====================

describe('التوافق مع المراجعات القائمة', () => {
  test('مراجعة قديمة بلا verifiedVisit لا تُلمس ولا تُكرَّر', async () => {
    // مراجعة كتبها العميل قبل المرحلة 4.
    await db.collection('reviews').doc(APPT).set({
      appointmentId: APPT, doctorId: DOCTOR, patientId: PATIENT,
      patientName: 'مريض', rating: 5, comment: 'قديمة',
      createdAt: new Date('2026-01-01T00:00:00Z'),
    });
    await db.collection('users').doc(DOCTOR).update({ rating: 5, reviews: 1 });

    const res = await review(PATIENT, request({ rating: 1 }));
    expect(res.duplicate).toBe(true);

    const stored = (await db.collection('reviews').doc(APPT).get()).data();
    expect(stored.comment).toBe('قديمة');
    expect(stored.rating).toBe(5);
    expect(stored.verifiedVisit).toBeUndefined();

    // ولا يرتفع العدّاد بسبب المحاولة المكرَّرة.
    const agg = await doctorAggregate();
    expect(agg.reviews).toBe(1);
  });
});
