import 'package:cloud_functions/cloud_functions.dart';

import '../../core/utils/app_logger.dart';
import '../../core/utils/error_messages.dart';

/// المدى الزمني للتحليلات — مجموعة مغلقة تطابق `RANGES` في
/// `functions/analytics.js`. العميل يختار من قائمة ولا يرسل تاريخين، فلا
/// يستطيع طلب مسح مفتوح.
enum AnalyticsRange {
  week('7d', 'آخر 7 أيام'),
  month('30d', 'آخر 30 يوماً'),
  quarter('90d', 'آخر 90 يوماً'),
  year('365d', 'آخر سنة');

  const AnalyticsRange(this.wireValue, this.arabicLabel);

  final String wireValue;
  final String arabicLabel;
}

/// نقطة على منحنى زمني.
class AnalyticsPoint {
  const AnalyticsPoint({
    required this.bucket,
    required this.booked,
    required this.completed,
    required this.cancelled,
  });

  /// مفتاح الفترة كما جمّعها الخادم: يوم أو أسبوع أو شهر.
  final String bucket;
  final int booked;
  final int completed;
  final int cancelled;

  static AnalyticsPoint fromMap(Map<String, dynamic> m) => AnalyticsPoint(
        bucket: (m['bucket'] ?? '').toString(),
        booked: (m['booked'] as num?)?.toInt() ?? 0,
        completed: (m['completed'] as num?)?.toInt() ?? 0,
        cancelled: (m['cancelled'] as num?)?.toInt() ?? 0,
      );
}

/// عدّادات الحالات.
class AnalyticsCounts {
  const AnalyticsCounts({
    required this.total,
    required this.open,
    required this.completed,
    required this.cancelled,
    required this.noShow,
    required this.rescheduled,
  });

  final int total;

  /// مواعيد لم تُحسم بعد **ضمن فترة التقرير** — لا كل المواعيد القادمة.
  /// المدى ينتهي اليوم، فموعد بعد أسبوع خارج تقرير آخر ثلاثين يوماً.
  final int open;
  final int completed;
  final int cancelled;
  final int noShow;
  final int rescheduled;

  static const empty = AnalyticsCounts(
    total: 0,
    open: 0,
    completed: 0,
    cancelled: 0,
    noShow: 0,
    rescheduled: 0,
  );

  static AnalyticsCounts fromMap(Map<String, dynamic>? m) {
    final d = m ?? const {};
    int v(String k) => (d[k] as num?)?.toInt() ?? 0;
    return AnalyticsCounts(
      total: v('total'),
      open: v('open'),
      completed: v('completed'),
      cancelled: v('cancelled'),
      noShow: v('noShow'),
      rescheduled: v('rescheduled'),
    );
  }
}

/// مؤشّرات الجودة.
class AnalyticsQuality {
  const AnalyticsQuality({
    required this.averageRating,
    required this.reviewCount,
    required this.completionRate,
    required this.cancellationRate,
    required this.noShowRate,
  });

  final double averageRating;
  final int reviewCount;

  /// نِسب على المواعيد **المنتهية** لا على الإجمالي — موعد لم يحن بعد ليس
  /// فشلاً، وإدخاله في المقام يجعل كل عيادة نشطة تبدو سيّئة.
  final double completionRate;
  final double cancellationRate;
  final double noShowRate;

  static AnalyticsQuality fromMap(Map<String, dynamic>? m) {
    final d = m ?? const {};
    double v(String k) => (d[k] as num?)?.toDouble() ?? 0;
    return AnalyticsQuality(
      averageRating: v('averageRating'),
      reviewCount: (d['reviewCount'] as num?)?.toInt() ?? 0,
      completionRate: v('completionRate'),
      cancellationRate: v('cancellationRate'),
      noShowRate: v('noShowRate'),
    );
  }
}

/// أعداد المنصّة — للإدارة وحدها.
class PlatformCounts {
  const PlatformCounts({
    required this.patients,
    required this.doctors,
    required this.verifiedDoctors,
    required this.suspendedDoctors,
    required this.pendingApplications,
  });

  final int patients;
  final int doctors;
  final int verifiedDoctors;
  final int suspendedDoctors;
  final int pendingApplications;

  static PlatformCounts fromMap(Map<String, dynamic>? m) {
    final d = m ?? const {};
    int v(String k) => (d[k] as num?)?.toInt() ?? 0;
    return PlatformCounts(
      patients: v('patients'),
      doctors: v('doctors'),
      verifiedDoctors: v('verifiedDoctors'),
      suspendedDoctors: v('suspendedDoctors'),
      pendingApplications: v('pendingApplications'),
    );
  }
}

/// عنصر في قائمة مرتَّبة (تخصص وعدد).
class AnalyticsBreakdown {
  const AnalyticsBreakdown({required this.name, required this.count});

