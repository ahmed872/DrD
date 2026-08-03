/// عناصر التقييم المشتركة.
///
/// كانت كل عناصر هذا الملف تأخذ `Colors.amber` كقيمة افتراضية مكتوبة في
/// التوقيع، فلم يكن ممكناً تغيير لون التقييم من مكان واحد ولا التكيّف مع
/// الوضع الليلي. اللون الآن يأتي من `tokens.gold` عند غياب قيمة صريحة.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_widgets.dart';

/// عرض تقييم بالنجوم (للقراءة فقط).
class RatingStarsDisplay extends StatelessWidget {
  final int rating;
  final int maxRating;
  final double size;
  final Color? color;

  const RatingStarsDisplay({
    super.key,
    required this.rating,
    this.maxRating = 5,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final starColor = color ?? tokens.gold;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxRating, (index) {
        return Icon(
          index < rating ? Icons.star_rounded : Icons.star_border_rounded,
          size: size,
          // النجوم غير المكتسبة بلون باهت بدل نفس الذهبي: الفرق بين ٣ و٥
          // نجوم يجب أن يُقرأ من مسافة، لا بعدّ الأيقونات.
          color: index < rating ? starColor : tokens.borderStrong,
        );
      }),
    );
  }
}

/// شارة تقييم مختصرة.
class RatingBadge extends StatelessWidget {
  final int rating;
  final String label;
  final Color? color;

  const RatingBadge({
    super.key,
    required this.rating,
    this.label = '',
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: label.isEmpty ? '$rating/5' : '$rating/5 · $label',
      color: color ?? context.tokens.gold,
      icon: Icons.star_rounded,
    );
  }
}

/// اختيار التقييم تفاعلياً.
class InteractiveRatingSelector extends StatefulWidget {
  final int initialRating;
  final ValueChanged<int> onRatingChanged;
  final bool showLabels;

  const InteractiveRatingSelector({
    super.key,
    this.initialRating = 0,
    required this.onRatingChanged,
    this.showLabels = true,
  });

  @override
  State<InteractiveRatingSelector> createState() =>
      _InteractiveRatingSelectorState();
}

class _InteractiveRatingSelectorState extends State<InteractiveRatingSelector> {
  late int _rating;

  static const List<String> _labels = [
    'سيء جداً',
    'سيء',
    'متوسط',
    'جيد',
    'ممتاز',
  ];

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final active = _rating > index;
            return GestureDetector(
              onTap: () {
                setState(() => _rating = index + 1);
                widget.onRatingChanged(_rating);
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                // التكبير الطفيف عند الاختيار يعطي إحساساً باستجابة اللمس
                // على شاشة لا يتغيّر فيها شيء آخر.
                child: AnimatedScale(
                  scale: active ? 1.08 : 1,
                  duration: const Duration(milliseconds: 140),
                  child: Icon(
                    active ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 42,
                    color: active ? tokens.gold : tokens.borderStrong,
                  ),
                ),
              ),
            );
          }),
        ),
        if (widget.showLabels) ...[
          const SizedBox(height: AppSpacing.md),
          // ارتفاع محجوز حتى لا يقفز باقي النموذج لأعلى وأسفل مع أول ضغطة.
          SizedBox(
            height: 22,
            child: _rating == 0
                ? Text(
                    'اضغط على النجوم للتقييم',
                    style: context.texts.bodySmall
                        ?.copyWith(color: tokens.textFaint),
                  )
                : Text(
                    _labels[_rating - 1],
                    style: context.texts.titleSmall?.copyWith(
                      color: tokens.gold,
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}

/// ملخّص التقييمات: المتوسط وعدد المقيّمين.
class RatingSummary extends StatelessWidget {
  final double averageRating;
  final int totalRatings;
  final Color? color;

  const RatingSummary({
    super.key,
    required this.averageRating,
    required this.totalRatings,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final starColor = color ?? tokens.gold;

    return AppCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: starColor.withValues(alpha: 0.13),
              borderRadius: AppRadius.rMd,
            ),
            child: Icon(Icons.star_rounded, size: 30, color: starColor),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'متوسط التقييم',
                  style: context.texts.bodySmall
                      ?.copyWith(color: tokens.textMuted),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      averageRating.toStringAsFixed(1),
                      style: context.texts.headlineSmall
                          ?.copyWith(color: starColor),
                    ),
                    Text(
                      ' / 5',
                      style: context.texts.bodySmall
                          ?.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'عدد التقييمات',
                style:
                    context.texts.bodySmall?.copyWith(color: tokens.textMuted),
              ),
              Text(
                totalRatings.toString(),
                style: context.texts.headlineSmall
                    ?.copyWith(color: context.colors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// شريط التقييم الأفقي.
class RatingBar extends StatelessWidget {
  final int rating;
  final int maxRating;
  final Color? color;

  const RatingBar({
    super.key,
    required this.rating,
    this.maxRating = 5,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ClipRRect(
      borderRadius: AppRadius.rPill,
      child: LinearProgressIndicator(
        value: (rating / maxRating).clamp(0.0, 1.0),
        backgroundColor: tokens.surfaceSunken,
        valueColor: AlwaysStoppedAnimation<Color>(color ?? tokens.gold),
        minHeight: 8,
      ),
    );
  }
}

/// تذكير بتقييم معلّق.
class PendingRatingNotification extends StatelessWidget {
  final String message;
  final VoidCallback onAction;
  final String actionLabel;

  const PendingRatingNotification({
    super.key,
    required this.message,
    required this.onAction,
    this.actionLabel = 'أكمل',
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AppCard(
      onTap: onAction,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.gold.withValues(alpha: 0.14),
              borderRadius: AppRadius.rMd,
            ),
            child: Icon(Icons.star_half_rounded, color: tokens.gold, size: 22),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(message, style: context.texts.bodyMedium),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: tokens.gold,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
