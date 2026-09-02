/**
 * دورة حياة الموعد بعد الحجز: الإلغاء وإعادة الجدولة — على الخادم.
 *
 * ## لماذا هنا لا في العميل
 *
 * قبل هذا الملف كان الإلغاء يتم مباشرة من `BookingService.cancel` بمعاملة
 * Firestore يكتبها العميل بنفسه، وإعادة الجدولة لم تكن موجودة إطلاقاً. هذا
 * يعمل بقواعد الأمان الحالية، لكنه يترك قرارين مهمّين في يد العميل: متى
 * يجوز الإلغاء (المهلة، حالة الموعد)، وكيف تُنقَل خانة كاملة (تحرير القديمة
 * وحجز الجديدة) دون أن تفشل نصف العملية.
 *
 * الآن كلا القرارين يُتّخذان هنا، بنفس مبدأ `booking.js`: العميل يرسل
 * **طلباً** (أي موعد، إلى أي وقت)، والخادم يتحقق من الملكية والحالة
 * والمهلة والجدول الفعلي، وينفّذ الكتابة الذرّية.
 *
 * ## إعادة استخدام محرّك التوفّر
 *
 * كل قرار جدولي هنا — هل هذا يوم عمل؟ هل هذا الوقت ضمن مواعيد الطبيب؟ هل
 * الخانة الجديدة لها مكان؟ — يمرّ عبر `availability.js`، نفس ما يستخدمه
 * `bookAppointment` و`getAvailability`. لا يوجد هنا نسخة موازية من هذا
 * المنطق.
 *
 * ## إعادة الجدولة كمستند جديد لا كتحديث في مكانه
 *
 * معرّف الموعد دالة في (الطبيب، التاريخ، الوقت، المريض) — `SlotId.forAppointment`.
 * تغيير التاريخ أو الوقت يعني أن المعرّف الصحيح للموعد تغيّر هو الآخر، وليس
 * فقط حقوله. لذلك تكتب إعادة الجدولة مستنداً **جديداً** بالمعرّف الجديد،
 * وتُبقي القديم بحالة `Cancelled` مع `rescheduledTo` يشير إلى الجديد
 * (والجديد يحمل `rescheduledFrom` يشير إلى القديم) — فيبقى سجل العيادة
 * كاملاً، ويستفيد الطلب المكرَّر تلقائياً من نفس آلية المعرّف الحتمي التي
 * تمنع الحجز المزدوج في `booking.js`.
 */

const {
  AppError,
  fail,
  isValidDateStr,
  isValidTimeStr,
  nowForDoctor,
  minutesBetween,
  normalizeStatusKey,
  ACTIVE_STATUSES,
  CANCELLABLE_STATUSES,
  slotCapacity,
  slotDurationMinutes,
  slotIdFor,
  appointmentIdFor,
  fetchBookableDoctor,
  assertSlotWithinSchedule,
  analyzeSameDay,
  planSlotReservation,
  planSlotRelease,
} = require('./availability');
const {
  NOTIFICATION_TYPES,
  queueNotification,
  deliverPendingPush,
} = require('./notifications');
const admin = require('firebase-admin');

/** أقل مدة قبل الموعد يُسمح خلالها بالإلغاء. */
const CANCEL_DEADLINE_MINUTES = 60;

/** أقل مدة قبل الموعد يُسمح خلالها بإعادة الجدولة. */
const RESCHEDULE_DEADLINE_MINUTES = 60;

/** الحد الأقصى لنص سبب الإلغاء أو إعادة الجدولة. */
const MAX_TEXT_LENGTH = 500;

const pad = (n) => String(n).padStart(2, '0');

const ID_PATTERN = /^[A-Za-z0-9_-]{1,300}$/;

/** نص حر اختياري (سبب الإلغاء أو إعادة الجدولة) — يُقصّ ويُحدّ طوله. */
function normalizeOptionalText(raw, label) {
  if (raw === undefined || raw === null) return '';
  if (typeof raw !== 'string') {
    fail('invalid-argument', 'invalid-argument', `${label} يجب أن يكون نصاً`);
  }
  const trimmed = raw.trim().replace(/\s+/g, ' ');
  if (trimmed.length > MAX_TEXT_LENGTH) {
    fail('invalid-argument', 'invalid-argument', `${label} أطول من ${MAX_TEXT_LENGTH} حرفاً`);
  }
  return trimmed;
}

