import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

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
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.88, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // الشاشة كلها بلون العلامة بدل الأبيض المحايد: هذه أول لحظة يرى فيها
    // المستخدم التطبيق، وشاشة بيضاء بمؤشّر رمادي لا تقول شيئاً عن هويّته.
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: tokens.brandGradient),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _scale,
                  child: Container(
                    width: 116,
                    height: 116,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      image: const DecorationImage(
                        image: AssetImage('assets/images/logo.png'),
                        fit: BoxFit.cover,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  'DrD',
                  style: context.texts.displaySmall?.copyWith(
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'حجز مواعيد الأطباء',
                  style: context.texts.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxxl),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor: AlwaysStoppedAnimation(
                      Colors.white.withValues(alpha: 0.9),
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'جارٍ التحميل…',
                  style: context.texts.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
