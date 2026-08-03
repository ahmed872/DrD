import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/presentation/screens/home_screen.dart';

/// اختبارات تخطيط الصفحة الرئيسية.
///
/// كلا العيبين المُغطَّيين هنا وصلا إلى جهاز المستخدم فعلاً، وكلاهما لا يرمي
/// استثناءً ولا يظهر في `flutter analyze`: الأول يدفن بطاقة الملف تحت الرأس
/// فتبدو الشاشة مقصوصة، والثاني يحوّل شبكة الخدمات إلى عمود واحد على الهاتف.
void main() {
  /// تحديد مقاس الشاشة الفعلي للاختبار.
  ///
  /// `MediaQuery` وحدها لا تكفي: عرض التخطيط يأتي من `tester.view`، والافتراضي
  /// 800×600 — أي مقاس لوحي. اختبار «عمودان على الهاتف» كان ينجح كذباً بأربعة
  /// أعمدة لأن الودجت لم يُبنَ أصلاً بعرض هاتف.
  void setScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget wrap(Widget child) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(theme: AppTheme.light, home: child),
    );
  }

  const body = HomeBody(
    userName: 'أحمد رضا',
    userPhone: '201093033884',
    isDoctor: true,
  );

  testWidgets('تُبنى بلا استثناءات تخطيط', (tester) async {
    setScreen(tester, const Size(390, 844));
    await tester.pumpWidget(wrap(body));
    expect(tester.takeException(), isNull);
    expect(find.text('أحمد رضا'), findsWidgets);
  });

  testWidgets('بطاقة الملف تعلو الرأس ولا يدفنها', (tester) async {
    setScreen(tester, const Size(390, 844));
    await tester.pumpWidget(wrap(body));

    // البطاقة مرفوعة عمداً لتتداخل مع الرأس. الاختبار هنا ليس على التداخل
    // نفسه بل على أن البطاقة ما زالت مرئية وقابلة للنقر بعده: حين كان الرأس
    // شريحة أولى في `CustomScrollView` كان يُرسم فوقها ويحجبها بالكامل.
    final card = find.text('201093033884');
    expect(card, findsOneWidget);

    // `hitTestable` تفشل إن كان عنصر آخر يغطّي البطاقة.
    expect(find.text('201093033884').hitTestable(), findsOneWidget);
  });

  testWidgets('شبكة الخدمات عمودان على عرض الهاتف', (tester) async {
    setScreen(tester, const Size(360, 800));
    await tester.pumpWidget(wrap(body));

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, 2);
  });

  testWidgets('شبكة الخدمات أربعة أعمدة على المتصفح', (tester) async {
    setScreen(tester, const Size(1400, 900));
    await tester.pumpWidget(wrap(body));

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, 4);
  });

  testWidgets('لوحة الطبيب والمريض تعرضان خدمات مختلفة', (tester) async {
    setScreen(tester, const Size(390, 844));
    await tester.pumpWidget(wrap(body));
    expect(find.text('لوحة الطبيب'), findsOneWidget);
    expect(find.text('المرضى'), findsOneWidget);

    await tester.pumpWidget(
      wrap(
        const HomeBody(
          userName: 'مريم',
          userPhone: '201000000000',
          isDoctor: false,
        ),
      ),
    );
    expect(find.text('الخدمات المتاحة'), findsOneWidget);
    expect(find.text('حجز موعد'), findsOneWidget);
  });
}
