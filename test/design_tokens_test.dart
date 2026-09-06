import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/core/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// نسبة التباين بين لونين حسب WCAG 2.1.
///
/// `computeLuminance` في Flutter هو نفسه تعريف السطوع النسبي في المواصفة،
/// فالمعادلة هنا مطابقة لما تقيسه أدوات الفحص.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

/// الحد الأدنى لنص المتن.
const double aaText = 4.5;

/// الحد الأدنى للأيقونات والحدود (عناصر غير نصية).
const double aaNonText = 3.0;

void main() {
  // هذه الاختبارات تحرس وعداً صريحاً مكتوباً في `design_tokens.dart`: أن
  // ألوان اللوحة تحقّق تباين AA. من غيرها يبقى الوعد تعليقاً يمكن أن يكذّبه
  // أول تعديل على لون.
  group('تباين النغمات داخل الحاويات', () {
    for (final (modeName, theme) in [
      ('فاتح', AppTheme.light),
      ('داكن', AppTheme.dark),
    ]) {
      for (final tone in DrdTone.values) {
        testWidgets('$modeName — ${tone.name}: النص والأيقونة يحقّقان AA',
            (tester) async {
          late DrdToneStyle style;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Builder(
                builder: (context) {
                  style = tone.resolve(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          );

          expect(
            contrast(style.onContainer, style.container),
            greaterThanOrEqualTo(aaText),
            reason: 'نص ${tone.name} على حاويته في الوضع $modeName',
          );
          expect(
            contrast(style.accent, style.container),
            greaterThanOrEqualTo(aaNonText),
            reason: 'أيقونة ${tone.name} على حاويتها في الوضع $modeName',
          );
        });
      }
    }
  });

  group('تباين أيقونة شريط الرسائل على السطح المعكوس', () {
    // الحالة التي تنكسر بصمت: السطح المعكوس يقلب السطوع، فلون النغمة
    // المأخوذ من الوضع الحالي ينتج أيقونة شبه غير مرئية. الاختبار يثبت أن
    // القلب يحدث فعلاً.
    for (final (modeName, theme) in [
      ('فاتح', AppTheme.light),
      ('داكن', AppTheme.dark),
    ]) {
      for (final tone in DrdTone.values) {
        testWidgets('$modeName — ${tone.name}: الأيقونة مرئية على الشريط',
            (tester) async {
          late Color icon;
          late Color bar;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Builder(
                builder: (context) {
                  icon = tone.onInverseSurface(context);
                  bar = Theme.of(context).colorScheme.inverseSurface;
                  return const SizedBox.shrink();
                },
              ),
            ),
          );

          expect(
            contrast(icon, bar),
            greaterThanOrEqualTo(aaNonText),
            reason: 'أيقونة ${tone.name} على شريط الرسائل في الوضع $modeName',
          );
        });
      }
    }
  });

  group('نص النسق الأساسي على أسطحه', () {
    testWidgets('النص الأساسي والثانوي يحقّقان AA في الوضعين', (tester) async {
      for (final (modeName, theme) in [
        ('فاتح', AppTheme.light),
        ('داكن', AppTheme.dark),
      ]) {
        final scheme = theme.colorScheme;

        expect(
          contrast(scheme.onSurface, scheme.surface),
          greaterThanOrEqualTo(aaText),
          reason: 'النص الأساسي على السطح — $modeName',
        );
        expect(
          contrast(scheme.onSurfaceVariant, scheme.surface),
          greaterThanOrEqualTo(aaText),
          reason: 'النص الثانوي على السطح — $modeName',
        );
        expect(
          contrast(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(aaText),
          reason: 'نص الزر المملوء — $modeName',
        );
        expect(
          contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
          greaterThanOrEqualTo(aaText),
          reason: 'نص حاوية اللون الأساسي — $modeName',
        );
      }
    });
  });

  group('اتساق النسق', () {
    test('اللونان الأساسيان يتبادلان الأدوار بين الوضعين', () {
      // الوضع الليلي يستعمل أساسياً أفتح، ويحتفظ بالفاتح كلون معكوس.
      expect(AppTheme.dark.colorScheme.inversePrimary,
          AppTheme.light.colorScheme.primary);
      expect(AppTheme.light.colorScheme.inversePrimary,
          AppTheme.dark.colorScheme.primary);
    });

    test('الأساسي في الوضع الليلي أفتح منه في الوضع الفاتح', () {
      // الخطأ الذي كان في النسق السابق: فيروزي أغمق على خلفية داكنة يذوب.
      expect(
        AppTheme.dark.colorScheme.primary.computeLuminance(),
        greaterThan(AppTheme.light.colorScheme.primary.computeLuminance()),
      );
    });

    test('النسق يحمل امتداد الألوان الدلالية في الوضعين', () {
      expect(AppTheme.light.extension<DrdColors>(), isNotNull);
      expect(AppTheme.dark.extension<DrdColors>(), isNotNull);
    });
  });
}
