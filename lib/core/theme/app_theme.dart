import 'package:flutter/material.dart';

/// ألوان التطبيق ونسقه في مكان واحد.
///
/// التطبيق كان يحتوي على 471 استدعاءً مباشراً لـ `Colors.*` موزّعة على
/// الشاشات، مع لونين أساسيين متضاربين: `Colors.blue` في `main.dart` و
/// `#0097A7` في شاشات أخرى. النتيجة واجهة غير متّسقة ولا سبيل لدعم الوضع
/// الليلي. هذا الملف هو المرجع الوحيد للألوان من الآن.
class AppColors {
  const AppColors._();

  /// الفيروزي الطبي — اللون المعتمد للتطبيق، وهو المستخدم في الشاشات
  /// الأحدث ولون `theme_color` في manifest.json.
  static const Color primary = Color(0xFF0097A7);
  static const Color primaryDark = Color(0xFF00363D);
  static const Color primaryLight = Color(0xFFB2EBF2);

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFEF6C00);
  static const Color danger = Color(0xFFB3261E);

  static const Color surfaceLight = Color(0xFFF5F7FA);
  static const Color surfaceDark = Color(0xFF0E1416);
}

/// نسق التطبيق للوضعين الفاتح والليلي.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.primaryDark : AppColors.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        // بدون هذا يرسم Material 3 لوناً مختلفاً عند تمرير المحتوى تحت الشريط.
        scrolledUnderElevation: 2,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        actionTextColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1A2226) : Colors.white,
        // يمنع تداخل نص التسمية مع الحد عند الكتابة بالعربية.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 48 بكسل هو الحد الأدنى الموصى به لمساحة اللمس، ومهم هنا لأن
          // كثيراً من المستخدمين كبار سن.
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
