import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/utils/error_messages.dart';
import 'package:medical_appointment_app/data/services/account_service.dart';

/// حذف الحساب — عقد الأسباب بين الخادم والواجهة.
///
/// الحذف لا رجعة فيه، وأخطاؤه تحتاج تصرّفاً مختلفاً لا رسالة مختلفة فقط:
/// «جلسة قديمة» تعني إعادة تسجيل الدخول، و«حساب طبيب» تعني التوقف. لو
/// انزلق رمز واحد بين `functions/account.js` وهذا الملف لسقط ذلك التمييز
/// بصمت وظهرت رسالة عامة مكان مخرجٍ صحيح.
void main() {
  group('ربط أسباب الخادم بتصرّف الواجهة', () {
    test('كل رمز في العقد له سبب محدَّد لا "غير معروف"', () {
      // مطابقة حرفية لجدول الأخطاء في توثيق `exports.deleteAccount`.
      const contract = {
        'unauthenticated': DeleteAccountFailure.notSignedIn,
        'confirmation-required': DeleteAccountFailure.needsConfirmation,
        'recent-login-required': DeleteAccountFailure.needsRecentLogin,
        'doctor-account': DeleteAccountFailure.doctorAccount,
      };

      contract.forEach((reason, expected) {
        expect(deleteAccountFailureFor(reason), expected, reason: reason);
      });
      expect(deleteAccountFailureByReason.keys.toSet(), contract.keys.toSet());
    });

    test('رمز غير معروف يسقط إلى unknown لا إلى تصرّف خاطئ', () {
      expect(deleteAccountFailureFor('something-new'),
          DeleteAccountFailure.unknown);
      expect(deleteAccountFailureFor(null), DeleteAccountFailure.unknown);
      expect(deleteAccountFailureFor(''), DeleteAccountFailure.unknown);
    });

    test('كل رمز في العقد له رسالة عربية — لا رسالة عامة', () {
      for (final reason in deleteAccountFailureByReason.keys) {
        final message = AppErrorMessages.forReason(reason);
        expect(message, isNotNull, reason: 'لا رسالة لـ $reason');
        expect(message, isNot(unknownMessage), reason: reason);
        expect(AppErrorMessages.looksTechnical(message!), isFalse,
            reason: 'رسالة تقنية لـ $reason');
      }
    });
  });

  group('نتيجة المحاولة', () {
    test('النجاح يحمل عدد المواعيد الملغاة', () {
      const result = DeleteAccountResult.success(cancelledAppointments: 2);
      expect(result.isSuccess, isTrue);
      expect(result.cancelledAppointments, 2);
      expect(result.needsRecentLogin, isFalse);
      expect(result.message, isNotEmpty);
    });

    test('الجلسة القديمة وحدها تطلب إعادة الدخول', () {
      const stale = DeleteAccountResult.failed(
          DeleteAccountFailure.needsRecentLogin, 'أعد الدخول');
      expect(stale.isSuccess, isFalse);
      expect(stale.needsRecentLogin, isTrue);

      for (final failure in DeleteAccountFailure.values) {
        if (failure == DeleteAccountFailure.needsRecentLogin) continue;
        expect(DeleteAccountResult.failed(failure, 'خطأ').needsRecentLogin,
            isFalse,
            reason: failure.name);
      }
    });
  });
}
