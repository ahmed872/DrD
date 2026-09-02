import 'dart:async' show TimeoutException;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/app_logger.dart';
import 'firebase_options.dart';
import 'presentation/providers/firebase_auth_service.dart';
import 'presentation/providers/rating_provider.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/support_screen.dart';
import 'presentation/screens/email_verification_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // على الويب، إعدادات Firebase تُمرَّر وقت البناء. تشغيل التطبيق بدونها
  // يُنتج انهياراً غامضاً في وحدة التحكم لا يفهمه أحد، لذا نعرض شاشة عربية
  // تشرح الخطوة الناقصة بدلاً من ذلك.
  if (kIsWeb && !DefaultFirebaseOptions.isWebConfigured) {
    runApp(const _MissingWebConfigApp());
    return;
  }

  var firebaseReady = false;
  try {
    // المهلة ضرورية وليست احتياطاً نظرياً.
    //
    // على الويب يُحمَّل Firebase SDK من gstatic.com عبر استيراد ديناميكي. لو
    // تعذّر الوصول إليه (شبكة ضعيفة، انقطاع، أو حجب) فإن `initializeApp`
    // **لا ترمي استثناءً** — بل يبقى الـ Future معلّقاً إلى الأبد، فيعلق
    // المستخدم أمام شاشة تحميل لا تنتهي بلا أي تفسير. رُصد هذا بتشغيل نسخة
    // الويب فعلياً خلف شبكة تحجب gstatic.
    //
    // بانتهاء المهلة نُكمل الإقلاع ونعرض رسالة عربية واضحة بدلاً من ذلك.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 15));
    firebaseReady = true;
    await _connectEmulatorsIfRequested();
    AppLogger.success('تم تهيئة Firebase بنجاح');
  } on TimeoutException {
    AppLogger.error('انتهت مهلة الاتصال بـ Firebase');
  } catch (e, s) {
    AppLogger.error('فشل تهيئة Firebase', e, s);
  }

  runApp(MedicalApp(firebaseReady: firebaseReady));
}

/// وصل التطبيق بمحاكيات Firebase المحلية — للتطوير والمراجعة البصرية فقط.
///
/// `bool.fromEnvironment` ثابتة وقت الترجمة: بلا
/// `--dart-define=USE_FIREBASE_EMULATOR=true` تُسقط هذه الدالة كلها من
/// النسخة المبنية، فمسار الإنتاج لا يتغيّر ولا يحمل شيئاً منها.
///
/// أُضيفت في المرحلة 6 لأن مراجعة شاشات الطبيب بصرياً تتطلّب جلسة طبيب
/// حقيقية، ولا سبيل إليها في بيئة بلا اعتمادات إنتاج.
Future<void> _connectEmulatorsIfRequested() async {
  const useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');
  if (!useEmulator) return;

  const host = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  try {
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    // المرحلة 8: التحليلات كلها عبر دوال قابلة للاستدعاء، فمراجعتها
    // بصرياً تتطلّب وصل محاكي الدوال أيضاً.
    FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
    AppLogger.warning('متصل بمحاكيات Firebase على $host — ليست بيئة إنتاج');
  } catch (e, s) {
    AppLogger.error('تعذّر الاتصال بالمحاكيات', e, s);
  }
}

class MedicalApp extends StatelessWidget {
  const MedicalApp({super.key, this.firebaseReady = true});

  /// عندما تفشل تهيئة Firebase لا معنى لبناء بقية التطبيق: كل شاشة فيه
  /// تستدعي Firestore وستنهار عند أول استعلام.
  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    if (!firebaseReady) {
      return const _StartupErrorApp(
        title: 'تعذّر تشغيل التطبيق',
        message:
            'لم نتمكّن من الاتصال بخوادم التطبيق.\nتأكد من اتصالك بالإنترنت '
            'ثم أعد فتح التطبيق.',
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FirebaseAuthService()),
        ChangeNotifierProvider(create: (_) => RatingProvider()),
      ],
      child: MaterialApp(
        title: 'DrD — حجز مواعيد الأطباء',
        debugShowCheckedModeBanner: false,

        // دعم العربية RTL
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ar', 'EG'),
          Locale('ar'),
          Locale('en', 'US'),
        ],
        locale: const Locale('ar', 'EG'),

        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,

        home: Consumer<FirebaseAuthService>(
          builder: (context, auth, _) {
            // انتظار أول رد من Firebase عن حالة الجلسة قبل اتخاذ قرار
            // التوجيه. بدونه تومض شاشة تسجيل الدخول لمستخدم مسجَّل بالفعل،
            // وهو ما كان يحدث في كل تحديث للصفحة على الويب.
            if (!auth.sessionRestored) return const SplashScreen();
            return auth.isLoggedIn ? const HomeScreen() : const LoginScreen();
          },
        ),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/email-verification': (context) => const EmailVerificationScreen(),
          '/home': (context) => Consumer<FirebaseAuthService>(
                builder: (context, auth, _) {
                  return auth.isLoggedIn
                      ? const HomeScreen()
                      : const LoginScreen();
                },
              ),
          '/support': (context) => const SupportScreen(),
        },
      ),
    );
  }
}

/// شاشة خطأ عامة تُعرض قبل توفّر أي نسق أو مزوّد.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // بدون `title` يمسح محرّك Flutter عنوان الصفحة في المتصفح فيظهر
      // التبويب فارغاً — وهو أول ما يراه المستخدم عند فشل الإقلاع.
      title: 'DrD — حجز مواعيد الأطباء',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off,
                      size: 64, color: AppColors.primary),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, height: 1.7),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// رسالة للمطوّر عند بناء نسخة ويب بلا إعدادات Firebase.
class _MissingWebConfigApp extends StatelessWidget {
  const _MissingWebConfigApp();

  @override
  Widget build(BuildContext context) {
    return const _StartupErrorApp(
      title: 'إعدادات Firebase للويب غير مضبوطة',
      message: 'شغّل الأمر التالي مرة واحدة ثم أعد البناء:\n\n'
          'flutterfire configure --platforms=web\n\n'
          'التفاصيل في docs/DEPLOYMENT.md',
    );
  }
}
