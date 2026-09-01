import 'package:cloud_functions/cloud_functions.dart';

import '../../core/utils/app_logger.dart';

/// سبب فشل إجراء إداري — يُترجم لرسالة عربية في الواجهة.
enum AdminActionFailure {
  /// المستخدم ليس admin (أو لم يُحدَّث رمزه بعد منح الصلاحية).
  notAdmin,

  /// لا يوجد طلب أو حساب بهذا المعرّف.
  notFound,

  /// حالة الطلب/الحساب لا تسمح بهذا الإجراء الآن.
  invalidState,

  /// مدخلات غير صالحة (سبب مفقود، معرّف غير صالح، ...).
  invalidRequest,

  /// الجلسة انتهت.
  notSignedIn,

  /// خطأ شبكة أو غير متوقع.
  unknown,
}

const Map<String, AdminActionFailure> _failureByReason = {
  'unauthenticated': AdminActionFailure.notSignedIn,
  'permission-denied': AdminActionFailure.notAdmin,
  'invalid-argument': AdminActionFailure.invalidRequest,
  'application-not-found': AdminActionFailure.notFound,
  'user-not-found': AdminActionFailure.notFound,
  'application-rejected': AdminActionFailure.invalidState,
  'application-approved': AdminActionFailure.invalidState,
  'application-not-pending': AdminActionFailure.invalidState,
  'doctor-not-active': AdminActionFailure.invalidState,
  'not-a-doctor': AdminActionFailure.invalidState,
};

const Map<AdminActionFailure, String> _fallbackMessages = {
  AdminActionFailure.notAdmin:
      'هذا الإجراء متاح للإدارة فقط — إن مُنحت الصلاحية للتو، حدّث الصلاحيات من شاشة حسابك',
  AdminActionFailure.notFound: 'لا يوجد طلب أو حساب بهذا المعرّف',
  AdminActionFailure.invalidState: 'الحالة الحالية لا تسمح بهذا الإجراء',
  AdminActionFailure.invalidRequest: 'طلب غير صالح',
  AdminActionFailure.notSignedIn: 'انتهت الجلسة، سجّل الدخول ثم حاول مرة أخرى',
  AdminActionFailure.unknown: 'تعذّر إتمام الإجراء، تأكد من اتصالك بالإنترنت',
};

/// نتيجة إجراء إداري (قبول/رفض/إيقاف/استعادة طبيب).
class AdminActionResult {
  const AdminActionResult.success(this.message, {this.wasNoop = false})
      : failure = null;

  const AdminActionResult.failed(this.failure, this.message) : wasNoop = false;

  final AdminActionFailure? failure;
  final String message;

  /// الإجراء لم يُنفَّذ لأن الحالة كانت مطابقة له بالفعل (طلب مكرَّر) — نجاح
  /// هادئ، لا خطأ.
  final bool wasNoop;

  bool get isSuccess => failure == null;
}

/// إرسال إجراءات الإدارة (توثيق الأطباء) إلى الدوال السحابية.
///
/// لا كتابة مباشرة على `users` أو `doctorApplications` من هذا الملف
/// لتغيير الحالة — `firestore.rules` تمنعها أصلاً لأي عميل بما فيه مدير؛
/// الاعتماد/الرفض/الإيقاف/الاستعادة تمر حصراً بالدوال السحابية التي تتحقق
/// من `admin` كـ Custom Claim موقَّع. راجع `functions/admin.js`.
class AdminService {
  AdminService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<AdminActionResult> _call(
    String name,
    Map<String, dynamic> data, {
    required String Function(Map<String, dynamic> data) onSuccess,
    required bool Function(Map<String, dynamic> data) isNoop,
  }) async {
    try {
      final callable = _functions.httpsCallable(name);
      final response = await callable.call<Object?>(data);
      final result = Map<String, dynamic>.from(response.data as Map);
      AppLogger.success('$name نجح: $result');
      return AdminActionResult.success(
        onSuccess(result),
        wasNoop: isNoop(result),
      );
    } on FirebaseFunctionsException catch (e) {
      final reasonCode = _reasonOf(e);
      final failure =
          _failureByReason[reasonCode] ?? AdminActionFailure.unknown;
      final serverMessage = (e.message ?? '').trim();
      final message = serverMessage.isNotEmpty
          ? serverMessage
          : _fallbackMessages[failure]!;
      AppLogger.warning('فشل $name ($reasonCode): $message');
      return AdminActionResult.failed(failure, message);
    } catch (e, s) {
      AppLogger.error('خطأ غير متوقع في $name', e, s);
      return AdminActionResult.failed(
        AdminActionFailure.unknown,
        _fallbackMessages[AdminActionFailure.unknown]!,
      );
    }
  }

  String _reasonOf(FirebaseFunctionsException e) {
    final details = e.details;
    if (details is Map && details['reason'] != null) {
      return details['reason'].toString();
    }
    return e.code;
  }

  /// قبول طلب توثيق — يرقّي المتقدّم إلى طبيب نشط وقابل للحجز فوراً.
  Future<AdminActionResult> approveDoctor(String applicantUid) => _call(
        'approveDoctor',
        {'uid': applicantUid},
        onSuccess: (r) => r['alreadyApproved'] == true
            ? 'هذا الطلب مقبول بالفعل'
            : 'تم قبول الطلب — الطبيب أصبح قابلاً للحجز',
        isNoop: (r) => r['alreadyApproved'] == true,
      );

  /// رفض طلب توثيق — لا يمسّ حساب المتقدّم، ويمكنه إعادة التقديم لاحقاً.
  Future<AdminActionResult> rejectDoctor(String applicantUid, String reason) =>
      _call(
        'rejectDoctor',
        {'uid': applicantUid, 'reason': reason},
        onSuccess: (r) => r['alreadyRejected'] == true
            ? 'هذا الطلب مرفوض بالفعل'
            : 'تم رفض الطلب',
        isNoop: (r) => r['alreadyRejected'] == true,
      );

  /// إيقاف طبيب موثَّق مؤقتاً — لا يقبل حجوزات جديدة، دون فقدان توثيقه.
  Future<AdminActionResult> suspendDoctor(String doctorUid, String reason) =>
      _call(
        'suspendDoctor',
        {'uid': doctorUid, 'reason': reason},
        onSuccess: (r) => r['alreadySuspended'] == true
            ? 'هذا الطبيب موقوف بالفعل'
            : 'تم إيقاف الطبيب',
        isNoop: (r) => r['alreadySuspended'] == true,
      );

  /// استعادة طبيب موقوف إلى النشاط.
  Future<AdminActionResult> restoreDoctor(String doctorUid) => _call(
        'restoreDoctor',
        {'uid': doctorUid},
        onSuccess: (r) => r['alreadyActive'] == true
            ? 'هذا الطبيب نشط بالفعل'
            : 'تمت استعادة الطبيب',
        isNoop: (r) => r['alreadyActive'] == true,
      );
}
