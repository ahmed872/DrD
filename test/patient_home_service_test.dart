import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/data/services/patient_home_service.dart';

/// الرئيسية الجديدة تعِد المريض بأن أعلى الشاشة يحمل موعده القادم. إن
/// أخطأ هذا الاختزال في اختيار «القادم» فالوعد مكسور بصمت.
void main() {
  final now = DateTime(2030, 6, 15, 10);
  String day(int offset) =>
      now.add(Duration(days: offset)).toIso8601String().substring(0, 10);

  Map<String, dynamic> appt(String date, String status,
          {String time = '09:00',
          String id = 'a',
          String doctor = 'د. سلمى'}) =>
      {
        '__id': id,
        'appointmentDate': date,
        'status': status,
        'startTime': time,
        'doctorName': doctor,
        'doctorSpecialization': 'باطنة',
      };

  PatientHomeSummary run(List<Map<String, dynamic>> items) =>
      PatientHomeService.summarize(items, now: now);

  test('الأقرب زمنياً هو الموعد القادم لا الأول في القائمة', () {
    final s = run([
      appt(day(6), 'Booked', id: 'far'),
      appt(day(1), 'Booked', id: 'near'),
    ]);
    expect(s.next!.id, 'near');
  });

  test('عند تساوي اليوم يفصل الوقت', () {
    final s = run([
      appt(day(0), 'Booked', time: '16:00', id: 'late'),
      appt(day(0), 'Booked', time: '08:00', id: 'early'),
    ]);
    expect(s.next!.id, 'early');
  });

  test('الماضي والملغى لا يظهران قادمين', () {
    final s = run([
      appt(day(-2), 'Booked', id: 'past'),
      appt(day(1), 'Cancelled', id: 'cancelled'),
      appt(day(3), 'Booked', id: 'real'),
    ]);
    expect(s.upcoming.map((a) => a.id), ['real']);
  });

  test('الصيغ القديمة للحالة تُقرأ', () {
    final s = run([
      appt(day(1), 'upcoming', id: 'u'),
      appt(day(-3), 'done', id: 'd'),
    ]);
    expect(s.next!.id, 'u');
    expect(s.pastCount, 1);
  });

  test('موعد اليوم يُعرَف بأنه اليوم', () {
    final s = run([appt(day(0), 'Booked')]);
    expect(s.next!.isToday(now), isTrue);
  });

  test('موعد الغد ليس اليوم', () {
    final s = run([appt(day(1), 'Booked')]);
    expect(s.next!.isToday(now), isFalse);
  });

  test('بلا مواعيد لا يوجد قادم', () {
    final s = run([appt(day(-5), 'Completed')]);
    expect(s.next, isNull);
    expect(s.hasUpcoming, isFalse);
  });

  test('تاريخ غير صالح يُتخطّى بلا انهيار', () {
    final s = run([
      {'__id': 'x', 'status': 'Booked', 'appointmentDate': 'ليس تاريخاً'},
      appt(day(2), 'Booked', id: 'ok'),
    ]);
    expect(s.upcoming.map((a) => a.id), ['ok']);
  });

  test('اسم الطبيب الغائب لا يعرض فراغاً', () {
    final s = PatientHomeService.summarize([
      {'__id': 'a', 'appointmentDate': day(1), 'status': 'Booked'},
    ], now: now);
    expect(s.next!.doctorName, isNotEmpty);
  });
}
