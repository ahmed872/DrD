import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس على تسلسل تسجيل الخروج — المرحلة 9.
///
/// رمز FCM خاصّ بتثبيت التطبيق لا بالمستخدم. لو بقي مستند
/// `users/{uid}/devices/{token}` بعد خروج (أ)، وصلت تذكيرات مواعيده — وفيها
/// اسم الطبيب وتخصّصه وموعد الكشف — إلى (ب) الذي دخل بعده على نفس الجهاز.
///
/// وحذفه **بعد** `signOut()` لا يعمل: قاعدة `users/{userId}/devices/{deviceId}`
/// تشترط `isUser(userId)` (مُثبَت في `test/firestore_rules/rules.test.js`:
/// «مستخدم آخر لا يستطيع حذف رمز ليس له»)، فبلا هوية يُرفض الحذف بصمت
/// ويبقى الرمز — أي أن الشيفرة تبدو صحيحة وهي لا تفعل شيئاً.
///
/// الشرط إذاً ترتيبي، والترتيب لا يظهر في أي اختبار سلوك بلا Firebase حيّ،
/// فالحارس نصّي — على غرار `firestore_query_bounds_test.dart`.
void main() {
  /// جسم أول تابع يبدأ اسمه بـ [signature]، بعدّ الأقواس المعقوفة.
  String bodyOf(String source, String signature) {
    final start = source.indexOf(signature);
    expect(start, isNot(-1), reason: 'لم يُعثر على «$signature»');
    var i = source.indexOf('{', start);
    expect(i, isNot(-1));
    var depth = 0;
    for (var j = i; j < source.length; j++) {
      if (source[j] == '{') depth++;
      if (source[j] == '}') {
        depth--;
        if (depth == 0) return source.substring(i, j + 1);
      }
    }
    fail('جسم غير مغلق لـ «$signature»');
  }

  final pushService =
      File('lib/core/services/push_token_service.dart').readAsStringSync();
  final authService =
      File('lib/presentation/providers/firebase_auth_service.dart')
          .readAsStringSync();

  test('onLogout يحذف مستند الجهاز فعلاً', () {
    final body = bodyOf(pushService, 'onLogout(');
    expect(body.contains("collection('devices')"), isTrue,
        reason: 'الخروج لا يمسّ مجموعة الأجهزة إطلاقاً');
    expect(body.contains('.delete()'), isTrue,
        reason: 'الرمز يبقى مسجَّلاً بعد الخروج — يصل إشعار صاحبه لمن بعده');
  });

  test('حذف الرمز يسبق signOut — وإلا رفضته القواعد', () {
    final body = bodyOf(authService, 'Future<void> logout(');
    final logoutIdx = body.indexOf('PushTokenService.instance.onLogout()');
    final signOutIdx = body.indexOf('_firebaseAuth.signOut()');

    expect(logoutIdx, isNot(-1), reason: 'الخروج لا ينظّف رمز الجهاز');
    expect(signOutIdx, isNot(-1));
    expect(logoutIdx < signOutIdx, isTrue,
        reason: 'الحذف بعد signOut يُرفض بصمت: لا هوية تُثبت ملكية الرمز');
    expect(body.contains('await PushTokenService.instance.onLogout()'), isTrue,
        reason: 'بلا await قد يسبق signOut الحذفَ فعلياً رغم ترتيب السطور');
  });
}
