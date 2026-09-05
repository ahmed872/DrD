import 'package:flutter/material.dart';

/// رموز التصميم لتطبيق DrD.
///
/// ## لماذا هذا الملف
///
/// كان في التطبيق **566 لوناً مكتوباً يدوياً** موزّعة على 21 ملفاً، و17
/// شريط تطبيق يعيد كل منها تعيين لونه، وتسع ألوان مختلفة للأزرار، وثماني
/// قيم مختلفة لاستدارة الحواف. النتيجة واجهة تبدو مجمّعة من تطبيقات مختلفة،
/// ولا سبيل لتغيير أي شيء فيها من مكان واحد.
///
/// الألوان هنا **دلالية**: `success` لا `green`. اللون وسيلة لنقل معنى، فإن
/// لم يكن هناك معنى فلا لون.
///
/// ## القاعدة
///
/// لا يُكتب لون في أي شاشة. كل شيء من `Theme.of(context)` أو من
/// `context.drd`. أي لون حرفي في شاشة هو خطأ يجب أن يُراجَع.

// ===========================================================================
// لوحة الألوان الخام — لا تُستخدم مباشرة في الواجهة
// ===========================================================================

/// القيم الخام — **المصدر الوحيد** لكل لون في التطبيق.
///
/// `AppTheme` يبني منها `ColorScheme`، و[DrdColors] يبني منها الألوان
/// الدلالية. الشاشات لا تقرأ من هنا أبداً: تغيير لون العلامة يجب أن يكون سطراً
/// واحداً في هذا الملف، لا بحثاً واستبدالاً عبر عشرين ملفاً.
abstract final class DrdPalette {
  // --- فاتح ---
  static const lightBackground = Color(0xFFF3F7F9);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceLow = Color(0xFFF8FBFC);
  static const lightSurfaceHigh = Color(0xFFEDF2F5);
  static const lightSurfaceVariant = Color(0xFFE9EFF2);

