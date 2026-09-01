import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/data/services/analytics_service.dart';

/// تفكيك رد التحليلات.
///
/// الخادم يجمّع والعميل يعرض. فإن أخطأ التفكيك، عُرضت أرقام خاطئة بثقة —
/// وهو أسوأ من عدم عرضها.
void main() {
  group('المديات', () {
    test('كل مدى له قيمة سلكية ووصف عربي', () {
      for (final range in AnalyticsRange.values) {
        expect(range.wireValue, isNotEmpty);
        expect(range.arabicLabel, isNotEmpty);
        // لا رمز لاتيني يتسرّب إلى واجهة عربية.
        expect(RegExp(r'[A-Za-z]{3,}').hasMatch(range.arabicLabel), isFalse);
      }
    });

    test('القيم السلكية تطابق عقد الخادم', () {
      // مجموعة مغلقة مطابقة لـ `RANGES` في `functions/analytics.js`.
      expect(
        AnalyticsRange.values.map((r) => r.wireValue).toSet(),
        {'7d', '30d', '90d', '365d'},
      );
    });
  });

  group('تفكيك العدّادات', () {
    test('الغياب يعطي أصفاراً لا انهياراً', () {
      final counts = AnalyticsCounts.fromMap(null);
      expect(counts.total, 0);
      expect(counts.cancelled, 0);
    });

    test('القيم الجزئية تُقرأ والباقي صفر', () {
      final counts = AnalyticsCounts.fromMap({'total': 5, 'completed': 3});
      expect(counts.total, 5);
      expect(counts.completed, 3);
      expect(counts.noShow, 0);
    });

    test('الأعداد العشرية من JSON تُقرأ صحيحةً', () {
      // JSON قد يعطي 5.0 بدل 5.
      final counts = AnalyticsCounts.fromMap({'total': 5.0});
      expect(counts.total, 5);
    });
  });

  group('تفكيك الجودة', () {
    test('النِّسب والتقييم تُقرأ', () {
      final q = AnalyticsQuality.fromMap({
        'averageRating': 4.5,
        'reviewCount': 20,
        'completionRate': 66.7,
        'cancellationRate': 33.3,
        'noShowRate': 0,
      });
      expect(q.averageRating, 4.5);
      expect(q.reviewCount, 20);
      expect(q.completionRate, closeTo(66.7, 0.01));
    });

    test('الغياب يعطي أصفاراً', () {
      final q = AnalyticsQuality.fromMap(null);
      expect(q.averageRating, 0);
      expect(q.reviewCount, 0);
      expect(q.completionRate, 0);
    });
  });

  group('تفكيك النقاط والقوائم', () {
    test('نقطة السلسلة تُقرأ كاملة', () {
      final p = AnalyticsPoint.fromMap({
        'bucket': '2030-03-05',
        'booked': 4,
        'completed': 2,
        'cancelled': 1
      });
      expect(p.bucket, '2030-03-05');
      expect(p.booked, 4);
      expect(p.completed, 2);
      expect(p.cancelled, 1);
    });

    test('عنصر التوزيع يُقرأ', () {
      final b = AnalyticsBreakdown.fromMap({'name': 'أسنان', 'count': 12});
      expect(b.name, 'أسنان');
      expect(b.count, 12);
    });

    test('أعداد المنصّة تُقرأ', () {
      final p = PlatformCounts.fromMap({
        'patients': 10,
        'doctors': 4,
        'verifiedDoctors': 3,
        'suspendedDoctors': 1,
        'pendingApplications': 2,
      });
      expect(p.patients, 10);
      expect(p.verifiedDoctors, 3);
      expect(p.pendingApplications, 2);
    });
  });

  group('الفراغ والحداثة', () {
    AnalyticsResult resultWith(AnalyticsCounts counts) => AnalyticsResult(
          scope: 'doctor',
          range: AnalyticsRange.month,
          rangeLabel: 'آخر 30 يوماً',
          timezone: 'Africa/Cairo',
          generatedAt: DateTime(2030, 3, 5, 14, 30),
          counts: counts,
          series: const [],
          truncated: false,
        );

    test('نتيجة بلا مواعيد تُعرَف بأنها فارغة', () {
      expect(resultWith(AnalyticsCounts.empty).isEmpty, isTrue);
    });

    test('وجود موعد واحد ينفي الفراغ', () {
      expect(
        resultWith(AnalyticsCounts.fromMap({'total': 1})).isEmpty,
        isFalse,
      );
    });
  });
}
