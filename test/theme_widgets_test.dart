import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/theme/app_spacing.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/presentation/widgets/app_widgets.dart';

/// الوضع الليلي كان مكسوراً لأن الشاشات تفرض ألواناً ثابتة بدل ألوان النسق:
/// نص أسود على خلفية داكنة، أو بطاقة بيضاء وسط شاشة سوداء. المكوّنات
/// المشتركة هي خط الدفاع — إن بقيت هي نفسها مقروءة في الوضعين، فأي شاشة
/// تُبنى منها ترث ذلك.
void main() {
  /// يبني المكوّن داخل نسق التطبيق الحقيقي وباتجاه عربي.
  Widget wrap(Widget child, {required Brightness brightness}) {
    return MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );
  }

  /// يشغّل الاختبار على الوضعين معاً.
  void forBothModes(String description, Widget Function() build) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final modeName = brightness == Brightness.dark ? 'ليلي' : 'فاتح';
      testWidgets('$description ($modeName)', (tester) async {
        await tester.pumpWidget(wrap(build(), brightness: brightness));
        // إطار واحد لا `pumpAndSettle`: مؤشّر التحميل يدور بلا توقّف فلا
        // تستقر شجرة الودجات أبداً.
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('الحالات المشتركة تعمل في الوضعين', () {
    forBothModes(
      'الحالة الفارغة',
      () => const EmptyState(
        icon: Icons.event_busy,
        title: 'لا توجد مواعيد',
        message: 'احجز موعدك الأول',
      ),
    );

    forBothModes(
      'حالة الخطأ',
      () => ErrorStateView(message: 'تعذّر الاتصال', onRetry: () {}),
    );

    forBothModes(
      'حالة التحميل',
      () => const LoadingStateView(message: 'جارٍ التحميل…'),
    );

    forBothModes('الهيكل العظمي', () => const SkeletonList());

    forBothModes(
      'نجوم التقييم',
      () => const RatingStars(rating: 4),
    );

    forBothModes(
      'سطر التفاصيل',
      () => const DetailRow(label: 'الطبيب', value: 'د. أحمد'),
    );

    forBothModes(
      'كل نغمات شارة الحالة',
      () => const Wrap(
        children: [
          StatusChip(label: 'محجوز', tone: StatusTone.info),
          StatusChip(label: 'مكتمل', tone: StatusTone.success),
          StatusChip(label: 'بانتظار', tone: StatusTone.warning),
          StatusChip(label: 'ملغي', tone: StatusTone.danger),
          StatusChip(label: 'محايد'),
        ],
      ),
    );
  });

  group('المحتوى يظهر فعلاً', () {
    testWidgets('الحالة الفارغة تعرض عنوانها ورسالتها وإجراءها',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(
        EmptyState(
          icon: Icons.event_busy,
          title: 'لا توجد مواعيد',
          message: 'احجز موعدك الأول',
          actionLabel: 'احجز الآن',
          onAction: () => tapped = true,
        ),
        brightness: Brightness.light,
      ));

      expect(find.text('لا توجد مواعيد'), findsOneWidget);
      expect(find.text('احجز موعدك الأول'), findsOneWidget);

      await tester.tap(find.text('احجز الآن'));
      expect(tapped, isTrue);
    });

    testWidgets('حالة الخطأ لا تُظهر زر إعادة المحاولة بلا معالج',
        (tester) async {
      await tester.pumpWidget(wrap(
        const ErrorStateView(message: 'تعذّر الاتصال'),
        brightness: Brightness.light,
      ));
      expect(find.text('تعذّر الاتصال'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsNothing);
    });

    testWidgets('النجوم القابلة للاختيار تُرجع القيمة المختارة',
        (tester) async {
      int? selected;
      await tester.pumpWidget(wrap(
        RatingStars(rating: 0, onChanged: (value) => selected = value),
        brightness: Brightness.light,
      ));

      // النجمة الثالثة — الترتيب في RTL يعكس المواضع، فنستهدف بالدلالة.
      await tester.tap(find.bySemanticsLabel('3 من 5'));
      expect(selected, 3);
    });
  });

  group('التباين مقروء في الوضعين', () {
    /// نسبة التباين بحسب WCAG.
    double contrastRatio(Color a, Color b) {
      double channel(double c) => c <= 0.03928
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
      double luminance(Color c) =>
          0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);

      final l1 = luminance(a);
      final l2 = luminance(b);
      final lighter = l1 > l2 ? l1 : l2;
      final darker = l1 > l2 ? l2 : l1;
      return (lighter + 0.05) / (darker + 0.05);
    }

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final modeName = theme.brightness == Brightness.dark ? 'ليلي' : 'فاتح';
      test('ألوان النسق الأساسية تحقق 4.5:1 ($modeName)', () {
        final scheme = theme.colorScheme;
        final pairs = <String, (Color, Color)>{
          'onSurface/surface': (scheme.onSurface, scheme.surface),
          'onPrimary/primary': (scheme.onPrimary, scheme.primary),
          'onError/error': (scheme.onError, scheme.error),
          'onPrimaryContainer/primaryContainer': (
            scheme.onPrimaryContainer,
            scheme.primaryContainer
          ),
          'onErrorContainer/errorContainer': (
            scheme.onErrorContainer,
            scheme.errorContainer
          ),
          'onTertiaryContainer/tertiaryContainer': (
            scheme.onTertiaryContainer,
            scheme.tertiaryContainer
          ),
          'onSurfaceVariant/surface': (scheme.onSurfaceVariant, scheme.surface),
        };

        pairs.forEach((name, colors) {
          final ratio = contrastRatio(colors.$1, colors.$2);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: '$name في الوضع الـ$modeName: '
                  '${ratio.toStringAsFixed(2)}:1');
        });
      });
    }
  });

  group('المقاييس المتجاوبة', () {
    testWidgets('عرض المحتوى محصور على الشاشات العريضة', (tester) async {
      tester.view.physicalSize = const Size(2400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(
        const ContentWidthLimit(child: SizedBox(height: 100)),
        brightness: Brightness.light,
      ));

      final box = tester.getSize(find.byType(SizedBox).first);
      expect(box.width, lessThanOrEqualTo(AppBreakpoints.contentMaxWidth));
    });
  });
}
