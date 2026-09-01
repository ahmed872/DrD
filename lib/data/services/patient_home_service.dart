import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/appointment_status.dart';

/// ملخّص الصفحة الرئيسية للمريض.
///
/// الرئيسية كانت تعرض في أعلى الشاشة بطاقةً تكرّر رقم هاتف المريض ونوع
/// حسابه — معلومتان يعرفهما أصلاً — بينما موعده اليوم بعد ساعة لا يُذكر
/// إطلاقاً. هذه الخدمة تجلب ما يستحقّ ذلك الموضع.
class PatientHomeSummary {
  const PatientHomeSummary({
    required this.upcoming,
    required this.pastCount,
  });

  /// المواعيد القائمة مرتّبة زمنياً، الأقرب أولاً.
  final List<PatientAppointmentBrief> upcoming;

  /// عدد الزيارات المنتهية — لجملة واحدة، لا للوحة أرقام.
  final int pastCount;

  PatientAppointmentBrief? get next => upcoming.isEmpty ? null : upcoming.first;

  bool get hasUpcoming => upcoming.isNotEmpty;
}

/// موعد كما تحتاجه الرئيسية: ما يكفي للتعرّف عليه والانتقال إليه.
class PatientAppointmentBrief {
  const PatientAppointmentBrief({
    required this.id,
    required this.doctorName,
    required this.specialization,
    required this.date,
    required this.startTime,
    required this.status,
  });

  final String id;
  final String doctorName;
  final String specialization;
  final DateTime date;
  final String startTime;
  final AppointmentStatus status;

  /// هل الموعد اليوم؟
  bool isToday(DateTime now) =>
      date.year == now.year && date.month == now.month && date.day == now.day;
}

class PatientHomeService {
  PatientHomeService({FirebaseFirestore? firestore}) : _injected = firestore;

  final FirebaseFirestore? _injected;
  FirebaseFirestore get _db => _injected ?? FirebaseFirestore.instance;

  static const int _limit = 300;

  Future<PatientHomeSummary> load(String patientId, {DateTime? now}) async {
    final snapshot = await _db
        .collection('appointments')
        .where('patientId', isEqualTo: patientId)
        .limit(_limit)
        .get();

    return summarize(
      [
        for (final d in snapshot.docs) {...d.data(), '__id': d.id},
      ],
      now: now ?? DateTime.now(),
    );
  }

  /// الاختزال بلا شبكة — هنا يقع المنطق الذي يستحقّ اختباراً.
  static PatientHomeSummary summarize(
    List<Map<String, dynamic>> appointments, {
    required DateTime now,
  }) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    final upcoming = <PatientAppointmentBrief>[];
    var past = 0;

    for (final data in appointments) {
      final date = _parseDate(data['appointmentDate']);
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      final status = AppointmentStatus.parse(data['status']);

      if (status == AppointmentStatus.completed) past++;

      if (status != AppointmentStatus.booked) continue;
      if (day.isBefore(startOfToday)) continue;

      upcoming.add(PatientAppointmentBrief(
        id: (data['__id'] ?? '').toString(),
        doctorName: (data['doctorName'] ?? 'الطبيب').toString(),
        specialization: (data['doctorSpecialization'] ?? '').toString(),
        date: day,
        startTime: (data['startTime'] ?? '').toString(),
        status: status,
      ));
    }

    upcoming.sort((a, b) {
      final byDay = a.date.compareTo(b.date);
      return byDay != 0 ? byDay : a.startTime.compareTo(b.startTime);
    });

    return PatientHomeSummary(upcoming: upcoming, pastCount: past);
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}
