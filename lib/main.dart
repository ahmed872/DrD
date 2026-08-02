import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
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

  // تهيئة Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase تم تهيئونه بنجاح');
  } catch (e) {
    print('❌ خطأ في تهيئة Firebase: $e');
    print('⚠️ سيتم استخدام Local Auth كبديل');
  }

  runApp(const MedicalApp());
}

class MedicalApp extends StatelessWidget {
  const MedicalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FirebaseAuthService()),
        ChangeNotifierProvider(create: (_) => RatingProvider()),
      ],
      child: MaterialApp(
        title: 'نظام حجز المواعيد',
        debugShowCheckedModeBanner: false,
        //
        // دعم العربية RTL
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ar', 'AE'),
          Locale('en', 'US'),
        ],
        locale: const Locale('ar', 'AE'),
        //
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.blue,
            centerTitle: true,
            foregroundColor: Colors.white,
          ),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior
                .floating, // يجعلها طافية ולא تلتصق بالأسفل دائماً
            actionTextColor: Colors.white,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            floatingLabelBehavior:
                FloatingLabelBehavior.always, // يمنع تداخل النص مع الخط
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        //
        home: Consumer<FirebaseAuthService>(
          builder: (context, auth, _) {
            // Check auth state immediately to route smoothly
            if (auth.isLoggedIn) {
              return const HomeScreen();
            }
            return const SplashScreen();
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
