// ignore_for_file: type=lint
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// إعدادات Firebase لكل منصّة.
///
/// ## ما الذي تغيّر ولماذا
///
/// النسخة السابقة كانت تحتوي على إعدادات أندرويد فقط، و`currentPlatform`
/// تُرجِع `android` دائماً مهما كانت المنصّة. على الويب هذا لا يعمل: إعدادات
/// أندرويد لا تحتوي على `authDomain`، وبدونه يفشل Firebase Auth تماماً في
/// المتصفح — أي أن تحويل التطبيق إلى PWA كان مستحيلاً قبل إصلاح هذا الملف.
///
/// ## المطلوب منك قبل أول نشر على الويب
///
/// إعدادات الويب أدناه فارغة لأن مشروع Firebase الحالي (`heldoc-68abf`) لا
/// يحتوي على تطبيق ويب مسجَّل بعد. لا يمكن تخمين هذه القيم — لا بد من
/// إنشائها:
///
/// ```bash
/// dart pub global activate flutterfire_cli
/// flutterfire configure --project=heldoc-68abf --platforms=web,android,ios
/// ```
///
/// أو يدوياً: Firebase Console ← Project Settings ← Your apps ← Add app ← Web،
/// ثم انسخ القيم إلى [web] بالأسفل.
///
/// ملاحظة أمنية: قيم `apiKey` في Firebase ليست أسراراً — فهي تُرسَل للمتصفح
/// بالضرورة. ما يحمي بياناتك هو `firestore.rules`، وليس إخفاء هذا المفتاح.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      default:
        // ويندوز ولينكس غير مُعدَّين في مشروع Firebase حالياً. نُرجع إعدادات
        // أندرويد بدل رمي استثناء يُعطّل التطبيق أثناء التطوير على سطح المكتب.
        return android;
    }
  }

  /// هل إعدادات الويب مكتملة؟
  ///
  /// `main.dart` يستخدمها ليعرض رسالة عربية واضحة بدل انهيار غامض عند تشغيل
  /// نسخة ويب لم تُضبط بعد.
  static bool get isWebConfigured =>
      web.apiKey.isNotEmpty &&
      web.appId.isNotEmpty &&
      (web.authDomain?.isNotEmpty ?? false);

  /// إعدادات الويب — تطبيق `DrD Web` المسجَّل في مشروع `heldoc-68abf`.
  ///
  /// القيم مكتوبة هنا مباشرة عمداً: كلها تُرسَل للمتصفح مع أول تحميل للصفحة،
  /// فهي ليست أسراراً ولا فائدة من إخفائها. أي زائر يستطيع قراءتها من أدوات
  /// المطوّر في أي موقع Firebase منشور. ما يحمي البيانات هو `firestore.rules`.
  ///
  /// تبقى قابلة للتجاوز وقت البناء عند الحاجة (مشروع اختبار مثلاً):
  /// ```bash
  /// flutter build web --release --dart-define=FIREBASE_WEB_PROJECT_ID=...
  /// ```
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment(
      'FIREBASE_WEB_API_KEY',
      defaultValue: 'AIzaSyBJTRMbaGayX4nZWhrxgSNewWVre6ExRR0',
    ),
    appId: String.fromEnvironment(
      'FIREBASE_WEB_APP_ID',
      defaultValue: '1:736610467870:web:c67826042ad41955b02e0f',
    ),
    messagingSenderId: String.fromEnvironment(
      'FIREBASE_WEB_SENDER_ID',
      defaultValue: '736610467870',
    ),
    projectId: String.fromEnvironment(
      'FIREBASE_WEB_PROJECT_ID',
      defaultValue: 'heldoc-68abf',
    ),
    authDomain: String.fromEnvironment(
      'FIREBASE_WEB_AUTH_DOMAIN',
      defaultValue: 'heldoc-68abf.firebaseapp.com',
    ),
    storageBucket: String.fromEnvironment(
      'FIREBASE_WEB_STORAGE_BUCKET',
      defaultValue: 'heldoc-68abf.firebasestorage.app',
    ),
    measurementId: String.fromEnvironment(
      'FIREBASE_WEB_MEASUREMENT_ID',
      defaultValue: 'G-L5GG3TKN3X',
    ),
  );

  /// إعدادات أندرويد — مطابقة لـ `android/app/google-services.json`.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCP8ArkxYPnwhMu1n-td0LDo-bMs7pd5kQ',
    appId: '1:736610467870:android:4d0e388c5e463639b02e0f',
    messagingSenderId: '736610467870',
    projectId: 'heldoc-68abf',
    storageBucket: 'heldoc-68abf.firebasestorage.app',
  );

  /// إعدادات iOS.
  ///
  /// مشروع Firebase لا يحتوي على تطبيق iOS مسجَّل بعد، ولا يوجد
  /// `ios/Runner/GoogleService-Info.plist`. القيم تُمرَّر وقت البناء إلى أن
  /// يُسجَّل التطبيق — راجع `docs/DEPLOYMENT.md` قسم App Store.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: String.fromEnvironment(
      'FIREBASE_IOS_API_KEY',
      defaultValue: 'AIzaSyCP8ArkxYPnwhMu1n-td0LDo-bMs7pd5kQ',
    ),
    appId: String.fromEnvironment('FIREBASE_IOS_APP_ID'),
    messagingSenderId: '736610467870',
    projectId: 'heldoc-68abf',
    storageBucket: 'heldoc-68abf.firebasestorage.app',
    iosBundleId: String.fromEnvironment(
      'FIREBASE_IOS_BUNDLE_ID',
      defaultValue: 'com.heldoc.drd',
    ),
  );
}
