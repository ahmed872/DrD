import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/appointment_status.dart';

/// ملخّص لوحة الطبيب — **من مصادر حقيقية فقط**.
///
/// لوحة الطبيب السابقة (`doctor_dashboard.dart`) كانت تعرض قيماً مكتوبة في
/// الشيفرة («30 دقيقة»، «09:00 - 17:00») وزرَّ حفظ لا يحفظ. هذا الملخّص
/// يقرأ من `appointments` و`notifications` وحدهما، ولا يحمل أي مؤشّر بلا
/// مصدر: ما لا يمكن اشتقاقه من قاعدة البيانات لا يُعرض.
class DoctorDashboardSummary {
  const DoctorDashboardSummary({
    required this.todayCount,
    required this.upcomingCount,
    required this.completedCount,
    required this.cancelledCount,
    required this.unreadNotifications,
    required this.nextAppointment,
  });

  /// مواعيد اليوم التي ما زالت قائمة (لم تُلغَ).
  final int todayCount;

  /// مواعيد قائمة بعد اليوم.
  final int upcomingCount;

  final int completedCount;
  final int cancelledCount;
  final int unreadNotifications;

  /// أقرب موعد قادم، أو `null` إن لم يكن هناك.
  final DoctorNextAppointment? nextAppointment;

  bool get isEmpty =>
      todayCount == 0 &&
      upcomingCount == 0 &&
      completedCount == 0 &&
      cancelledCount == 0;
}

/// أقرب موعد قادم للطبيب، بالحقول التي يحتاجها لتشغيل الموعد فقط.
class DoctorNextAppointment {
  const DoctorNextAppointment({
    required this.id,
    required this.patientName,
    required this.date,
    required this.startTime,
  });

  final String id;

  /// الاسم وحده. لا هاتف ولا بريد ولا سبب زيارة على شاشة الملخّص — تلك
  /// بيانات المريض، وعرضها في بطاقة عامّة توسيعٌ بلا حاجة (الجزء 5).
  final String patientName;

  final DateTime date;
  final String startTime;
}

/// يقرأ الملخّص. لا يكتب شيئاً.
class DoctorDashboardService {
  DoctorDashboardService({FirebaseFirestore? firestore})
      : _injected = firestore;

  final FirebaseFirestore? _injected;

  /// كسول عمداً: بناء الخدمة في اختبار لا يجوز أن يلمس `instance` — فهو
  /// يرمي ما لم تُهيَّأ Firebase.
  FirebaseFirestore get _db => _injected ?? FirebaseFirestore.instance;

  /// سقف للقراءة: طبيب بآلاف المواعيد لا يجوز أن يسحبها كلها لعدّها.
  /// الأرقام المعروضة تخصّ نافذة زمنية محدودة، وهذا مذكور في الواجهة.
  static const int _limit = 500;

  /// عدد الأيام الماضية التي تُحسب منها «المكتملة» و«الملغاة».
  static const int windowDays = 30;

  Future<DoctorDashboardSummary> load(String doctorId, {DateTime? now}) async {
    final today = now ?? DateTime.now();

    // فلترة التاريخ في Dart لا في الاستعلام: `appointmentDate` مخزَّن نصّاً
    // بصيغ مختلفة عبر تاريخ التطبيق، ومقارنة النصوص في Firestore كانت
    // ستُسقط مستندات قديمة صامتةً.
    final snapshot = await _db
        .collection('appointments')
        .where('doctorId', isEqualTo: doctorId)
        .limit(_limit)
        .get();

    final unread = await _db
        .collection('notifications')
        .where('recipientId', isEqualTo: doctorId)
        .where('isRead', isEqualTo: false)
        .limit(_limit)
        .get();

    return summarize(
      [
        for (final doc in snapshot.docs) {...doc.data(), '__id': doc.id},
      ],
      unreadNotifications: unread.docs.length,
      now: today,
    );
  }

  /// الاختزال نفسه، بلا شبكة: هنا يقع كل المنطق الذي يستحقّ اختباراً —
  /// نافذة الأيام، وأيّ الحالات تُعدّ، وأيّ موعد هو الأقرب.
  static DoctorDashboardSummary summarize(
    List<Map<String, dynamic>> appointments, {
    required int unreadNotifications,
    required DateTime now,
  }) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    final windowStart = startOfToday.subtract(const Duration(days: windowDays));

    var todayCount = 0;
    var upcomingCount = 0;
    var completedCount = 0;
    var cancelledCount = 0;
    DoctorNextAppointment? next;

    for (final data in appointments) {
      final date = _parseDate(data['appointmentDate']);
      if (date == null) continue;

      final status = AppointmentStatus.parse(data['status']);
      final day = DateTime(date.year, date.month, date.day);

      if (day.isAfter(windowStart) || day.isAtSameMomentAs(windowStart)) {
        if (status == AppointmentStatus.completed) completedCount++;
        if (status == AppointmentStatus.cancelled) cancelledCount++;
      }

      if (status != AppointmentStatus.booked) continue;

      if (day.isAtSameMomentAs(startOfToday)) {
        todayCount++;
      } else if (day.isAfter(startOfToday)) {
        upcomingCount++;
      }

      if (day.isBefore(startOfToday)) continue;

      final startTime = (data['startTime'] ?? '').toString();
      final candidate = DoctorNextAppointment(
        id: (data['__id'] ?? '').toString(),
        patientName: (data['patientName'] ?? 'مريض').toString(),
        date: day,
        startTime: startTime,
      );
      if (next == null || _isEarlier(candidate, next)) next = candidate;
    }

    return DoctorDashboardSummary(
      todayCount: todayCount,
      upcomingCount: upcomingCount,
      completedCount: completedCount,
      cancelledCount: cancelledCount,
      unreadNotifications: unreadNotifications,
      nextAppointment: next,
    );
  }

  static bool _isEarlier(DoctorNextAppointment a, DoctorNextAppointment b) {
    final byDay = a.date.compareTo(b.date);
    if (byDay != 0) return byDay < 0;
    return a.startTime.compareTo(b.startTime) < 0;
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}
