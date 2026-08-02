import 'package:flutter/material.dart';

/// شاشة البداية — عرض فقط، بلا أي منطق تنقّل.
///
/// كانت هذه الشاشة تنتظر 1500 مللي ثانية ثابتة ثم تستدعي `checkSession()`
/// وتنتقل بنفسها عبر `pushReplacementNamed`. بعد أن صار `main.dart` يوجّه
/// المستخدم تفاعلياً حسب حالة المصادقة، كان بقاء ذلك المنطق يعني تنقّلين
/// متنافسين على نفس اللحظة. كما أن التأخير الثابت كان يضيف ثانية ونصفاً لكل
/// إقلاع بلا سبب.
///
/// الآن: تُعرض ما دامت الجلسة قيد الاستعادة، وتختفي فور معرفة النتيجة.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // الأيقونة الرئيسية
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: const DecorationImage(
                    image: AssetImage('assets/images/logo.png'),
                    fit: BoxFit.cover,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey[300]!,
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // اسم التطبيق
              Text(
                'نظام حجز المواعيد',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0097A7),
                      fontSize: 26,
                    ),
              ),

              const SizedBox(height: 12),

              // الشعار
              Text(
                'Medical Appointment System',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
              ),

              const SizedBox(height: 60),

              // مؤشر التحميل
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(Colors.grey[400]),
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'جاري التحميل...',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
