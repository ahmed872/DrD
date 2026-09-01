import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/theme/app_spacing.dart';
import '../../data/services/doctor_dashboard_service.dart';
import 'app_surfaces.dart';
import 'app_widgets.dart';

/// ملخّص لوحة الطبيب: أرقام اليوم وأقرب موعد.
///
/// كل رقم هنا مشتقّ من `appointments` و`notifications` — لا مؤشّر بلا مصدر.
/// اللوحة القديمة (`doctor_dashboard.dart`، غير موصولة) كانت تعرض قيماً
/// مكتوبة في الشيفرة وزرَّ حفظ لا يحفظ؛ هذا بديلها الحقيقي.
class DoctorSummaryCard extends StatefulWidget {
  const DoctorSummaryCard({
    super.key,
    required this.doctorId,
    this.service,
  });

  final String doctorId;

  /// للاختبار: حاقن بديل بدل الاتصال بـ Firestore.
  final DoctorDashboardService? service;

  @override
  State<DoctorSummaryCard> createState() => _DoctorSummaryCardState();
}

class _DoctorSummaryCardState extends State<DoctorSummaryCard> {
  late Future<DoctorDashboardSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<DoctorDashboardSummary> _load() =>
      (widget.service ?? DoctorDashboardService()).load(widget.doctorId);

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DoctorDashboardSummary>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SkeletonCard(height: 150);
        }
        // الخطأ يُقال صراحةً: لوحة تعرض أصفاراً عند فشل القراءة تكذب على
        // الطبيب — «لا مواعيد اليوم» و«تعذّر القراءة» ليسا الشيء نفسه.
        if (snapshot.hasError) {
          return ErrorStateView(
            message: 'تعذّر تحميل ملخّص اليوم. تحقّق من اتصالك.',
            onRetry: _retry,
          );
        }

        final summary = snapshot.data!;
        if (summary.isEmpty) {
          return const EmptyState(
            icon: Icons.event_available_outlined,
            title: 'لا مواعيد بعد',
            message: 'ستظهر هنا مواعيد اليوم وأقرب موعد قادم فور أن يحجز '
                'المرضى عندك.',
          );
        }

        return _SummaryBody(summary: summary);
      },
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.summary});

  final DoctorDashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = summary.nextAppointment;

    // الترتيب مقصود: الموعد القادم أولاً ثم الأرقام. كان العكس، فتسرق
    // خمس بطاقات أرقام الانتباهَ من السطر الوحيد الذي يقول للطبيب من
    // ينتظره الآن.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (next != null) ...[
          _NextForDoctor(next: next),
          const SizedBox(height: AppSpacing.lg),
        ],
        Row(
          children: [
            _Stat(
              label: 'اليوم',
              value: '${summary.todayCount}',
              icon: Icons.today_outlined,
            ),
            const SizedBox(width: AppSpacing.md),
            _Stat(
              label: 'قادمة',
              value: '${summary.upcomingCount}',
              icon: Icons.event_outlined,
            ),
            const SizedBox(width: AppSpacing.md),
            _Stat(
              label: 'غير مقروء',
              value: '${summary.unreadNotifications}',
              icon: Icons.notifications_none,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            _Stat(
              label: 'مكتملة',
              value: '${summary.completedCount}',
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(width: AppSpacing.md),
            _Stat(
              label: 'ملغاة',
              value: '${summary.cancelledCount}',
              icon: Icons.cancel_outlined,
            ),
          ],
        ),
        // النافذة الزمنية مذكورة لأن الرقمين يخصّانها وحدها — رقم بلا مدى
        // يُقرأ كأنه إجمالي كل الوقت.
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            'المكتملة والملغاة خلال آخر ${DoctorDashboardService.windowDays} يوماً',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// أقرب موعد للطبيب — العنصر الأول في ملخّصه.
class _NextForDoctor extends StatelessWidget {
  const _NextForDoctor({required this.next});

  final DoctorNextAppointment next;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final isToday = next.date.year == now.year &&
        next.date.month == now.month &&
        next.date.day == now.day;
    final when =
        isToday ? 'اليوم' : DateFormat('EEEE d MMMM', 'ar').format(next.date);

    return AppCard(
      emphasized: true,
      tone: scheme.primaryContainer,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: scheme.onPrimaryContainer),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'أقرب موعد',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            next.patientName,
            style: theme.textTheme.titleLarge
                ?.copyWith(color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(when,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onPrimaryContainer)),
              if (next.startTime.isNotEmpty) ...[
                Text('  •  ',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onPrimaryContainer)),
                Text(
                  next.startTime,
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md,
          horizontal: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
