import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/data/services/analytics_service.dart';
import 'package:medical_appointment_app/presentation/widgets/analytics_widgets.dart';

/// عناصر عرض التحليلات.
///
/// رسم بيانيّ يُقرأ خطأً أسوأ من غيابه، فما يُحرَس هنا هو أن الرقم مكتوب
/// دائماً إلى جانب شكله، وأن الحالات الحدّية لا تنهار.
void main() {
  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  AnalyticsPoint point(String bucket, int booked) => AnalyticsPoint(
        bucket: bucket,
        booked: booked,
        completed: 0,
        cancelled: 0,
      );

  group('رسم الاتجاه', () {
    testWidgets('كل عمود يحمل قيمته مكتوبة — لا اعتماد على اللون وحده',
        (tester) async {
      await tester.pumpWidget(wrap(TrendBars(points: [
        point('2030-03-01', 3),
        point('2030-03-02', 7),
      ])));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('قيمة صفرية تُرسم ولا تختفي', (tester) async {
      // فرق بين «صفر» و«لا بيانات» يجب أن يُرى.
      await tester.pumpWidget(wrap(TrendBars(points: [
        point('2030-03-01', 0),
        point('2030-03-02', 5),
      ])));
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('كل القيم أصفار لا تُنتج قسمة على صفر', (tester) async {
      await tester.pumpWidget(wrap(TrendBars(points: [
        point('2030-03-01', 0),
        point('2030-03-02', 0),
      ])));
      expect(tester.takeException(), isNull);
    });

    testWidgets('سلسلة طويلة تُقتطع لآخرها بلا فيضان', (tester) async {
      final many = [
        for (var i = 1; i <= 40; i++)
          point('2030-03-${i.toString().padLeft(2, '0')}', i),
      ];
      await tester.pumpWidget(wrap(TrendBars(points: many)));
      expect(tester.takeException(), isNull);
      // آخر نقطة معروضة، وأولى النقاط الأربعين ليست كذلك.
      expect(find.text('40'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('سلسلة فارغة لا ترسم شيئاً ولا تنهار', (tester) async {
      await tester.pumpWidget(wrap(const TrendBars(points: [])));
      expect(tester.takeException(), isNull);
    });

    testWidgets('يعمل في الوضع الليلي', (tester) async {
      await tester.pumpWidget(wrap(
        TrendBars(points: [point('2030-03-01', 4)]),
        brightness: Brightness.dark,
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('4'), findsOneWidget);
    });
  });

  group('شريط النسبة', () {
    testWidgets('النسبة مكتوبة رقماً', (tester) async {
      await tester.pumpWidget(
          wrap(const RateBar(label: 'نسبة الإتمام', percent: 66.7)));
      expect(find.text('66.7%'), findsOneWidget);
      expect(find.text('نسبة الإتمام'), findsOneWidget);
    });

    testWidgets('نسبة خارج المدى تُحصر ولا تنهار', (tester) async {
      await tester.pumpWidget(wrap(const Column(children: [
        RateBar(label: 'فوق', percent: 150),
        RateBar(label: 'تحت', percent: -20),
      ])));
      expect(tester.takeException(), isNull);
    });
  });

  group('التوزيع', () {
    testWidgets('العناصر تظهر بأسمائها وأعدادها', (tester) async {
      await tester.pumpWidget(wrap(const BreakdownList(items: [
        AnalyticsBreakdown(name: 'أسنان', count: 12),
        AnalyticsBreakdown(name: 'جلدية', count: 4),
      ])));
      expect(find.text('أسنان'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('اسم طويل يُقتطع ولا يفيض', (tester) async {
      await tester.pumpWidget(wrap(const BreakdownList(items: [
        AnalyticsBreakdown(
          name: 'جراحة العظام والمفاصل وإصابات الملاعب والعمود الفقري',
          count: 3,
        ),
      ])));
      expect(tester.takeException(), isNull);
    });

    testWidgets('قائمة فارغة لا ترسم شيئاً', (tester) async {
      await tester.pumpWidget(wrap(const BreakdownList(items: [])));
      expect(tester.takeException(), isNull);
    });
  });

  group('المؤشّرات وشبكتها', () {
    testWidgets('البطاقة تعرض قيمتها وتسميتها', (tester) async {
      await tester.pumpWidget(wrap(const KpiCard(
        label: 'مكتملة',
        value: '12',
        icon: Icons.check,
      )));
      expect(find.text('12'), findsOneWidget);
      expect(find.text('مكتملة'), findsOneWidget);
    });

    testWidgets('الشبكة تتكيّف مع العرض بلا فيضان', (tester) async {
      for (final width in [360.0, 800.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(wrap(const KpiGrid(cards: [
          KpiCard(label: 'أ', value: '1', icon: Icons.abc),
          KpiCard(label: 'ب', value: '2', icon: Icons.abc),
          KpiCard(label: 'ج', value: '3', icon: Icons.abc),
          KpiCard(label: 'د', value: '4', icon: Icons.abc),
        ])));
        expect(tester.takeException(), isNull, reason: 'عند العرض $width');
      }
    });
  });

  group('حداثة البيانات', () {
    testWidgets('وقت الحساب معروض — لا إيهام بأنها لحظية', (tester) async {
      await tester.pumpWidget(wrap(FreshnessNote(
        generatedAt: DateTime(2030, 3, 5, 14, 30),
        timezone: 'Africa/Cairo',
      )));
      expect(find.textContaining('14:30'), findsOneWidget);
    });

    testWidgets('البتر يُقال صراحةً', (tester) async {
      await tester.pumpWidget(wrap(FreshnessNote(
        generatedAt: DateTime(2030, 3, 5, 14, 30),
        timezone: 'Africa/Cairo',
        truncated: true,
      )));
      expect(find.textContaining('جزءاً'), findsOneWidget);
    });
  });

  group('اختيار المدى', () {
    testWidgets('كل المديات معروضة والاختيار يُبلَّغ', (tester) async {
      AnalyticsRange? picked;
      await tester.pumpWidget(wrap(RangeSelector(
        selected: AnalyticsRange.month,
        onChanged: (r) => picked = r,
      )));
      for (final range in AnalyticsRange.values) {
        expect(find.text(range.arabicLabel), findsOneWidget);
      }
      await tester.tap(find.text(AnalyticsRange.week.arabicLabel));
      expect(picked, AnalyticsRange.week);
    });
  });
}
