import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/data/services/doctor_dashboard_service.dart';

/// ملخّص لوحة الطبيب يحلّ محلّ لوحة كانت تعرض قيماً مكتوبة في الشيفرة.
/// فإن كان بديلها يخطئ في العدّ، فلا فرق بينه وبينها.
///
/// `summarize` دالة خالصة، فتُختبر بلا Firebase إطلاقاً.
void main() {
  final now = DateTime(2030, 6, 15, 10);
  String day(int offset) =>
      now.add(Duration(days: offset)).toIso8601String().substring(0, 10);

  Map<String, dynamic> appt(String date, String status,
          {String time = '09:00', String name = 'مريض', String id = 'a'}) =>
      {
        '__id': id,
        'appointmentDate': date,
        'status': status,
        'startTime': time,
        'patientName': name,
      };

  DoctorDashboardSummary run(List<Map<String, dynamic>> items,
          {int unread = 0}) =>
      DoctorDashboardService.summarize(items,
          unreadNotifications: unread, now: now);

  group('عدّ المواعيد', () {
    test('مواعيد اليوم والقادمة تُفصل', () {
      final s = run([
        appt(day(0), 'Booked'),
        appt(day(0), 'Booked'),
        appt(day(3), 'Booked'),
      ]);
      expect(s.todayCount, 2);
      expect(s.upcomingCount, 1);
    });

    test('الملغى لا يُعدّ ضمن مواعيد اليوم', () {
      // اللوحة تقول للطبيب كم موعداً عليه اليوم؛ الملغى ليس منها.
      final s = run([
        appt(day(0), 'Booked'),
        appt(day(0), 'Cancelled'),
      ]);
      expect(s.todayCount, 1);
    });

    test('الصيغ القديمة للحالة تُقرأ مثل الجديدة', () {
      // قاعدة البيانات تحمل سبع صيغ. `upcoming` و`done` و`canceled` منها.
      final s = run([
        appt(day(0), 'upcoming'),
        appt(day(-2), 'done'),
        appt(day(-2), 'canceled'),
      ]);
      expect(s.todayCount, 1);
      expect(s.completedCount, 1);
      expect(s.cancelledCount, 1);
    });

    test('ما قبل النافذة لا يدخل المكتملة والملغاة', () {
      final s = run([
        appt(day(-(DoctorDashboardService.windowDays + 5)), 'Completed'),
        appt(day(-1), 'Completed'),
      ]);
      expect(s.completedCount, 1);
    });

    test('مستند بلا تاريخ صالح يُتخطّى بلا انهيار', () {
      final s = run([
        {'__id': 'x', 'status': 'Booked'},
        {'__id': 'y', 'appointmentDate': 'ليس تاريخاً', 'status': 'Booked'},
        appt(day(0), 'Booked'),
      ]);
      expect(s.todayCount, 1);
    });
  });

  group('أقرب موعد', () {
    test('الأقرب زمنياً هو المختار، لا الأول في القائمة', () {
      final s = run([
        appt(day(5), 'Booked', id: 'far', name: 'بعيد'),
        appt(day(1), 'Booked', id: 'near', name: 'قريب'),
      ]);
      expect(s.nextAppointment!.id, 'near');
    });

    test('عند تساوي اليوم يفصل الوقت', () {
      final s = run([
        appt(day(0), 'Booked', time: '14:00', id: 'late'),
        appt(day(0), 'Booked', time: '08:30', id: 'early'),
      ]);
      expect(s.nextAppointment!.id, 'early');
    });

    test('الماضي والملغى لا يكونان «أقرب موعد»', () {
      final s = run([
        appt(day(-1), 'Booked', id: 'past'),
        appt(day(0), 'Cancelled', id: 'cancelled'),
        appt(day(2), 'Booked', id: 'real'),
      ]);
      expect(s.nextAppointment!.id, 'real');
    });

    test('بلا مواعيد قادمة لا يوجد أقرب موعد', () {
      expect(run([appt(day(-3), 'Completed')]).nextAppointment, isNull);
    });
  });

  group('الحالة الفارغة', () {
    test('لا شيء إطلاقاً = فارغ', () {
      expect(run(const []).isEmpty, isTrue);
    });

    test('وجود أي موعد ينفي الفراغ', () {
      expect(run([appt(day(0), 'Booked')]).isEmpty, isFalse);
    });

    test('الإشعارات غير المقروءة تُمرَّر كما هي', () {
      expect(run(const [], unread: 4).unreadNotifications, 4);
    });
  });
}
