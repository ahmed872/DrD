import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/theme/app_spacing.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/core/theme/app_typography.dart';
import 'package:medical_appointment_app/presentation/widgets/app_surfaces.dart';
import 'package:medical_appointment_app/presentation/widgets/app_widgets.dart';

/// حرّاس نظام التصميم (المرحلة 6.5).
///
/// المكاسب البصرية هنا مركزية: خطّ واحد، وسلّم مقاسات واحد، وشكل بطاقة
/// واحد. ما يحرسه هذا الملف ليس «شكل الشاشة» بل ألّا تنفرط هذه المركزية
/// مرّة أخرى إلى مقاسات وألوان متفرّقة في الشاشات.
void main() {
  group('سلّم الخطوط', () {
    test('النسق يحمل عائلة الخط في كل درجة', () {
      // قبل المرحلة 6.5 لم يكن هناك `textTheme` إطلاقاً، فكان كل نصّ يقع
      // على خطّ النظام الافتراضي.
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final t = theme.textTheme;
        for (final style in [
          t.displaySmall,
          t.headlineMedium,
          t.headlineSmall,
          t.titleLarge,
          t.titleMedium,
          t.titleSmall,
          t.bodyLarge,
          t.bodyMedium,
          t.bodySmall,
          t.labelLarge,
          t.labelMedium,
          t.labelSmall,
        ]) {
          expect(style, isNotNull);
          expect(style!.fontFamily, AppTypography.family);
        }
      }
    });

    test('الدرجات متمايزة ومرتّبة تنازلياً', () {
      // سلّم لا تُقرأ فيه الدرجة أكبر من التي تحتها ليس سلّماً.
      final t = AppTheme.light.textTheme;
      final sizes = [
        t.displaySmall!.fontSize!,
        t.headlineMedium!.fontSize!,
        t.headlineSmall!.fontSize!,
        t.titleLarge!.fontSize!,
        t.titleMedium!.fontSize!,
        t.bodyMedium!.fontSize!,
        t.bodySmall!.fontSize!,
      ];
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], lessThan(sizes[i - 1]),
            reason: 'الدرجة ${sizes[i]} ليست أصغر مما قبلها ${sizes[i - 1]}');
      }
    });

    test('ارتفاع السطر يتّسع للتشكيل العربي', () {
      // السطر الضيّق يجعل النقاط والتشكيل تتلامس فوق الحروف وتحتها.
      final t = AppTheme.light.textTheme;
      expect(t.bodyMedium!.height, greaterThanOrEqualTo(1.5));
      expect(t.bodyLarge!.height, greaterThanOrEqualTo(1.5));
    });

    test('ملفات الخط الثلاثة موجودة ومعرَّفة', () {
      for (final weight in ['400', '600', '700']) {
        final file = File('assets/fonts/Cairo-$weight.ttf');
        expect(file.existsSync(), isTrue, reason: 'مفقود: ${file.path}');
        expect(file.lengthSync(), greaterThan(10000));
      }
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: Cairo'));
    });
  });

  group('الشكل والمسافات', () {
    test('أدوار الشكل مرتّبة: البطاقة أعرض انحناءً من الزرّ ومن الحقل', () {
      expect(AppRadii.card, greaterThan(AppRadii.button));
      expect(AppRadii.dialog, greaterThan(AppRadii.card));
      expect(AppRadii.button, equals(AppRadii.input));
    });

    test('سلّم المسافات تصاعدي', () {
      final scale = [
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxl,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
    });
  });

  group('الأسطح', () {
    testWidgets('خلفية الصفحة تُميَّز عن سطح البطاقة في الوضعين',
        (tester) async {
      // كانت الخلفية `#F5F7FA` والبطاقة بيضاء — فارق لا يكاد يُرى، فبدت
      // الشاشات مسطّحة بلا طبقات.
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        expect(theme.scaffoldBackgroundColor,
            isNot(equals(theme.colorScheme.surface)));
      }
    });

    testWidgets('شريط التطبيق لم يعد لوحاً ملوّناً', (tester) async {
      // اللوح الفيروزي المشبع بعرض الشاشة كان أكثر عنصر يجعل الواجهة
      // تبدو قديمة.
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        expect(theme.appBarTheme.backgroundColor,
            equals(theme.scaffoldBackgroundColor));
        expect(theme.appBarTheme.foregroundColor,
            equals(theme.colorScheme.onSurface));
      }
    });

    testWidgets('AppCard يُرسم ويستقبل النقر في الوضعين', (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        var tapped = false;
        await tester.pumpWidget(MaterialApp(
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: AppCard(
                onTap: () => tapped = true,
                child: const Text('محتوى'),
              ),
            ),
          ),
        ));
        expect(find.text('محتوى'), findsOneWidget);
        await tester.tap(find.text('محتوى'));
        expect(tapped, isTrue);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('QuickAction هدفه ≥48 بكسل', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: QuickActionsRow(actions: [
              QuickAction(icon: Icons.event, label: 'مواعيدي', onTap: () {}),
              QuickAction(icon: Icons.search, label: 'بحث', onTap: () {}),
            ]),
          ),
        ),
      ));
      final size = tester.getSize(find.byType(InkWell).first);
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('الاتجاهية', () {
    testWidgets('سهم «التالي» يشير يساراً في العربية ويميناً في الإنجليزية',
        (tester) async {
      // Flutter يعكس أيقونات الأسهم تلقائياً، فاختيارُ الشكل حسب الاتجاه
      // ثم تركُ الانعكاس يعمل يقلبه مرّتين ويعيده إلى الخلف. رُصد ذلك في
      // لقطات فعلية: سهم «>» في كل بطاقة موعد بواجهة تُقرأ من اليمين.
      for (final direction in [TextDirection.rtl, TextDirection.ltr]) {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: direction,
            child: const Scaffold(body: DirectionalForwardIcon()),
          ),
        ));
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(
          icon.icon,
          direction == TextDirection.rtl
              ? Icons.chevron_left
              : Icons.chevron_right,
        );
        // فرض سياق `ltr` على الأيقونة وحدها هو ما يمنع الانعكاس الثاني.
        expect(icon.textDirection, TextDirection.ltr);
      }
    });
  });
}
