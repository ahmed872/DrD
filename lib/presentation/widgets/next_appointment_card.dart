import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/theme/app_spacing.dart';
import '../../data/services/patient_home_service.dart';
import 'app_surfaces.dart';
import 'app_widgets.dart';

/// بطاقة «موعدك القادم» — العنصر الأول في الصفحة الرئيسية للمريض.
///
/// هذا هو التغيير الأهم في المرحلة 6.5: كان أعلى الرئيسية بطاقةً تعرض رقم
/// هاتف المريض ونوع حسابه، والموعد الذي بعد ساعة لا يظهر إطلاقاً. أهمّ
/// معلومة في التطبيق تستحقّ أهمّ موضع فيه.
class NextAppointmentCard extends StatelessWidget {
  const NextAppointmentCard({
    super.key,
    required this.appointment,
    required this.now,
    this.onTap,
  });

  final PatientAppointmentBrief appointment;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = appointment.isToday(now);

    // اليوم يُقال بكلمة «اليوم»، لا بتاريخ يضطر القارئ لحسابه.
    final when = today
        ? 'اليوم'
        : DateFormat('EEEE d MMMM', 'ar').format(appointment.date);

    return AppCard(
      emphasized: true,
      // البطاقة البارزة: نبرة العلامة في الفاتح، وسطح مرتفع في الليلي.
      //
      // `primaryContainer` في الليلي فيروزيّ داكن، فتصير أكبر بطاقة في
      // الشاشة لوحاً فيروزياً يبتلع ما حوله — «الأسطح الفيروزية الداكنة
      // الضخمة» التي رُصدت على الجهاز. السطح المرتفع يبرزها بالطبقة لا
      // باللون، وتبقى العلامة في الأيقونة والنصّ.
      tone: Theme.of(context).brightness == Brightness.dark
          ? scheme.surfaceContainerHigh
          : scheme.primaryContainer,
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_available,
                  size: 18, color: scheme.onPrimaryContainer),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'موعدك القادم',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            appointment.doctorName,
            style: theme.textTheme.headlineSmall
                ?.copyWith(color: scheme.onPrimaryContainer),
          ),
          if (appointment.specialization.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              appointment.specialization,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: scheme.onPrimaryContainer),
              const SizedBox(width: AppSpacing.sm),
              Text(
                when,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: scheme.onPrimaryContainer),
              ),
              if (appointment.startTime.isNotEmpty) ...[
                Text(
                  '  •  ',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
                Text(
                  appointment.startTime,
                  // رقم لاتيني داخل سطر عربي.
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.titleMedium
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

/// البديل حين لا يوجد موعد قادم: دعوة واضحة لا فراغ.
class NoUpcomingAppointmentCard extends StatelessWidget {
  const NoUpcomingAppointmentCard({super.key, required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('لا مواعيد قادمة', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'ابحث عن طبيب واحجز موعدك في دقيقة.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.search),
            label: const Text('ابحث عن طبيب'),
          ),
        ],
      ),
    );
  }
}

/// سطر موعد مضغوط لقائمة «مواعيد قادمة».
class AppointmentListTile extends StatelessWidget {
  const AppointmentListTile({
    super.key,
    required this.appointment,
    required this.now,
    this.onTap,
  });

  final PatientAppointmentBrief appointment;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final when = appointment.isToday(now)
        ? 'اليوم'
        : DateFormat('d MMMM', 'ar').format(appointment.date);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.event, size: 20, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appointment.doctorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  appointment.startTime.isEmpty
                      ? when
                      : '$when • ${appointment.startTime}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const DirectionalForwardIcon(),
        ],
      ),
    );
  }
}
