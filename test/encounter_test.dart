import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/data/models/encounter.dart';
import 'package:medical_appointment_app/data/services/encounter_service.dart';
import 'package:medical_appointment_app/presentation/screens/doctor_encounter_screen.dart';
import 'package:medical_appointment_app/presentation/screens/encounter_detail_screen.dart';

Widget wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      locale: const Locale('ar'),
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    );

/// يرسم شاشة كاملة على سطح طويل.
///
/// السطح الافتراضي في الاختبار 800×600، وشاشتا السجل أطول منه — فزرّ الحفظ
/// يقع خارج الإطار ولا يُعثر عليه. الطول هنا يجعل الاختبار يقيس المنطق لا
/// حدود النافذة.
Future<void> pumpScreen(WidgetTester tester, Widget child,
    {ThemeData? theme}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(child, theme: theme));
  await tester.pumpAndSettle();
}

Encounter sample({
  String diagnosis = 'التهاب لوزتين حاد',
  String clinicalNotes = 'حرارة 38.5 ولا ضيق تنفس.',
  String treatmentPlan = 'مضاد حيوي 500مغ مرتين يومياً لخمسة أيام.',
  String followUpNotes = '',
  String followUpDate = '',
  DateTime? createdAt,
  DateTime? updatedAt,
}) =>
    Encounter(
      appointmentId: 'appt_1',
      patientId: 'patient_1',
      doctorId: 'doctor_1',
      doctorName: 'د. أحمد يوسف',
      doctorSpecialization: 'طب الأسرة',
      encounterDate: '2030-02-01',
      diagnosis: diagnosis,
      clinicalNotes: clinicalNotes,
      treatmentPlan: treatmentPlan,
      followUpNotes: followUpNotes,
      followUpDate: followUpDate,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

/// خدمة مزيّفة: تسجّل ما طُلب منها وتردّ بما يُطلب.
class _FakeService extends EncounterService {
  _FakeService({this.result = const EncounterResult.success()});

  final EncounterResult result;
  Map<String, dynamic>? saved;

  @override
  Future<EncounterResult> save({
    required String appointmentId,
    required String patientId,
    required String doctorId,
    required String doctorName,
    required String doctorSpecialization,
    required String encounterDate,
    required String diagnosis,
    String clinicalNotes = '',
    String treatmentPlan = '',
    String followUpNotes = '',
    String followUpDate = '',
  }) async {
    saved = {
      'appointmentId': appointmentId,
      'patientId': patientId,
      'doctorId': doctorId,
      'encounterDate': encounterDate,
      'diagnosis': diagnosis,
      'clinicalNotes': clinicalNotes,
      'treatmentPlan': treatmentPlan,
    };
    return result;
  }
}

Widget formUnder(_FakeService service, {Encounter? existing}) =>
    DoctorEncounterScreen(
      appointmentId: 'appt_1',
      patientId: 'patient_1',
      patientName: 'أحمد',
      doctorId: 'doctor_1',
      doctorName: 'د. أحمد يوسف',
      doctorSpecialization: 'طب الأسرة',
      encounterDate: '2030-02-01',
      existing: existing,
      service: service,
    );

void main() {
  // بيانات التقويم العربي.
  //
  // في التطبيق يهيّئها `GlobalMaterialLocalizations.delegate`، ولا وجود له
  // في اختبار ودجة معزول — فبدونها ترمي `DateFormat(..., 'ar')` استثناءً
  // وتفشل الشاشة كلها في البناء.
  setUpAll(() => initializeDateFormatting('ar'));

  // =========================================================================
  group('نموذج السجل', () {
    test('معرّف السجل هو معرّف الموعد', () {
      // هو ما يفرض «سجل واحد لكل زيارة» بنيوياً.
      expect(sample().id, sample().appointmentId);
    });

    test('التصحيح يُكتشف بفارق زمني لا بمساواة', () {
      // الطابعان يُكتبان في نفس الدفعة عند الإنشاء وقد يختلفان بميلي ثانية.
      final t = DateTime(2030, 2, 1, 10);
      expect(
        sample(createdAt: t, updatedAt: t.add(const Duration(milliseconds: 40)))
            .wasEdited,
        isFalse,
      );
      expect(
        sample(createdAt: t, updatedAt: t.add(const Duration(hours: 3)))
            .wasEdited,
        isTrue,
      );
      expect(sample().wasEdited, isFalse);
    });
  });

  // =========================================================================
  group('تحقّق النموذج', () {
    test('التشخيص مطلوب', () {
      expect(EncounterService.validateDiagnosis(''), isNotNull);
      expect(EncounterService.validateDiagnosis(' '), isNotNull);
      expect(EncounterService.validateDiagnosis('ن'), isNotNull);
      expect(EncounterService.validateDiagnosis('التهاب'), isNull);
    });

    test('حدود الطول مطابقة لما تفرضه القاعدة', () {
      // لو انحرف أحدهما عن الآخر لقبل النموذج ما يرفضه الخادم.
      expect(EncounterService.maxDiagnosisLength, 300);
      expect(EncounterService.maxNotesLength, 4000);
      expect(EncounterService.maxFollowUpNotesLength, 1000);
      expect(EncounterService.validateDiagnosis('ط' * 301), isNotNull);
      expect(EncounterService.validateNotes('ط' * 4001), isNotNull);
      expect(EncounterService.validateFollowUpNotes('ط' * 1001), isNotNull);
    });

    test('الحقول الاختيارية تقبل الفراغ', () {
      // ليست كل زيارة تنتهي بوصفة أو متابعة.
      expect(EncounterService.validateNotes(''), isNull);
      expect(EncounterService.validateNotes(null), isNull);
      expect(EncounterService.validateFollowUpNotes(''), isNull);
    });
  });

  // =========================================================================
  group('نموذج الطبيب', () {
    testWidgets('لا يُحفظ سجل بلا تشخيص', (tester) async {
      final service = _FakeService();
      await pumpScreen(tester, formUnder(service));

      await tester.tap(find.text('حفظ السجل'));
      await tester.pumpAndSettle();

      expect(service.saved, isNull, reason: 'حُفظ سجل بلا تشخيص');
      expect(find.textContaining('اكتب التشخيص'), findsOneWidget);
    });

    testWidgets('الحفظ يمرّر بيانات الزيارة كما هي', (tester) async {
      final service = _FakeService();
      await pumpScreen(tester, formUnder(service));

      await tester.enterText(find.byType(TextFormField).first, 'التهاب لوزتين');
      await tester.tap(find.text('حفظ السجل'));
      await tester.pumpAndSettle();

      expect(service.saved, isNotNull);
      expect(service.saved!['diagnosis'], 'التهاب لوزتين');
      expect(service.saved!['appointmentId'], 'appt_1');
      expect(service.saved!['patientId'], 'patient_1');
      expect(service.saved!['doctorId'], 'doctor_1');
      // تاريخ الزيارة من الموعد لا من اليوم.
      expect(service.saved!['encounterDate'], '2030-02-01');
    });

    testWidgets('النجاح يُعرض كنجاح لا كخطأ', (tester) async {
      final service = _FakeService();
      await pumpScreen(tester, formUnder(service));
      await tester.enterText(find.byType(TextFormField).first, 'التهاب');
      await tester.tap(find.text('حفظ السجل'));
      await tester.pump();
      await tester.pump();

      expect(find.text('تم حفظ سجل الزيارة بنجاح.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
    });

    testWidgets('الفشل يشرح السبب بلغة الطبيب', (tester) async {
      final service = _FakeService(
        result: const EncounterResult.failure(
          'لا يمكن حفظ هذا السجل. تأكّد أن الزيارة مُعلَّمة كمكتملة.',
        ),
      );
      await pumpScreen(tester, formUnder(service));
      await tester.enterText(find.byType(TextFormField).first, 'التهاب');
      await tester.tap(find.text('حفظ السجل'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('تأكّد أن الزيارة مُعلَّمة كمكتملة'),
          findsOneWidget);
    });

    testWidgets('التصحيح يملأ الحقول ويعلن حفظ النسخة السابقة', (tester) async {
      final service = _FakeService();
      await pumpScreen(tester, formUnder(service, existing: sample()));

      expect(find.text('تصحيح سجل الزيارة'), findsOneWidget);
      expect(find.text('التهاب لوزتين حاد'), findsOneWidget);
      expect(find.textContaining('يحفظ نسخة مما كان عليه'), findsOneWidget);
      expect(find.text('حفظ التصحيح'), findsOneWidget);
    });

    testWidgets('يعرض المريض وتاريخ الزيارة قبل الحقول', (tester) async {
      // حتى لا يُكتب سجل على المريض الخطأ.
      await pumpScreen(tester, formUnder(_FakeService()));
      expect(find.text('أحمد'), findsOneWidget);
      expect(find.text('زيارة 2030-02-01'), findsOneWidget);
    });
  });

  // =========================================================================
  group('تفاصيل الزيارة — قراءة', () {
    testWidgets('تعرض المحتوى السريري كاملاً', (tester) async {
      await pumpScreen(
          tester,
          EncounterDetailScreen(
            encounter: sample(
              followUpNotes: 'راجع بعد أسبوع إن استمرت الحرارة.',
              followUpDate: '2030-02-08',
            ),
          ));

      expect(find.text('التهاب لوزتين حاد'), findsOneWidget);
      expect(find.text('حرارة 38.5 ولا ضيق تنفس.'), findsOneWidget);
      expect(find.textContaining('مضاد حيوي'), findsOneWidget);
      expect(find.textContaining('راجع بعد أسبوع'), findsOneWidget);
      expect(find.text('د. أحمد يوسف'), findsOneWidget);
      expect(find.text('طب الأسرة'), findsOneWidget);
    });

    testWidgets('المريض لا يرى زرّ تصحيح', (tester) async {
      // `onEdit` لا يُمرَّر للمريض. والقاعدة ترفض كتابته على أي حال.
      await pumpScreen(tester, EncounterDetailScreen(encounter: sample()));
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('الطبيب المؤلِّف يرى زرّ التصحيح', (tester) async {
      var tapped = false;
      await pumpScreen(
          tester,
          EncounterDetailScreen(
            encounter: sample(),
            onEdit: () => tapped = true,
          ));
      await tester.tap(find.byIcon(Icons.edit_outlined));
      expect(tapped, isTrue);
    });

    testWidgets('لا حذف — السجل الطبي لا يُمحى', (tester) async {
      await pumpScreen(
          tester,
          EncounterDetailScreen(
            encounter: sample(),
            onEdit: () {},
          ));
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.textContaining('حذف'), findsNothing);
    });

    testWidgets('السجل المُصحَّح يقول ذلك للمريض', (tester) async {
      final t = DateTime(2030, 2, 1, 10);
      await pumpScreen(
          tester,
          EncounterDetailScreen(
            encounter: sample(
              createdAt: t,
              updatedAt: t.add(const Duration(days: 2)),
            ),
          ));
      expect(find.textContaining('صُحِّح هذا السجل'), findsOneWidget);
    });

    testWidgets('الأقسام الفارغة لا تُعرض', (tester) async {
      await pumpScreen(
          tester,
          EncounterDetailScreen(
            encounter: sample(clinicalNotes: '', treatmentPlan: ''),
          ));
      expect(find.text('ملاحظات الكشف'), findsNothing);
      expect(find.text('العلاج / الوصفة'), findsNothing);
      expect(find.text('التشخيص'), findsOneWidget);
    });

    testWidgets('لا مشاركة بعد — لا زرّ وهمي', (tester) async {
      // المشاركة مرحلة رابعة. زرّ معطّل يَعِد بما لا يعمل.
      await pumpScreen(tester, EncounterDetailScreen(encounter: sample()));
      expect(find.textContaining('مشاركة'), findsNothing);
      expect(find.byIcon(Icons.share), findsNothing);
    });

    testWidgets('تُرسم في الوضع الليلي بلا انهيار', (tester) async {
      await pumpScreen(tester, EncounterDetailScreen(encounter: sample()),
          theme: AppTheme.dark);
      expect(tester.takeException(), isNull);
    });

    testWidgets('الاتجاه عربي من اليمين لليسار', (tester) async {
      await pumpScreen(tester, EncounterDetailScreen(encounter: sample()));
      final dir = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.text('التهاب لوزتين حاد'),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(dir.textDirection, TextDirection.rtl);
    });
  });
}
