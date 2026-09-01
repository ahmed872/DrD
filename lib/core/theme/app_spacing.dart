import 'package:flutter/material.dart';

/// المسافات والزوايا — مقياس واحد بدل أرقام متفرقة.
///
/// الشاشات كانت تستخدم `EdgeInsets.all(16)` و`all(12)` و`all(20)` و`all(24)`
/// بلا قاعدة، فتختلف الحواف بين شاشة وأخرى بمقدار يُرى. المقياس هنا مضاعفات
/// أربعة، وهو ما تبنى عليه Material.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// حافة الشاشة الافتراضية.
  static const EdgeInsets page = EdgeInsets.all(lg);

  /// حافة داخل البطاقة.
  static const EdgeInsets card = EdgeInsets.all(lg);
}

/// أنصاف أقطار الزوايا — مطابقة لما يضبطه `AppTheme`.
class AppRadii {
  const AppRadii._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 14;
  static const double xl = 16;
  static const double pill = 999;

  // ===== أدوار الشكل (المرحلة 6.5) =====
  //
  // كانت الشاشات تحمل 118 استدعاءً لـ `BorderRadius.circular` بست قيم
  // مختلفة (4, 6, 8, 10, 12, 20)، بينما `AppRadii` أعلاه مستعمَل في
  // شاشتين من أربع وعشرين. القيم أدناه تُسمّى بدورها لا بمقاسها، فيصعب
  // اختيار الخطأ: البطاقة أعرض انحناءً من الزرّ، والزرّ من الحقل.
  static const double card = 18;
  static const double button = 14;
  static const double input = 14;
  static const double dialog = 22;
  static const double chip = pill;

  // اختصارات جاهزة بنفس القيم أعلاه.
  static BorderRadius get cardRadius => BorderRadius.circular(card);
  static BorderRadius get buttonRadius => BorderRadius.circular(button);
  static BorderRadius get fieldRadius => BorderRadius.circular(input);
  static BorderRadius get chipRadius => BorderRadius.circular(chip);
}

/// نقاط التكسّر للتخطيط المتجاوب.
///
/// التطبيق يعمل على الويب أيضاً، وبعرض شاشة مكتب كانت البطاقات تُمطّ إلى
/// 1900 بكسل فيصير سطر النص أعرض من أن يُقرأ. [contentMaxWidth] يحصر
/// المحتوى في عرض مريح ويوسّطه، بلا أي تغيير على الهاتف.
class AppBreakpoints {
  const AppBreakpoints._();

  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;

  /// أقصى عرض للمحتوى النصّي/النموذجي.
  static const double contentMaxWidth = 720;

  /// أقصى عرض للشبكات والقوائم العريضة.
  static const double wideMaxWidth = 1080;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobile;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= mobile && width < desktop;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;

  /// عدد الأعمدة المناسب لشبكة البطاقات على العرض الحالي.
  static int gridColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= desktop) return 4;
    if (width >= tablet) return 3;
    if (width >= mobile) return 2;
    return 2;
  }
}

/// يحصر المحتوى في عرض مقروء ويوسّطه على الشاشات العريضة.
///
/// على الهاتف لا أثر له إطلاقاً — العرض المتاح أقل من الحد أصلاً.
class ContentWidthLimit extends StatelessWidget {
  const ContentWidthLimit({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.contentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
