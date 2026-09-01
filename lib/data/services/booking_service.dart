import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/constants/appointment_status.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/slot_id.dart';

/// سبب فشل الحجز — يُترجم لرسالة عربية في الواجهة.
enum BookingFailure {
  /// الخانة امتلأت بينما كان المريض يؤكّد.
  slotTaken,

  /// المريض حاجز نفس الخانة بالفعل.
  alreadyBookedBySamePatient,

  /// المريض عنده موعد آخر عند نفس الطبيب في نفس اليوم.
  duplicateSameDay,

  /// الوقت المطلوب مضى بالفعل، أو خارج المدى المسموح.
  slotInThePast,

  /// الطبيب غير متاح: غير موثَّق، أو موقوف، أو لا يعمل في هذا الوقت.
  doctorUnavailable,

  /// الجلسة انتهت — يحتاج المستخدم لتسجيل الدخول من جديد.
  notSignedIn,

  /// طلب غير صالح — لا يحدث في الاستخدام الطبيعي.
  invalidRequest,

  /// خطأ شبكة أو خطأ غير متوقع.
  unknown,
}

/// ترجمة رمز السبب القادم من الخادم إلى تصنيف تعرفه الواجهة.
///
/// الرموز مُعرَّفة في `functions/index.js`، والرسالة العربية تأتي من الخادم
/// أيضاً؛ هذه الخريطة للتصنيف وللرسالة الاحتياطية عند انقطاع غير متوقع.
const Map<String, BookingFailure> _failureByReason = {
  'unauthenticated': BookingFailure.notSignedIn,
  'permission-denied': BookingFailure.invalidRequest,
  'invalid-argument': BookingFailure.invalidRequest,
  'doctor-not-found': BookingFailure.doctorUnavailable,
  'doctor-not-verified': BookingFailure.doctorUnavailable,
  'doctor-disabled': BookingFailure.doctorUnavailable,
  'doctor-not-working': BookingFailure.doctorUnavailable,
  'slot-not-found': BookingFailure.doctorUnavailable,
  'slot-closed': BookingFailure.doctorUnavailable,
  'slot-conflict': BookingFailure.unknown,
  'slot-expired': BookingFailure.slotInThePast,
  'slot-out-of-range': BookingFailure.slotInThePast,
  'slot-unavailable': BookingFailure.slotTaken,
  'already-booked-same-day': BookingFailure.duplicateSameDay,
  'patient-not-found': BookingFailure.invalidRequest,
};

/// سبب فشل الإلغاء أو إعادة الجدولة — يُترجم لرسالة عربية في الواجهة.
enum LifecycleFailure {
  /// لا موعد بهذا المعرّف.
  appointmentNotFound,

  /// الموعد ليس ملكاً لصاحب الطلب.
  notOwner,

  /// الموعد تم الكشف فيه بالفعل.
  alreadyCompleted,

  /// حالة الموعد لا تسمح بالعملية (ملغى، لم يحضر، ...).
  notEligible,

  /// فات وقت الموعد.
  appointmentPast,

  /// أقرب من المهلة المسموحة قبل الموعد.
  deadlinePassed,

  /// الوجهة الجديدة (طبيب/وقت) غير متاحة — نفس أسباب فشل الحجز.
  destinationUnavailable,

  /// موعد آخر قائم لنفس اليوم عند نفس الطبيب.
  duplicateSameDay,

  /// الجلسة انتهت.
  notSignedIn,

  /// طلب غير صالح.
  invalidRequest,

  /// خطأ شبكة أو غير متوقع.
  unknown,
}

const Map<String, LifecycleFailure> _lifecycleFailureByReason = {
  'unauthenticated': LifecycleFailure.notSignedIn,
  'invalid-argument': LifecycleFailure.invalidRequest,
  'appointment-not-found': LifecycleFailure.appointmentNotFound,
  'permission-denied': LifecycleFailure.notOwner,
  'appointment-completed': LifecycleFailure.alreadyCompleted,
  'appointment-not-cancellable': LifecycleFailure.notEligible,
  'appointment-not-reschedulable': LifecycleFailure.notEligible,
  'appointment-past': LifecycleFailure.appointmentPast,
  'cancellation-deadline-passed': LifecycleFailure.deadlinePassed,
  'reschedule-deadline-passed': LifecycleFailure.deadlinePassed,
  'doctor-not-found': LifecycleFailure.destinationUnavailable,
  'doctor-not-verified': LifecycleFailure.destinationUnavailable,
  'doctor-disabled': LifecycleFailure.destinationUnavailable,
  'doctor-not-working': LifecycleFailure.destinationUnavailable,
  'slot-not-found': LifecycleFailure.destinationUnavailable,
  'slot-closed': LifecycleFailure.destinationUnavailable,
  'slot-expired': LifecycleFailure.destinationUnavailable,
  'slot-out-of-range': LifecycleFailure.destinationUnavailable,
  'slot-unavailable': LifecycleFailure.destinationUnavailable,
  'already-booked-same-day': LifecycleFailure.duplicateSameDay,
};

