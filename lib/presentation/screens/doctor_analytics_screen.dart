import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/analytics_service.dart';
import '../widgets/analytics_widgets.dart';
import '../widgets/app_surfaces.dart';
import '../widgets/app_widgets.dart';
import '../widgets/role_guard.dart';

/// إحصاءات الطبيب.
///
/// ===== المرحلة 8: الحساب انتقل إلى الخادم =====
///
/// كانت الشاشة تقرأ مواعيد الطبيب إلى العميل ثم تحسب كل شيء في Dart:
/// العدّ، والنِّسب، والتوزيع الأسبوعي، وأكثر أسباب الزيارة. ثلاث علل في ذلك:
///
///   1. **التكلفة تُدفع على العميل**: مستندات كاملة تعبر الشبكة لتُختزل إلى
///      خمسة أرقام. المرحلة 7 حدّت المدى، لكن الاختزال بقي في المكان الخطأ.
///   2. **المنطق مكرَّر**: تصنيف الحالات وحساب النِّسب كان له نسخة هنا ونسخة
///      في الخادم، ونسختان تتباعدان مع الوقت.
///   3. **لا سبيل لتحليلات المنصّة**: المدير يحتاج أرقاماً عن كل الأطباء،
///      وذلك لا يمكن أن يمرّ عبر العميل بأي حال.
///
/// الآن `getDoctorAnalytics` تُرجع الأرقام مجمَّعة، والشاشة تعرضها. النطاق
/// `doctorId == uid` على الخادم، فلا يمكن طلب إحصاءات طبيب آخر أصلاً.
class DoctorAnalyticsScreen extends StatefulWidget {
  const DoctorAnalyticsScreen({super.key});

  @override
  State<DoctorAnalyticsScreen> createState() => _DoctorAnalyticsScreenState();
}

class _DoctorAnalyticsScreenState extends State<DoctorAnalyticsScreen> {
  final AnalyticsService _service = AnalyticsService();

  AnalyticsRange _range = AnalyticsRange.month;
  late Future<AnalyticsResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.doctor(range: _range);
  }

  void _select(AnalyticsRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _future = _service.doctor(range: _range);
    });
  }

  void _retry() => setState(() => _future = _service.doctor(range: _range));

  @override
  Widget build(BuildContext context) {
    return RoleGuard(
      requireDoctorClinicAccess: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإحصائيات')),
        body: SafeArea(
          child: SingleChildScrollView(
            child: ContentWidthLimit(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RangeSelector(selected: _range, onChanged: _select),
                    const SizedBox(height: AppSpacing.xl),
                    FutureBuilder<AnalyticsResult>(
                      future: _future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Column(
                            children: [
                              SkeletonCard(height: 120),
                              SizedBox(height: AppSpacing.md),
                              SkeletonCard(height: 180),
                            ],
                          );
                        }
                        if (snapshot.hasError) {
                          final error = snapshot.error;
                          return ErrorStateView(
                            message: error is AnalyticsFailure
                                ? error.message
                                : 'تعذّر تحميل الإحصاءات.',
                            onRetry: _retry,
                          );
                        }
                        return _Body(result: snapshot.data!);
                      },
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.result});

  final AnalyticsResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = result.counts;
    final quality = result.quality;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiGrid(cards: [
          KpiCard(
            label: 'إجمالي المواعيد',
            value: '${counts.total}',
            icon: Icons.event_note,
          ),
          KpiCard(
            // «قائمة» لا «قادمة»: المدى ينتهي اليوم، فهذا ما لم يُحسم ضمن
            // فترة التقرير لا كل المواعيد القادمة.
            label: 'قائمة',
            value: '${counts.open}',
            icon: Icons.schedule,
            tone: scheme.primary,
          ),
          KpiCard(
            label: 'مكتملة',
            value: '${counts.completed}',
            icon: Icons.check_circle_outline,
            tone: scheme.tertiary,
          ),
          KpiCard(
            label: 'ملغاة',
            value: '${counts.cancelled}',
            icon: Icons.cancel_outlined,
            tone: scheme.error,
          ),
        ]),
        const SizedBox(height: AppSpacing.xl),
        if (result.isEmpty)
          const EmptyState(
            icon: Icons.insights_outlined,
            title: 'لا بيانات في هذا المدى',
            message: 'اختر مدى أطول، أو انتظر حتى تُسجَّل مواعيد جديدة.',
          )
        else ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle(title: 'المواعيد عبر الوقت'),
                TrendBars(points: result.series),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (quality != null)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle(title: 'الأداء'),
                  RateBar(
                    label: 'نسبة الإتمام',
                    percent: quality.completionRate,
                    tone: scheme.tertiary,
                  ),
                  RateBar(
                    label: 'نسبة الإلغاء',
                    percent: quality.cancellationRate,
                    tone: scheme.error,
                  ),
                  RateBar(
                    label: 'نسبة عدم الحضور',
                    percent: quality.noShowRate,
                    tone: scheme.secondary,
                  ),
                  // النِّسب على المنتهية لا على الإجمالي — يُقال صراحةً وإلا
                  // قُرئت خطأً عند وجود مواعيد لم تحن بعد.
                  Text(
                    'النِّسب محسوبة على المواعيد المنتهية '
                    '(مكتملة + ملغاة + عدم حضور).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (quality != null)
          AppCard(
            child: Row(
              children: [
                const Icon(Icons.star_rounded,
                    size: 28, color: AppColors.rating),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quality.reviewCount == 0
                            ? 'لا تقييمات بعد'
                            : quality.averageRating.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        quality.reviewCount == 0
                            ? 'ستظهر هنا فور أن يقيّمك مريض'
                            : 'متوسط تقييمك من ${quality.reviewCount} مراجعة',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        FreshnessNote(
          generatedAt: result.generatedAt,
          timezone: result.timezone,
          truncated: result.truncated,
        ),
      ],
    );
  }
}
