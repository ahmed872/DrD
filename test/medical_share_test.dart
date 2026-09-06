import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:medical_appointment_app/core/constants/medical_share_status.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/core/widgets/widgets.dart';
import 'package:medical_appointment_app/data/models/encounter.dart';
import 'package:medical_appointment_app/data/models/medical_share.dart';
import 'package:medical_appointment_app/data/services/medical_share_service.dart';
import 'package:medical_appointment_app/presentation/screens/share_records_screen.dart';
import 'package:medical_appointment_app/presentation/screens/shared_record_detail_screen.dart';

Widget wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      locale: const Locale('ar'),
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    );

Future<void> pumpScreen(WidgetTester tester, Widget child,
    {ThemeData? theme}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(child, theme: theme));
  await tester.pumpAndSettle();
}

Encounter enc(String id, String diagnosis) => Encounter(
      appointmentId: id,
      patientId: 'p1',
      doctorId: 'd_author',
      doctorName: 'د. أحمد',
      doctorSpecialization: 'طب الأسرة',
      encounterDate: '2030-05-01',
      diagnosis: diagnosis,
    );

MedicalShare share({
  MedicalShareStatus status = MedicalShareStatus.active,
  List<SharedEncounterSnapshot>? snapshots,
  String? rejectionReason,
}) =>
    MedicalShare(
      id: 'share_1',
      patientId: 'p1',
      patientName: 'أحمد يوسف',
      recipientDoctorId: 'd_recipient',
      recipientDoctorName: 'د. سعيد',
      recipientDoctorSpecialization: 'جلدية',
      encounterIds: const ['enc_1'],
      status: status,
      rejectionReason: rejectionReason,
      createdAt: DateTime(2030, 5, 2),
      snapshots: snapshots ??
          const [
            SharedEncounterSnapshot(
              encounterId: 'enc_1',
              encounterDate: '2030-05-01',
              diagnosis: 'التهاب في الحلق',
              doctorName: 'د. أحمد',
              doctorSpecialization: 'طب الأسرة',
              clinicalNotes: 'حرارة 38.',
              treatmentPlan: 'مضاد حيوي.',
            ),
          ],
    );

/// خدمة مزيّفة تسجّل ما طُلب منها.
class _FakeService extends MedicalShareService {
  _FakeService({
    this.doctors = const [],
    this.createResult = const ShareResult.success('new_share'),
    this.revokeResult = const ShareResult.success(),
    this.shareStream,
    this.doctorsThrow = false,
  });

  final List<DirectoryDoctor> doctors;
  final ShareResult createResult;
  final ShareResult revokeResult;
  final Stream<MedicalShare?>? shareStream;
  final bool doctorsThrow;

  Map<String, dynamic>? created;
  String? revokedId;

  @override
  Future<List<DirectoryDoctor>> fetchApprovedDoctors(
      {String? excludeId}) async {
    if (doctorsThrow) throw Exception('network');
    return doctors;
  }

  @override
  Future<ShareResult> createShare({
    required String patientId,
    required String patientName,
    required DirectoryDoctor recipient,
    required List<String> encounterIds,
  }) async {
    created = {
      'patientId': patientId,
      'recipientId': recipient.id,
      'encounterIds': encounterIds,
    };
    return createResult;
  }

  @override
  Future<ShareResult> revoke(String shareId) async {
    revokedId = shareId;
    return revokeResult;
  }

  @override
  Stream<MedicalShare?> watchShare(String shareId) =>
      shareStream ?? Stream.value(share());
}

