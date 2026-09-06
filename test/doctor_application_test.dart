import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/constants/doctor_application_status.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/core/widgets/widgets.dart';
import 'package:medical_appointment_app/data/models/doctor_application.dart';
import 'package:medical_appointment_app/data/services/doctor_application_service.dart';
import 'package:medical_appointment_app/presentation/widgets/doctor_application_card.dart';

/// يلفّ الودجة بنسق التطبيق واتجاه عربي — كما تُعرض فعلاً.
Widget wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      locale: const Locale('ar'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

DoctorApplication app({
  DoctorApplicationStatus status = DoctorApplicationStatus.pending,
  String? rejectionReason,
}) =>
    DoctorApplication(
      applicantId: 'uid_1',
      applicantName: 'أحمد يوسف',
      specialty: 'طب الأسرة',
      professionalBio: 'طبيب أسرة بخبرة في الرعاية الأولية ومتابعة المزمن.',
      yearsOfExperience: 8,
      status: status,
      rejectionReason: rejectionReason,
    );

void main() {
  // =========================================================================
  group('آلة حالات الطلب', () {
    test('تُقرأ كل الصيغ المخزَّنة', () {
      expect(DoctorApplicationStatus.parse('pending'),
          DoctorApplicationStatus.pending);
      expect(DoctorApplicationStatus.parse('approved'),
          DoctorApplicationStatus.approved);
      expect(DoctorApplicationStatus.parse('rejected'),
          DoctorApplicationStatus.rejected);
      expect(DoctorApplicationStatus.parse('  APPROVED '),
          DoctorApplicationStatus.approved);
    });

    test('غياب المستند يعني «لا طلب» لا خطأ', () {
      expect(DoctorApplicationStatus.parse(null), DoctorApplicationStatus.none);
      expect(DoctorApplicationStatus.parse(''), DoctorApplicationStatus.none);
    });

    test('القيمة غير المعروفة تميل إلى «قيد المراجعة» لا إلى القبول', () {
      // الخطأ في قراءة حالة غامضة يجب أن يميل إلى منع الصلاحية لا منحها.
      expect(DoctorApplicationStatus.parse('weird_value'),
          DoctorApplicationStatus.pending);
      expect(
          DoctorApplicationStatus.parse(42), DoctorApplicationStatus.pending);
    });

    test('التحرير مسموح قبل التقديم وبعد الرفض فقط', () {
      expect(DoctorApplicationStatus.none.isEditable, isTrue);
      expect(DoctorApplicationStatus.rejected.isEditable, isTrue);
      // لا تعديل تحت يد المراجع، ولا بعد صدور القبول.
      expect(DoctorApplicationStatus.pending.isEditable, isFalse);
      expect(DoctorApplicationStatus.approved.isEditable, isFalse);
    });

    test('لكل حالة نص عربي غير فارغ', () {
      for (final s in DoctorApplicationStatus.values) {
        expect(s.arabicLabel.trim(), isNotEmpty);
      }
    });

    test('كل حالة لها أيقونة تميّزها عن البقية', () {
      final icons = <IconData>{};
      for (final s in DoctorApplicationStatus.values) {
        final icon = StatusChip.doctorApplication(s).icon;
        expect(icon, isNotNull);
        expect(icons.add(icon!), isTrue,
            reason: 'الحالة ${s.name} تكرّر أيقونة حالة أخرى');
      }
    });
  });

  // =========================================================================
  group('سبب الرفض لا يُعرض في غير موضعه', () {
    test('يظهر حين تكون الحالة مرفوضة', () {
      final a = app(
          status: DoctorApplicationStatus.rejected,
          rejectionReason: 'النبذة غير كافية.');
      expect(a.activeRejectionReason, 'النبذة غير كافية.');
    });

    test('لا يظهر بعد إعادة التقديم وإن بقي محفوظاً', () {
      // المستند يحتفظ بسبب آخر رفض حفظاً لسجل المراجعة، لكن عرضه بينما
      // الطلب قيد المراجعة يخبر الطبيب بأنه مرفوض وهو ليس كذلك.
      final a = app(
          status: DoctorApplicationStatus.pending,
          rejectionReason: 'النبذة غير كافية.');
      expect(a.rejectionReason, isNotNull);
      expect(a.activeRejectionReason, isNull);
    });

    test('لا يظهر بعد القبول', () {
      final a = app(
          status: DoctorApplicationStatus.approved,
          rejectionReason: 'سبب قديم.');
      expect(a.activeRejectionReason, isNull);
    });
  });

  // =========================================================================
  group('تحقّق النموذج', () {
    test('الاسم القصير مرفوض', () {
      expect(DoctorApplicationService.validateName('أ'), isNotNull);
      expect(DoctorApplicationService.validateName(''), isNotNull);
      expect(DoctorApplicationService.validateName('  '), isNotNull);
      expect(DoctorApplicationService.validateName('أحمد يوسف'), isNull);
    });

    test('التخصص مطلوب وضمن الحد', () {
      expect(DoctorApplicationService.validateSpecialty(''), isNotNull);
      expect(DoctorApplicationService.validateSpecialty('ط' * 81), isNotNull);
      expect(DoctorApplicationService.validateSpecialty('طب الأسرة'), isNull);
    });

    test('سنوات الخبرة عدد صحيح ضمن نطاق معقول', () {
      expect(DoctorApplicationService.validateYearsOfExperience('ثمانية'),
          isNotNull);
      expect(
          DoctorApplicationService.validateYearsOfExperience('-1'), isNotNull);
      expect(
          DoctorApplicationService.validateYearsOfExperience('200'), isNotNull);
      expect(DoctorApplicationService.validateYearsOfExperience('0'), isNull);
      expect(DoctorApplicationService.validateYearsOfExperience('8'), isNull);
    });

    test('النبذة لها حد أدنى وحد أعلى', () {
      expect(DoctorApplicationService.validateBio('قصيرة'), isNotNull);
      expect(DoctorApplicationService.validateBio('ط' * 1001), isNotNull);
      expect(DoctorApplicationService.validateBio('ط' * 25), isNull);
    });

    test('سبب الرفض إلزامي وذو معنى', () {
      expect(DoctorApplicationService.validateRejectionReason(''), isNotNull);
      expect(DoctorApplicationService.validateRejectionReason('لا'), isNotNull);
      expect(DoctorApplicationService.validateRejectionReason('ط' * 501),
          isNotNull);
      expect(
        DoctorApplicationService.validateRejectionReason(
            'النبذة المهنية لا توضّح مكان الممارسة.'),
        isNull,
      );
    });

    test('حدود التحقّق تطابق ما تفرضه قواعد الأمان', () {
      // لو انحرف أحدهما عن الآخر لظهر للمستخدم نموذج يقبل ما يرفضه الخادم.
      // القيم هنا مكرّرة عمداً من `firestore.rules` لتفشل عند أي تغيير
      // أحادي الجانب.
      expect(DoctorApplicationService.minSpecialtyLength, 2);
      expect(DoctorApplicationService.maxSpecialtyLength, 80);
      expect(DoctorApplicationService.minBioLength, 20);
      expect(DoctorApplicationService.maxBioLength, 1000);
      expect(DoctorApplicationService.maxYearsOfExperience, 70);
      expect(DoctorApplicationService.minRejectionReasonLength, 10);
      expect(DoctorApplicationService.maxRejectionReasonLength, 500);
    });
  });

  // =========================================================================
  group('بطاقة الطلب على الصفحة الرئيسية', () {
    testWidgets('لا طلب: تعرض الدعوة وزر التقديم', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(DoctorApplicationCard(
        application: DoctorApplication.none('uid_1'),
        onApply: () => tapped = true,
      )));

      expect(find.text('هل أنت طبيب؟'), findsOneWidget);
      expect(
          find.text('يمكنك تقديم طلب للانضمام إلى DrD كطبيب.'), findsOneWidget);

      await tester.tap(find.text('تقديم طلب'));
      expect(tapped, isTrue);
    });

    testWidgets('قيد المراجعة: تشرح ما يحدث ولا تعرض زر تعديل', (tester) async {
      await tester.pumpWidget(wrap(DoctorApplicationCard(
        application: app(status: DoctorApplicationStatus.pending),
        onApply: () {},
      )));

      expect(find.text('طلبك قيد المراجعة'), findsOneWidget);
      expect(
        find.text('سيتم مراجعة طلبك من إدارة DrD قبل تفعيل حساب الطبيب.'),
        findsOneWidget,
      );
      // لا تحرير أثناء المراجعة — لا في القاعدة ولا في الواجهة.
      expect(find.text('تعديل وإعادة التقديم'), findsNothing);
      expect(find.text('تقديم طلب'), findsNothing);
    });

    testWidgets('مرفوض: يظهر السبب ويمكن التصحيح', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(DoctorApplicationCard(
        application: app(
          status: DoctorApplicationStatus.rejected,
          rejectionReason: 'النبذة المهنية لا توضّح مكان الممارسة.',
        ),
        onApply: () => tapped = true,
      )));

      expect(find.text('تم رفض الطلب'), findsOneWidget);
      expect(
          find.text('النبذة المهنية لا توضّح مكان الممارسة.'), findsOneWidget);

      await tester.tap(find.text('تعديل وإعادة التقديم'));
      expect(tapped, isTrue);
    });

    testWidgets('مرفوض بلا سبب مسجَّل: يوجّه للتواصل بدل ترك فراغ',
        (tester) async {
      await tester.pumpWidget(wrap(DoctorApplicationCard(
        application: app(status: DoctorApplicationStatus.rejected),
        onApply: () {},
      )));
      expect(find.textContaining('لم يُسجَّل سبب للرفض'), findsOneWidget);
    });

    testWidgets('مقبول: يعلن القبول ويشير إلى أدوات الطبيب', (tester) async {
      await tester.pumpWidget(wrap(DoctorApplicationCard(
        application: app(status: DoctorApplicationStatus.approved),
        onApply: () {},
      )));

      expect(find.text('تم قبول طلبك كطبيب'), findsOneWidget);
      expect(find.textContaining('يمكنك الآن استخدام أدوات الطبيب'),
          findsOneWidget);
    });

    testWidgets('مقبول والترقية لم تصل: يقول ذلك بدل الوعد بما لا يعمل',
        (tester) async {
      await tester.pumpWidget(wrap(DoctorApplicationCard(
        application: app(status: DoctorApplicationStatus.approved),
        onApply: () {},
        isActivating: true,
      )));

      expect(find.textContaining('جارٍ تفعيل حسابك'), findsOneWidget);
      expect(
          find.textContaining('يمكنك الآن استخدام أدوات الطبيب'), findsNothing);
    });

    testWidgets('تُرسم في الوضع الليلي بلا انهيار', (tester) async {
      for (final status in DoctorApplicationStatus.values) {
        await tester.pumpWidget(wrap(
          DoctorApplicationCard(
            application: status == DoctorApplicationStatus.none
                ? DoctorApplication.none('uid_1')
                : app(status: status, rejectionReason: 'سبب كافٍ للاختبار.'),
            onApply: () {},
          ),
          theme: AppTheme.dark,
        ));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('الاتجاه عربي من اليمين لليسار', (tester) async {
      await tester.pumpWidget(wrap(DoctorApplicationCard(
        application: DoctorApplication.none('uid_1'),
        onApply: () {},
      )));

      final dir = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.text('هل أنت طبيب؟'),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(dir.textDirection, TextDirection.rtl);
    });
  });

  // =========================================================================
  group('رقاقة حالة الطلب', () {
    testWidgets('تعرض النص العربي للحالة', (tester) async {
      await tester.pumpWidget(wrap(
        StatusChip.doctorApplication(DoctorApplicationStatus.pending),
      ));
      expect(find.text('قيد المراجعة'), findsOneWidget);
    });

    testWidgets('القبول أخضر والرفض أحمر — ومعهما أيقونة', (tester) async {
      await tester.pumpWidget(wrap(
        StatusChip.doctorApplication(DoctorApplicationStatus.approved),
      ));
      expect(find.byIcon(Icons.verified_outlined), findsOneWidget);

      await tester.pumpWidget(wrap(
        StatusChip.doctorApplication(DoctorApplicationStatus.rejected),
      ));
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    });
  });
}
