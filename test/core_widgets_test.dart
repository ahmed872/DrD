import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/constants/appointment_status.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/core/widgets/widgets.dart';

Widget wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      locale: const Locale('ar'),
      home: Scaffold(body: child),
    );

void main() {
  group('StatusChip', () {
    test('لكل حالة أيقونة مختلفة عن كل الحالات الأخرى', () {
      // الوعد الذي تقوم عليه المكتبة: الشكل يميّز الحالة حين يفشل اللون.
      // «ملغي» و«منتهٍ» يتشاركان النغمة المحايدة، فلو تشاركا الأيقونة أيضاً
      // لأصبحا عنصرين متطابقين بنصّين مختلفين.
      final icons = <IconData>{};
      for (final status in AppointmentStatus.values) {
        final icon = StatusChip.appointment(status).icon;
        expect(icon, isNotNull, reason: 'الحالة ${status.name} بلا أيقونة');
        expect(
          icons.add(icon!),
          isTrue,
          reason: 'الحالة ${status.name} تكرّر أيقونة حالة أخرى',
        );
      }
      expect(icons.length, AppointmentStatus.values.length);
    });

    test('الحالات الطبيعية ليست خطأ', () {
      // الإلغاء تصرّف مشروع؛ صبغه بالأحمر يجعل سجل المواعيد يبدو كسجل أعطال.
      expect(StatusChip.appointment(AppointmentStatus.cancelled).tone,
          DrdTone.neutral);
      expect(StatusChip.appointment(AppointmentStatus.expired).tone,
          DrdTone.neutral);
      expect(StatusChip.appointment(AppointmentStatus.completed).tone,
          DrdTone.success);
      expect(
          StatusChip.appointment(AppointmentStatus.noShow).tone, DrdTone.error);
    });

    testWidgets('يعرض النص العربي للحالة مع أيقونتها', (tester) async {
      await tester.pumpWidget(
        wrap(StatusChip.appointment(AppointmentStatus.completed)),
      );

      expect(find.text('مكتمل'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });

  group('AppBanner', () {
    testWidgets('يرسم أيقونة إلى جانب النص — لا لوناً وحده', (tester) async {
      await tester.pumpWidget(
        wrap(const AppBanner.error(message: 'تعذّر حفظ الموعد')),
      );

      expect(find.text('تعذّر حفظ الموعد'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('لكل نغمة أيقونتها', (tester) async {
      for (final (banner, icon) in [
        (const AppBanner.success(message: 'م'), Icons.check_circle_outline),
        (const AppBanner.warning(message: 'م'), Icons.warning_amber_rounded),
        (const AppBanner.error(message: 'م'), Icons.error_outline),
        (const AppBanner.info(message: 'م'), Icons.info_outline),
      ]) {
        await tester.pumpWidget(wrap(banner));
        expect(find.byIcon(icon), findsOneWidget);
      }
    });

    testWidgets('يعرض العنوان والإجراء حين يُمرَّران', (tester) async {
      await tester.pumpWidget(
        wrap(
          AppBanner.warning(
            title: 'حسابك غير مُفعَّل',
            message: 'راجع بريدك الإلكتروني',
            action: TextButton(onPressed: () {}, child: const Text('إعادة')),
          ),
        ),
      );

      expect(find.text('حسابك غير مُفعَّل'), findsOneWidget);
      expect(find.text('راجع بريدك الإلكتروني'), findsOneWidget);
      expect(find.text('إعادة'), findsOneWidget);
    });

    testWidgets('زر الإغلاق يظهر فقط مع onDismiss', (tester) async {
      await tester.pumpWidget(wrap(const AppBanner.info(message: 'م')));
      expect(find.byIcon(Icons.close), findsNothing);

      var dismissed = false;
      await tester.pumpWidget(
        wrap(AppBanner.info(message: 'م', onDismiss: () => dismissed = true)),
      );
      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });
  });

  group('AppSnackBar', () {
    testWidgets('يُبنى بلا BuildContext ويعرض أيقونة النغمة', (tester) async {
      // البناء بلا سياق هو ما يسمح باستدعائه بعد `await` دون تحذير
      // use_build_context_synchronously.
      final bar = AppSnackBar.success('تم حفظ الموعد');

      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(bar),
              child: const Text('اعرض'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('اعرض'));
      await tester.pump();

      expect(find.text('تم حفظ الموعد'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    test('رسالة الخطأ تبقى أطول من رسالة النجاح', () {
      // المستخدم يحتاج وقتاً لقراءة سبب الفشل، لا للاحتفاء بالنجاح.
      expect(
        AppSnackBar.error('x').duration,
        greaterThan(AppSnackBar.success('x').duration),
      );
    });

    testWidgets('امتداد السياق يعرض الشريط', (tester) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => context.showError('فشل الاتصال'),
              child: const Text('اعرض'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('اعرض'));
      await tester.pump();
      expect(find.text('فشل الاتصال'), findsOneWidget);
    });
  });

  group('حالات الصفحة', () {
    testWidgets('EmptyView و ErrorView قابلتان للتمييز', (tester) async {
      // الفارق الذي يهم: «لا يوجد» يعني أن الطلب نجح وكانت النتيجة فارغة،
      // و«تعذّر التحميل» يعني أننا لا نعرف. الثانية وحدها تعرض إعادة محاولة.
      await tester.pumpWidget(
        wrap(const EmptyView(title: 'لا يوجد مرضى')),
      );
      expect(find.text('لا يوجد مرضى'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);

      var retried = false;
      await tester.pumpWidget(
        wrap(ErrorView(
            message: 'تحقّق من اتصالك', onRetry: () => retried = true)),
      );
      expect(find.text('تعذّر تحميل البيانات'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh));
      expect(retried, isTrue);
    });

    testWidgets('ErrorView بلا onRetry لا يعرض زر إعادة', (tester) async {
      await tester.pumpWidget(wrap(const ErrorView(message: 'خطأ')));
      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    testWidgets('LoadingView يعرض رسالته حين تُمرَّر', (tester) async {
      await tester.pumpWidget(wrap(const LoadingView()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(wrap(const LoadingView(message: 'جارٍ الحجز')));
      expect(find.text('جارٍ الحجز'), findsOneWidget);
    });
  });

  group('AppCard', () {
    testWidgets('يستجيب للنقر حين يُمرَّر onTap فقط', (tester) async {
      await tester.pumpWidget(wrap(const AppCard(child: Text('محتوى'))));
      expect(find.byType(InkWell), findsNothing);

      var tapped = false;
      await tester.pumpWidget(
        wrap(AppCard(onTap: () => tapped = true, child: const Text('محتوى'))),
      );
      await tester.tap(find.text('محتوى'));
      expect(tapped, isTrue);
    });
  });

  group('SectionHeader', () {
    testWidgets('يعرض العنوان والشرح والإجراء', (tester) async {
      await tester.pumpWidget(
        wrap(
          SectionHeader(
            title: 'مواعيدك القادمة',
            subtitle: 'خلال الأسبوع',
            trailing: TextButton(onPressed: () {}, child: const Text('الكل')),
          ),
        ),
      );

      expect(find.text('مواعيدك القادمة'), findsOneWidget);
      expect(find.text('خلال الأسبوع'), findsOneWidget);
      expect(find.text('الكل'), findsOneWidget);
    });
  });
}
