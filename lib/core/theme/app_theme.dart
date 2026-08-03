import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// نظام التصميم لتطبيق DrD.
///
/// ## الفكرة اللي التصميم قايم عليها
///
/// المنتج ده مش «تطبيق طبي» عام — هو وعد بحاجة واحدة: **إنك تعرف دقيقتك
/// بالظبط فمتقعدش تستنى**. عشان كده الوقت هو بطل الشاشة: الأرقام كبيرة،
/// بخط بأعمدة متساوية (tabular)، والعدّاد أوضح عنصر في التطبيق كله.
///
/// اللون الفيروزي متسيب زي ما هو لأنه هوية التطبيق (الشعار والأيقونات)،
/// بس اتظبط: درجة أعمق وأهدى للأساسي، ورمادي مايل للسماوي بدل الرمادي
/// المحايد اللي بيدّي إحساس إن التصميم مش مقصود.
class AppColors {
  const AppColors._();

  // ── الهوية ──────────────────────────────────────────────
  /// الفيروزي الطبي — لون الشعار.
  static const Color brand = Color(0xFF00838F);
  static const Color brandBright = Color(0xFF00ACC1);
  static const Color brandDeep = Color(0xFF00363D);
  static const Color brandTint = Color(0xFFE0F4F6);

  /// لون ثانوي دافئ يكسر برودة الأزرق الطبي دون أن ينافس الهوية.
  /// يُستخدم بحساب: التقييمات والتمييزات الصغيرة فقط.
  static const Color accent = Color(0xFFE8A33D);

  // ── ألوان دلالية (منفصلة عن الهوية عمداً) ───────────────
  static const Color success = Color(0xFF1E7A46);
  static const Color warning = Color(0xFFC46A0A);
  static const Color danger = Color(0xFFB3261E);

  // ── الأسطح والنصوص: فاتح ────────────────────────────────
  static const Color bgLight = Color(0xFFF4F7F8);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceAltLight = Color(0xFFEAF1F3);
  static const Color lineLight = Color(0xFFDCE6E9);
  static const Color inkLight = Color(0xFF12242A);
  static const Color inkMutedLight = Color(0xFF566B73);

  // ── الأسطح والنصوص: داكن ────────────────────────────────
  static const Color bgDark = Color(0xFF0C1315);
  static const Color surfaceDark = Color(0xFF152024);
  static const Color surfaceAltDark = Color(0xFF1C292E);
  static const Color lineDark = Color(0xFF2A383D);
  static const Color inkDark = Color(0xFFE3EBED);
  static const Color inkMutedDark = Color(0xFF9CADB4);
}

/// المسافات — سلّم واحد يمنع الأرقام العشوائية المتناثرة في الشاشات.
class Gap {
  const Gap._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// أنصاف أقطار الحواف.
class Radii {
  const Radii._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double pill = 999;
}

class AppTheme {
  const AppTheme._();

  /// الخط: IBM Plex Sans Arabic.
  ///
  /// الخطوط الافتراضية للنظام هي أكتر حاجة بتخلي تطبيق عربي يبان غير
  /// محترف — بتختلف من جهاز لجهاز وأوزانها محدودة. الخط ده له أربع أوزان
  /// حقيقية وأرقامه واضحة، وهو مهم هنا تحديداً لأن الأرقام (المواعيد
  /// والعدّاد) هي محور الواجهة.
  static const String fontFamily = 'IBMPlexSansArabic';

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final surfaceAlt =
        isDark ? AppColors.surfaceAltDark : AppColors.surfaceAltLight;
    final line = isDark ? AppColors.lineDark : AppColors.lineLight;
    final ink = isDark ? AppColors.inkDark : AppColors.inkLight;
    final inkMuted = isDark ? AppColors.inkMutedDark : AppColors.inkMutedLight;
    // الفيروزي الداكن ما بيقراش على خلفية سودا، فبيفتح في الوضع الليلي.
    final primary = isDark ? AppColors.brandBright : AppColors.brand;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: isDark ? const Color(0xFF00272C) : Colors.white,
      primaryContainer: isDark ? AppColors.brandDeep : AppColors.brandTint,
      onPrimaryContainer: isDark ? AppColors.brandTint : AppColors.brandDeep,
      secondary: AppColors.accent,
      onSecondary: const Color(0xFF3D2600),
      error: AppColors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: surfaceAlt,
      onSurfaceVariant: inkMuted,
      outline: line,
      outlineVariant: line,
    );

    // سلّم أحجام ثابت — كل نص في التطبيق بيشتق منه.
    final text = TextTheme(
      displaySmall: TextStyle(
          fontSize: 34, fontWeight: FontWeight.w700, height: 1.2, color: ink),
      headlineMedium: TextStyle(
          fontSize: 26, fontWeight: FontWeight.w700, height: 1.25, color: ink),
      headlineSmall: TextStyle(
          fontSize: 21, fontWeight: FontWeight.w700, height: 1.3, color: ink),
      titleLarge: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, height: 1.35, color: ink),
      titleMedium: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, height: 1.4, color: ink),
      bodyLarge: TextStyle(
          fontSize: 15.5, fontWeight: FontWeight.w400, height: 1.6, color: ink),
      bodyMedium: TextStyle(
          fontSize: 14.5, fontWeight: FontWeight.w400, height: 1.6, color: ink),
      bodySmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: inkMuted),
      labelLarge:
          TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: ink),
      labelSmall: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: .4,
          color: inkMuted),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      textTheme: text,
      dividerColor: line,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surfaceAltDark : surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.lg),
        hintStyle: text.bodyMedium?.copyWith(color: inkMuted),
        labelStyle: text.bodyMedium?.copyWith(color: inkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: BorderSide(color: primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: colorScheme.onPrimary,
          // 52 بكسل — أكبر من الحد الأدنى، لأن جزء كبير من المستخدمين كبار سن.
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
              fontFamily: fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.sm)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: line, width: 1.5),
          textStyle: const TextStyle(
              fontFamily: fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.sm)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(
              fontFamily: fontFamily,
              fontSize: 14.5,
              fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.surfaceAltDark : AppColors.inkLight,
        contentTextStyle: const TextStyle(
            fontFamily: fontFamily, fontSize: 14.5, color: Colors.white),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.sm)),
        insetPadding: const EdgeInsets.all(Gap.lg),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        side: BorderSide(color: line),
        labelStyle: text.bodySmall?.copyWith(color: ink),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.pill)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: inkMuted,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: surfaceAlt,
        circularTrackColor: surfaceAlt,
      ),
    );
  }
}

/// نمط الأرقام: أعمدة متساوية العرض.
///
/// من غيره الأرقام «بترقص» أثناء العدّ التنازلي لأن عرض كل رقم مختلف —
/// وهو أوضح تفصيلة بتفرق بين واجهة متقنة وواجهة عادية.
const List<FontFeature> kTabularFigures = [FontFeature.tabularFigures()];
