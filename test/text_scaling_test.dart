import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/constants/appointment_status.dart';
import 'package:medical_appointment_app/core/constants/doctor_application_status.dart';
import 'package:medical_appointment_app/core/constants/medical_share_status.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/core/widgets/widgets.dart';

/// فيض التخطيط عند تكبير خط النظام.
///
/// ## لماذا هذا الاختبار موجود
///
/// `StatusChip` كانت تفيض عند عرض 320 بكسل وتكبير ×1.5 — وهو **دون** إعداد
/// «كبير جداً» في أندرويد، أي أنه يصيب مستخدمين عاديين. ولا يلتقط ذلك محلّل
/// ولا اختبار وجود عنصر: التخطيط يُبنى بنجاح، ويظهر العطل شريطاً أصفر على
/// الشاشة وحدها.
///
/// ## فخّ في القياس نفسه
///
/// `RenderFlex` لا يبلّغ عن الفيض إلا **مرة واحدة لكل كائن رسم**. و`pumpWidget`
/// يعيد استخدام شجرة العناصر حين يتطابق نوع الودجت، فقياس عشر حالات متتالية
/// لنفس المكوّن يُبلّغ عن الأولى ويبتلع التسع. لذلك تُهدَم الشجرة صراحةً قبل
/// كل قياس — بدون ذلك يمرّ هذا الاختبار وهو أعمى.
void main() {
  // 320 أضيق شاشة أندرويد شائعة، و430 أعرض هاتف حديث.
  const widths = <double>[320, 360, 390, 430];

  // ×1.15 و×1.3 إعدادا أندرويد «كبير» و«أكبر»، و×2.0 سقف إعدادات الوصولية.
  const scales = <double>[1.0, 1.15, 1.3, 1.5, 1.8, 2.0];

  Future<String?> overflowOf(
    WidgetTester tester,
    Widget child, {
    required double width,
    required double scale,
  }) async {
    // شجرة نظيفة لكل قياس — راجع «فخّ في القياس» أعلاه.
    await tester.pumpWidget(const SizedBox.shrink());

    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ar'),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      ),
    );

    final error = tester.takeException();
    return error?.toString().split('\n').first;
  }

  testWidgets('لا مكوّن مشترك يفيض عند أي عرض أو تكبير مدعوم', (tester) async {
    // كل الحالات لكل رقاقة: أطول نص هو ما يفيض أولاً، وتثبيت حالة واحدة
    // يترك البقية بلا حراسة.
    final subjects = <String, Widget>{
      for (final s in AppointmentStatus.values)
        'StatusChip.appointment(${s.name})': StatusChip.appointment(s),
      for (final s in DoctorApplicationStatus.values)
        'StatusChip.doctorApplication(${s.name})':
            StatusChip.doctorApplication(s),
      for (final s in MedicalShareStatus.values)
        'StatusChip.medicalShare(${s.name})': StatusChip.medicalShare(s),
      'AppBanner.error': const AppBanner.error(
        message: 'تعذّر حفظ الموعد، تأكد من اتصالك بالإنترنت وحاول مرة أخرى',
      ),
      'AppBanner.success':
          const AppBanner.success(message: 'تم حفظ البيانات بنجاح'),
      'SectionHeader': const SectionHeader(
        title: 'المواعيد القادمة',
        subtitle: 'كل ما هو محجوز خلال الأيام السبعة القادمة',
      ),
      'EmptyView': const EmptyView(
        icon: Icons.event_busy_outlined,
        title: 'لا توجد مواعيد',
        message: 'لم تحجز أي موعد بعد. ابحث عن طبيب وابدأ الحجز.',
      ),
      'ErrorView': const ErrorView(
        message: 'تعذّر الاتصال بالخادم، تحقق من الشبكة ثم أعد المحاولة.',
      ),
      'LoadingView': const LoadingView(message: 'جارٍ تحميل مواعيدك...'),
      'AppCard': const AppCard(
        child: Text('د. أحمد يوسف — استشاري جراحة عامة وجراحة المناظير'),
      ),
    };

    final failures = <String>[];
    for (final width in widths) {
      for (final scale in scales) {
        for (final entry in subjects.entries) {
          final error = await overflowOf(
            tester,
            entry.value,
            width: width,
            scale: scale,
          );
          if (error != null) {
            failures.add('عرض $width · تكبير $scale · ${entry.key} → $error');
          }
        }
      }
    }

    expect(
      failures,
      isEmpty,
      reason: 'فيض تخطيط عند تكبير الخط:\n${failures.join('\n')}',
    );
  });

  testWidgets('أيقونة الرقاقة تكبر مع النص', (tester) async {
    // الحارس على سبب الفيض لا على أثره: أيقونة بمقاس ثابت تجعل النص وحده
    // ينمو، فيصطدم بحافة لم تنمُ معه. ولو عاد الرقم الحرفي إلى مكانه لمرّ
    // اختبار الفيض أعلاه (لأن `Flexible` يلتقط الحمل) بينما تصغر الأيقونة
    // بصرياً حتى تفقد معناها.
    double iconSize(WidgetTester t) =>
        t.widget<Icon>(find.byType(Icon).first).size!;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ar'),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.0)),
          child: Scaffold(
            body: StatusChip.appointment(AppointmentStatus.pendingConfirmation),
          ),
        ),
      ),
    );
    final atOne = iconSize(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ar'),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: StatusChip.appointment(AppointmentStatus.pendingConfirmation),
          ),
        ),
      ),
    );
    final atTwo = iconSize(tester);

    expect(atTwo, greaterThan(atOne),
        reason: 'مقاس الأيقونة ثابت رغم تكبير الخط');
    expect(atTwo, closeTo(atOne * 2, 0.01));
  });
}
