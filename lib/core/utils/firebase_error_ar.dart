/// ترجمة أخطاء Firebase إلى رسائل عربية يفهمها المستخدم.
///
/// ## المشكلة التي يحلّها هذا الملف
///
/// كانت رسائل الخطأ في المصادقة تُبنى هكذا:
///
/// ```dart
/// _errorMessage = 'خطأ في التسجيل: $e';
/// ```
///
/// و`$e` على استثناء Firebase يُنتج نصاً مثل:
///
///     [firebase_auth/email-already-in-use] The email address is already in
///     use by another account.
///
/// فيرى مستخدم عربي على شاشة تسجيل الدخول اسمَ حزمة ورمزَ خطأ وجملة
/// إنجليزية. وهو ليس مجرد قبح: النص قد يحمل مسار مستند أو معرّف مستخدم حسب
/// نوع الاستثناء، أي تسريب تفاصيل داخلية إلى شاشة عامة.
///
/// والأسوأ أن الرسالة **لا تفيد**: «email-already-in-use» له إجراء واضح
/// (سجّل الدخول بدل إنشاء حساب)، لكن النص الخام لا يقوله.
///
/// ## المبدأ
///
/// كل رسالة تجيب سؤالين: ماذا حدث، وماذا أفعل الآن. وما لا نعرفه يُترجم إلى
/// رسالة عامة **مع تسجيل التفاصيل في السجلّ** — لا بعرضها.
library;

import 'package:firebase_auth/firebase_auth.dart';

/// رسالة عربية لخطأ Firebase، مناسبة للعرض المباشر للمستخدم.
///
/// [fallback] ما يُعرض حين لا يكون الرمز معروفاً — اكتبه بصيغة العملية
/// الجارية («تعذّر حفظ الموعد») لا بصيغة عامة («حدث خطأ»).
String firebaseErrorAr(Object error, {required String fallback}) {
  if (error is FirebaseAuthException) return _authMessage(error, fallback);
  if (error is FirebaseException) return _firestoreMessage(error, fallback);
  return fallback;
}

String _authMessage(FirebaseAuthException e, String fallback) {
  return switch (e.code) {
    // ── بيانات الدخول ──────────────────────────────────────────────────
    // الثلاثة تُترجَم إلى رسالة واحدة عمداً: التفريق بينها يكشف أي الأرقام
    // مسجَّلة لدينا، وهو ما تتفاداه شاشة الدخول أصلاً.
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' =>
      'رقم الجوال أو كلمة المرور غير صحيحة.',
    'user-disabled' => 'تم تعطيل هذا الحساب. تواصل مع الدعم.',
    'invalid-email' => 'صيغة البريد الإلكتروني غير صحيحة.',

    // ── إنشاء الحساب ───────────────────────────────────────────────────
    'email-already-in-use' =>
      'هذا البريد الإلكتروني مستخدم بالفعل. سجّل الدخول أو استخدم بريداً آخر.',
    'weak-password' => 'كلمة المرور ضعيفة. اختر كلمة أطول وأصعب في التخمين.',
    'operation-not-allowed' => 'هذه الطريقة غير مفعّلة حالياً. تواصل مع الدعم.',

    // ── حدود ومحاولات ─────────────────────────────────────────────────
    'too-many-requests' =>
      'محاولات كثيرة متتالية. انتظر قليلاً ثم حاول مرة أخرى.',
    'requires-recent-login' =>
      'لأمانك، سجّل الخروج ثم الدخول مرة أخرى قبل هذه الخطوة.',

    // ── الشبكة ────────────────────────────────────────────────────────
    'network-request-failed' =>
      'تعذّر الاتصال بالإنترنت. تحقّق من الشبكة وحاول مرة أخرى.',
    _ => fallback,
  };
}

String _firestoreMessage(FirebaseException e, String fallback) {
  return switch (e.code) {
    'permission-denied' => 'ليس لديك صلاحية لتنفيذ هذا الإجراء.',
    'unavailable' ||
    'deadline-exceeded' =>
      'تعذّر الوصول إلى الخادم. تحقّق من اتصالك وحاول مرة أخرى.',
    'not-found' => 'لم يعد هذا العنصر موجوداً.',
    'already-exists' => 'هذا العنصر موجود بالفعل.',
    'resource-exhausted' => 'الخدمة مشغولة حالياً. حاول مرة أخرى بعد قليل.',
    'unauthenticated' => 'انتهت جلستك. سجّل الدخول مرة أخرى.',
    // `failed-precondition` في Firestore يعني غالباً فهرساً ناقصاً — عطل
    // نشر لا عطل مستخدم. الرسالة تبقى عامة، والتفاصيل في السجلّ.
    'failed-precondition' => fallback,
    _ => fallback,
  };
}