/**
 * لحظة «الآن» بمنطقة عمل طبيب هذا الموعد.
 *
 * تتسامح مع غياب مستند الطبيب (حُذف أو تعذّرت قراءته) بالسقوط إلى المنطقة
 * الافتراضية، بدل أن يفشل الإلغاء بالكامل بسبب غياب بيانات جانبية.
 */
async function nowForAppointmentDoctor(db, appointment, now) {
  try {
    const snap = await db.collection('users').doc(appointment.doctorId).get();
    return nowForDoctor(snap.exists ? snap.data() : {}, now);
  } catch (e) {
    return nowForDoctor({}, now);
  }
}

function assertValidAppointmentId(id) {
  if (typeof id !== 'string' || !ID_PATTERN.test(id)) {
    fail('invalid-argument', 'invalid-argument', 'معرّف الموعد غير صالح');
  }
}

// ===================== الإلغاء =====================

/**
 * مَن يملك إلغاء هذا الموعد — ودوره.
 *
 * المريض صاحبه، أو طبيبه. لا ثالث: لا مريض آخر، ولا طبيب آخر، ولا إدارة
 * (للإدارة إيقاف الطبيب لا إلغاء مواعيده فرداً فرداً). أي غير ذلك يُرفض
 * برسالة واحدة عامة لا تكشف إن كان الموعد موجوداً لغيره.
 *
 * المرحلة 10: قبلها كانت هذه الدالة تخدم المريض وحده، وكان الطبيب يلغي
 * بكتابة مباشرة من العميل (`BookingService.cancelAsDoctor`) — قفل الخانة
 * والموعد في معاملة يكتبها العميل بنفسه. ذلك المسار أُغلق، فانتقلت سلطة
 * الإلغاء كاملةً إلى هنا.
 *
 * @returns {'patient'|'doctor'}
 */
function cancellerRoleFor(appointment, uid) {
  if (appointment.patientId === uid) return 'patient';
  if (appointment.doctorId === uid) return 'doctor';
  return fail('permission-denied', 'permission-denied',
    'لا يمكنك إلغاء هذا الموعد');
}

/**
 * إلغاء موعد وتحرير مكانه في الخانة، بمعاملة ذرّية واحدة.
 *
 * طرفا الموعد وحدهما — مريضه أو طبيبه — يستطيعان استدعاء هذا. الفرق
 * بينهما قيد المهلة: المريض يلتزم بها، والطبيب لا (راجع `cancellerRoleFor`
 * والتعليق عند فحص المهلة). إعادة نفس الطلب على موعد أُلغي بالفعل تُعيد
 * نجاحاً هادئاً (`alreadyCancelled: true`) بدل خطأ أو عملية ثانية —
 * وهذا ما يجعل إعادة المحاولة بعد انقطاع الشبكة آمنة.
 *
 * @param {object} args
 * @param {FirebaseFirestore.Firestore} args.db
 * @param {string} args.uid  معرّف صاحب الطلب من رمز المصادقة.
 * @param {object} args.data `{ appointmentId, reason? }`.
 * @param {Date}   [args.now]
 * @param {import('firebase-admin').messaging.Messaging} [args.messaging]
 */
