import 'package:flutter/material.dart';

/// سلّم الخطوط المعتمد.
///
/// قبل المرحلة 6.5 لم يكن للتطبيق `textTheme` إطلاقاً: 149 استدعاءً لـ
/// `fontSize` موزّعة على الشاشات بأربع عشرة قيمة مختلفة (10, 11, 12, 13,
/// 14, 15, 16, 18, 20, 24, 26, 28, 32, 48). أي أن التسلسل الهرمي لم يكن
/// مصمَّماً بل ناتجاً عن اختيارات متفرّقة — وهذا وحده يكفي ليبدو التطبيق
/// قالباً عاماً مهما حُسّنت الألوان.
///
/// السلّم هنا ستّ درجات فقط. الفارق بين كل درجة والتي تليها كافٍ ليُقرأ
/// بوصفه فرقاً في الأهمية، لا فرقاً عشوائياً في المقاس.
///
/// **ارتفاع السطر (`height`) أكبر مما تفترضه Material**: الحروف العربية
/// تحمل تشكيلاً ونقاطاً فوق السطر وتحته، فالسطر الضيّق يجعل النصّ متلاصقاً.
class AppTypography {
  const AppTypography._();

  static const String family = 'Cairo';

  /// أرقام ولاتينية داخل نصّ عربي تأتي من نفس العائلة، فلا حاجة لبديل.
  static const List<String> fallback = <String>[];

  static TextTheme textTheme(ColorScheme scheme) {
    final onSurface = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    TextStyle s(double size, FontWeight weight, double height,
            {Color? color, double spacing = 0}) =>
        TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: spacing,
          color: color ?? onSurface,
        );

    return TextTheme(
      // Display — الترحيب واسم المستخدم على الرئيسية، ولا شيء غيرهما.
      displaySmall: s(28, FontWeight.w700, 1.35),

      // Headline — عنوان الشاشة داخل المحتوى.
      headlineMedium: s(24, FontWeight.w700, 1.35),
      headlineSmall: s(20, FontWeight.w700, 1.4),

      // Title — عناوين البطاقات والأقسام.
      titleLarge: s(18, FontWeight.w700, 1.4),
      titleMedium: s(16, FontWeight.w600, 1.45),
      titleSmall: s(14, FontWeight.w600, 1.45),

      // Body — النصّ الجاري.
      bodyLarge: s(16, FontWeight.w400, 1.6),
      bodyMedium: s(14, FontWeight.w400, 1.6),
      bodySmall: s(13, FontWeight.w400, 1.55, color: muted),

      // Label — الأزرار والشارات.
      labelLarge: s(15, FontWeight.w600, 1.3),
      labelMedium: s(13, FontWeight.w600, 1.3),
      labelSmall: s(12, FontWeight.w600, 1.3, color: muted),
    );
  }
}
