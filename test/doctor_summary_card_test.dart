import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/data/services/doctor_dashboard_service.dart';
import 'package:medical_appointment_app/presentation/widgets/doctor_summary_card.dart';

/// خدمة بديلة: تُرجع ما نمليه، أو ترمي — بلا Firebase.
class _StubService extends DoctorDashboardService {
  _StubService(this._result, {this.pending = false});

  final Object _result;

  /// يبقى معلَّقاً بلا مؤقّت — مؤقّتٌ معلّق عند نهاية الاختبار يُسقطه.
  final bool pending;

  @override
  Future<DoctorDashboardSummary> load(String doctorId, {DateTime? now}) {
    if (pending) return Completer<DoctorDashboardSummary>().future;
    if (_result is DoctorDashboardSummary) {
      return Future.value(_result as DoctorDashboardSummary);
    }
    return Future.error(_result);
  }
}

DoctorDashboardSummary summary({
  int today = 0,
  int upcoming = 0,
  int completed = 0,
  int cancelled = 0,
  int unread = 0,
  DoctorNextAppointment? next,
}) =>
    DoctorDashboardSummary(
      todayCount: today,
      upcomingCount: upcoming,
      completedCount: completed,
      cancelledCount: cancelled,
      unreadNotifications: unread,
      nextAppointment: next,
    );

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  testWidgets('أثناء التحميل يظهر هيكل لا أصفار', (tester) async {
    await tester.pumpWidget(wrap(DoctorSummaryCard(
      doctorId: 'd1',
      service: _StubService(summary(), pending: true),
    )));
    await tester.pump();
    // «٠ اليوم» أثناء التحميل كذبة: قد تكون هناك مواعيد لم تصل بعد.
    expect(find.text('0'), findsNothing);
  });

  testWidgets('فشل القراءة يُقال صراحةً مع إعادة محاولة', (tester) async {
    await tester.pumpWidget(wrap(DoctorSummaryCard(
      doctorId: 'd1',
      service: _StubService(StateError('انقطاع')),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذّر تحميل'), findsOneWidget);
    expect(find.textContaining('0'), findsNothing);
  });

  testWidgets('لا مواعيد إطلاقاً = حالة فارغة مفهومة', (tester) async {
    await tester.pumpWidget(wrap(DoctorSummaryCard(
      doctorId: 'd1',
      service: _StubService(summary()),
    )));
    await tester.pumpAndSettle();
    expect(find.text('لا مواعيد بعد'), findsOneWidget);
  });

  testWidgets('الأرقام الحقيقية تُعرض مع مدى النافذة', (tester) async {
    await tester.pumpWidget(wrap(DoctorSummaryCard(
      doctorId: 'd1',
      service: _StubService(summary(
        today: 3,
        upcoming: 7,
        completed: 12,
        cancelled: 2,
        unread: 5,
      )),
    )));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    // رقم بلا مدى يُقرأ كإجمالي كل الوقت.
    expect(
      find.textContaining('${DoctorDashboardService.windowDays}'),
      findsOneWidget,
    );
  });

  testWidgets('أقرب موعد يظهر باسم المريض ولا يعرض هاتفه', (tester) async {
    await tester.pumpWidget(wrap(DoctorSummaryCard(
      doctorId: 'd1',
      service: _StubService(summary(
        today: 1,
        next: DoctorNextAppointment(
          id: 'a1',
          patientName: 'سميرة',
          date: DateTime(2030, 6, 15),
          startTime: '09:00',
        ),
      )),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('سميرة'), findsOneWidget);
    expect(find.textContaining('09:00'), findsOneWidget);
  });

  testWidgets('يعمل في الوضع الليلي بلا استثناء', (tester) async {
    await tester.pumpWidget(wrap(
      DoctorSummaryCard(
        doctorId: 'd1',
        service: _StubService(summary(today: 2)),
      ),
      brightness: Brightness.dark,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('2'), findsOneWidget);
  });
}
