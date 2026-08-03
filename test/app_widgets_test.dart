import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/presentation/widgets/app_widgets.dart';

/// حراسة تخطيط مكتبة العناصر.
///
/// العنصران المختبَران هنا انكسرا فعلاً أثناء التطوير، وكلاهما ينتج شاشة
/// فارغة تماماً لا رسالة خطأ: المستخدم يرى الرأس ثم فراغاً أبيض. لا يكشفهما
/// `flutter analyze` لأن الكسر في وقت التخطيط لا في وقت الترجمة.
void main() {
  Widget wrap(Widget child, {Size size = const Size(400, 800)}) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: MaterialApp(
          theme: AppTheme.light,
          home: child,
        ),
      ),
    );
  }

  group('AppCard', () {
    testWidgets('البطاقة ذات الشريط اللوني ترسم داخل عمود غير محدود الارتفاع',
        (tester) async {
      // `Row(crossAxisAlignment: stretch)` كان يطلب ارتفاعاً لا نهائياً هنا،
      // فينهار التخطيط وتختفي كل بطاقات المواعيد.
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  AppCard(
                    accent: const Color(0xFF0E9D6E),
                    child: const Text('موعد'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('موعد'), findsOneWidget);
    });

    testWidgets('البطاقة العادية تُبنى بلا استثناء', (tester) async {
      await tester.pumpWidget(
        wrap(const Scaffold(body: AppCard(child: Text('بطاقة')))),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('بطاقة'), findsOneWidget);
    });
  });

  group('AppScaffold', () {
    testWidgets('الرأس يحجز مساحة لعنصر headerBottom فلا يفيض', (tester) async {
      // `preferredSize` كان يتجاهل `headerBottom`، فيفيض الرأس ويُخفي الجسم
      // في كل شاشة فيها بحث أو تبويبات.
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrap(
          AppScaffold(
            title: 'المرضى',
            subtitle: '12 مريض',
            headerBottom: AppSearchField(
              controller: controller,
              hint: 'ابحث',
            ),
            child: const Text('محتوى الصفحة'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('المرضى'), findsOneWidget);
      expect(find.text('محتوى الصفحة'), findsOneWidget);
    });

    testWidgets('الرأس مع مبدّل شرائح لا يفيض', (tester) async {
      await tester.pumpWidget(
        wrap(
          AppScaffold(
            title: 'مواعيدي',
            headerBottom: AppSegmented(
              labels: const ['القادمة', 'السابقة'],
              selectedIndex: 0,
              onChanged: (_) {},
            ),
            child: const Text('قائمة'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('قائمة'), findsOneWidget);
    });

    testWidgets('جسم الصفحة محصور العرض على الشاشات العريضة', (tester) async {
      await tester.pumpWidget(
        wrap(
          const AppScaffold(
            title: 'الإعدادات',
            maxWidth: AppBreakpoints.form,
            child: SizedBox(width: double.infinity, height: 40),
          ),
          size: const Size(1600, 900),
        ),
      );

      expect(tester.takeException(), isNull);

      final bodyWidth = tester.getSize(find.byType(SizedBox).last).width;
      expect(bodyWidth, lessThanOrEqualTo(AppBreakpoints.form));
    });
  });

  group('AppTokens', () {
    test('لكل حالة موعد لون وخلفية معرّفان', () {
      const statuses = [
        'Scheduled',
        'Booked',
        'pending',
        'Completed',
        'Cancelled',
        'Rejected',
      ];

      final tokens = AppTheme.light.extension<AppTokens>();
      expect(tokens, isNotNull);

      for (final status in statuses) {
        expect(tokens!.statusColor(status), isNotNull);
        expect(tokens.statusSoft(status), isNotNull);
      }
    });

    test('النسق الليلي يوفّر نفس الرموز بقيم مختلفة', () {
      final light = AppTheme.light.extension<AppTokens>()!;
      final dark = AppTheme.dark.extension<AppTokens>()!;

      // لو تساوى لون النص بين الوضعين فالوضع الليلي غير مطبَّق فعلياً.
      expect(dark.textStrong, isNot(equals(light.textStrong)));
      expect(dark.surfaceRaised, isNot(equals(light.surfaceRaised)));
    });
  });
}
