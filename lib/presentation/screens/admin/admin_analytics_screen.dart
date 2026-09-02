import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/services/analytics_service.dart';
import '../../widgets/analytics_widgets.dart';
import '../../widgets/app_surfaces.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/role_guard.dart';

/// تحليلات المنصّة — للإدارة.
///
/// كل رقم هنا من `getAdminAnalytics`، وهي دالة تفحص `token.admin` قبل أي
/// قراءة. لوحة الإدارة السابقة كانت تعدّ من العميل بـ `count()`، وتلك
/// الاستعلامات تنجح لأي مستخدم مسجَّل لأن القواعد تسمح بقراءة مستندات
/// الأطباء — فكانت أعداد المنصّة متاحة عملياً للجميع.
///
/// `RoleGuard` هنا اتّساق واجهة لا تفويض: الحدّ الحقيقي في الدالة.
class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  final AnalyticsService _service = AnalyticsService();

  AnalyticsRange _range = AnalyticsRange.month;
  late Future<AnalyticsResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.admin(range: _range);
  }

  void _select(AnalyticsRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _future = _service.admin(range: _range);
    });
  }

  void _retry() => setState(() => _future = _service.admin(range: _range));

  @override
  Widget build(BuildContext context) {
    return RoleGuard(
      requireAdmin: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('تحليلات المنصّة')),
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
                                : 'تعذّر تحميل التحليلات.',
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
    final platform = result.platform;
    final counts = result.counts;
    final quality = result.quality;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (platform != null) ...[
          const SectionTitle(title: 'المنصّة الآن'),
          KpiGrid(cards: [
            KpiCard(
              label: 'مرضى',
              value: '${platform.patients}',
              icon: Icons.people_outline,
            ),
            KpiCard(
              label: 'أطباء',
              value: '${platform.doctors}',
              icon: Icons.medical_services_outlined,
            ),
            KpiCard(
              label: 'موثَّقون',
              value: '${platform.verifiedDoctors}',
              icon: Icons.verified_outlined,
              tone: scheme.tertiary,
            ),
            KpiCard(
              label: 'موقوفون',
              value: '${platform.suspendedDoctors}',
              icon: Icons.block,
              tone: scheme.error,
            ),
          ]),
          if (platform.pendingApplications > 0) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              tone: scheme.secondaryContainer,
              child: Row(
                children: [
                  Icon(Icons.pending_actions,
                      color: scheme.onSecondaryContainer),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      '${platform.pendingApplications} طلب توثيق ينتظر المراجعة',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
        SectionTitle(title: 'المواعيد — ${result.rangeLabel}'),
        KpiGrid(cards: [
          KpiCard(
            label: 'محجوزة',
            value: '${counts.total}',
            icon: Icons.event_note,
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
          KpiCard(
            label: 'أُعيد جدولتها',
            value: '${counts.rescheduled}',
            icon: Icons.swap_horiz,
          ),
        ]),
        const SizedBox(height: AppSpacing.xl),
        if (result.isEmpty)
          const EmptyState(
            icon: Icons.insights_outlined,
            title: 'لا مواعيد في هذا المدى',
            message: 'اختر مدى أطول لرؤية النشاط.',
          )
        else ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle(title: 'الحجوزات عبر الوقت'),
                TrendBars(points: result.series),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (result.specialties.isNotEmpty) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle(title: 'التخصصات الأكثر طلباً'),
                  BreakdownList(items: result.specialties),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (quality != null)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle(title: 'مؤشّرات التشغيل'),
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
                  Text(
                    'النِّسب محسوبة على المواعيد المنتهية في هذا المدى.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
        ],
        FreshnessNote(
          generatedAt: result.generatedAt,
          timezone: result.timezone,
          truncated: result.truncated,
        ),
      ],
    );
  }
}
