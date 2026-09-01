/**
 * المراجعات والتقييمات على الخادم.
 *
 * ## ما الذي كان يحدث قبل هذا الملف
 *
 * المراجعة كانت تُكتب من التطبيق مباشرة، ثم يُحدَّث متوسط تقييم الطبيب
 * بمعاملة **منفصلة** من العميل أيضاً:
 *
 * ```dart
 * await FirebaseFirestore.instance.collection('reviews').doc(id).set({...});
 * await FirebaseFirestore.instance.runTransaction((tx) async {
 *   final newRating = ((currentRating * currentReviews) + rating)
 *                     / (currentReviews + 1);
 *   tx.update(doctorRef, {'rating': newRating, 'reviews': currentReviews + 1});
 * });
 * ```
 *
 * ثلاث مشاكل في هذه الأسطر:
 *
 * 1. **لا ذرّية بين الاثنين.** فشل المعاملة الثانية — أو إغلاق التطبيق
 *    بينهما — يترك مراجعة بلا أثر في المتوسط، أو العكس عند إعادة المحاولة.
 * 2. **المتوسط يُحسب على العميل** ويُكتب كقيمة نهائية. القاعدة كانت تسمح
 *    لأي مستخدم مسجَّل بكتابة أي متوسط بين 0 و5 على أي طبيب مع زيادة العدّاد
 *    بواحد — بلا أي ربط بمراجعة حقيقية. أي أن تحريك تقييم طبيب لم يكن يحتاج
 *    زيارة ولا مراجعة، بل طلب `update` واحداً.
 * 3. **تراكم عائم.** المتوسط يُعاد حسابه من متوسط سابق مضروب في عدّاد، فيتسرّب
 *    خطأ التقريب مع كل مراجعة ولا يمكن استرجاع المجموع الصحيح منه.
 *
 * ## ما يفعله هذا الملف
 *
 * المراجعة والمُجمَّع يُكتبان في **معاملة واحدة**، والخادم هو من يستخرج
 * المريض والطبيب والموعد من مستند الموعد نفسه — لا من الطلب. والمجموع يُحفظ
 * كعدد صحيح (`ratingSum`) فيبقى المتوسط قابلاً لإعادة الحساب بدقّة تامة.
 */

const {
  AppError,
  fail,
  normalizeStatusKey,
} = require('./availability');

/** أقصى طول لنص المراجعة. */
const MAX_COMMENT_LENGTH = 1000;

/**
 * الحالات التي تُثبت أن الزيارة تمّت فعلاً.
 *
 * `done` صيغة قديمة موجودة في بيانات التطبيق ومُعترف بها في
 * `AppointmentStatus._legacyAliases` وفي قواعد الأمان — إسقاطها هنا كان
 * سيحرم مواعيد قديمة مكتملة من حق التقييم.
 */
const COMPLETED_STATUSES = new Set(['completed', 'done']);

/** معرّف الموعد يصير معرّف مستند المراجعة، فلا يجوز أن يحمل محارف مسار. */
function assertValidAppointmentId(value) {
  if (typeof value !== 'string' || !value.trim()) {
    fail('invalid-argument', 'invalid-argument', 'معرّف الموعد مطلوب');
  }
  if (value.includes('/') || value.includes('..') || value.length > 1500) {
    fail('invalid-argument', 'invalid-argument', 'معرّف الموعد غير صالح');
  }
}

/**
 * التقييم: عدد صحيح من 1 إلى 5.
 *
 * الصرامة مقصودة. النجوم في الواجهة عدد صحيح دائماً، وقبول الكسور كان
 * يفتح باب `4.999999` وما شابهه في المجموع، ويُفقد `ratingSum` معناه كعدد
 * صحيح دقيق.
 */
function normalizeRating(raw) {
  if (typeof raw !== 'number' || !Number.isFinite(raw)) {
    fail('invalid-argument', 'invalid-argument', 'التقييم يجب أن يكون رقماً');
  }
  if (!Number.isInteger(raw)) {
    fail('invalid-argument', 'invalid-argument', 'التقييم يجب أن يكون عدداً صحيحاً');
  }
  if (raw < 1 || raw > 5) {
    fail('invalid-argument', 'invalid-argument', 'التقييم يجب أن يكون بين 1 و5');
  }
  return raw;
}

/** نص المراجعة — المدخل الحر الوحيد، ولا يدخل في أي قرار. */
function normalizeComment(raw) {
  if (raw === undefined || raw === null) return '';
  if (typeof raw !== 'string') {
    fail('invalid-argument', 'invalid-argument', 'التعليق يجب أن يكون نصاً');
  }
  const trimmed = raw.trim().replace(/\s+/g, ' ');
  if (trimmed.length > MAX_COMMENT_LENGTH) {
    fail('invalid-argument', 'invalid-argument',
      `التعليق أطول من ${MAX_COMMENT_LENGTH} حرفاً`);
  }
  return trimmed;
}