  final String name;
  final int count;

  static AnalyticsBreakdown fromMap(Map<String, dynamic> m) =>
      AnalyticsBreakdown(
        name: (m['name'] ?? '').toString(),
        count: (m['count'] as num?)?.toInt() ?? 0,
      );
}

/// نتيجة تحليلية كاملة.
class AnalyticsResult {
  const AnalyticsResult({
    required this.scope,
    required this.range,
    required this.rangeLabel,
    required this.timezone,
    required this.generatedAt,
    required this.counts,
    required this.series,
    required this.truncated,
    this.quality,
    this.platform,
    this.specialties = const [],
  });

  final String scope;
  final AnalyticsRange range;
  final String rangeLabel;

  /// المنطقة التي حُسبت بها حدود المدى والتجميع — تُعرض للمستخدم حتى لا
  /// يُقرأ «اليوم» بتوقيت جهازه إن اختلف.
  final String timezone;

  /// لحظة توليد الأرقام. هذه نتيجة **عند الطلب** لا بثّاً حيّاً، فالوقت
  /// يُعرض بدل الإيهام بأنها لحظية.
  final DateTime generatedAt;

  final AnalyticsCounts counts;
  final List<AnalyticsPoint> series;

  /// بلغت القراءة سقفها على الخادم، فالأرقام تخصّ جزءاً من المدى.
  final bool truncated;

  final AnalyticsQuality? quality;
  final PlatformCounts? platform;
  final List<AnalyticsBreakdown> specialties;

  bool get isEmpty => counts.total == 0;
}

/// عميل التحليلات.
///
/// كل شيء عبر دوال قابلة للاستدعاء: التجميع والصلاحية على الخادم. لا
/// استعلام Firestore واحد هنا، فلا مجال لقراءة غير محدودة ولا لتجاوز حدّ.
class AnalyticsService {
  AnalyticsService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<AnalyticsResult> patient({
    AnalyticsRange range = AnalyticsRange.month,
  }) =>
      _call('getPatientAnalytics', range);

  Future<AnalyticsResult> doctor({
    AnalyticsRange range = AnalyticsRange.month,
  }) =>
      _call('getDoctorAnalytics', range);

  Future<AnalyticsResult> admin({
    AnalyticsRange range = AnalyticsRange.month,
  }) =>
      _call('getAdminAnalytics', range);

  Future<AnalyticsResult> _call(String name, AnalyticsRange range) async {
    try {
      final response = await _functions
          .httpsCallable(name)
          .call<Map<String, dynamic>>({'range': range.wireValue});
      return _parse(response.data, range);
    } on FirebaseFunctionsException catch (e) {
      AppLogger.info('تعذّر جلب التحليلات ($name): ${e.code}');
      final reason =
          e.details is Map ? (e.details as Map)['reason']?.toString() : null;
      throw AnalyticsFailure(
        AppErrorMessages.resolve(reason: reason, serverMessage: e.message),
      );
    } catch (e) {
      AppLogger.info('تعذّر جلب التحليلات ($name): $e');
      throw AnalyticsFailure(unknownMessage);
    }
  }

  static AnalyticsResult _parse(
    Map<String, dynamic>? raw,
    AnalyticsRange requested,
  ) {
    final data = raw ?? const <String, dynamic>{};
    final rangeMap = (data['range'] as Map?)?.cast<String, dynamic>() ?? {};
    final seriesRaw = (data['series'] as List?) ?? const [];
    final specialtiesRaw = (data['specialties'] as List?) ?? const [];

    return AnalyticsResult(
      scope: (data['scope'] ?? '').toString(),
      range: requested,
      rangeLabel: (rangeMap['label'] ?? requested.arabicLabel).toString(),
      timezone: (data['timezone'] ?? '').toString(),
      generatedAt: DateTime.tryParse((data['generatedAt'] ?? '').toString())
              ?.toLocal() ??
          DateTime.now(),
      counts: AnalyticsCounts.fromMap(
          (data['counts'] as Map?)?.cast<String, dynamic>()),
      series: seriesRaw
          .whereType<Map>()
          .map((m) => AnalyticsPoint.fromMap(m.cast<String, dynamic>()))
          .toList(),
      truncated: data['truncated'] == true,
      quality: data['quality'] == null
          ? null
          : AnalyticsQuality.fromMap(
              (data['quality'] as Map).cast<String, dynamic>()),
      platform: data['platform'] == null
          ? null
          : PlatformCounts.fromMap(
              (data['platform'] as Map).cast<String, dynamic>()),
      specialties: specialtiesRaw
          .whereType<Map>()
          .map((m) => AnalyticsBreakdown.fromMap(m.cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// فشل بجملة عربية جاهزة للعرض.
class AnalyticsFailure implements Exception {
  const AnalyticsFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
