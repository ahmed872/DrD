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

  // ===================== المرحلة 11: لوحة رعاية هادئة =====================
  //
  // ما أظهره الفحص على جهاز حقيقي: التطبيق يبدو «تقنياً» لا طبياً — خلفية
  // ليلية تقارب الأسود (#0B1113)، وفيروزي فاتح مشبع (#7FD4DE) على كل زرّ،
  // وكتل حمراء واسعة في الإعدادات. المريض لا يريد لوحة تحكم؛ يريد شاشة
  // تطمئنه.
  //
  // المبدأ هنا: **الفاتح هو التجربة الأساسية**، والليلي نسخة هادئة منه لا
  // نقيضه. لا أسود صريح، ولا نيون، ولا أحمر إلا حيث يكون الخطر حقيقياً.

  /// الفيروزي الطبي — هوية DrD. أهدأ من السابق (#0097A7) وأقرب إلى الأزرق،
  /// فيقرأ «رعاية» لا «تقنية». يبقى لون `theme_color` في manifest متوافقاً.
  static const Color primary = Color(0xFF12707C);
  static const Color primaryDark = Color(0xFF0A3B42);
  static const Color primaryLight = Color(0xFFD6EBEE);

  /// نجمة التقييم — الذهبي عرفٌ لا يُستبدل، وتباينه كافٍ كرمز.
  static const Color rating = Color(0xFFE0A02C);

  /// أخضر طبي هادئ لا أخضر «نجاح» فاقع.
  static const Color success = Color(0xFF2E7D5B);

  /// كهرماني للتنبيه — ملحوظ بلا إنذار.
  static const Color warning = Color(0xFFB86E00);

  /// أحمر مكبوح: يُستعمل للنصّ والحدود والأيقونات، لا كخلفية لأقسام كاملة.
  static const Color danger = Color(0xFFB3261E);

  // ===== الأسطح =====
  //
  // الفاتح: أزرق-رمادي شديد الفتحة يفصل الصفحة عن البطاقة البيضاء بلا
  // رمادية باردة. الليلي: أزرق-رمادي معتم متدرّج الطبقات — لا #0B1113
  // التي تجعل الشاشة حفرة سوداء، ولا لوح فيروزي داكن يبتلع المحتوى.
  static const Color surfaceLight = Color(0xFFF3F7F9);
  static const Color surfaceDark = Color(0xFF141B21);

  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF1C242B);
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
      // ===== أدوار العلامة صريحة لا مشتقّة =====
      //
      // `fromSeed` من بذرة فيروزية يعطي `primaryContainer` سماوياً فاقعاً
      // يشبه قلم التظليل. القيم هنا مختارة ومقيسة (يحرسها
      // `theme_widgets_test.dart` بحدّ 4.5:1)، والليلي مكتوم عمداً: فيروزي
      // فاتح مشبع على سطح داكن هو ما جعل الأزرار تبدو نيون على الجهاز.
      primary: isDark ? const Color(0xFF6FBAC4) : AppColors.primary,
      onPrimary: isDark ? const Color(0xFF04333A) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF12454D) : const Color(0xFFD8EBEE),
      onPrimaryContainer:
          isDark ? const Color(0xFFC7E6EA) : AppColors.primaryDark,

      // الثانوي أزرق هادئ — للمعلومة والحالة، لا لمنافسة زرّ الإجراء.
      secondary: isDark ? const Color(0xFF9FBBD4) : const Color(0xFF3F6484),
      onSecondary: isDark ? const Color(0xFF102434) : Colors.white,
      secondaryContainer:
          isDark ? const Color(0xFF23394C) : const Color(0xFFDDE7F0),
      onSecondaryContainer:
          isDark ? const Color(0xFFD6E4F0) : const Color(0xFF17303F),

      // الثالثي = «النجاح» في هذا التطبيق (يُستعمل في رسائل التأكيد).
      tertiary: isDark ? const Color(0xFF7FC0A2) : AppColors.success,
      onTertiary: isDark ? const Color(0xFF06301F) : Colors.white,
      tertiaryContainer:
          isDark ? const Color(0xFF1B4434) : const Color(0xFFD8EDE2),
      onTertiaryContainer:
          isDark ? const Color(0xFFCCE8D9) : const Color(0xFF0C3A28),

      // ===== الأسطح: طبقات مقروءة في الوضعين =====
      surface: isDark ? AppColors.cardDark : AppColors.cardLight,
      surfaceContainerLowest: isDark ? AppColors.surfaceDark : Colors.white,
      surfaceContainerLow:
          isDark ? const Color(0xFF182026) : const Color(0xFFF9FBFC),
      surfaceContainer:
          isDark ? const Color(0xFF1C242B) : const Color(0xFFF3F7F9),
      surfaceContainerHigh:
          isDark ? const Color(0xFF222B33) : const Color(0xFFEBF1F4),
      surfaceContainerHighest:
          isDark ? const Color(0xFF29333C) : const Color(0xFFE2EAEF),

      // نصّ ثانوي مريح: رمادي مزرقّ لا رمادي ميت.
      onSurfaceVariant:
          isDark ? const Color(0xFFB4C0CA) : const Color(0xFF54636F),
      outline: isDark ? const Color(0xFF43505B) : const Color(0xFFB9C6CF),
      outlineVariant:
          isDark ? const Color(0xFF2E3941) : const Color(0xFFDCE5EA),
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
      // ===== الحقول: ممتلئة بلا إطار (المرحلة 11) =====
      //
      // كان الحقل مؤطَّراً مع `floatingLabelBehavior: always`، فتستقرّ
      // التسمية **فوق خطّ الإطار**: يفتح Flutter فجوة في الخطّ، ويظهر خلف
      // التسمية لونُ ما تحت الحقل لا لون الحقل — لطخة رمادية تحت كل تسمية
      // على شاشة الدخول. رُصدت في لقطة حقيقية بعد إعادة تلوين اللوحة.
      //
      // الحلّ ليس ضبط لون الفجوة (لا لون واحد يطابق كل أب: صفحة ملوّنة،
      // وبطاقة بيضاء، وحوار)، بل ألّا تُوضع التسمية على خطّ أصلاً: حقل
      // ممتلئ بلا إطار، والتسمية تطفو **داخله**. وهو كذلك أهدأ بصرياً:
      // الحدود العريضة كانت جزءاً مما جعل الشاشات تبدو ثقيلة.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF222B33) : const Color(0xFFEDF2F5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        // التسمية تلتصق بأعلى الحقل من الداخل، فلا تتداخل مع النصّ العربي.
        alignLabelWithHint: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide.none,
        ),
        // التركيز يُرى بحلقة داخلية لا بخطّ يقطعه نصّ: الحقل يفتح فجوة
        // للتسمية فقط حين تكون التسمية على الخطّ — وهي هنا داخل الحقل.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      // ===== زرّ الإجراء: قويّ في الفاتح، نبريّ في الليلي =====
      //
      // Material يملأ الزرّ بـ `primary`. في الوضع الليلي `primary` لونٌ
      // **فاتح** بطبيعته، فيصير كل زرّ رئيسي لوحاً فيروزياً ساطعاً بعرض
      // الشاشة على خلفية داكنة — وهو بالضبط «الفيروزي الزائد» الذي رُصد
      // على الجهاز. الزرّ النبري (`primaryContainer`) إجراء أساسي أيضاً في
      // Material 3، لكنه يهدأ على السطح الداكن بدل أن يصرخ فيه.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? scheme.primaryContainer : scheme.primary,
          foregroundColor:
              isDark ? scheme.onPrimaryContainer : scheme.onPrimary,
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
