import 'package:flutter/foundation.dart';

/// تسجيل موحّد يختفي تماماً في نسخة الإصدار.
///
/// المشكلة التي يحلّها: التطبيق كان يستخدم `print()` في 51 موضعاً. على الويب
/// كل استدعاء منها يظهر في console المتصفح لأي شخص يفتح أدوات المطوّر —
/// وبعضها كان يطبع رسائل أخطاء Firebase كاملة. هنا كل شيء محصور بـ
/// [kDebugMode] فلا يصل شيء للمستخدم النهائي.
class AppLogger {
  const AppLogger._();

  static void success(String message) => _log('✅', message);

  static void info(String message) => _log('ℹ️', message);

  static void warning(String message) => _log('⚠️', message);

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    debugPrint('❌ $message');
    if (error != null) debugPrint('   السبب: $error');
    if (stackTrace != null) debugPrint('   $stackTrace');
  }

  static void _log(String icon, String message) {
    if (!kDebugMode) return;
    debugPrint('$icon $message');
  }
}
