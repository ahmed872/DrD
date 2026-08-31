import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/constants/appointment_status.dart';
import '../../core/utils/app_logger.dart';
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

const Map<BookingFailure, String> _fallbackMessages = {
  BookingFailure.slotTaken: 'للأسف تم حجز هذا الموعد للتو، اختر وقتاً آخر',
  BookingFailure.alreadyBookedBySamePatient: 'أنت حاجز هذا الموعد بالفعل',
  BookingFailure.duplicateSameDay:
      'لديك موعد محجوز مسبقاً عند هذا الطبيب في نفس اليوم',
  BookingFailure.slotInThePast: 'لا يمكن الحجز في هذا الوقت، اختر موعداً آخر',
  BookingFailure.doctorUnavailable: 'هذا الطبيب غير متاح للحجز حالياً',
  BookingFailure.notSignedIn: 'انتهت الجلسة، سجّل الدخول ثم حاول مرة أخرى',
  BookingFailure.invalidRequest: 'تعذّر إتمام الحجز، حدّث التطبيق وحاول مجدداً',
  BookingFailure.unknown:
      'تعذّر إتمام الحجز، تأكد من اتصالك بالإنترنت وحاول مرة أخرى',
};

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

  CollectionReference<Map<String, dynamic>> get _slots =>
      _db.collection('slots');
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
      final serverMessage = (e.message ?? '').trim();
      final message = serverMessage.isNotEmpty
          ? serverMessage
          : _fallbackMessages[failure]!;

      AppLogger.warning('فشل الحجز ($reasonCode): $message');
      return BookingResult.failed(failure, message);
    } catch (e, s) {
      AppLogger.error('خطأ غير متوقع أثناء الحجز', e, s);
      return BookingResult.failed(
        BookingFailure.unknown,
        _fallbackMessages[BookingFailure.unknown]!,
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

  /// إلغاء موعد وتحرير مكانه في الخانة، في معاملة واحدة.
  ///
  /// بدون هذا، الإلغاء كان يترك العدّاد مرفوعاً فتبقى الخانة تبدو ممتلئة
  /// للأبد رغم أن أحداً لا يستخدمها.
  Future<bool> cancel({required String appointmentId}) async {
    try {
      await _db.runTransaction<void>((transaction) async {
        final appointmentRef = _appointments.doc(appointmentId);
        final appointmentSnapshot = await transaction.get(appointmentRef);

        if (!appointmentSnapshot.exists) return;

        final data = appointmentSnapshot.data()!;
        final slotId = data['slotId'] as String?;
        // يُقرأ من المستند نفسه بدل تمريره من الواجهة: الطبيب يُلغي مواعيد
        // مرضاه، ولا يملك معرّف المريض في يده عند الضغط على زر الإلغاء.
        final patientId = (data['patientId'] ?? '').toString();

        // المواعيد القديمة لا تحمل `slotId`؛ نلغيها بدون لمس أي قفل.
        if (slotId != null && slotId.isNotEmpty) {
          final slotRef = _slots.doc(slotId);
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
        });
      });
      return true;
    } catch (e, s) {
      AppLogger.error('فشل إلغاء الموعد', e, s);
      return false;
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