async function cancelAppointmentCore({
  db, uid, data, now = new Date(), messaging = admin.messaging(),
}) {
  if (!uid || typeof uid !== 'string') {
    fail('unauthenticated', 'unauthenticated', 'يجب تسجيل الدخول أولاً');
  }

  const payload = data && typeof data === 'object' ? data : {};
  const appointmentId = payload.appointmentId;
  assertValidAppointmentId(appointmentId);
  const cancelReason = normalizeOptionalText(payload.reason, 'سبب الإلغاء');

  const appointmentRef = db.collection('appointments').doc(appointmentId);

  // فحص أولي رخيص خارج المعاملة — يرفض الطلبات الواضحة الفساد بلا فتح
  // معاملة. الفحص الحاسم يتكرر **داخل** المعاملة أدناه على قراءة طازجة.
  const preSnap = await appointmentRef.get();
  if (!preSnap.exists) {
    fail('appointment-not-found', 'not-found', 'هذا الموعد غير موجود');
  }
  const pre = preSnap.data();
  const actorRole = cancellerRoleFor(pre, uid);

  const preStatus = normalizeStatusKey(pre.status);
  if (preStatus === 'cancelled' || preStatus === 'canceled') {
    return { ok: true, appointmentId, status: 'Cancelled', alreadyCancelled: true };
  }
  if (preStatus === 'completed' || preStatus === 'done') {
    fail('appointment-completed', 'failed-precondition', 'لا يمكن إلغاء موعد تم الكشف فيه بالفعل');
  }
  if (!CANCELLABLE_STATUSES.has(preStatus)) {
    fail('appointment-not-cancellable', 'failed-precondition', 'هذا الموعد لم يعد قابلاً للإلغاء');
  }

  // المهلة قيد على **المريض** وحده.
  //
  // الطبيب صاحب الوقت نفسه: طارئ، أو غياب، أو إغلاق يوم — كلّها تقع بعد
  // انقضاء المهلة بطبيعتها، والمسار المباشر الذي حلّت هذه الدالة محلّه
  // (`BookingService.cancelAsDoctor`) لم يكن يفحص وقتاً إطلاقاً. فرض مهلة
  // المريض على الطبيب هنا كان سيكسر سلوكاً قائماً ومشروعاً، لا يغلق ثغرة.
  if (actorRole === 'patient') {
    const nowInfo = await nowForAppointmentDoctor(db, pre, now);
    const minutesUntil = minutesBetween(
      nowInfo.date, nowInfo.time, pre.appointmentDate, pre.startTime);
    if (minutesUntil <= 0) {
      fail('appointment-past', 'failed-precondition', 'لا يمكن إلغاء موعد فات وقته بالفعل');
    }
    if (minutesUntil < CANCEL_DEADLINE_MINUTES) {
      fail('cancellation-deadline-passed', 'failed-precondition',
        `لا يمكن الإلغاء قبل أقل من ${CANCEL_DEADLINE_MINUTES} دقيقة من موعد الكشف`);
    }
  }

  const slotId = typeof pre.slotId === 'string' && pre.slotId ? pre.slotId : null;
  const slotRef = slotId ? db.collection('slots').doc(slotId) : null;

  const outcome = await db.runTransaction(async (tx) => {
    // كل القراءات أولاً.
    const [apptSnap, slotSnap] = await Promise.all([
      tx.get(appointmentRef),
      slotRef ? tx.get(slotRef) : Promise.resolve(null),
    ]);

    if (!apptSnap.exists) {
      fail('appointment-not-found', 'not-found', 'هذا الموعد غير موجود');
    }
    const appt = apptSnap.data();
    // يُعاد الفحص على القراءة الطازجة داخل المعاملة، لا على `pre` وحدها.
    cancellerRoleFor(appt, uid);

    const status = normalizeStatusKey(appt.status);
    if (status === 'cancelled' || status === 'canceled') {
      // طلب مكرَّر — سبق إلغاؤه بين الفحص الأولي وهذه المعاملة.
      return { duplicate: true };
    }
    if (status === 'completed' || status === 'done') {
      fail('appointment-completed', 'failed-precondition', 'لا يمكن إلغاء موعد تم الكشف فيه بالفعل');
    }
    if (!CANCELLABLE_STATUSES.has(status)) {
      fail('appointment-not-cancellable', 'failed-precondition', 'هذا الموعد لم يعد قابلاً للإلغاء');
    }

    if (slotRef && slotSnap) {
      // `appt.patientId` لا `uid`: حين يلغي الطبيب، المقعد المحجوز في
      // الخانة يخصّ المريض. تمرير `uid` هنا كان سيجعل التحرير `noop`
      // (الطبيب ليس في `patientIds`) فيبقى العدّاد مرفوعاً على موعد ملغى،
      // وتُحجب الخانة عن كل مَن بعده.
      const plan = planSlotRelease(slotSnap, appt.patientId);
      if (plan.action === 'update') {
        tx.update(slotRef, { ...plan.data, updatedAt: new Date() });
      }
    }

    tx.update(appointmentRef, {
      status: 'Cancelled',
      cancelledAt: new Date(),
      cancelledBy: uid,
      cancelledByRole: actorRole,
      cancelReason,
      updatedAt: new Date(),
    });

    // إشعارا الحدث — للمريض تأكيد، وللطبيب إبلاغ. راجع تعليق الحجز
    // (`booking.js`) عن سبب الكتابة هنا داخل المعاملة تحديداً.
    const notificationCtx = {
      doctorName: appt.doctorName, patientName: appt.patientName,
      date: appt.appointmentDate, startTime: appt.startTime,
    };
    // الطرفان يُبلَّغان أياً كان الملغي — الفرق أن المريض حين يلغي الطبيب
    // موعده يحتاج الإبلاغ أكثر لا أقل.
    const notificationRefs = [
      queueNotification(tx, db, {
        recipientId: appt.patientId, recipientRole: 'patient',
        type: NOTIFICATION_TYPES.BOOKING_CANCELLED,
        appointmentId, metadata: notificationCtx,
      }),
      queueNotification(tx, db, {
        recipientId: appt.doctorId, recipientRole: 'doctor',
        type: NOTIFICATION_TYPES.APPOINTMENT_CANCELLED,
        appointmentId, metadata: notificationCtx,
      }),
    ];

    return { duplicate: false, notificationRefs };
  });

  if (!outcome.duplicate && outcome.notificationRefs) {
    await deliverPendingPush({ db, messaging, refs: outcome.notificationRefs });
  }

  return {
    ok: true,
    appointmentId,
    status: 'Cancelled',
    alreadyCancelled: !!outcome.duplicate,
  };
}

