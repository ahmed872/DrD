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

    // هذه الشاشة نسخة طبق الأصل من شاشة الإقلاع المكتوبة بـ HTML في
    // `web/index.html`: نفس التدرّج، ونفس مقاسات الشعار والنص والمسافات.
    //
    // السبب أن المستخدم يرى الاثنتين متتاليتين — الأولى قبل تحميل محرّك
    // Flutter والثانية بعده. أي فرق بينهما يظهر كقفزة بصرية في أول ثانيتين
    // من عمر التطبيق. التطابق يجعل التسليم بينهما غير مرئي.
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: tokens.brandGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              // توسيط بصري لا هندسي: الكتلة الموسَّطة رياضياً تبدو للعين
              // واقعة تحت المنتصف، فتُرفع بنسبة صغيرة من ارتفاع الشاشة.
              // النسبة نفسها المستخدمة في `#boot-screen`.
              padding: EdgeInsets.only(
                bottom: MediaQuery.sizeOf(context).height * 0.07,
              ),
              child: FadeTransition(
                opacity: _fade,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _scale,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          image: const DecorationImage(
                            image: AssetImage('assets/images/logo.png'),
                            fit: BoxFit.cover,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.22),
                              blurRadius: 34,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'DrD — حجز مواعيد الأطباء',
                      textAlign: TextAlign.center,
                      style: context.texts.titleLarge?.copyWith(
                        color: Colors.white,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'جارٍ التحميل…',
                      style: context.texts.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                        backgroundColor: Colors.white.withValues(alpha: 0.24),
                      ),
                    ),
                  ],
                ),
              ),
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
