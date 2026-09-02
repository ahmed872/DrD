import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/constants/doctor_account_state.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/presentation/widgets/role_guard.dart';

/// `RoleGuard` ليس طبقة صلاحيات — الصلاحية على الخادم. وظيفته أن الواجهة
/// **متّسقة** معها: من لا يملك الصلاحية يرى رسالة مفهومة بدل شاشة تفشل
/// استعلاماتها بصمت. هذه الاختبارات تحرس تلك الاتساقية.
///
/// شريط حالة الطبيب يُختبر هنا أيضاً لأنه في نفس الملف ويخدم نفس الغرض.
void main() {
  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    );
  }

  group('شريط حالة الطبيب', () {
    testWidgets('الحساب النشط لا يعرض شريطاً', (tester) async {
      // الحالة الطبيعية لا تستحق شريطاً دائماً يزاحم المحتوى.
      await tester.pumpWidget(wrap(const Scaffold(
        body: DoctorStatusBanner(state: DoctorAccountState.active),
      )));
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.textContaining('نشط'), findsNothing);
    });

    for (final state in [
      DoctorAccountState.pending,
      DoctorAccountState.rejected,
      DoctorAccountState.suspended,
    ]) {
      testWidgets('حالة ${state.name} تُعرض بعنوانها وشرحها', (tester) async {
        await tester.pumpWidget(wrap(Scaffold(
          body: DoctorStatusBanner(state: state),
        )));
        expect(find.text(state.arabicLabel), findsOneWidget);
        expect(find.text(state.arabicDescription), findsOneWidget);
      });

      testWidgets('حالة ${state.name} مقروءة في الوضع الليلي', (tester) async {
        await tester.pumpWidget(wrap(
          Scaffold(body: DoctorStatusBanner(state: state)),
          brightness: Brightness.dark,
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text(state.arabicLabel), findsOneWidget);
      });
    }

    testWidgets('المرفوض وحده يعرض زر إعادة التقديم', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(Scaffold(
        body: DoctorStatusBanner(
          state: DoctorAccountState.rejected,
          onAction: () => tapped = true,
        ),
      )));
      await tester.tap(find.text('تعديل الطلب وإعادة التقديم'));
      expect(tapped, isTrue);
    });

    testWidgets('الموقوف لا يعرض زر إعادة التقديم', (tester) async {
      await tester.pumpWidget(wrap(Scaffold(
        body: DoctorStatusBanner(
          state: DoctorAccountState.suspended,
          onAction: () {},
        ),
      )));
      expect(find.text('تعديل الطلب وإعادة التقديم'), findsNothing);
    });
  });
}