/// نتيجة محاولة الإلغاء.
class CancelResult {
  const CancelResult.success({this.alreadyCancelled = false})
      : failure = null,
        message = alreadyCancelled
            ? 'هذا الموعد ملغى بالفعل'
            : 'تم إلغاء الموعد بنجاح';

  const CancelResult.failed(this.failure, this.message)
      : alreadyCancelled = false;

  final LifecycleFailure? failure;
  final String message;
  final bool alreadyCancelled;

  bool get isSuccess => failure == null;
}

/// نتيجة محاولة إعادة الجدولة.
class RescheduleResult {
  const RescheduleResult.success(
    this.appointmentId, {
    this.unchanged = false,
    this.duplicate = false,
  })  : failure = null,
        message = unchanged ? 'الموعد كما هو بالفعل' : 'تم تعديل موعدك بنجاح';

  const RescheduleResult.failed(this.failure, this.message)
      : appointmentId = null,
        unchanged = false,
        duplicate = false;

  final String? appointmentId;
  final LifecycleFailure? failure;
  final String message;
  final bool unchanged;
  final bool duplicate;

  bool get isSuccess => failure == null;
}

/// نتيجة محاولة الحجز.
class BookingResult {
  BookingResult.success(this.appointmentId, {this.duplicate = false})
      : failure = null,
        message = duplicate
            ? 'هذا الموعد محجوز لك بالفعل'
            : 'تم حجز الموعد بنجاح، ألف سلامة عليك';

  const BookingResult.failed(this.failure, this.message)
      : appointmentId = null,
        duplicate = false;

  final String? appointmentId;
  final BookingFailure? failure;
  final String message;

  /// الطلب وصل الخادم مرتين (ضغطة مزدوجة أو إعادة محاولة) وأُعيد نفس الموعد.
  final bool duplicate;

  bool get isSuccess => failure == null;
}