const _doctors = [
  DirectoryDoctor(id: 'd_recipient', name: 'د. سعيد', specialization: 'جلدية'),
  DirectoryDoctor(id: 'd_other', name: 'د. منى', specialization: 'باطنة'),
];

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  // =========================================================================
  group('آلة حالات المشاركة', () {
    test('كل الصيغ تُقرأ', () {
      expect(MedicalShareStatus.parse('active'), MedicalShareStatus.active);
      expect(MedicalShareStatus.parse('revoked'), MedicalShareStatus.revoked);
      expect(MedicalShareStatus.parse('rejected'), MedicalShareStatus.rejected);
      expect(MedicalShareStatus.parse('pending'), MedicalShareStatus.pending);
    });

    test('المجهول يميل إلى منع الوصول لا منحه', () {
      // الخطأ في قراءة حالة غامضة يجب ألّا ينتهي بكشف سجل طبي.
      expect(MedicalShareStatus.parse(null), MedicalShareStatus.pending);
      expect(MedicalShareStatus.parse('weird'), MedicalShareStatus.pending);
      expect(MedicalShareStatus.parse('ACTIVE'), MedicalShareStatus.active);
    });

    test('الطبيب يرى النشطة وحدها — مطابقة لشرط القاعدة', () {
      expect(MedicalShareStatus.active.isVisibleToRecipient, isTrue);
      for (final s in [
        MedicalShareStatus.pending,
        MedicalShareStatus.revoked,
        MedicalShareStatus.rejected,
      ]) {
        expect(s.isVisibleToRecipient, isFalse,
            reason: '${s.name} يجب ألّا تكون مرئية للطبيب');
      }
    });

    test('الإلغاء ممكن قبل التفعيل وبعده فقط', () {
      expect(MedicalShareStatus.active.isRevocable, isTrue);
      expect(MedicalShareStatus.pending.isRevocable, isTrue);
      expect(MedicalShareStatus.revoked.isRevocable, isFalse);
      expect(MedicalShareStatus.rejected.isRevocable, isFalse);
    });

    test('لكل حالة أيقونة تميّزها', () {
      final icons = <IconData>{};
      for (final s in MedicalShareStatus.values) {
        final icon = StatusChip.medicalShare(s).icon;
        expect(icons.add(icon!), isTrue, reason: '${s.name} يكرّر أيقونة');
      }
    });
  });

  // =========================================================================
  group('شاشة المشاركة', () {
    testWidgets('تعرض السجلات المختارة قبل اختيار الطبيب', (tester) async {
      await pumpScreen(
          tester,
          ShareRecordsScreen(
            patientId: 'p1',
            patientName: 'أحمد',
            encounters: [enc('enc_1', 'التهاب في الحلق')],
            service: _FakeService(doctors: _doctors),
          ));

      expect(find.text('السجلات المختارة'), findsOneWidget);
      expect(find.text('التهاب في الحلق'), findsOneWidget);
      expect(find.text('اختر الطبيب'), findsOneWidget);
    });

    testWidgets('لا مشاركة قبل اختيار طبيب', (tester) async {
      final service = _FakeService(doctors: _doctors);
      await pumpScreen(
          tester,
          ShareRecordsScreen(
            patientId: 'p1',
            patientName: 'أحمد',
            encounters: [enc('enc_1', 'التهاب')],
            service: service,
          ));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(find.text('اختر طبيباً للمتابعة'), findsOneWidget);
      expect(service.created, isNull);
    });

    testWidgets('المراجعة تسبق الإرسال — حوار تأكيد', (tester) async {
      final service = _FakeService(doctors: _doctors);
      await pumpScreen(
          tester,
          ShareRecordsScreen(
            patientId: 'p1',
            patientName: 'أحمد',
            encounters: [enc('enc_1', 'التهاب')],
            service: service,
          ));

      await tester.tap(find.text('د. سعيد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مشاركة مع د. سعيد'));
      await tester.pumpAndSettle();

      // لا يُرسل شيء قبل التأكيد.
      expect(service.created, isNull);
      expect(find.text('تأكيد المشاركة'), findsOneWidget);
      expect(find.textContaining('يمكنك إلغاء المشاركة في أي وقت'),
          findsOneWidget);
    });

    testWidgets('التأكيد يرسل المعرّفات فقط', (tester) async {
      final service = _FakeService(doctors: _doctors);
      await pumpScreen(
          tester,
          ShareRecordsScreen(
            patientId: 'p1',
            patientName: 'أحمد',
            encounters: [enc('enc_1', 'التهاب'), enc('enc_2', 'حساسية')],
            service: service,
          ));

      await tester.tap(find.text('د. سعيد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مشاركة مع د. سعيد'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'مشاركة'));
      await tester.pumpAndSettle();

      expect(service.created, isNotNull);
      expect(service.created!['recipientId'], 'd_recipient');
      expect(service.created!['encounterIds'], ['enc_1', 'enc_2']);
      expect(service.created!['patientId'], 'p1');
    });

    testWidgets('الوعد لا يتجاوز ما تفرضه القاعدة', (tester) async {
      await pumpScreen(
          tester,
          ShareRecordsScreen(
            patientId: 'p1',
            patientName: 'أحمد',
            encounters: [enc('enc_1', 'التهاب')],
            service: _FakeService(doctors: _doctors),
          ));
      expect(find.textContaining('السجلات التي اخترتها فقط'), findsOneWidget);
      expect(find.textContaining('لن يتغيّر ما يراه'), findsOneWidget);
    });

    testWidgets('فشل تحميل الأطباء يعرض حالة خطأ لا شاشة فارغة',
        (tester) async {
      await pumpScreen(
          tester,
          ShareRecordsScreen(
            patientId: 'p1',
            patientName: 'أحمد',
            encounters: [enc('enc_1', 'التهاب')],
            service: _FakeService(doctorsThrow: true),
          ));
      expect(find.textContaining('تعذّر تحميل قائمة الأطباء'), findsOneWidget);
    });

    testWidgets('لا أطباء: حالة فارغة هادئة', (tester) async {
      await pumpScreen(
          tester,
          ShareRecordsScreen(
            patientId: 'p1',
            patientName: 'أحمد',
            encounters: [enc('enc_1', 'التهاب')],
            service: _FakeService(doctors: const []),
          ));
      expect(find.text('لا يوجد أطباء متاحون للمشاركة'), findsOneWidget);
    });
  });

  // =========================================================================
  group('تفاصيل المشاركة', () {
    testWidgets('المريض يرى الطبيب المستقبِل وزرّ الإلغاء', (tester) async {
      await pumpScreen(
          tester,
          SharedRecordDetailScreen(
            shareId: 'share_1',
            viewer: ShareViewer.patient,
            service: _FakeService(),
          ));

      expect(find.text('د. سعيد'), findsOneWidget);
      expect(find.text('إلغاء المشاركة'), findsOneWidget);
      expect(find.textContaining('لا تتغيّر إذا عُدِّل السجل'), findsOneWidget);
    });

    testWidgets('الطبيب يرى المريض ولا يرى زرّ الإلغاء', (tester) async {
      await pumpScreen(
          tester,
          SharedRecordDetailScreen(
            shareId: 'share_1',
            viewer: ShareViewer.doctor,
            service: _FakeService(),
          ));

      expect(find.text('أحمد يوسف'), findsOneWidget);
      // تمييز صريح: نسخة شاركها المريض، لا سجل من عيادته.
      expect(find.text('شاركها معك المريض'), findsOneWidget);
      expect(find.text('إلغاء المشاركة'), findsNothing);
    });

    testWidgets('المحتوى السريري يظهر من اللقطة', (tester) async {
      await pumpScreen(
          tester,
          SharedRecordDetailScreen(
            shareId: 'share_1',
            viewer: ShareViewer.doctor,
            service: _FakeService(),
          ));

      expect(find.text('التهاب في الحلق'), findsOneWidget);
      expect(find.text('حرارة 38.'), findsOneWidget);
      expect(find.text('مضاد حيوي.'), findsOneWidget);
      expect(find.text('د. أحمد'), findsOneWidget);
    });

    testWidgets('الإلغاء يمرّ بحوار تأكيد', (tester) async {
      final service = _FakeService();
      await pumpScreen(
          tester,
          SharedRecordDetailScreen(
            shareId: 'share_1',
            viewer: ShareViewer.patient,
            service: service,
          ));

      // قبل فتح الحوار لا يوجد إلا زرّ واحد بهذا النص.
      await tester.tap(find.text('إلغاء المشاركة'));
      await tester.pumpAndSettle();

      expect(service.revokedId, isNull);
      expect(find.textContaining('لن يتمكّن د. سعيد'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'إلغاء المشاركة'));
      await tester.pumpAndSettle();
      expect(service.revokedId, 'share_1');
    });

    testWidgets('المعلّقة تقول إن الطبيب لا يراها بعد', (tester) async {
      await pumpScreen(
          tester,
          SharedRecordDetailScreen(
            shareId: 'share_1',
            viewer: ShareViewer.patient,
            service: _FakeService(
              shareStream:
                  Stream.value(share(status: MedicalShareStatus.pending)),
            ),
          ));
      expect(find.textContaining('لن يراها الطبيب قبل ذلك'), findsOneWidget);
    });

    testWidgets('المرفوضة تشرح السبب', (tester) async {
      await pumpScreen(
          tester,
          SharedRecordDetailScreen(
            shareId: 'share_1',
            viewer: ShareViewer.patient,
            service: _FakeService(
              shareStream: Stream.value(share(
                status: MedicalShareStatus.rejected,
                rejectionReason: 'لا يمكن مشاركة سجل لا يخصّك.',
              )),
            ),
          ));
      expect(find.text('تعذّرت المشاركة'), findsOneWidget);
      expect(find.text('لا يمكن مشاركة سجل لا يخصّك.'), findsOneWidget);
    });

    testWidgets('الملغاة تقول إن الوصول انقطع', (tester) async {
      await pumpScreen(
          tester,
          SharedRecordDetailScreen(
            shareId: 'share_1',
            viewer: ShareViewer.patient,
            service: _FakeService(
              shareStream:
                  Stream.value(share(status: MedicalShareStatus.revoked)),
            ),
          ));
      expect(find.textContaining('لم يعد الطبيب يرى السجلات'), findsOneWidget);
      expect(find.text('إلغاء المشاركة'), findsNothing);
    });

    testWidgets('الطبيب بعد الإلغاء يرى سبباً مفهوماً لا عطلاً',
        (tester) async {
      await pumpScreen(
          tester,
          SharedRecordDetailScreen(
            shareId: 'share_1',
            viewer: ShareViewer.doctor,
            service: _FakeService(
              shareStream: Stream.error(Exception('permission-denied')),
            ),
          ));
      expect(find.text('لم تعد لديك صلاحية الاطلاع'), findsOneWidget);
      expect(find.textContaining('ألغى المريض'), findsOneWidget);
    });

    testWidgets('تُرسم في الوضع الليلي بلا انهيار', (tester) async {
      await pumpScreen(
        tester,
        SharedRecordDetailScreen(
          shareId: 'share_1',
          viewer: ShareViewer.doctor,
          service: _FakeService(),
        ),
        theme: AppTheme.dark,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('الاتجاه عربي من اليمين لليسار', (tester) async {
      await pumpScreen(
          tester,
          SharedRecordDetailScreen(
            shareId: 'share_1',
            viewer: ShareViewer.patient,
            service: _FakeService(),
          ));
      final dir = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.text('التهاب في الحلق'),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(dir.textDirection, TextDirection.rtl);
    });
  });

  // =========================================================================
  group('حدود الخدمة', () {
    test('حدّ السجلات مطابق لما تفرضه القاعدة', () {
      expect(MedicalShareService.maxEncountersPerShare, 20);
    });

    test('لا مشاركة بلا سجلات', () async {
      final r = await const MedicalShareService().createShare(
        patientId: 'p1',
        patientName: 'أحمد',
        recipient: _doctors.first,
        encounterIds: const [],
      );
      expect(r.isSuccess, isFalse);
      expect(r.message, contains('سجلاً واحداً على الأقل'));
    });

    test('لا مشاركة مع النفس', () async {
      final r = await const MedicalShareService().createShare(
        patientId: 'p1',
        patientName: 'أحمد',
        recipient: const DirectoryDoctor(id: 'p1', name: 'أنا'),
        encounterIds: const ['enc_1'],
      );
      expect(r.isSuccess, isFalse);
    });
  });
}