/**
 * هل هذا الموعد الملغى بالفعل هو نتيجة طلب إعادة جدولة **مطابق** سبق أن
 * نجح بالكامل؟ إن كان كذلك تُعاد نتيجة النجاح المكرَّر بدل رفضه — نفس
 * فكرة الطلب المكرَّر في `bookAppointmentCore`، لكن عبر مستندين مرتبطين
 * لا مستند واحد.
 */
async function detectCompletedDuplicateReschedule(db, appointmentId, pre, newDate, newTime) {
  if (typeof pre.rescheduledTo !== 'string' || !pre.rescheduledTo) return null;
  const targetSnap = await db.collection('appointments').doc(pre.rescheduledTo).get();
  if (!targetSnap.exists) return null;
  const target = targetSnap.data();
  if (target.appointmentDate !== newDate || target.startTime !== newTime) return null;
  if (!ACTIVE_STATUSES.has(normalizeStatusKey(target.status))) return null;

  return {
    ok: true,
    appointmentId: pre.rescheduledTo,
    previousAppointmentId: appointmentId,
    slotId: target.slotId,
    doctorId: target.doctorId,
    appointmentDate: target.appointmentDate,
    startTime: target.startTime,
    endTime: target.endTime,
    price: target.price,
    status: 'Booked',
    duplicate: true,
    unchanged: false,
  };
}

// ===================== إعادة الجدولة =====================

/**
 * نقل موعد إلى خانة جديدة عند نفس الطبيب، بمعاملة ذرّية واحدة: إما ينجح كل
 * شيء (تحرير الخانة القديمة + حجز الجديدة + كتابة سجل الانتقال)، أو لا
 * يتغيّر شيء إطلاقاً.
 *
 * لا يجوز نقل الموعد إلى طبيب آخر من هنا — الطبيب يُقرأ من الموعد القائم
 * نفسه، لا من الطلب. نقل لطبيب آخر يعني إلغاءً وحجزاً جديداً كاملَين
 * (`cancelAppointment` ثم `bookAppointment`)، بقصد.
 *
 * @param {object} args
 * @param {FirebaseFirestore.Firestore} args.db
 * @param {string} args.uid  معرّف صاحب الطلب من رمز المصادقة.
 * @param {object} args.data `{ appointmentId, newDate, newTime, reason? }`.
 * @param {Date}   [args.now]
 * @param {import('firebase-admin').messaging.Messaging} [args.messaging]
 */
