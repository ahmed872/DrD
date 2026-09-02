/// ترجمة أخطاء الخادم إلى رسائل يفهمها المريض.
///
/// ## لماذا مكان واحد
///
/// كل خدمة كانت تحمل خريطتها الخاصة (`booking_service`, `review_service`)،
/// فتكرّرت الرموز نفسها بصياغات مختلفة، وكان أي رمز جديد على الخادم يظهر
/// للمستخدم كما هو: `slot-unavailable` أو `HttpsError(failed-precondition)`.
/// النص التقني في وجه مريض ليس رسالة خطأ، بل طريق مسدود.
///
/// الرسالة العربية تأتي من الخادم أصلاً وهي الأولى بالعرض؛ هذا الملف هو
/// شبكة الأمان: رمز بلا رسالة، أو انقطاع شبكة، أو استثناء غير متوقع.
library;

/// رموز الأسباب التي ترسلها دوال الخادم في `details.reason`.
///
/// مطابقة لما هو موثَّق أعلى كل دالة في `functions/index.js`. أي رمز غير
/// معروف هنا يسقط إلى [unknownMessage] بدل أن يُعرض كما هو.
const Map<String, String> _messagesByReason = {
  // ===== عام =====
  'unauthenticated': 'انتهت الجلسة، سجّل الدخول ثم حاول مرة أخرى',
  'permission-denied': 'ليس لديك صلاحية لهذا الإجراء',
  'invalid-argument': 'البيانات المُرسلة غير مكتملة أو غير صحيحة',
  'internal': 'حدث خطأ غير متوقع، حاول مرة أخرى بعد قليل',

  // ===== الطبيب =====
  'doctor-not-found': 'هذا الطبيب غير موجود',
  'doctor-not-verified': 'هذا الطبيب غير متاح للحجز حالياً',
  'doctor-disabled': 'هذا الطبيب غير متاح للحجز حالياً',
  'doctor-not-working': 'الطبيب لا يعمل في هذا اليوم، اختر يوماً آخر',

  // ===== الخانات والحجز =====
  'slot-not-found': 'هذا الوقت ليس ضمن مواعيد الطبيب',
  'slot-expired': 'لا يمكن الحجز في وقت مضى، اختر موعداً لاحقاً',
  'slot-out-of-range': 'التاريخ خارج المدى المتاح للحجز',
  'slot-closed': 'هذا الموعد مغلق حالياً',
  'slot-unavailable': 'الوقت لم يعد متاحاً، اختر موعداً آخر',
  'slot-conflict': 'تعذّر إتمام الحجز، حاول مرة أخرى',
  'already-booked-same-day':
      'لديك موعد محجوز مسبقاً عند هذا الطبيب في نفس اليوم',
  'patient-not-found': 'لم يكتمل ملفك الشخصي بعد',

  // ===== دورة حياة الموعد =====
  'appointment-not-found': 'لم نعثر على هذا الموعد',
  'appointment-completed': 'تم الكشف في هذا الموعد بالفعل',
  'appointment-not-cancellable': 'لا يمكن إلغاء هذا الموعد في حالته الحالية',
  'appointment-not-reschedulable': 'لا يمكن تعديل هذا الموعد في حالته الحالية',
  'appointment-past': 'هذا الموعد فات وقته',
  'cancellation-deadline-passed': 'انتهت مهلة الإلغاء، تواصل مع العيادة مباشرة',
  'reschedule-deadline-passed':
      'انتهت مهلة تعديل الموعد، تواصل مع العيادة مباشرة',

  // ===== المراجعات =====
  'appointment-not-completed': 'يمكنك التقييم بعد اكتمال الكشف فقط',
  'already-reviewed': 'سبق أن قيّمت هذه الزيارة',

  // ===== حذف الحساب (المرحلة 10) =====
  'confirmation-required': 'لم يصل تأكيد الحذف، حاول مرة أخرى',
  'recent-login-required': 'لأمان حسابك، سجّل الدخول من جديد ثم أعد المحاولة',
  'doctor-account': 'حسابات الأطباء تُغلق من إدارة التطبيق، تواصل معنا',

  // ===== الإدارة =====
  'application-not-found': 'لا يوجد طلب توثيق بهذا المعرّف',
  'user-not-found': 'هذا الحساب غير موجود',
  'application-rejected': 'هذا الطلب مرفوض — على المتقدّم إعادة التقديم',
  'application-not-pending': 'حالة الطلب لا تسمح بهذا الإجراء',
};

