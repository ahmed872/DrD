import 'package:cloud_functions/cloud_functions.dart';

import '../../core/utils/app_logger.dart';
import '../../core/utils/error_messages.dart';

/// سبب فشل حذف الحساب — يُترجم لتصرّف مختلف في الواجهة، لا لرسالة فقط.
enum DeleteAccountFailure {
  /// الجلسة انتهت — يعود للمستخدم شاشة الدخول.
  notSignedIn,

  /// تسجيل الدخول قديم. الواجهة تطلب إعادة الدخول ثم المحاولة من جديد.
  needsRecentLogin,

  /// حساب طبيب — يُغلق من الإدارة لا ذاتياً.
  doctorAccount,

  /// طلب بلا تأكيد (لا يقع من الواجهة، لكنه جزء من العقد).
  needsConfirmation,

  /// شبكة أو خطأ غير متوقع.
  unknown,
}

/// عقد أسباب `deleteAccount` كما تُصدرها `functions/account.js`.
///
/// مكشوفة للاختبار عمداً: الربط بين رمز الخادم وتصرّف الواجهة هو ما ينكسر
/// بصمت حين يتغيّر أحد الطرفين وحده.
const Map<String, DeleteAccountFailure> deleteAccountFailureByReason = {
  'unauthenticated': DeleteAccountFailure.notSignedIn,
  'recent-login-required': DeleteAccountFailure.needsRecentLogin,
  'doctor-account': DeleteAccountFailure.doctorAccount,
  'confirmation-required': DeleteAccountFailure.needsConfirmation,
};

/// سبب الفشل المقابل لرمز الخادم — وأي رمز غير معروف يسقط إلى [unknown]
/// لا إلى تصرّف خاطئ.
DeleteAccountFailure deleteAccountFailureFor(String? reason) =>
    deleteAccountFailureByReason[reason] ?? DeleteAccountFailure.unknown;

/// نتيجة محاولة حذف الحساب.
class DeleteAccountResult {
  const DeleteAccountResult.success({this.cancelledAppointments = 0})
      : failure = null,
        message = 'تم حذف حسابك وكل بياناتك الشخصية';

  const DeleteAccountResult.failed(this.failure, this.message)
      : cancelledAppointments = 0;

  final DeleteAccountFailure? failure;
  final String message;

  /// كم موعداً قائماً أُلغي ضمن الحذف — تعرضه الواجهة في رسالة التأكيد.
  final int cancelledAppointments;

  bool get isSuccess => failure == null;

  /// هل يكفي إعادة تسجيل الدخول ثم المحاولة؟
  bool get needsRecentLogin => failure == DeleteAccountFailure.needsRecentLogin;
}

/// حذف الحساب — عبر الدالة السحابية وحدها.
///
/// لا يستدعي `FirebaseAuth.currentUser.delete()` إطلاقاً: تلك تحذف حساب
/// المصادقة وتترك البيانات كاملة خلفها — مستند المستخدم، ومدخل فهرس الهاتف
/// الذي يحجز الرقم للأبد، ومواعيد قائمة تشغل مقاعد لن يحضرها أحد. القواعد
/// نفسها تمنع العميل من حذف مستنده (`users` → `allow delete: if false`)
/// لأن الحذف يجب أن يجرّ هذا كلّه معه. راجع `functions/account.js`.
class AccountService {
  AccountService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<DeleteAccountResult> deleteAccount() async {
    try {
      final callable = _functions.httpsCallable('deleteAccount');
      final response = await callable.call<Object?>({'confirm': true});
      final data = Map<String, dynamic>.from(response.data as Map);

      AppLogger.success('تم حذف الحساب');
      return DeleteAccountResult.success(
        cancelledAppointments:
            (data['cancelledAppointments'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final reason = details is Map && details['reason'] != null
          ? details['reason'].toString()
          : e.code;
      final failure = deleteAccountFailureFor(reason);
      final message = AppErrorMessages.resolve(
        reason: reason,
        serverMessage: e.message,
      );

      AppLogger.warning('فشل حذف الحساب ($reason): $message');
      return DeleteAccountResult.failed(failure, message);
    } catch (e, s) {
      AppLogger.error('خطأ غير متوقع أثناء حذف الحساب', e, s);
      return DeleteAccountResult.failed(
        DeleteAccountFailure.unknown,
        unknownMessage,
      );
    }
  }
}
