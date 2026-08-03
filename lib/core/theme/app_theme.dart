/// نظام التصميم الكامل للتطبيق: الألوان، الخطوط، المسافات، الحواف، الظلال.
///
/// كان التطبيق يحتوي على أكثر من 470 استدعاءً مباشراً لـ `Colors.*` موزّعة على
/// الشاشات، بلونين أساسيين متضاربين (أزرق وفيروزي) وأخضر ثالث للأزرار. النتيجة
/// واجهة غير متّسقة، ووضع ليلي مكسور تماماً (نصوص رمادية على خلفيات بيضاء
/// مثبَّتة). هذا الملف هو المرجع الوحيد لكل قرار بصري في التطبيق.
///
/// القاعدة: لا يُكتب لون خام داخل أي شاشة. تُؤخذ الألوان إمّا من
/// `Theme.of(context).colorScheme` أو من `context.tokens`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// اللوحة الخام
// =============================================================================

/// درجات العلامة والمحايدات. لا تُستعمل مباشرة في الشاشات — استخدم
/// `colorScheme` أو `context.tokens` حتى يعمل الوضع الليلي تلقائياً.
class AppPalette {
  const AppPalette._();

  // الفيروزي الطبي — تطوير للّون الأصلي 0097A7 مع سُلّم كامل يسمح ببناء
  // تدرّجات وحالات (hover/selected/disabled) دون تخمين.
  static const Color brand50 = Color(0xFFE8F7F9);
  static const Color brand100 = Color(0xFFC5ECF0);
  static const Color brand200 = Color(0xFF97DEE6);
  static const Color brand300 = Color(0xFF63CCD8);
  static const Color brand400 = Color(0xFF31B8C6);
  static const Color brand500 = Color(0xFF12A2B2);
  static const Color brand600 = Color(0xFF0A8C9B);
  static const Color brand700 = Color(0xFF077180);
  static const Color brand800 = Color(0xFF085C67);
  static const Color brand900 = Color(0xFF0A424A);

  // محايدات بميل بارد خفيف نحو الفيروزي حتى لا يبدو الرمادي «متّسخاً» بجوار
  // لون العلامة.
  static const Color ink900 = Color(0xFF0B1F24);
  static const Color ink800 = Color(0xFF16323A);
  static const Color ink700 = Color(0xFF2C4349);
  static const Color ink600 = Color(0xFF44595F);
  static const Color ink500 = Color(0xFF5F777E);
  static const Color ink400 = Color(0xFF85999F);
  static const Color ink300 = Color(0xFFAFC1C6);
  static const Color ink200 = Color(0xFFD8E3E6);
  static const Color ink100 = Color(0xFFEAF1F3);
  static const Color ink50 = Color(0xFFF4F8F9);

  // ألوان الحالة. لكل واحدة درجة أساسية ودرجة خلفية هادئة.
  static const Color success = Color(0xFF0E9D6E);
  static const Color successSoft = Color(0xFFE4F6EF);
  static const Color warning = Color(0xFFC97706);
  static const Color warningSoft = Color(0xFFFDF1E0);
  static const Color danger = Color(0xFFD03A3A);
  static const Color dangerSoft = Color(0xFFFCEBEB);
  static const Color info = Color(0xFF2E6FE0);
  static const Color infoSoft = Color(0xFFE9F0FD);

  /// نجوم التقييم فقط — ليست لوناً عامّاً.
  static const Color gold = Color(0xFFF0AF1B);

  /// أخضر واتساب الرسمي، يُستعمل لزر التواصل وحده.
  static const Color whatsapp = Color(0xFF25D366);

  // أسطح الوضع الليلي: ثلاث طبقات متدرّجة بدل لون واحد، وإلا اختفت الحدود
  // بين البطاقة والخلفية.
  static const Color darkBg = Color(0xFF091316);
  static const Color darkSurface = Color(0xFF101F23);
  static const Color darkSurfaceHigh = Color(0xFF172C32);
  static const Color darkBorder = Color(0xFF244047);
}

