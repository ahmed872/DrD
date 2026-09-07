import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/utils/firebase_error_ar.dart';

/// حارس رسائل الخطأ.
///
/// ## ما الذي يحرسه
///
/// كانت رسائل المصادقة تُبنى بـ`'خطأ في التسجيل: $e'`، فيرى مستخدم عربي على
/// شاشة الدخول نصّاً مثل:
///
///     [firebase_auth/email-already-in-use] The email address is already in use
///
/// اسم حزمة، ورمز خطأ، وجملة إنجليزية — وأحياناً مسار مستند أو معرّف مستخدم
/// حسب نوع الاستثناء.
void main() {
  FirebaseAuthException auth(String code) =>
      FirebaseAuthException(code: code, message: 'English technical text');

  FirebaseException store(String code) => FirebaseException(
        plugin: 'cloud_firestore',
        code: code,
        message:
            'PERMISSION_DENIED at /databases/(default)/documents/users/abc',
      );

  const fallback = 'تعذّر إتمام العملية. حاول مرة أخرى.';

  final arabic = RegExp(r'[؀-ۿ]');
  final latin = RegExp(r'[A-Za-z]');

  test('كل رسالة عربية وبلا حرف لاتيني واحد', () {
    final codes = [
      'user-not-found',
      'wrong-password',
      'invalid-credential',
      'user-disabled',
      'invalid-email',
      'email-already-in-use',
      'weak-password',
      'operation-not-allowed',
      'too-many-requests',
      'requires-recent-login',
      'network-request-failed',
    ];
    for (final code in codes) {
      final msg = firebaseErrorAr(auth(code), fallback: fallback);
      expect(arabic.hasMatch(msg), isTrue, reason: '«$code» بلا نص عربي');
      expect(latin.hasMatch(msg), isFalse,
          reason: '«$code» يسرّب نصاً لاتينياً: $msg');
    }
  });

  test('لا تصل تفاصيل الاستثناء إلى المستخدم', () {
    // أخطر ما في الصيغة القديمة: مسار المستند داخل رسالة Firestore.
    final msg = firebaseErrorAr(store('permission-denied'), fallback: fallback);
    expect(msg, isNot(contains('/databases/')));
    expect(msg, isNot(contains('users/abc')));
    expect(msg, isNot(contains('cloud_firestore')));
    expect(msg, 'ليس لديك صلاحية لتنفيذ هذا الإجراء.');
  });

  test('بيانات الدخول الخاطئة لا تكشف أي الأرقام مسجَّلة', () {
    // التفريق بين «الحساب غير موجود» و«كلمة المرور خاطئة» يحوّل شاشة الدخول
    // إلى أداة تعداد للحسابات.
    final notFound =
        firebaseErrorAr(auth('user-not-found'), fallback: fallback);
    final wrongPass =
        firebaseErrorAr(auth('wrong-password'), fallback: fallback);
    final invalid =
        firebaseErrorAr(auth('invalid-credential'), fallback: fallback);
    expect(notFound, wrongPass);
    expect(wrongPass, invalid);
  });

  test('الرمز المجهول يعطي رسالة العملية لا رسالة عامة', () {
    expect(firebaseErrorAr(auth('some-new-code-2027'), fallback: fallback),
        fallback);
    expect(firebaseErrorAr(Exception('boom'), fallback: fallback), fallback);
  });

  test('لا سطر في الواجهة يعرض الاستثناء الخام', () {
    // الحارس البنيوي: المترجم لا ينفع إن عاد أحدهم يكتب `$e` في رسالة.
    final offenders = <String>[];
    final uiText = RegExp(
      r'(AppSnackBar\.\w+|SnackBar|_errorMessage\s*=|Text)\('
      r'[^)\n]*\$(e|error)\b',
    );
    for (final entity
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('AppLogger') || line.trimLeft().startsWith('//')) {
          continue;
        }
        if (uiText.hasMatch(line)) {
          offenders.add('${entity.path}:${i + 1}  ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'استثناء خام في نص يراه المستخدم:\n${offenders.join('\n')}');
  });
}