  static const lightPrimary = Color(0xFF12707C);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFD7EAEC);
  static const lightOnPrimaryContainer = Color(0xFF06333A);

  static const lightSecondary = Color(0xFF3F6484);
  static const lightOnSecondary = Color(0xFFFFFFFF);
  static const lightSecondaryContainer = Color(0xFFDEE7EF);
  static const lightOnSecondaryContainer = Color(0xFF1B2E3F);

  static const lightSuccess = Color(0xFF2E7D5B);
  static const lightOnSuccess = Color(0xFFFFFFFF);
  static const lightSuccessContainer = Color(0xFFDDEFE5);
  static const lightOnSuccessContainer = Color(0xFF103826);

  /// نصّ التحذير أغمق من لون الأيقونة عمداً.
  ///
  /// اللون البرتقالي المقترح أصلاً (#B86E00) يقيس نحو 4.0:1 على الأبيض — أقل
  /// من حدّ AA لنص المتن (4.5:1). فصلنا الاثنين: النص بهذا اللون الأغمق،
  /// والأيقونة والحدود بالبرتقالي الأفتح حيث لا يُشترط نفس الحد.
  static const lightWarning = Color(0xFF8F5600);
  static const lightWarningAccent = Color(0xFFB86E00);
  static const lightWarningContainer = Color(0xFFFBEEDC);
  static const lightOnWarningContainer = Color(0xFF442900);

  static const lightError = Color(0xFFB3261E);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightErrorContainer = Color(0xFFF9E4E2);
  static const lightOnErrorContainer = Color(0xFF48110D);

  static const lightOnSurface = Color(0xFF141D26);
  static const lightMuted = Color(0xFF54636F);
  static const lightOutline = Color(0xFFB9C4CC);
  static const lightBorder = Color(0xFFE2E8ED);
  static const lightDivider = Color(0xFFEDF1F4);
  static const lightDisabled = Color(0xFFA6B2BC);
  static const lightInverseSurface = Color(0xFF212C35);
  static const lightOnInverseSurface = Color(0xFFF0F4F6);

  // --- داكن ---
  //
  // ليس انعكاساً للفاتح: الخلفية ليست سوداء، والأسطح ترتفع بالإضاءة لا
  // بالظل، واللون الأساسي **أفتح** من نظيره الفاتح لا أغمق — وهو الخطأ الذي
  // كان في النسق السابق (شريط تطبيق بلون أغمق على خلفية داكنة يختفي).
  static const darkBackground = Color(0xFF141B21);
  static const darkSurfaceLowest = Color(0xFF10171E);
  static const darkSurfaceLow = Color(0xFF181F26);
  static const darkSurface = Color(0xFF1C242B);
  static const darkSurfaceHigh = Color(0xFF232C34);
  static const darkSurfaceVariant = Color(0xFF2A343D);

  static const darkPrimary = Color(0xFF6FBAC4);
  static const darkOnPrimary = Color(0xFF04282E);
  static const darkPrimaryContainer = Color(0xFF1E3A40);
  static const darkOnPrimaryContainer = Color(0xFFA8DCE4);

  static const darkSecondary = Color(0xFF9FBBD4);
  static const darkOnSecondary = Color(0xFF12222F);
  static const darkSecondaryContainer = Color(0xFF243545);
  static const darkOnSecondaryContainer = Color(0xFFC5D9EA);

  static const darkSuccess = Color(0xFF7FC0A2);
  static const darkOnSuccess = Color(0xFF0B2A1D);
  static const darkSuccessContainer = Color(0xFF1A3128);
  static const darkOnSuccessContainer = Color(0xFFA9DCC3);

  static const darkWarning = Color(0xFFE0A458);
  static const darkWarningAccent = Color(0xFFE0A458);
  static const darkWarningContainer = Color(0xFF332616);
  static const darkOnWarningContainer = Color(0xFFF0C894);

  static const darkError = Color(0xFFE39A93);
  static const darkOnError = Color(0xFF3A100C);
  static const darkErrorContainer = Color(0xFF331E1B);
  static const darkOnErrorContainer = Color(0xFFF2C2BC);

  static const darkOnSurface = Color(0xFFE6ECF1);
  static const darkMuted = Color(0xFFB4C0CA);
  static const darkOutline = Color(0xFF54626D);
  static const darkBorder = Color(0xFF33404A);
  static const darkDivider = Color(0xFF28323A);
  static const darkDisabled = Color(0xFF5C6873);
  static const darkInverseSurface = Color(0xFFE6ECF1);
  static const darkOnInverseSurface = Color(0xFF1C242B);
}

// ===========================================================================
// الألوان الدلالية غير الموجودة في ColorScheme
// ===========================================================================

/// نجاح وتحذير ومعلومة وحدود — مفاهيم لا يعرّفها `ColorScheme` في Material.
///
/// تُقرأ عبر `context.drd`.
@immutable
class DrdColors extends ThemeExtension<DrdColors> {
  const DrdColors({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningAccent,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.muted,
    required this.border,
    required this.divider,
    required this.disabled,
  });

  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;

  /// لون نصّ التحذير — يحقّق تباين AA.
  final Color warning;

  /// لون أيقونة/حدّ التحذير — أفتح، لا يُستخدم لنص المتن.
  final Color warningAccent;
  final Color warningContainer;
  final Color onWarningContainer;

  /// المعلومة الهادئة — الأزرق الثانوي، لا الأساسي، حتى لا تُشبه الإجراء.
  final Color info;
  final Color infoContainer;
  final Color onInfoContainer;

  /// النص الثانوي.
  final Color muted;

  /// حدّ شعري حول الأسطح — بديل الظل.
  final Color border;
  final Color divider;
  final Color disabled;

  static const light = DrdColors(
    success: DrdPalette.lightSuccess,
    successContainer: DrdPalette.lightSuccessContainer,
    onSuccessContainer: DrdPalette.lightOnSuccessContainer,
    warning: DrdPalette.lightWarning,
    warningAccent: DrdPalette.lightWarningAccent,
    warningContainer: DrdPalette.lightWarningContainer,
    onWarningContainer: DrdPalette.lightOnWarningContainer,
    info: DrdPalette.lightSecondary,
    infoContainer: DrdPalette.lightSecondaryContainer,
    onInfoContainer: DrdPalette.lightOnSecondaryContainer,
    muted: DrdPalette.lightMuted,
    border: DrdPalette.lightBorder,
    divider: DrdPalette.lightDivider,
    disabled: DrdPalette.lightDisabled,
  );