// =============================================================================
// المسافات والحواف
// =============================================================================

/// سُلّم مسافات ثابت. الأرقام العشوائية (13، 18، 36) كانت السبب الأول في
/// شعور الواجهة بعدم الترتيب.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double xxxl = 40;
}

/// أنصاف أقطار الحواف.
class AppRadius {
  const AppRadius._();

  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;

  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));
}

/// عرض المحتوى الأقصى على الشاشات الكبيرة.
///
/// التطبيق يُفتح من المتصفح على سطح المكتب، وبدون هذه الحدود يمتد النموذج
/// على 1900 بكسل فتصبح حقول الإدخال أشرطة عرضها متر — وهو أوضح ما يفضح أن
/// الواجهة صُمّمت للهاتف ونُشرت على الويب كما هي.
class AppBreakpoints {
  const AppBreakpoints._();

  /// نماذج وحقول إدخال (تسجيل الدخول، الإعدادات).
  static const double form = 480;

  /// محتوى قرائي (قوائم، تفاصيل).
  static const double content = 720;

  /// شبكات وبطاقات متعدّدة الأعمدة.
  static const double wide = 1080;

  /// الحدّ الذي يُعتبر بعده العرض «سطح مكتب».
  static const double desktop = 900;
}

// =============================================================================
// الرموز المرتبطة بالنسق (تعمل في الوضعين تلقائياً)
// =============================================================================