/**
 * قراءة المُجمَّع الحالي من مستند الطبيب.
 *
 * `ratingSum` هو مصدر الحقيقة، لكنه لم يكن موجوداً قبل هذه المرحلة. عند
 * غيابه يُعاد بناؤه من الحقلين القديمين (`rating` متوسط، `reviews` عدد) —
 * وهو أفضل تقدير ممكن من البيانات القائمة، ويحدث **مرة واحدة** داخل أول
 * معاملة تلمس هذا الطبيب.
 *
 * هذا ليس ترحيلاً: لا يُكتب شيء على الأطباء الذين لا تصلهم مراجعات جديدة،
 * ولا تُمسّ أي مراجعة قائمة.
 */
function readAggregate(doctorData) {
  const data = doctorData || {};

  const rawCount = Number(data.reviews);
  const count = Number.isFinite(rawCount) && rawCount > 0
    ? Math.floor(rawCount)
    : 0;

  const rawSum = Number(data.ratingSum);
  if (Number.isFinite(rawSum) && rawSum >= 0) {
    return { count, sum: Math.round(rawSum), reconstructed: false };
  }

  const rawAverage = Number(data.rating);
  const average = Number.isFinite(rawAverage) && rawAverage > 0 ? rawAverage : 0;
  return { count, sum: Math.round(average * count), reconstructed: count > 0 };
}

/**
 * المُجمَّع بعد إضافة تقييم جديد.
 *
 * المتوسط يُشتق من عددين صحيحين في كل مرة بدل أن يُبنى على متوسط سابق، فلا
 * يتراكم خطأ التقريب مهما بلغ عدد المراجعات.
 */
function nextAggregate(current, rating) {
  const count = current.count + 1;
  const sum = current.sum + rating;
  return {
    reviews: count,
    ratingSum: sum,
    // تقريب لأقرب منزلتين: يكفي للعرض ويمنع أرقاماً مثل 4.333333333333333
    // في مستند يقرأه العميل. المصدر الدقيق يبقى `ratingSum`/`reviews`.
    rating: Math.round((sum / count) * 100) / 100,
  };
}

/**
 * ما يستطيع أي مستخدم مسجَّل رؤيته من المراجعة.
 *
 * لا هاتف ولا بريد ولا ملاحظات الطبيب الطبية. الاسم المعروض وحده — وهو ما
 * كانت الواجهة تعرضه أصلاً — ويؤخذ من مستند المريض على الخادم لا من الطلب.
 */
function publicReviewFields(review) {
  return {
    reviewId: review.appointmentId,
    appointmentId: review.appointmentId,
    doctorId: review.doctorId,
    rating: review.rating,
    comment: review.comment,
    patientName: review.patientName,
    verifiedVisit: review.verifiedVisit,
  };
}

/**
 * يقرأ الموعد ويتحقق من ملكيته واكتمال الزيارة.
 *
 * يُستدعى من داخل المعاملة (بـ `tx`) ومن خارجها (بلا `tx`) — نفس المنطق في
 * الحالتين، فلا يفترق ما تعرضه الواجهة عمّا يقبله الخادم.
 */
async function loadAppointmentForReview(db, tx, uid, appointmentId) {
  const ref = db.collection('appointments').doc(appointmentId);
  const snap = tx ? await tx.get(ref) : await ref.get();

  if (!snap.exists) {
    fail('appointment-not-found', 'not-found', 'لا يوجد موعد بهذا المعرّف');
  }

  const appointment = snap.data();

  // الملكية تُفحص قبل أي شيء آخر: من لا يملك الموعد لا يُخبَر بحالته.
  if (appointment.patientId !== uid) {
    fail('permission-denied', 'permission-denied', 'هذا ليس موعدك');
  }

  return appointment;
}

/**
 * إنشاء مراجعة عن زيارة مكتملة.
 *
 * ```
 * الطلب:  { appointmentId, rating: 1..5, comment? }
 * الرد:   { ok, reviewId, appointmentId, doctorId, rating,
 *           doctorRating, doctorReviews, duplicate }
 * ```
 *
 * `patientId` و`doctorId` و`verifiedVisit` و`createdAt` كلها من الخادم؛ أي
 * قيمة لها في الطلب تُتجاهل بالكامل.
 */