/// رسائل أخطاء الشبكة — تُميَّز عن أخطاء المنطق لأن علاجها مختلف تماماً:
/// المستخدم هنا يعيد المحاولة، لا يغيّر اختياره.
const Map<String, String> _messagesByNetworkCode = {
  'unavailable': 'تعذّر الاتصال بالخادم، تحقق من الإنترنت وحاول مرة أخرى',
  'deadline-exceeded': 'استغرق الطلب وقتاً طويلاً، حاول مرة أخرى',
  'network-request-failed': 'لا يوجد اتصال بالإنترنت',
  'resource-exhausted': 'الخدمة مزدحمة حالياً، حاول بعد قليل',
  'cancelled': 'أُلغي الطلب قبل اكتماله',
};

/// الرسالة الافتراضية حين يتعذّر التعرّف على الخطأ.
const String unknownMessage =
    'تعذّر إتمام الطلب، تأكد من اتصالك بالإنترنت وحاول مرة أخرى';

/// ترجمة أخطاء الخادم إلى نص عربي صالح للعرض.
class AppErrorMessages {
  const AppErrorMessages._();

  /// رسالة رمز السبب، أو `null` إن كان الرمز غير معروف.
  static String? forReason(String? reason) {
    if (reason == null || reason.isEmpty) return null;
    return _messagesByReason[reason] ?? _messagesByNetworkCode[reason];
  }

  /// هل هذا الرمز مشكلة اتصال لا مشكلة منطق؟
  ///
  /// الواجهة تستخدمه لتعرض «أعد المحاولة» بدل «اختر وقتاً آخر».
  static bool isNetworkIssue(String? reason) =>
      reason != null && _messagesByNetworkCode.containsKey(reason);

  /// الرسالة النهائية المعروضة.
  ///
  /// الأولوية لرسالة الخادم — فهي عربية ومكتوبة للحالة بعينها — ثم لخريطة
  /// الرموز، ثم للرسالة العامة. [serverMessage] يُتجاهل إن بدا نصاً تقنياً
  /// (رمز إنجليزي أو أثر استثناء)، فذلك ليس رسالة للمستخدم.
  static String resolve({String? reason, String? serverMessage}) {
    final trimmed = serverMessage?.trim() ?? '';
    if (trimmed.isNotEmpty && !looksTechnical(trimmed)) return trimmed;
    return forReason(reason) ?? unknownMessage;
  }

  /// هل هذا النص تقني لا يصلح لعرضه؟
  ///
  /// يلتقط ما كان يتسرّب فعلاً: أسماء الاستثناءات، أكواد HttpsError،
  /// ورموز الأسباب نفسها حين تُرسَل مكان الرسالة.
  static bool looksTechnical(String message) {
    final value = message.trim();
    if (value.isEmpty) return true;

    const technicalMarkers = [
      'Exception',
      'HttpsError',
      'FirebaseException',
      'PlatformException',
      'FirebaseFunctionsException',
      'StackTrace',
      '#0 ',
      'Error:',
      'null',
    ];
    for (final marker in technicalMarkers) {
      if (value.contains(marker)) return true;
    }

    // رمز سبب مثل `slot-unavailable`: لاتيني بالكامل وبشرطات، بلا مسافات.
    if (RegExp(r'^[a-z0-9]+(-[a-z0-9]+)+$').hasMatch(value)) return true;

    // نص لاتيني خالص في واجهة عربية — غالباً رسالة مكتبة لا رسالة منتج.
    if (!RegExp(r'[؀-ۿ]').hasMatch(value) &&
        RegExp(r'[A-Za-z]').hasMatch(value)) {
      return true;
    }

    return false;
  }
}