/// القيم التي يحتاجها التطبيق ولا يوفّرها `ColorScheme`: ألوان الحالة،
/// درجات النص الثانوي، التدرّجات، والظلال.
///
/// تُقرأ عبر `context.tokens`، فتتبدّل مع الوضع الليلي دون أي شرط في الشاشات.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.textStrong,
    required this.textBody,
    required this.textMuted,
    required this.textFaint,
    required this.border,
    required this.borderStrong,
    required this.surfaceSunken,
    required this.surfaceRaised,
    required this.success,
    required this.onSuccessSoft,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.gold,
    required this.whatsapp,
    required this.brandGradient,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
  });

  /// عناوين وأرقام بارزة.
  final Color textStrong;

  /// نص الفقرات.
  final Color textBody;

  /// تسميات وشروح ثانوية.
  final Color textMuted;

  /// نص باهت جداً: العناصر المعطّلة وحالات الفراغ.
  final Color textFaint;

  final Color border;
  final Color borderStrong;

  /// خلفية أغمق قليلاً من السطح — لمناطق الإدخال والشرائح غير المختارة.
  final Color surfaceSunken;

  /// سطح مرتفع فوق خلفية الصفحة (البطاقات).
  final Color surfaceRaised;

  final Color success;
  final Color onSuccessSoft;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;
  final Color gold;
  final Color whatsapp;

  /// تدرّج العلامة المستخدم في الرؤوس والأزرار الرئيسية.
  final Gradient brandGradient;

  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowLg;

  /// لون الحالة المطابق لحالة الموعد، بلا جداول ألوان مكرّرة في كل شاشة.
  Color statusColor(String status) {
    switch (status) {
      case 'Completed':
        return success;
      case 'Cancelled':
      case 'Rejected':
        return danger;
      case 'pending':
        return warning;
      default:
        return info;
    }
  }

  Color statusSoft(String status) {
    switch (status) {
      case 'Completed':
        return successSoft;
      case 'Cancelled':
      case 'Rejected':
        return dangerSoft;
      case 'pending':
        return warningSoft;
      default:
        return infoSoft;
    }
  }

  static const AppTokens _light = AppTokens(
    textStrong: AppPalette.ink900,
    textBody: AppPalette.ink700,
    textMuted: AppPalette.ink500,
    textFaint: AppPalette.ink400,
    border: AppPalette.ink200,
    borderStrong: AppPalette.ink300,
    surfaceSunken: AppPalette.ink100,
    surfaceRaised: Colors.white,
    success: AppPalette.success,
    onSuccessSoft: Color(0xFF076B4B),
    successSoft: AppPalette.successSoft,
    warning: AppPalette.warning,
    warningSoft: AppPalette.warningSoft,
    danger: AppPalette.danger,
    dangerSoft: AppPalette.dangerSoft,
    info: AppPalette.info,
    infoSoft: AppPalette.infoSoft,
    gold: AppPalette.gold,
    whatsapp: AppPalette.whatsapp,
    brandGradient: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [AppPalette.brand700, AppPalette.brand400],
    ),
    // ظلال ناعمة بطبقتين. ظلّ Material الافتراضي رمادي مائل للأسود ويجعل
    // البطاقات تبدو «متسخة» فوق خلفية باردة.
    shadowSm: [
      BoxShadow(
        color: Color(0x0D0B1F24),
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x0F0B1F24),
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
      BoxShadow(
        color: Color(0x0A0B1F24),
        blurRadius: 4,
        offset: Offset(0, 1),
      ),
    ],
    shadowLg: [
      BoxShadow(
        color: Color(0x1A0B1F24),
        blurRadius: 32,
        offset: Offset(0, 12),
      ),
    ],
  );

  static const AppTokens _dark = AppTokens(
    textStrong: Color(0xFFEAF2F4),
    textBody: Color(0xFFC7D6DA),
    textMuted: Color(0xFF93A9AF),
    textFaint: Color(0xFF6B848B),
    border: AppPalette.darkBorder,
    borderStrong: Color(0xFF335159),
    surfaceSunken: Color(0xFF0D1A1E),
    surfaceRaised: AppPalette.darkSurface,
    success: Color(0xFF3FCC9B),
    onSuccessSoft: Color(0xFF7FE3C1),
    successSoft: Color(0xFF10322A),
    warning: Color(0xFFE9A23B),
    warningSoft: Color(0xFF33260F),
    danger: Color(0xFFF07070),
    dangerSoft: Color(0xFF3A1D1D),
    info: Color(0xFF6E9CF0),
    infoSoft: Color(0xFF16243F),
    gold: Color(0xFFF5C55D),
    whatsapp: AppPalette.whatsapp,
    brandGradient: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [AppPalette.brand900, AppPalette.brand700],
    ),
    shadowSm: [
      BoxShadow(
        color: Color(0x40000000),
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x59000000),
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
    ],
    shadowLg: [
      BoxShadow(
        color: Color(0x73000000),
        blurRadius: 32,
        offset: Offset(0, 12),
      ),
    ],
  );

  @override
  AppTokens copyWith({
    Color? textStrong,
    Color? textBody,
    Color? textMuted,
    Color? textFaint,
    Color? border,
    Color? borderStrong,
    Color? surfaceSunken,
    Color? surfaceRaised,
    Color? success,
    Color? onSuccessSoft,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? infoSoft,
    Color? gold,
    Color? whatsapp,
    Gradient? brandGradient,
    List<BoxShadow>? shadowSm,
    List<BoxShadow>? shadowMd,
    List<BoxShadow>? shadowLg,
  }) {
    return AppTokens(
      textStrong: textStrong ?? this.textStrong,
      textBody: textBody ?? this.textBody,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      success: success ?? this.success,
      onSuccessSoft: onSuccessSoft ?? this.onSuccessSoft,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      gold: gold ?? this.gold,
      whatsapp: whatsapp ?? this.whatsapp,
      brandGradient: brandGradient ?? this.brandGradient,
      shadowSm: shadowSm ?? this.shadowSm,
      shadowMd: shadowMd ?? this.shadowMd,
      shadowLg: shadowLg ?? this.shadowLg,
    );
  }

  @override
  AppTokens lerp(covariant ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      textStrong: Color.lerp(textStrong, other.textStrong, t)!,
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccessSoft: Color.lerp(onSuccessSoft, other.onSuccessSoft, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      whatsapp: Color.lerp(whatsapp, other.whatsapp, t)!,
      brandGradient: Gradient.lerp(brandGradient, other.brandGradient, t)!,
      shadowSm: BoxShadow.lerpList(shadowSm, other.shadowSm, t)!,
      shadowMd: BoxShadow.lerpList(shadowMd, other.shadowMd, t)!,
      shadowLg: BoxShadow.lerpList(shadowLg, other.shadowLg, t)!,
    );
  }
}