async function createReviewCore({ db, uid, data }) {
  const payload = data && typeof data === 'object' ? data : {};

  const appointmentId = payload.appointmentId;
  assertValidAppointmentId(appointmentId);
  const rating = normalizeRating(payload.rating);
  const comment = normalizeComment(payload.comment);

  const reviewRef = db.collection('reviews').doc(appointmentId);

  const outcome = await db.runTransaction(async (tx) => {
    const appointment = await loadAppointmentForReview(db, tx, uid, appointmentId);

    const status = normalizeStatusKey(appointment.status);
    if (!COMPLETED_STATUSES.has(status)) {
      fail('appointment-not-completed', 'failed-precondition',
        'يمكنك التقييم بعد اكتمال الكشف فقط');
    }

    const doctorId = appointment.doctorId;
    if (typeof doctorId !== 'string' || !doctorId) {
      // بيانات موعد فاسدة — لا مُجمَّع يمكن تحديثه بأمان.
      fail('doctor-not-found', 'failed-precondition',
        'تعذّر تحديد طبيب هذا الموعد');
    }

    const doctorRef = db.collection('users').doc(doctorId);
    const patientRef = db.collection('users').doc(uid);

    const [reviewSnap, doctorSnap, patientSnap] = await Promise.all([
      tx.get(reviewRef),
      tx.get(doctorRef),
      tx.get(patientRef),
    ]);

    // طلب مكرَّر: نفس الزيارة قُيّمت بالفعل.
    //
    // معرّف المستند هو معرّف الموعد، فالضغطة المزدوجة أو إعادة المحاولة بعد
    // انقطاع تصل إلى نفس المستند. نُعيد نجاحاً هادئاً بالمراجعة القائمة بدل
    // كتابة ثانية ترفع العدّاد مرتين على زيارة واحدة.
    if (reviewSnap.exists) {
      const existing = reviewSnap.data();
      const doctorData = doctorSnap.exists ? doctorSnap.data() : {};
      return {
        duplicate: true,
        review: existing,
        doctorRating: Number(doctorData.rating) || 0,
        doctorReviews: Number(doctorData.reviews) || 0,
      };
    }

    if (!doctorSnap.exists) {
      fail('doctor-not-found', 'not-found', 'حساب الطبيب غير موجود');
    }

    const patientName = patientSnap.exists
      ? String(patientSnap.data().name || '').trim()
      : '';

    const aggregate = nextAggregate(readAggregate(doctorSnap.data()), rating);

    const review = {
      appointmentId,
      doctorId,
      patientId: uid,
      patientName: patientName || 'مريض',
      rating,
      comment,
      // شهادة الخادم بأن المراجعة مبنية على زيارة تمّت — لا تُقبل من العميل
      // إطلاقاً، ووجودها هنا يعني أن الفحوص أعلاه مرّت كلها.
      verifiedVisit: true,
      appointmentDate: appointment.appointmentDate || null,
      createdAt: new Date(),
    };

    tx.set(reviewRef, review);

    // نفس المعاملة: لا مراجعة بلا أثر في المتوسط، ولا متوسط بلا مراجعة.
    tx.update(doctorRef, {
      rating: aggregate.rating,
      reviews: aggregate.reviews,
      ratingSum: aggregate.ratingSum,
    });

    return {
      duplicate: false,
      review,
      doctorRating: aggregate.rating,
      doctorReviews: aggregate.reviews,
    };
  });

  return {
    ...publicReviewFields(outcome.review),
    doctorRating: outcome.doctorRating,
    doctorReviews: outcome.doctorReviews,
    duplicate: outcome.duplicate,
  };
}

/**
 * هل يستطيع صاحب الطلب تقييم هذا الموعد؟
 *
 * ```
 * الطلب:  { appointmentId }
 * الرد:   { ok, appointmentId, eligible, alreadyReviewed, reason, doctorId }
 * ```
 *
 * الواجهة لا تقرّر الأهلية من حالة الموعد وحدها: القرار هنا، بنفس الفحوص
 * التي ينفّذها `createReview` — فلا يظهر زر تقييم يفشل عند الضغط.
 *
 * انعدام الملكية أو وجود الموعد يُرفَعان كخطأ (لا يُخبَر أحد بحالة موعد
 * ليس له)، أما الحالات المشروعة — لم يكتمل بعد، أو قُيّم بالفعل — فتُرجَع
 * كردٍّ عادي ليعرضه التطبيق.
 */
async function getReviewEligibilityCore({ db, uid, data }) {
  const payload = data && typeof data === 'object' ? data : {};
  const appointmentId = payload.appointmentId;
  assertValidAppointmentId(appointmentId);

  const appointment = await loadAppointmentForReview(db, null, uid, appointmentId);
  const doctorId = typeof appointment.doctorId === 'string'
    ? appointment.doctorId
    : null;

  const reviewSnap = await db.collection('reviews').doc(appointmentId).get();
  if (reviewSnap.exists) {
    const existing = reviewSnap.data();
    return {
      appointmentId,
      doctorId,
      eligible: false,
      alreadyReviewed: true,
      reason: 'already-reviewed',
      rating: Number(existing.rating) || null,
      comment: typeof existing.comment === 'string' ? existing.comment : '',
    };
  }

  const status = normalizeStatusKey(appointment.status);
  if (!COMPLETED_STATUSES.has(status)) {
    return {
      appointmentId,
      doctorId,
      eligible: false,
      alreadyReviewed: false,
      reason: 'appointment-not-completed',
    };
  }

  return {
    appointmentId,
    doctorId,
    eligible: true,
    alreadyReviewed: false,
    reason: null,
  };
}

module.exports = {
  createReviewCore,
  getReviewEligibilityCore,
  AppError,
  // مُصدَّرة للاختبارات
  MAX_COMMENT_LENGTH,
  COMPLETED_STATUSES,
  normalizeRating,
  normalizeComment,
  readAggregate,
  nextAggregate,
};
