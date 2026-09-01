import 'package:cloud_functions/cloud_functions.dart';

import '../../core/utils/app_logger.dart';
import '../../core/utils/error_messages.dart';

/// سبب فشل كتابة المراجعة — يُترجم لرسالة عربية في الواجهة.
enum ReviewFailure {
  /// الجلسة انتهت — يحتاج المستخدم لتسجيل الدخول من جديد.
  notSignedIn,

  /// الموعد ليس للمستخدم الحالي.
  notYourAppointment,

  /// لا موعد بهذا المعرّف.
  appointmentNotFound,

  /// الكشف لم يكتمل بعد، فلا تقييم.
  notCompleted,

  /// تقييم خارج النطاق، أو تعليق طويل، أو مدخل غير صالح.
  invalidInput,

  /// حساب الطبيب غير موجود.
  doctorNotFound,

  /// خطأ شبكة أو خطأ غير متوقع.
  unknown,
}

const Map<String, ReviewFailure> _failureByReason = {
  'unauthenticated': ReviewFailure.notSignedIn,
  'permission-denied': ReviewFailure.notYourAppointment,
  'appointment-not-found': ReviewFailure.appointmentNotFound,
  'appointment-not-completed': ReviewFailure.notCompleted,
  'invalid-argument': ReviewFailure.invalidInput,
  'doctor-not-found': ReviewFailure.doctorNotFound,
};

/// نتيجة إرسال مراجعة.
class ReviewResult {
  ReviewResult.success({
    required this.reviewId,
    required this.doctorRating,
    required this.doctorReviews,
    this.duplicate = false,
  })  : failure = null,
        message = duplicate
            ? 'سبق أن قيّمت هذه الزيارة، شكراً لك'
            : 'تم إرسال تقييمك بنجاح، شكراً لك';

  const ReviewResult.failed(this.failure, this.message)
      : reviewId = null,
        doctorRating = null,
        doctorReviews = null,
        duplicate = false;

  final String? reviewId;
  final double? doctorRating;
  final int? doctorReviews;
  final ReviewFailure? failure;
  final String message;

  /// الطلب وصل الخادم مرتين (ضغطة مزدوجة أو إعادة محاولة) والمراجعة قائمة.
  final bool duplicate;

  bool get isSuccess => failure == null;
}

/// أهلية تقييم موعد — قرار الخادم، لا استنتاج من حالة الموعد في الواجهة.
class ReviewEligibility {
  const ReviewEligibility({
    required this.eligible,
    required this.alreadyReviewed,
    this.reason,
    this.rating,
    this.comment,
  });

  /// الافتراض الآمن عند تعذّر السؤال: لا نعرض زر تقييم قد يفشل.
  const ReviewEligibility.unknown()
      : eligible = false,
        alreadyReviewed = false,
        reason = null,
        rating = null,
        comment = null;

  final bool eligible;
  final bool alreadyReviewed;
  final String? reason;

  /// التقييم السابق إن كانت الزيارة مُقيَّمة بالفعل.
  final int? rating;
  final String? comment;
}

/// المراجعات والتقييمات — غلاف رفيع حول دوال الخادم.
///
/// لا يحسب هذا الملف متوسطاً ولا يكتب مستند مراجعة ولا يقرّر أهلية. كان
/// التطبيق يفعل الثلاثة (راجع `functions/reviews.js` لشرح ما كان يحدث ولماذا
/// انتقل)، والآن يرسل طلباً ويعرض النتيجة.
class ReviewService {
  ReviewService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// إرسال مراجعة عن زيارة مكتملة.
  ///
  /// [rating] عدد صحيح من 1 إلى 5. الطبيب والمريض وتاريخ الزيارة كلها
  /// يستخرجها الخادم من مستند الموعد — لا تُرسل من هنا.
  Future<ReviewResult> submit({
    required String appointmentId,
    required int rating,
    String? comment,
  }) async {
    try {
      final callable = _functions.httpsCallable('createReview');
      final response = await callable.call<Object?>({
        'appointmentId': appointmentId,
        'rating': rating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      });

      final data = Map<String, dynamic>.from(response.data as Map);
      final result = ReviewResult.success(
        reviewId: (data['reviewId'] ?? '').toString(),
        doctorRating: (data['doctorRating'] as num?)?.toDouble(),
        doctorReviews: (data['doctorReviews'] as num?)?.toInt(),
        duplicate: data['duplicate'] == true,
      );
      AppLogger.success('تم إرسال التقييم: ${result.reviewId}');
      return result;
    } on FirebaseFunctionsException catch (e) {
      final reasonCode = _reasonOf(e);
      final failure = _failureByReason[reasonCode] ?? ReviewFailure.unknown;
      // الرسالة تمرّ عبر المصدر المركزي، فلا يصل المستخدم رمز خطأ ولا نص
      // استثناء مهما أرسل الخادم.
      final message = AppErrorMessages.resolve(
        reason: reasonCode,
        serverMessage: e.message,
      );

      AppLogger.warning('فشل إرسال التقييم ($reasonCode): $message');
      return ReviewResult.failed(failure, message);
    } catch (e, s) {
      AppLogger.error('خطأ غير متوقع أثناء إرسال التقييم', e, s);
      return const ReviewResult.failed(ReviewFailure.unknown, unknownMessage);
    }
  }

  /// هل يمكن تقييم هذا الموعد؟
  ///
  /// عند تعذّر السؤال (شبكة أو خطأ) تُرجَع [ReviewEligibility.unknown] —
  /// أي لا يظهر زر التقييم. إخفاء زر متاح أهون من عرض زر يفشل عند الضغط.
  Future<ReviewEligibility> checkEligibility(String appointmentId) async {
    try {
      final callable = _functions.httpsCallable('getReviewEligibility');
      final response = await callable.call<Object?>({
        'appointmentId': appointmentId,
      });

      final data = Map<String, dynamic>.from(response.data as Map);
      return ReviewEligibility(
        eligible: data['eligible'] == true,
        alreadyReviewed: data['alreadyReviewed'] == true,
        reason: data['reason']?.toString(),
        rating: (data['rating'] as num?)?.toInt(),
        comment: data['comment']?.toString(),
      );
    } catch (e) {
      AppLogger.warning('تعذّر التحقق من أهلية التقييم: $e');
      return const ReviewEligibility.unknown();
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
}
