import 'package:flutter/material.dart';

import 'design_tokens.dart';

export 'design_tokens.dart';

/// نسق التطبيق للوضعين الفاتح والليلي.
///
/// ## لماذا لا يوجد `ColorScheme.fromSeed` هنا
///
/// كان النسق السابق يشتق نحو ثلاثين دوراً لونياً من بذرة فيروزية واحدة.
/// تلك الأسطح المولَّدة خوارزمياً هي سبب الشعور بأن التطبيق «ملوّن» لا
/// «مصمَّم»: كل لون يُختار بعناية ينتهي مصطدماً بلون آخر لم يختره أحد.
///
/// كل دور هنا مكتوب صراحةً. القائمة أطول، لكن ما يظهر على الشاشة هو ما
/// قرّرناه بالضبط.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  // -------------------------------------------------------------------------
  // أنساق الألوان
  // -------------------------------------------------------------------------

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF12707C),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD7EAEC),
    onPrimaryContainer: Color(0xFF06333A),
    secondary: Color(0xFF3F6484),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDEE7EF),
    onSecondaryContainer: Color(0xFF1B2E3F),
    tertiary: Color(0xFF2E7D5B),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFDDEFE5),
    onTertiaryContainer: Color(0xFF103826),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9E4E2),
    onErrorContainer: Color(0xFF48110D),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF141D26),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF8FBFC),
    surfaceContainer: Color(0xFFF3F7F9),
    surfaceContainerHigh: Color(0xFFEDF2F5),
    surfaceContainerHighest: Color(0xFFE9EFF2),
    onSurfaceVariant: Color(0xFF54636F),
    outline: Color(0xFFB9C4CC),
    outlineVariant: Color(0xFFE2E8ED),
    inverseSurface: Color(0xFF212C35),
    onInverseSurface: Color(0xFFF0F4F6),
    inversePrimary: Color(0xFF6FBAC4),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    // الأساسي في الوضع الليلي **أفتح** من نظيره الفاتح. النسق السابق استعمل
    // فيروزياً أغمق، فكان شريط التطبيق يذوب في الخلفية بدل أن يفصلها.
    primary: Color(0xFF6FBAC4),
    onPrimary: Color(0xFF04282E),
    primaryContainer: Color(0xFF1E3A40),
    onPrimaryContainer: Color(0xFFA8DCE4),
    secondary: Color(0xFF9FBBD4),
    onSecondary: Color(0xFF12222F),
    secondaryContainer: Color(0xFF243545),
    onSecondaryContainer: Color(0xFFC5D9EA),
    tertiary: Color(0xFF7FC0A2),
    onTertiary: Color(0xFF0B2A1D),
    tertiaryContainer: Color(0xFF1A3128),
    onTertiaryContainer: Color(0xFFA9DCC3),
    error: Color(0xFFE39A93),
    onError: Color(0xFF3A100C),
    errorContainer: Color(0xFF331E1B),
    onErrorContainer: Color(0xFFF2C2BC),
    surface: Color(0xFF1C242B),
    onSurface: Color(0xFFE6ECF1),
    // الأسطح ترتفع بالإضاءة لا بالظل — الظل لا يُرى على خلفية داكنة.
    surfaceContainerLowest: Color(0xFF10171E),
    surfaceContainerLow: Color(0xFF181F26),
    surfaceContainer: Color(0xFF1C242B),
    surfaceContainerHigh: Color(0xFF232C34),
    surfaceContainerHighest: Color(0xFF2A343D),
    onSurfaceVariant: Color(0xFFB4C0CA),
    outline: Color(0xFF54626D),
    outlineVariant: Color(0xFF33404A),
    inverseSurface: Color(0xFFE6ECF1),
    onInverseSurface: Color(0xFF1C242B),
    inversePrimary: Color(0xFF12707C),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  // -------------------------------------------------------------------------

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = isDark ? _darkScheme : _lightScheme;
    final drd = isDark ? DrdColors.dark : DrdColors.light;
    final base = ThemeData(brightness: brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[drd],

      // الخلفية الهادئة خلف كل شيء؛ البطاقات بيضاء فوقها.
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF141B21) : const Color(0xFFF3F7F9),

      textTheme: _textTheme(base.textTheme, scheme, drd),

      // ---------------------------------------------------------------------
      // شريط التطبيق
      //
      // كان لكل شاشة شريط فيروزي مشبع تُعيد تعيينه بنفسها — 17 موضعاً. النتيجة
      // شريط ثقيل يهيمن على كل شاشة ويجعل التطبيق يبدو كلوحة تحكم.
      //
      // الشريط الآن بلون السطح نفسه، بفاصل شعري أسفله. الهوية تأتي من المحتوى
      // لا من كتلة لون في الأعلى.
      // ---------------------------------------------------------------------
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          height: 1.4,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
        shape: Border(
          bottom: BorderSide(color: drd.border, width: DrdSizes.hairline),
        ),
      ),

      // ---------------------------------------------------------------------
      // الأسطح
      // ---------------------------------------------------------------------
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        // بلا ظل: الفصل بالحدّ الشعري. الظلال المتراكمة كانت تجعل كل بطاقة
        // تبدو وكأنها تطفو فوق الأخرى بلا تسلسل واضح.
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: DrdRadius.lgAll,
          side: BorderSide(color: drd.border, width: DrdSizes.hairline),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: drd.divider,
        thickness: DrdSizes.hairline,
        space: DrdSpacing.md,
      ),

      // ---------------------------------------------------------------------
      // الأزرار
      //
      // ثلاثة مستويات لا أكثر: مملوء = الإجراء الأساسي الوحيد، محدَّد =
      // ثانوي، نصّي = ثالثي وقابل للتراجع. الأحمر للإجراءات المدمّرة وحدها.
      // ---------------------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // في الوضع الليلي يُستخدم لون الحاوية لا الأساسي المشبع: زر فيروزي
          // ساطع على خلفية داكنة يصرخ، وهذا تطبيق طبي لا لعبة.
          backgroundColor: isDark ? scheme.primaryContainer : scheme.primary,
          foregroundColor: isDark ? scheme.onPrimaryContainer : scheme.onPrimary,
          disabledBackgroundColor: drd.disabled.withValues(alpha: 0.25),
          disabledForegroundColor: drd.disabled,
          minimumSize: const Size.fromHeight(DrdSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: DrdSpacing.lg),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: DrdRadius.mdAll),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size.fromHeight(DrdSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: DrdSpacing.lg),
          side: BorderSide(color: drd.border, width: DrdSizes.hairline),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: DrdRadius.mdAll),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, DrdSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: DrdSpacing.sm),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: DrdRadius.smAll),
        ),
      ),

      // `ElevatedButton` لم يعد يُستخدم في التطبيق، لكن تنسيقه هنا يضمن ألّا
      // يظهر أي زر قديم بشكل غريب لو بقي في مكان ما.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? scheme.primaryContainer : scheme.primary,
          foregroundColor: isDark ? scheme.onPrimaryContainer : scheme.onPrimary,
          minimumSize: const Size.fromHeight(DrdSizes.touchTarget),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: DrdRadius.mdAll),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size.square(DrdSizes.touchTarget),
        ),
      ),

      // ---------------------------------------------------------------------
      // الحقول
      //
      // حقول مملوءة بلا إطار خارجي. السبب عملي: التسمية العائمة فوق إطار
      // تحتاج «قطع» الإطار خلفها، وكان ذلك يُنفَّذ بلون أبيض ثابت — فيرسم
      // مستطيلاً أبيض على حقل داكن في الوضع الليلي. الحقل المملوء لا يحتاج
      // قطعاً أصلاً، فالمشكلة تختفي بنيوياً لا بترقيع.
      // ---------------------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DrdSpacing.md,
          vertical: DrdSpacing.md,
        ),
        border: const OutlineInputBorder(
          borderRadius: DrdRadius.smAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: DrdRadius.smAll,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: DrdRadius.smAll,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: DrdRadius.smAll,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: DrdRadius.smAll,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: TextStyle(color: drd.muted, fontSize: 14),
        floatingLabelStyle: TextStyle(color: scheme.primary, fontSize: 13),
        hintStyle: TextStyle(color: drd.disabled, fontSize: 14),
        helperStyle: TextStyle(color: drd.muted, fontSize: 12),
        errorStyle: TextStyle(color: scheme.error, fontSize: 12, height: 1.4),
        prefixIconColor: drd.muted,
        suffixIconColor: drd.muted,
      ),

      // ---------------------------------------------------------------------
      // العناصر الأخرى
      // ---------------------------------------------------------------------
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
        secondaryLabelStyle:
            TextStyle(fontSize: 13, color: scheme.onPrimaryContainer),
        side: BorderSide(color: drd.border, width: DrdSizes.hairline),
        shape:
            const RoundedRectangleBorder(borderRadius: DrdRadius.smAll),
        padding: const EdgeInsets.symmetric(
          horizontal: DrdSpacing.sm,
          vertical: DrdSpacing.xxs,
        ),
        showCheckmark: false,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: DrdRadius.lgAll),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        contentTextStyle: TextStyle(
          fontSize: 15,
          height: 1.6,
          color: scheme.onSurfaceVariant,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DrdRadius.lg),
          ),
        ),
      ),

      // شريط الرسائل المؤقتة يستخدم السطح المعكوس، لا الأحمر ولا الأخضر.
      // نوع الرسالة يُنقل بأيقونة ولون نصّ داخل `AppBanner`، لا بخلفية
      // كاملة تصبغ الشاشة.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 14),
        actionTextColor: scheme.inversePrimary,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: DrdRadius.smAll),
        insetPadding: const EdgeInsets.all(DrdSpacing.md),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearMinHeight: 2,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : null,
        ),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : drd.muted,
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: drd.muted,
        titleTextStyle: TextStyle(fontSize: 15, color: scheme.onSurface),
        subtitleTextStyle: TextStyle(fontSize: 13, color: drd.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DrdSpacing.md,
          vertical: DrdSpacing.xxs,
        ),
        shape: const RoundedRectangleBorder(borderRadius: DrdRadius.smAll),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // الطباعة
  //
  // ملاحظة مهمة: التطبيق **لا يحمل خطاً عربياً مخصصاً**. لا `google_fonts`
  // ولا ملفات خط في `assets`. النص العربي يُرسم بخط النظام الاحتياطي، وهو
  // ليس خطاً مصمَّماً للعربية. راجع تقرير المرحلة: إضافة خط (Cairo مثلاً)
  // تحتاج قراراً منفصلاً لأنها تُضيف أصولاً أو اعتماداً جديداً.
  //
  // ما يمكن ضبطه بلا خط مخصص — وهو أهم نصف المسألة — هو المقياس والوزن
  // وارتفاع السطر. العربية تحتاج ارتفاع سطر أكبر من اللاتينية، ولذلك
  // 1.6–1.7 لنص المتن.
  // -------------------------------------------------------------------------
  static TextTheme _textTheme(
    TextTheme base,
    ColorScheme scheme,
    DrdColors drd,
  ) {
    TextStyle style(
      double size,
      FontWeight weight,
      Color color, {
      double height = 1.5,
      double spacing = 0,
    }) {
      return TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing,
      );
    }

    return base.copyWith(
      // عنوان الصفحة
      headlineSmall: style(28, FontWeight.w700, scheme.onSurface, height: 1.3),
      // عنوان قسم كبير
      titleLarge: style(22, FontWeight.w600, scheme.onSurface, height: 1.35),
      // عنوان بطاقة
      titleMedium: style(17, FontWeight.w600, scheme.onSurface, height: 1.4),
      // عنوان فرعي
      titleSmall: style(15, FontWeight.w600, scheme.onSurface, height: 1.45),
      // نص المتن — الارتفاع 1.7 للعربية
      bodyLarge: style(16, FontWeight.w400, scheme.onSurface, height: 1.7),
      bodyMedium: style(15, FontWeight.w400, scheme.onSurface, height: 1.65),
      // نص ثانوي
      bodySmall: style(13, FontWeight.w400, drd.muted, height: 1.6),
      // تسميات
      labelLarge: style(15, FontWeight.w600, scheme.onSurface, height: 1.4),
      labelMedium: style(13, FontWeight.w500, drd.muted, height: 1.4),
      // نص مساعد / خطأ
      labelSmall: style(12, FontWeight.w400, drd.muted, height: 1.5),
    );
  }
}