  static const dark = DrdColors(
    success: DrdPalette.darkSuccess,
    successContainer: DrdPalette.darkSuccessContainer,
    onSuccessContainer: DrdPalette.darkOnSuccessContainer,
    warning: DrdPalette.darkWarning,
    warningAccent: DrdPalette.darkWarningAccent,
    warningContainer: DrdPalette.darkWarningContainer,
    onWarningContainer: DrdPalette.darkOnWarningContainer,
    info: DrdPalette.darkSecondary,
    infoContainer: DrdPalette.darkSecondaryContainer,
    onInfoContainer: DrdPalette.darkOnSecondaryContainer,
    muted: DrdPalette.darkMuted,
    border: DrdPalette.darkBorder,
    divider: DrdPalette.darkDivider,
    disabled: DrdPalette.darkDisabled,
  );

  @override
  DrdColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningAccent,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? muted,
    Color? border,
    Color? divider,
    Color? disabled,
  }) {
    return DrdColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningAccent: warningAccent ?? this.warningAccent,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      muted: muted ?? this.muted,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      disabled: disabled ?? this.disabled,
    );
  }

  @override
  DrdColors lerp(covariant DrdColors? other, double t) {
    if (other == null) return this;
    return DrdColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningAccent: Color.lerp(warningAccent, other.warningAccent, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
    );
  }
}

/// اختصار قراءة الألوان الدلالية: `context.drd.success`.
extension DrdThemeAccess on BuildContext {
  DrdColors get drd => Theme.of(this).extension<DrdColors>() ?? DrdColors.light;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

// ===========================================================================
// المسافات
// ===========================================================================

/// شبكة 4 بكسل. كل حشوة وكل فراغ في التطبيق من هذه القائمة.
abstract final class DrdSpacing {
  /// 4 — بين عنصرين متلاصقين منطقياً (أيقونة ونصها).
  static const double xxs = 4;

  /// 8 — داخل مكوّن صغير.
  static const double xs = 8;

  /// 12 — بين عناصر مجموعة واحدة.
  static const double sm = 12;

  /// 16 — الحشوة القياسية للبطاقات وحواف الشاشة.
  static const double md = 16;

  /// 24 — بين أقسام الصفحة.
  static const double lg = 24;

  /// 32 — فصل بصري واضح.
  static const double xl = 32;

  /// 48 — الحالات الفارغة والمساحات التنفسية الكبيرة.
  static const double xxl = 48;

  /// حشوة حواف الشاشة على الجوال.
  static const EdgeInsets screen = EdgeInsets.symmetric(horizontal: md);

  /// الحشوة الداخلية القياسية لبطاقة.
  static const EdgeInsets card = EdgeInsets.all(md);
}

// ===========================================================================
// الاستدارة
// ===========================================================================

/// ثلاث قيم فقط. كان في التطبيق ثماني قيم مختلفة بلا قاعدة.
abstract final class DrdRadius {
  /// 8 — الحقول والرقاقات والعناصر الصغيرة.
  static const double sm = 8;

  /// 12 — الأزرار.
  static const double md = 12;

  /// 16 — البطاقات والحوارات والأوراق السفلية.
  static const double lg = 16;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
}

// ===========================================================================
// أحجام أخرى
// ===========================================================================

abstract final class DrdSizes {
  /// الحد الأدنى لمساحة اللمس.
  ///
  /// ليس رقماً اعتباطياً: كثير من مستخدمي التطبيق كبار في السن، والهدف
  /// الأصغر يعني ضغطات خاطئة على شاشة تخص مواعيد طبية.
  static const double touchTarget = 48;

  /// سماكة الحدّ الشعري حول الأسطح.
  static const double hairline = 1;

  /// أقصى عرض للمحتوى على الشاشات العريضة، حتى لا يتمدد النص بلا نهاية.
  static const double maxContentWidth = 560;
}
