import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// المعنى الذي ينقله عنصر الواجهة — لا لونه.
///
/// كان في التطبيق 37 شريط رسالة، 17 منها أحمر و8 خضراء، كُتب لون كل واحد
/// منها يدوياً في موضعه. اللون وحده لا ينقل معنى: نحو 8% من الذكور لا
/// يميّزون الأحمر من الأخضر، ومريض يقرأ «تم الحجز» بخلفية حمراء لا يعرف
/// أنجح الحجز أم فشل.
///
/// لذلك كل مكوّن في هذه المكتبة يأخذ [DrdTone] لا `Color`، وكل نغمة تحمل
/// **أيقونة مميّزة الشكل** إلى جانب لونها. الشكل يعمل حيث يفشل اللون.
enum DrdTone {
  /// اكتمل الإجراء.
  success,

  /// يحتاج انتباهاً أو إجراءً لاحقاً — لا فشل.
  warning,

  /// فشل الإجراء.
  error,

  /// معلومة محايدة. الأزرق الثانوي لا الأساسي، حتى لا تُقرأ كزر.
  info,

  /// حالة ساكنة بلا شحنة — ملغى، منتهٍ، غير متاح.
  neutral,
}

/// الألوان والأيقونة التي تُرسم بها نغمة في السياق الحالي.
@immutable
class DrdToneStyle {
  const DrdToneStyle({
    required this.icon,
    required this.accent,
    required this.container,
    required this.onContainer,
  });

  /// أيقونة مميّزة الشكل — لا تعتمد على اللون وحده.
  final IconData icon;

  /// لون الأيقونة والحدّ فوق [container]. يحقّق 3:1 على الأقل.
  final Color accent;

  /// خلفية العنصر.
  final Color container;

  /// لون النص فوق [container]. يحقّق 4.5:1 على الأقل.
  final Color onContainer;
}

extension DrdToneResolver on DrdTone {
  /// يحلّ النغمة إلى ألوان الوضع الحالي.
  DrdToneStyle resolve(BuildContext context) {
    final drd = context.drd;
    final scheme = context.colors;

    return switch (this) {
      DrdTone.success => DrdToneStyle(
          icon: Icons.check_circle_outline,
          accent: drd.success,
          container: drd.successContainer,
          onContainer: drd.onSuccessContainer,
        ),
      DrdTone.warning => DrdToneStyle(
          // مثلّث — شكل مختلف عن دوائر بقية النغمات.
          icon: Icons.warning_amber_rounded,
          // اللمسة الأفتح للأيقونة؛ نص التحذير له لون أغمق منفصل.
          accent: drd.warningAccent,
          container: drd.warningContainer,
          onContainer: drd.onWarningContainer,
        ),
      DrdTone.error => DrdToneStyle(
          icon: Icons.error_outline,
          accent: scheme.error,
          container: scheme.errorContainer,
          onContainer: scheme.onErrorContainer,
        ),
      DrdTone.info => DrdToneStyle(
          icon: Icons.info_outline,
          accent: drd.info,
          container: drd.infoContainer,
          onContainer: drd.onInfoContainer,
        ),
      DrdTone.neutral => DrdToneStyle(
          icon: Icons.circle_outlined,
          accent: drd.muted,
          container: scheme.surfaceContainerHigh,
          onContainer: scheme.onSurface,
        ),
    };
  }

  /// لون الأيقونة فوق **السطح المعكوس** (شريط الرسائل المؤقتة).
  ///
  /// السطح المعكوس يقلب السطوع: في الوضع الفاتح الشريط داكن، وفي الوضع
  /// الليلي فاتح. لذلك تُؤخذ الألوان من اللوحة المعاكسة — استعمال ألوان
  /// الوضع الحالي هنا ينتج 1.77:1 على شريط فاتح، أي أيقونة غير مرئية عملياً.
  Color onInverseSurface(BuildContext context) {
    final barIsDark = Theme.of(context).brightness == Brightness.light;

    return switch (this) {
      DrdTone.success =>
        barIsDark ? DrdPalette.darkSuccess : DrdPalette.lightSuccess,
      DrdTone.warning => barIsDark
          ? DrdPalette.darkWarningAccent
          : DrdPalette.lightWarningAccent,
      DrdTone.error => barIsDark ? DrdPalette.darkError : DrdPalette.lightError,
      DrdTone.info =>
        barIsDark ? DrdPalette.darkSecondary : DrdPalette.lightSecondary,
      DrdTone.neutral =>
        barIsDark ? DrdPalette.darkMuted : DrdPalette.lightMuted,
    };
  }
}