/// إرسال طلبات الحجز إلى الخادم.
///
/// ## أين صار قرار الحجز
///
/// كان هذا الملف يتّخذ القرار كاملاً: يقرأ عدّاد الخانة، ويقارنه بسعة أرسلها
/// العميل، ويكتب مستند الموعد بحقول أرسلها العميل أيضاً — بما فيها السعر
/// واسم الطبيب واسم المريض ورقمه. القواعد كانت تحرس ما تستطيع (السعة،
/// التوثيق، ربط الموعد بقفل) لكنها لا تعرف كم يساوي الكشف، ولا أن الساعة
/// الثالثة فجراً ليست ضمن دوام الطبيب.
///
/// الآن القرار كله في `bookAppointment` (راجع `functions/booking.js`):
/// العميل يرسل **طلباً** — أي طبيب، أي يوم، أي ساعة، ولماذا — والخادم يستخرج
/// الباقي من Firestore وينفّذ نفس المعاملة الذرّية التي كانت هنا.
///
/// ما بقي في هذا الملف: الإلغاء، وقراءات العرض التي تحتاجها شاشة الحجز.
class BookingService {
  BookingService({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _db = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _appointments =>
      _db.collection('appointments');

  /// طلب حجز خانة زمنية.
  ///
  /// لا تُرسَل هنا سعة ولا سعر ولا أسماء: الخادم يستخرجها من مستند الطبيب
  /// ومستند المريض. [time] يُقبل بأي صيغة تعرضها الواجهة ويُوحَّد قبل الإرسال.
  ///
  /// إعادة إرسال نفس الطلب (ضغطة مزدوجة أو إعادة محاولة من الشبكة) تُرجع نفس
  /// الموعد بـ [BookingResult.duplicate] بدل إنشاء حجز ثانٍ.
  Future<BookingResult> book({
    required String doctorId,
    required DateTime date,
    required String time,
    String? reason,
  }) async {
    try {
      final callable = _functions.httpsCallable('bookAppointment');
      final response = await callable.call<Object?>({
        'doctorId': doctorId,
        'date': SlotId.formatDate(date),
        'time': SlotId.normalizeTime(time),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

      final data = Map<String, dynamic>.from(response.data as Map);
      final appointmentId = (data['appointmentId'] ?? '').toString();
      final duplicate = data['duplicate'] == true;

      AppLogger.success('تم الحجز: $appointmentId');
      return BookingResult.success(appointmentId, duplicate: duplicate);
    } on FirebaseFunctionsException catch (e) {
      final reasonCode = _reasonOf(e);
      final failure = _failureByReason[reasonCode] ?? BookingFailure.unknown;
      // رسالة الخادم عربية وجاهزة للعرض؛ الاحتياطية لانقطاع غير متوقع.
      final message = AppErrorMessages.resolve(
        reason: reasonCode,
        serverMessage: e.message,
      );

      AppLogger.warning('فشل الحجز ($reasonCode): $message');
      return BookingResult.failed(failure, message);
    } catch (e, s) {
      AppLogger.error('خطأ غير متوقع أثناء الحجز', e, s);
      return BookingResult.failed(
        BookingFailure.unknown,
        unknownMessage,
      );
    }
  }

  /// رمز السبب الذي يرسله الخادم في `details.reason`.
  String _reasonOf(FirebaseFunctionsException e) {
    final details = e.details;
    if (details is Map && details['reason'] != null) {
      return details['reason'].toString();
    }
    return e.code;
  }

  /// إلغاء موعد وتحرير مكانه في الخانة — عبر الخادم لا بكتابة مباشرة.
  ///
  /// ## أين صار قرار الإلغاء
  ///
  /// كان هذا الملف يكتب الإلغاء وتحرير الخانة مباشرة بمعاملة من العميل. هذا
  /// يعمل، لكنه يترك قرارين في يد العميل: متى يجوز الإلغاء (حالة الموعد،
  /// المهلة قبل الكشف)، وهل العدّاد يبقى سليماً عند طلبات متكرّرة أو
  /// متزامنة. الآن `cancelAppointment` (راجع `functions/lifecycle.js`)
  /// تتحقق من كل هذا على الخادم، وتنفّذ نفس التحرير الذرّي.
  ///
  /// إعادة إرسال نفس الطلب بعد إلغاء ناجح لا تفشل ولا تُنقص العدّاد ثانية —
  /// تُعاد نتيجة ناجحة بـ [CancelResult.alreadyCancelled].
  Future<CancelResult> cancel({
    required String appointmentId,
    String? reason,
  }) async {
    try {
      final callable = _functions.httpsCallable('cancelAppointment');
      final response = await callable.call<Object?>({
        'appointmentId': appointmentId,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

      final data = Map<String, dynamic>.from(response.data as Map);
      final alreadyCancelled = data['alreadyCancelled'] == true;

      AppLogger.success('تم إلغاء الموعد: $appointmentId');
      return CancelResult.success(alreadyCancelled: alreadyCancelled);
    } on FirebaseFunctionsException catch (e) {
      final reasonCode = _reasonOf(e);
      final failure =
          _lifecycleFailureByReason[reasonCode] ?? LifecycleFailure.unknown;
      final message = AppErrorMessages.resolve(
        reason: reasonCode,
        serverMessage: e.message,
      );

      AppLogger.warning('فشل إلغاء الموعد ($reasonCode): $message');
      return CancelResult.failed(failure, message);
    } catch (e, s) {
      AppLogger.error('خطأ غير متوقع أثناء إلغاء الموعد', e, s);
      return CancelResult.failed(
        LifecycleFailure.unknown,
        unknownMessage,
      );
    }
  }

  /// إلغاء الطبيب لموعد أحد مرضاه من شاشة جدوله.
  ///
  /// `cancelAppointment` على الخادم (أعلاه) للمريض وحده — راجع توثيقها.
  /// إلغاء الطبيب يبقى بالمسار المباشر القديم عمداً: قواعد الأمان تمنحه
  /// حرية إدارة خانات عيادته ومواعيدها أصلاً (`isUser(doctorId)` على
  /// `slots`، و`isDoctorOwner()` على `appointments`)، بلا حاجة لمهلة أو
  /// تحقق إضافي كالذي يحتاجه إلغاء المريض. هذا خارج نطاق المرحلة 1ب.
  Future<bool> cancelAsDoctor({required String appointmentId}) async {
    try {
      await _db.runTransaction<void>((transaction) async {
        final appointmentRef = _appointments.doc(appointmentId);
        final appointmentSnapshot = await transaction.get(appointmentRef);

        if (!appointmentSnapshot.exists) return;

        final data = appointmentSnapshot.data()!;
        final slotId = data['slotId'] as String?;
        final patientId = (data['patientId'] ?? '').toString();

        // المواعيد القديمة لا تحمل `slotId`؛ نلغيها بدون لمس أي قفل.
        if (slotId != null && slotId.isNotEmpty) {
          final slotRef = _db.collection('slots').doc(slotId);
          final slotSnapshot = await transaction.get(slotRef);
          if (slotSnapshot.exists) {
            final bookedCount =
                (slotSnapshot.data()!['bookedCount'] as num?)?.toInt() ?? 0;
            transaction.update(slotRef, {
              // `clamp` يحمي من عدّاد سالب لو تكرّر الإلغاء لأي سبب.
              'bookedCount': (bookedCount - 1).clamp(0, 1 << 30),
              'patientIds': FieldValue.arrayRemove([patientId]),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }

        transaction.update(appointmentRef, {
          'status': AppointmentStatus.cancelled.wireValue,
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': 'doctor',
        });
      });
      return true;
    } catch (e, s) {
      AppLogger.error('فشل إلغاء الطبيب للموعد', e, s);
      return false;
    }
  }

  /// نقل موعد إلى خانة جديدة عند **نفس الطبيب** — عبر الخادم، بمعاملة
  /// واحدة (تحرير القديمة + حجز الجديدة). راجع `functions/lifecycle.js`.
  ///
  /// طلب مكرَّر بنفس المعطيات يُعيد نفس النتيجة الناجحة بـ
  /// [RescheduleResult.duplicate] بدل تنفيذ نقل ثانٍ. طلب إلى نفس الخانة
  /// الحالية يُعيد [RescheduleResult.unchanged] بلا أي تعديل.
  Future<RescheduleResult> reschedule({
    required String appointmentId,
    required DateTime newDate,
    required String newTime,
    String? reason,
  }) async {
    try {
      final callable = _functions.httpsCallable('rescheduleAppointment');
      final response = await callable.call<Object?>({
        'appointmentId': appointmentId,
        'newDate': SlotId.formatDate(newDate),
        'newTime': SlotId.normalizeTime(newTime),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

      final data = Map<String, dynamic>.from(response.data as Map);
      final newAppointmentId = (data['appointmentId'] ?? '').toString();
      final unchanged = data['unchanged'] == true;
      final duplicate = data['duplicate'] == true;

      AppLogger.success('تم تعديل الموعد: $appointmentId → $newAppointmentId');
      return RescheduleResult.success(
        newAppointmentId,
        unchanged: unchanged,
        duplicate: duplicate,
      );
    } on FirebaseFunctionsException catch (e) {
      final reasonCode = _reasonOf(e);
      final failure =
          _lifecycleFailureByReason[reasonCode] ?? LifecycleFailure.unknown;
      final message = AppErrorMessages.resolve(
        reason: reasonCode,
        serverMessage: e.message,
      );

      AppLogger.warning('فشل تعديل الموعد ($reasonCode): $message');
      return RescheduleResult.failed(failure, message);
    } catch (e, s) {
      AppLogger.error('خطأ غير متوقع أثناء تعديل الموعد', e, s);
      return RescheduleResult.failed(
        LifecycleFailure.unknown,
        unknownMessage,
      );
    }
  }

  /// عدد الحجوزات القائمة لكل خانة زمنية عند طبيب في يوم محدد.
  ///
  /// يُرجع عدداً وليس مجرد "محجوز/متاح" لأن نظام المجموعات يسمح بعدة مرضى في
  /// نفس الخانة، والواجهة تحتاج أن تعرض "٣ من ٤".
  ///
  /// يقرأ من `appointments` وليس من `slots` عمداً: مجموعة `slots` حديثة، بينما
  /// `appointments` تحتوي على كل المواعيد بما فيها ما حُجز قبل هذا التحديث.
  Future<Map<String, int>> bookedCountsFor({
    required String doctorId,
    required DateTime date,
  }) async {
    final snapshot = await _appointments
        .where('doctorId', isEqualTo: doctorId)
        .where('appointmentDate', isEqualTo: SlotId.formatDate(date))
        .get();

    final counts = <String, int>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (!AppointmentStatus.occupying.contains(
        AppointmentStatus.parse(data['status']),
      )) {
        continue;
      }
      final raw = data['startTime'] ?? data['time'];
      if (raw == null) continue;
      final time = SlotId.normalizeTime(raw.toString());
      counts[time] = (counts[time] ?? 0) + 1;
    }
    return counts;
  }

  /// هل للمريض موعد قائم عند هذا الطبيب في هذا اليوم؟
  Future<bool> hasAppointmentOnDate({
    required String doctorId,
    required String patientId,
    required DateTime date,
  }) async {
    final snapshot = await _appointments
        .where('doctorId', isEqualTo: doctorId)
        .where('patientId', isEqualTo: patientId)
        .where('appointmentDate', isEqualTo: SlotId.formatDate(date))
        .get();

    return snapshot.docs.any(
      (doc) => AppointmentStatus.parse(doc.data()['status']).isActive,
    );
  }
}
