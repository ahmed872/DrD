import 'package:flutter/material.dart';

import 'app_spacing.dart';
import 'app_typography.dart';

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

  /// نجمة التقييم. كانت تُرسم بلون `tertiary` المشتقّ من البذرة — بنفسجي
  /// لا يقرأه أحد نجمةَ تقييم. الذهبي هو العرف، وتباينه على السطح الفاتح
  /// كافٍ لأنه رمز لا نصّ.
  static const Color rating = Color(0xFFE8A317);

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFEF6C00);
  static const Color danger = Color(0xFFB3261E);

  /// خلفية الصفحة. كانت `#F5F7FA` — أفتح من أن تُميّز عن بطاقة بيضاء،
  /// فبدت الشاشات مسطّحة بلا طبقات. هذه أعمق قليلاً فتظهر البطاقة فوقها.
  static const Color surfaceLight = Color(0xFFEEF2F5);
  static const Color surfaceDark = Color(0xFF0B1113);

  /// سطح البطاقة — أبيض صريح في الفاتح، وأفتح من الخلفية في الليلي.
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF161E21);
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
      // الأحمر الداكن يصلح خلفيةً لنص أبيض في الوضع الفاتح، لكن فرضه في
      // الوضع الليلي أنتج تبايناً 2:1 بين `onError` و`error` — أي نص غير
      // مقروء على أهم رسالة في التطبيق. في الليلي يشتق Material أحمر أفتح
      // يحقق الحد المطلوب. (يحرسه `test/theme_widgets_test.dart`.)
      error: isDark ? null : AppColors.danger,
    );

    // أدوار الأسطح تُضبط يدوياً: `fromSeed` يشتقّ رماديات مائلة إلى
    // الفيروزي، فتصير الخلفية والبطاقة متقاربتين ويختفي الإحساس بالطبقات.
    final scheme = colorScheme.copyWith(
      // أدوار العلامة صريحة لا مشتقّة: `fromSeed` من بذرة فيروزية مشبعة
      // يعطي `primaryContainer` سماوياً فاقعاً يشبه قلم التظليل، فتبدو
      // البطاقة البارزة صارخة لا فاخرة. هذه أهدأ، وتباينها مقيس:
      // 10.53:1 فاتح و7.81:1 ليلي بين الحاوية ونصّها.
      primary: isDark ? const Color(0xFF7FD4DE) : const Color(0xFF00707C),
      onPrimary: isDark ? const Color(0xFF00333A) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF0D454D) : const Color(0xFFD2E9EC),
      onPrimaryContainer:
          isDark ? const Color(0xFFBCE4EA) : const Color(0xFF04353B),
      surface: isDark ? AppColors.cardDark : AppColors.cardLight,
      surfaceContainerLowest: isDark ? AppColors.surfaceDark : Colors.white,
      surfaceContainerLow:
          isDark ? const Color(0xFF121A1D) : const Color(0xFFF7F9FB),
      surfaceContainer:
          isDark ? const Color(0xFF161E21) : const Color(0xFFF1F5F7),
      surfaceContainerHigh:
          isDark ? const Color(0xFF1B2528) : const Color(0xFFE9EFF2),
      surfaceContainerHighest:
          isDark ? const Color(0xFF212C30) : const Color(0xFFE1E9ED),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppTypography.family,
      textTheme: AppTypography.textTheme(scheme),
      // `ThemeData` يختار افتراضياً كثافة سطح المكتب على الويب، فتنقص 8 بكسل
      // من ارتفاع كل زر: الـ 48 المقصودة أدناه تصير 40 على المتصفّح وحده.
      // والتطبيق يُستخدم كـ PWA على متصفّح الهاتف، فيصغر هدف اللمس على نفس
      // الشاشة التي يكون فيها 48 في النسخة الأصلية. نثبّت الكثافة القياسية
      // ليكون ما نقيسه في المتصفّح هو ما يراه المستخدم على هاتفه.
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor:
          isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      // شريط التطبيق: كان لوحاً فيروزياً مشبعاً بعرض الشاشة ونصّاً أبيض —
      // أكثر عنصر يجعل الواجهة تبدو قديمة، ويسرق الانتباه من المحتوى.
      // صار بلون الخلفية نفسها فيذوب فيها، والعلامة تظهر حيث تفيد: في
      // الأزرار والحالات. والعنوان إلى البداية لا في الوسط — أقرب إلى
      // القراءة العربية وأوضح في التسلسل.
      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleSpacing: AppSpacing.lg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.textTheme(scheme).titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1A2226) : Colors.white,
        // يمنع تداخل نص التسمية مع الحد عند الكتابة بالعربية.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 48 بكسل هو الحد الأدنى الموصى به لمساحة اللمس، ومهم هنا لأن
          // كثيراً من المستخدمين كبار سن.
          minimumSize: const Size.fromHeight(52),
          textStyle: AppTypography.textTheme(scheme).labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: AppTypography.textTheme(scheme).labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
        ),
      ),
      // الأزرار النصية («نسيت كلمة المرور؟»، «سجل الآن») كانت 32 بكسل ارتفاعاً
      // على الويب: `ThemeData` يختار كثافة سطح المكتب هناك فتنكمش، بينما
      // هي 48 على الهاتف. والتطبيق يُستخدم كـ PWA على متصفّح الهاتف أيضاً،
      // فيصبح الرابط أصغر من الحد الأدنى للمس على نفس الشاشة تماماً.
      // القياس أعلاه من شجرة الدلالات في متصفّح فعلي، لا تقدير.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: AppTypography.textTheme(scheme).labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
        ),
      ),
      // ظلّ خفيف واحد على البطاقات، وحدّ في الوضع الليلي وحده حيث لا يُرى
      // الظلّ. «ظلّ على كل شيء» يلغي معنى الظلّ.
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        shadowColor: const Color(0x14000000),
        surfaceTintColor: Colors.transparent,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: isDark
              ? BorderSide(color: scheme.outlineVariant)
              : BorderSide.none,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: AppTypography.textTheme(scheme).labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        titleTextStyle: AppTypography.textTheme(scheme).titleLarge,
        contentTextStyle: AppTypography.textTheme(scheme).bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: AppTypography.textTheme(scheme)
            .bodyMedium
            ?.copyWith(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    );
  }
}