/// اختصار قراءة الرموز: `context.tokens.textMuted`.
extension AppTokensX on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens._light;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;

  /// هل نحن على شاشة عريضة (متصفح سطح مكتب)؟
  bool get isDesktop => MediaQuery.sizeOf(this).width >= AppBreakpoints.desktop;
}

// =============================================================================
// النسق
// =============================================================================

class AppTheme {
  const AppTheme._();

  /// خط عربي مُضمَّن مع التطبيق.
  ///
  /// بدونه يستعمل محرّك الويب خط الاحتياط الذي ينزّله CanvasKit من gstatic
  /// وقت التشغيل: يظهر النص بخط مختلف على كل جهاز، ويختفي تماماً خلف الشبكات
  /// التي تحجب gstatic — وهي الحالة التي بُني لها هذا المشروع أصلاً.
  static const String fontFamily = 'Cairo';

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final tokens = isDark ? AppTokens._dark : AppTokens._light;

    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary: AppPalette.brand300,
            onPrimary: AppPalette.brand900,
            primaryContainer: AppPalette.brand800,
            onPrimaryContainer: AppPalette.brand100,
            secondary: AppPalette.brand400,
            onSecondary: AppPalette.brand900,
            surface: AppPalette.darkSurface,
            onSurface: Color(0xFFEAF2F4),
            surfaceContainerHighest: AppPalette.darkSurfaceHigh,
            outline: AppPalette.darkBorder,
            outlineVariant: AppPalette.darkBorder,
            error: Color(0xFFF07070),
            onError: Color(0xFF3A1D1D),
          )
        : const ColorScheme.light(
            primary: AppPalette.brand600,
            onPrimary: Colors.white,
            primaryContainer: AppPalette.brand50,
            onPrimaryContainer: AppPalette.brand800,
            secondary: AppPalette.brand500,
            onSecondary: Colors.white,
            surface: Colors.white,
            onSurface: AppPalette.ink900,
            surfaceContainerHighest: AppPalette.ink100,
            outline: AppPalette.ink300,
            outlineVariant: AppPalette.ink200,
            error: AppPalette.danger,
            onError: Colors.white,
          );

    final textTheme = _textTheme(tokens);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark ? AppPalette.darkBg : AppPalette.ink50,
      canvasColor: isDark ? AppPalette.darkBg : AppPalette.ink50,
      splashFactory: InkSparkle.splashFactory,
      extensions: [tokens],

      // شريط علوي شفّاف: الرؤوس المتدرّجة تُرسم داخل كل شاشة، فيبقى الشريط
      // طبقة نص وأيقونات فقط.
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      cardTheme: CardThemeData(
        color: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.rLg,
          side: BorderSide(color: tokens.border),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: tokens.border,
        thickness: 1,
        space: 1,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppPalette.darkSurfaceHigh : Colors.white,
        // يمنع تداخل نص التسمية مع الحدّ عند الكتابة بالعربية.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        prefixIconColor: tokens.textMuted,
        suffixIconColor: tokens.textMuted,
        hintStyle: textTheme.bodyMedium?.copyWith(color: tokens.textFaint),
        labelStyle: textTheme.labelMedium?.copyWith(color: tokens.textMuted),
        floatingLabelStyle:
            textTheme.labelMedium?.copyWith(color: colorScheme.primary),
        border: _inputBorder(tokens.border),
        enabledBorder: _inputBorder(tokens.border),
        focusedBorder: _inputBorder(colorScheme.primary, width: 1.8),
        errorBorder: _inputBorder(tokens.danger),
        focusedErrorBorder: _inputBorder(tokens.danger, width: 1.8),
        errorStyle: textTheme.bodySmall?.copyWith(color: tokens.danger),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 52 بكسل مساحة لمس مريحة؛ جزء كبير من مستخدمي التطبيق كبار سن.
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd),
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd),
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: colorScheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          side: BorderSide(color: tokens.borderStrong),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.rSm),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.textBody,
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: tokens.surfaceSunken,
        selectedColor: colorScheme.primary,
        checkmarkColor: colorScheme.onPrimary,
        side: BorderSide(color: tokens.border),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rPill),
        labelStyle: textTheme.labelMedium!.copyWith(color: tokens.textBody),
        secondaryLabelStyle:
            textTheme.labelMedium!.copyWith(color: colorScheme.onPrimary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        showCheckmark: false,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rXl),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: tokens.borderStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? AppPalette.darkSurfaceHigh : AppPalette.ink800,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: AppPalette.brand200,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd),
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: tokens.textMuted,
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: tokens.textMuted,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark ? AppPalette.ink400 : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colorScheme.primary;
          return tokens.surfaceSunken;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colorScheme.primary;
          return tokens.borderStrong;
        }),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colorScheme.primary;
          return tokens.borderStrong;
        }),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colorScheme.primary;
          return Colors.transparent;
        }),
        side: BorderSide(color: tokens.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: tokens.surfaceSunken,
        circularTrackColor: tokens.surfaceSunken,
        strokeWidth: 3,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: tokens.textMuted,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? AppPalette.darkSurfaceHigh : AppPalette.ink800,
          borderRadius: AppRadius.rSm,
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rXl),
        headerBackgroundColor: colorScheme.primary,
        headerForegroundColor: colorScheme.onPrimary,
      ),

      timePickerTheme: TimePickerThemeData(
        backgroundColor: tokens.surfaceRaised,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rXl),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.rMd,
          side: BorderSide(color: tokens.border),
        ),
        textStyle: textTheme.bodyMedium,
      ),

      // منع الحركة الأفقية الافتراضية على الويب: انتقال iOS/أندرويد يبدو
      // غريباً داخل تبويب متصفح، والتلاشي أسرع إحساساً.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: AppRadius.rMd,
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// سُلّم نصوص مضبوط للعربية.
  ///
  /// فارقان مهمّان عن الافتراضي: `letterSpacing: 0` — أي تباعد حروف يفصل
  /// الحروف العربية المتّصلة بصرياً ويجعل النص يبدو مكسوراً — و`height` أعلى،
  /// لأن العربية بها علامات فوق وتحت السطر تتلامس عند التقارب.
  static TextTheme _textTheme(AppTokens tokens) {
    TextStyle s(
      double size,
      FontWeight weight, {
      double height = 1.45,
      Color? color,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: 0,
        color: color ?? tokens.textStrong,
      );
    }

    return TextTheme(
      displayLarge: s(38, FontWeight.w800, height: 1.25),
      displayMedium: s(32, FontWeight.w800, height: 1.28),
      displaySmall: s(28, FontWeight.w700, height: 1.3),
      headlineLarge: s(26, FontWeight.w700, height: 1.32),
      headlineMedium: s(23, FontWeight.w700, height: 1.35),
      headlineSmall: s(20, FontWeight.w700, height: 1.4),
      titleLarge: s(18, FontWeight.w700, height: 1.4),
      titleMedium: s(16, FontWeight.w600, height: 1.45),
      titleSmall: s(14.5, FontWeight.w600, height: 1.45),
      bodyLarge: s(15.5, FontWeight.w400, height: 1.6, color: tokens.textBody),
      bodyMedium: s(14, FontWeight.w400, height: 1.6, color: tokens.textBody),
      bodySmall:
          s(12.5, FontWeight.w400, height: 1.55, color: tokens.textMuted),
      labelLarge: s(15, FontWeight.w600, height: 1.3),
      labelMedium:
          s(13, FontWeight.w600, height: 1.35, color: tokens.textMuted),
      labelSmall:
          s(11.5, FontWeight.w600, height: 1.35, color: tokens.textMuted),
    );
  }
}