async function rescheduleAppointmentCore({
  db, uid, data, now = new Date(), messaging = admin.messaging(),
}) {
  if (!uid || typeof uid !== 'string') {
    fail('unauthenticated', 'unauthenticated', 'يجب تسجيل الدخول أولاً');
  }

  const payload = data && typeof data === 'object' ? data : {};
  const appointmentId = payload.appointmentId;
  assertValidAppointmentId(appointmentId);

  const newDate = payload.newDate;
  if (!isValidDateStr(newDate)) {
    fail('invalid-argument', 'invalid-argument', 'التاريخ الجديد غير صالح');
  }
  const newTime = payload.newTime;
  if (!isValidTimeStr(newTime)) {
    fail('invalid-argument', 'invalid-argument', 'الوقت الجديد غير صالح');
  }
  const requestedReason = payload.reason === undefined
    ? undefined
    : normalizeOptionalText(payload.reason, 'سبب الزيارة');

  const appointmentRef = db.collection('appointments').doc(appointmentId);

  // ---------- فحص أولي رخيص خارج المعاملة ----------

  const preSnap = await appointmentRef.get();
  if (!preSnap.exists) {
    fail('appointment-not-found', 'not-found', 'هذا الموعد غير موجود');
  }
  const pre = preSnap.data();
  if (pre.patientId !== uid) {
    fail('permission-denied', 'permission-denied', 'لا يمكنك تعديل موعد مريض آخر');
  }

  const preStatus = normalizeStatusKey(pre.status);
  if (preStatus === 'completed' || preStatus === 'done') {
    fail('appointment-completed', 'failed-precondition', 'لا يمكن تعديل موعد تم الكشف فيه بالفعل');
  }
  if (preStatus === 'cancelled' || preStatus === 'canceled') {
    // ربما هذا الطلب بعينه سبق تنفيذه بنجاح كامل — تحقّق قبل الرفض.
    const duplicate = await detectCompletedDuplicateReschedule(db, appointmentId, pre, newDate, newTime);
    if (duplicate) return duplicate;
    fail('appointment-not-reschedulable', 'failed-precondition', 'هذا الموعد ملغى ولا يمكن تعديل موعده');
  }
  if (!CANCELLABLE_STATUSES.has(preStatus)) {
    fail('appointment-not-reschedulable', 'failed-precondition', 'هذا الموعد لم يعد قابلاً لإعادة الجدولة');
  }

  const doctorId = pre.doctorId;
  const doctor = await fetchBookableDoctor(db, doctorId);
  const nowInfo = nowForDoctor(doctor, now);

  const minutesUntilOld = minutesBetween(nowInfo.date, nowInfo.time, pre.appointmentDate, pre.startTime);
  if (minutesUntilOld <= 0) {
    fail('appointment-past', 'failed-precondition', 'لا يمكن تعديل موعد فات وقته بالفعل');
  }
  if (minutesUntilOld < RESCHEDULE_DEADLINE_MINUTES) {
    fail('reschedule-deadline-passed', 'failed-precondition',
      `لا يمكن تعديل الموعد قبل أقل من ${RESCHEDULE_DEADLINE_MINUTES} دقيقة منه`);
  }

  // الوجهة الجديدة يجب أن تقع فعلياً ضمن جدول هذا الطبيب — نفس الدالة
  // التي يستخدمها الحجز و`getAvailability`، بلا استثناء.
  assertSlotWithinSchedule(doctor, newDate, newTime, nowInfo);

  const newSlotId = slotIdFor(doctorId, newDate, newTime);
  const newAppointmentId = appointmentIdFor(newSlotId, uid);

  // إعادة جدولة إلى **نفس** الخانة الحالية — لا شيء يتغيّر فعلياً.
  if (newAppointmentId === appointmentId) {
    return {
      ok: true,
      appointmentId,
      previousAppointmentId: appointmentId,
      slotId: newSlotId,
      doctorId,
      appointmentDate: newDate,
      startTime: newTime,
      status: 'Booked',
      unchanged: true,
      duplicate: false,
    };
  }

  const capacity = slotCapacity(doctor);
  const duration = slotDurationMinutes(doctor);
  const price = Number.isFinite(Number(doctor.price)) ? Number(doctor.price) : 0;
  const startMinutes = parseInt(newTime.slice(0, 2), 10) * 60 + parseInt(newTime.slice(3), 10);
  const endMinutes = startMinutes + duration;
  const endTime = `${pad(Math.floor(endMinutes / 60) % 24)}:${pad(endMinutes % 60)}`;

  const patientSnap = await db.collection('users').doc(uid).get();
  const patient = patientSnap.exists ? patientSnap.data() : {};

  const oldSlotId = typeof pre.slotId === 'string' && pre.slotId ? pre.slotId : null;
  const oldSlotRef = oldSlotId ? db.collection('slots').doc(oldSlotId) : null;
  const newSlotRef = db.collection('slots').doc(newSlotId);
  const newAppointmentRef = db.collection('appointments').doc(newAppointmentId);
  const sameDayQuery = db.collection('appointments')
    .where('doctorId', '==', doctorId)
    .where('appointmentDate', '==', newDate);

  const outcome = await db.runTransaction(async (tx) => {
    // ---------- كل القراءات أولاً ----------
    const [apptSnap, newApptSnap, newSlotSnap, oldSlotSnap, sameDaySnap] = await Promise.all([
      tx.get(appointmentRef),
      tx.get(newAppointmentRef),
      tx.get(newSlotRef),
      oldSlotRef ? tx.get(oldSlotRef) : Promise.resolve(null),
      tx.get(sameDayQuery),
    ]);

    if (!apptSnap.exists) {
      fail('appointment-not-found', 'not-found', 'هذا الموعد غير موجود');
    }
    const appt = apptSnap.data();
    if (appt.patientId !== uid) {
      fail('permission-denied', 'permission-denied', 'لا يمكنك تعديل موعد مريض آخر');
    }

    const status = normalizeStatusKey(appt.status);

    if (status === 'cancelled' || status === 'canceled') {
      // طلب مكرَّر لعملية إعادة جدولة سبق أن نجحت بالكامل.
      if (appt.rescheduledTo === newAppointmentId && newApptSnap.exists) {
        return { appointmentId: newAppointmentId, previousAppointmentId: appointmentId, duplicate: true };
      }
      fail('appointment-not-reschedulable', 'failed-precondition', 'هذا الموعد ملغى ولا يمكن تعديل موعده');
    }
    if (status === 'completed' || status === 'done') {
      fail('appointment-completed', 'failed-precondition', 'لا يمكن تعديل موعد تم الكشف فيه بالفعل');
    }
    if (!CANCELLABLE_STATUSES.has(status)) {
      fail('appointment-not-reschedulable', 'failed-precondition', 'هذا الموعد لم يعد قابلاً لإعادة الجدولة');
    }

    // الوجهة الجديدة محجوزة سلفاً لنفس المريض — طلب مكرَّر توقف بعد إنشاء
    // الموعد الجديد ولم يُنهِ إلغاء القديم.
    if (newApptSnap.exists) {
      const newData = newApptSnap.data();
      const newStatus = normalizeStatusKey(newData.status);
      if (newData.patientId === uid && ACTIVE_STATUSES.has(newStatus)) {
        tx.update(appointmentRef, {
          status: 'Cancelled',
          cancelledAt: new Date(),
          cancelledBy: uid,
          cancelReason: 'rescheduled',
          rescheduledTo: newAppointmentId,
          updatedAt: new Date(),
        });
        return { appointmentId: newAppointmentId, previousAppointmentId: appointmentId, duplicate: true };
      }
    }

    const { sameSlotCount, duplicateSameDay } = analyzeSameDay(sameDaySnap, {
      uid, time: newTime, excludeIds: [appointmentId, newAppointmentId],
    });
    if (duplicateSameDay) {
      fail('already-booked-same-day', 'already-exists',
        'لديك موعد آخر عند هذا الطبيب في نفس اليوم الجديد');
    }

    const plan = planSlotReservation({
      slotSnap: newSlotSnap, doctorId, date: newDate, time: newTime, uid, capacity, sameSlotCount,
    });

    let slotAlreadyIn = false;
    if (plan.action === 'create') {
      tx.set(newSlotRef, { ...plan.data, createdAt: new Date(), updatedAt: new Date() });
    } else if (plan.action === 'update') {
      tx.update(newSlotRef, { ...plan.data, updatedAt: new Date() });
    } else if (plan.alreadyIn) {
      slotAlreadyIn = true;
    }

    if (oldSlotRef && oldSlotSnap) {
      const releasePlan = planSlotRelease(oldSlotSnap, uid);
      if (releasePlan.action === 'update') {
        tx.update(oldSlotRef, { ...releasePlan.data, updatedAt: new Date() });
      }
    }

    tx.update(appointmentRef, {
      status: 'Cancelled',
      cancelledAt: new Date(),
      cancelledBy: uid,
      cancelReason: 'rescheduled',
      rescheduledTo: newAppointmentId,
      updatedAt: new Date(),
    });

    let notificationRefs = [];
    if (!slotAlreadyIn) {
      tx.set(newAppointmentRef, {
        doctorId,
        patientId: uid,
        slotId: newSlotId,
        appointmentDate: newDate,
        startTime: newTime,
        endTime,
        duration,
        status: 'Booked',
        price,
        reason: requestedReason !== undefined ? requestedReason : (appt.reason || ''),
        patientName: patient.name || appt.patientName || '',
        patientPhone: patient.phone || appt.patientPhone || '',
        doctorName: doctor.name || '',
        doctorNameEn: doctor.nameEn || '',
        doctorSpecialization: doctor.specialization || '',
        clinicLocation: doctor.clinicLocation || '',
        clinicPhone: doctor.phone || '',
        bookedVia: 'callable',
        rescheduledFrom: appointmentId,
        createdAt: new Date(),
      });

      // إشعارا الحدث — على معرّف الموعد **الجديد**، فطلب مكرَّر (يعيد إنتاج
      // نفس newAppointmentId) لا يكتب إشعاراً ثانياً بفضل نفس المعرّف الحتمي.
      const notificationCtx = {
        doctorName: doctor.name, patientName: patient.name || appt.patientName,
        date: newDate, startTime: newTime,
        oldDate: appt.appointmentDate, oldStartTime: appt.startTime,
      };
      notificationRefs = [
        queueNotification(tx, db, {
          recipientId: uid, recipientRole: 'patient',
          type: NOTIFICATION_TYPES.BOOKING_RESCHEDULED,
          appointmentId: newAppointmentId, metadata: notificationCtx,
        }),
        queueNotification(tx, db, {
          recipientId: doctorId, recipientRole: 'doctor',
          type: NOTIFICATION_TYPES.APPOINTMENT_RESCHEDULED,
          appointmentId: newAppointmentId, metadata: notificationCtx,
        }),
      ];
    }

    return {
      appointmentId: newAppointmentId, previousAppointmentId: appointmentId,
      duplicate: slotAlreadyIn, notificationRefs,
    };
  });

  if (!outcome.duplicate && outcome.notificationRefs?.length) {
    await deliverPendingPush({ db, messaging, refs: outcome.notificationRefs });
  }

  return {
    ok: true,
    appointmentId: outcome.appointmentId,
    previousAppointmentId: outcome.previousAppointmentId,
    slotId: newSlotId,
    doctorId,
    appointmentDate: newDate,
    startTime: newTime,
    endTime,
    price,
    status: 'Booked',
    duplicate: !!outcome.duplicate,
    unchanged: false,
  };
}

module.exports = {
  cancelAppointmentCore,
  rescheduleAppointmentCore,
  AppError,
  CANCEL_DEADLINE_MINUTES,
  RESCHEDULE_DEADLINE_MINUTES,
};
