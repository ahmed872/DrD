import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/utils/error_messages.dart';

/// رسائل الخطأ هي آخر ما يراه المستخدم حين يفشل شيء، وأسوأ ما يمكن أن يراه
/// هو `slot-unavailable` أو `FirebaseFunctionsException`. هذه الاختبارات
/// تحرس ذلك الحد.
void main() {
  group('ترجمة رموز الأسباب', () {
    test('الرموز المعروفة لها رسائل عربية', () {
      for (final reason in [
        'slot-unavailable',
        'appointment-not-found',
        'doctor-not-verified',
        'permission-denied',
        'cancellation-deadline-passed',
        'appointment-not-completed',
      ]) {
        final message = AppErrorMessages.forReason(reason);
        expect(message, isNotNull, reason: 'الرمز $reason بلا رسالة');
        expect(message, isNotEmpty);
        // لا رمز لاتيني يتسرّب داخل الرسالة نفسها.
        expect(AppErrorMessages.looksTechnical(message!), isFalse);
      }
    });

    test('رمز غير معروف يُرجع null لا نصاً تقنياً', () {
      expect(AppErrorMessages.forReason('some-new-server-code'), isNull);
      expect(AppErrorMessages.forReason(null), isNull);
      expect(AppErrorMessages.forReason(''), isNull);
    });

    test('أخطاء الشبكة تُميَّز عن أخطاء المنطق', () {
      expect(AppErrorMessages.isNetworkIssue('unavailable'), isTrue);
      expect(AppErrorMessages.isNetworkIssue('deadline-exceeded'), isTrue);
      expect(AppErrorMessages.isNetworkIssue('slot-unavailable'), isFalse);
      expect(AppErrorMessages.isNetworkIssue(null), isFalse);
    });
  });

  group('كشف النص التقني', () {
    test('يلتقط ما كان يتسرّب فعلاً', () {
      const leaks = [
        'slot-unavailable',
        'appointment-not-found',
        'Exception: something failed',
        '[firebase_functions/internal] INTERNAL',
        'FirebaseException (auth/user-not-found)',
        'PlatformException(error, null, null)',
        'Error: bad state',
        'null',
        '',
        '   ',
      ];
      for (final leak in leaks) {
        expect(AppErrorMessages.looksTechnical(leak), isTrue,
            reason: 'لم يُلتقط: $leak');
      }
    });

    test('لا يرفض الرسائل العربية السليمة', () {
      const good = [
        'الوقت لم يعد متاحاً، اختر موعداً آخر',
        'لديك موعد محجوز مسبقاً عند هذا الطبيب في نفس اليوم',
        'تم حجز الموعد بنجاح',
      ];
      for (final message in good) {
        expect(AppErrorMessages.looksTechnical(message), isFalse,
            reason: 'رُفضت رسالة سليمة: $message');
      }
    });
  });

  group('اشتقاق الرسالة النهائية', () {
    test('رسالة الخادم العربية لها الأولوية', () {
      expect(
        AppErrorMessages.resolve(
          reason: 'slot-unavailable',
          serverMessage: 'للأسف تم حجز هذا الموعد للتو',
        ),
        'للأسف تم حجز هذا الموعد للتو',
      );
    });

    test('رسالة الخادم التقنية تُتجاهل لصالح خريطة الرموز', () {
      final message = AppErrorMessages.resolve(
        reason: 'slot-unavailable',
        serverMessage: 'FirebaseFunctionsException: aborted',
      );
      expect(message, AppErrorMessages.forReason('slot-unavailable'));
      expect(AppErrorMessages.looksTechnical(message), isFalse);
    });

    test('بلا رسالة ولا رمز معروف تُستخدم الرسالة العامة', () {
      expect(
        AppErrorMessages.resolve(reason: 'brand-new-code', serverMessage: ''),
        unknownMessage,
      );
      expect(AppErrorMessages.resolve(), unknownMessage);
    });

    test('لا مخرج ممكن يكون نصاً تقنياً', () {
      // أي تركيبة مدخلات — بما فيها ما يرسله خادم لم يُحدَّث بعد.
      const reasons = [null, '', 'slot-unavailable', 'unknown-code'];
      const serverMessages = [
        null,
        '',
        'Exception: boom',
        'internal',
        'رسالة عربية سليمة',
      ];
      for (final reason in reasons) {
        for (final serverMessage in serverMessages) {
          final result = AppErrorMessages.resolve(
            reason: reason,
            serverMessage: serverMessage,
          );
          expect(result, isNotEmpty);
          expect(AppErrorMessages.looksTechnical(result), isFalse,
              reason: 'تسرّب نص تقني من ($reason, $serverMessage)');
        }
      }
    });
  });
}
