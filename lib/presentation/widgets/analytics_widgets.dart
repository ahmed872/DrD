import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../data/services/analytics_service.dart';
import 'app_surfaces.dart';

/// عناصر عرض التحليلات.
///
/// **بلا مكتبة رسم**: الرسوم هنا أعمدة وأشرطة نسبية يرسمها التخطيط نفسه.
/// إضافة اعتمادية رسم (fl_chart أو ما شابه) كانت ستضيف مئات الكيلوبايتات
/// إلى حزمة الويب مقابل رسمين بسيطين، ولها لوحة ألوان وخطوط خاصة بها
/// تتعارض مع نظام المرحلة 6.5. حين تحتاج الشاشة رسماً حقيقياً (خطّي متعدّد
/// السلاسل، تكبير، تفاعل) تُعاد المسألة عندها.
///
/// كل ما هنا يقرأ من `Theme` فيعمل في الوضعين، ولا يعتمد على اللون وحده:
/// كل قيمة مكتوبة رقماً إلى جانب شكلها.

/// بطاقة مؤشّر واحد.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tone ?? scheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.sm),
          Text(value, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// شبكة مؤشّرات متجاوبة: عمودان على الهاتف، أربعة على الشاشات الأوسع.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.cards});

  final List<KpiCard> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= AppBreakpoints.mobile ? 4 : 2;
        final spacing = AppSpacing.md;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

/// رسم أعمدة زمني.
///
/// الارتفاع نسبي إلى أكبر قيمة في المدى. العمود الفارغ يبقى بخطّ رفيع
/// مرئي: فرق بين «صفر» و«لا بيانات» يجب أن يُرى.
class TrendBars extends StatelessWidget {
  const TrendBars({
    super.key,
    required this.points,
    this.height = 150,
  });

  final List<AnalyticsPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (points.isEmpty) return const SizedBox.shrink();

    final maxValue =
        points.map((p) => p.booked).fold<int>(0, (a, b) => a > b ? a : b);

    // مدى طويل بنقاط كثيرة: نعرض آخرها بدل ضغط الجميع في عرض واحد.
    final visible =
        points.length > 14 ? points.sublist(points.length - 14) : points;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final point in visible)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${point.booked}',
                          style: theme.textTheme.labelSmall,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: maxValue == 0
                              ? 2
                              : (point.booked / maxValue) * (height - 44) + 2,
                          decoration: BoxDecoration(
                            color: point.booked == 0
                                ? scheme.outlineVariant
                                : scheme.primary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // تسميتان فقط: أول فترة وآخرها. أربع عشرة تسمية تحت أعمدة ضيّقة
        // تتراكب في العربية وتصير غير مقروءة.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_short(visible.last.bucket),
                style: theme.textTheme.labelSmall),
            Text(_short(visible.first.bucket),
                style: theme.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }

  /// اليوم والشهر من مفتاح الفترة، أو الشهر وحده للمفاتيح الشهرية.
  static String _short(String bucket) {
    final parts = bucket.split('-');
    if (parts.length >= 3) return '${parts[2]}/${parts[1]}';
    if (parts.length == 2) return '${parts[1]}/${parts[0].substring(2)}';
    return bucket;
  }
}

/// شريط نسبة أفقي مع قيمته مكتوبة — لا يعتمد على اللون وحده.
class RateBar extends StatelessWidget {
  const RateBar({
    super.key,
    required this.label,
    required this.percent,
    this.tone,
  });

  final String label;
  final double percent;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final clamped = percent.clamp(0, 100) / 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
              Text('${percent.toStringAsFixed(1)}%',
                  style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: LinearProgressIndicator(
              value: clamped.toDouble(),
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(tone ?? scheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// قائمة تفصيلية مرتَّبة (تخصصات) بأشرطة نسبية.
class BreakdownList extends StatelessWidget {
  const BreakdownList({super.key, required this.items});

  final List<AnalyticsBreakdown> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (items.isEmpty) return const SizedBox.shrink();
    final max = items.first.count;

    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : item.count / max,
                      minHeight: 8,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(scheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 32,
                  child: Text('${item.count}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// شريط اختيار المدى.
class RangeSelector extends StatelessWidget {
  const RangeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AnalyticsRange selected;
  final ValueChanged<AnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final range in AnalyticsRange.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(range.arabicLabel),
                selected: range == selected,
                onSelected: (_) => onChanged(range),
              ),
            ),
        ],
      ),
    );
  }
}

/// سطر «آخر تحديث» — الأرقام تُحسب عند الطلب لا تُبثّ حيّاً، وقول ذلك
/// أصدق من تركها تُقرأ كأنها لحظية.
class FreshnessNote extends StatelessWidget {
  const FreshnessNote({
    super.key,
    required this.generatedAt,
    required this.timezone,
    this.truncated = false,
  });

  final DateTime generatedAt;
  final String timezone;
  final bool truncated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = generatedAt;
    final time = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'حُسبت الساعة $time'
          '${timezone.isEmpty ? '' : ' • التواريخ بتوقيت العيادة'}',
          style: theme.textTheme.bodySmall,
        ),
        if (truncated) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'المدى كبير، والأرقام تغطّي جزءاً منه فقط.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}
