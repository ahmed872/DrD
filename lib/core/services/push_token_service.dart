import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';

/// تسجيل رمز FCM للجهاز الحالي في `users/{uid}/devices/{token}`.
///
/// ## لماذا مستقلة تماماً عن منطق الإشعارات في الخادم
///
/// هذه الخدمة لا "تقرر" شيئاً عن الإشعارات — لا تُنشئ، ولا تُقيّم، ولا حتى
/// تعرف بأنواعها. دورها الوحيد هو أن يعرف الخادم أين يرسل: معرّف مستند
/// الجهاز هو الرمز (token) نفسه — يطابق تماماً ما يقرأه ويحذفه
/// `functions/notifications.js` (`deliverOne`: `devicesSnap.docs.map((d) =>
/// d.id)` وحذف الرموز الميتة عبر `.doc(t)`). لو اختلف شكل المعرّف هنا عن
/// هناك يتوقف تنظيف الرموز الميتة عن العمل بصمت.
///
/// ## لماذا كل شيء هنا محاط بـ try/catch صارم
///
/// لا يوجد تطبيق ويب مسجَّل في مشروع Firebase الحالي بعد (راجع
/// `firebase_options.dart`)، ولا عامل خدمة `firebase-messaging-sw.js`، ولا
/// مفتاح VAPID. طلب رمز FCM على الويب في هذه الحالة يفشل حتماً — وهذا
/// متوقَّع ومقبول: الخدمة تسجّل الفشل محلياً (وضع التطوير فقط) وتعود بهدوء،
/// ولا يجوز أبداً أن يُسقط ذلك تسجيل الدخول أو أي جزء آخر من التطبيق. حين
/// يُضبط مشروع الويب لاحقاً (`flutterfire configure` + عامل خدمة FCM) تعمل
/// هذه الخدمة بلا أي تعديل.
class PushTokenService {
  PushTokenService._();
  static final PushTokenService instance = PushTokenService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<String>? _refreshSubscription;
  String? _currentUid;

  /// يطلب إذن الإشعارات (إن لزم) ويسجّل رمز الجهاز الحالي لهذا المستخدم،
  /// ثم يستمع لتحديث الرمز طوال الجلسة. تُستدعى مرة واحدة بعد كل تسجيل
  /// دخول ناجح — راجع `FirebaseAuthService._onAuthStateChanged`.
  Future<void> registerForUser(String uid) async {
    _currentUid = uid;
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: false,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        AppLogger.info('صلاحية الإشعارات مرفوضة — لن يُسجَّل رمز الجهاز');
        return;
      }

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveToken(uid, token);
      }

      // تحديث الرمز يحدث تلقائياً من مكتبة FCM (انتهاء صلاحية، إعادة تثبيت،
      // ...). الاشتراك واحد فقط طوال عمر التطبيق — إلغاؤه عند تسجيل الخروج.
      await _refreshSubscription?.cancel();
      _refreshSubscription = messaging.onTokenRefresh.listen((newToken) {
        final uidNow = _currentUid;
        if (uidNow != null && newToken.isNotEmpty) {
          _saveToken(uidNow, newToken);
        }
      }, onError: (Object e) {
        AppLogger.error('خطأ في مراقبة تحديث رمز FCM', e);
      });
    } catch (e) {
      // أي فشل هنا (منصّة غير مُعدَّة، عامل خدمة غائب، متصفح لا يدعم
      // Push، ...) هو حالة متوقَّعة في بيئة بلا مشروع Firebase ويب مكتمل
      // الإعداد — لا يجوز أن يكسر تدفّق الدخول.
      AppLogger.error('تعذّر تسجيل رمز إشعارات الجهاز', e);
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(token)
          .set({
        'token': token,
        'platform': _platformName(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      AppLogger.error('تعذّر حفظ رمز الجهاز', e);
    }
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'web',
    };
  }

  /// يوقف الاستماع لتحديث الرمز. لا يحذف مستندات `devices` الحالية عمداً:
  /// جهاز واحد قد يبقى صالحاً لتسجيلات دخول لاحقة لنفس المستخدم، وحذفه هنا
  /// يعني فقدان القدرة على الوصول له عبر Push فور تسجيل الخروج من هذه
  /// الجلسة فقط — بينما تنظيف الرموز الميتة الفعلي مسؤولية الخادم
  /// (`DEAD_TOKEN_ERROR_CODES` في `functions/notifications.js`) عند فشل
  /// إرسال حقيقي.
  void onLogout() {
    _currentUid = null;
    _refreshSubscription?.cancel();
    _refreshSubscription = null;
  }
}
