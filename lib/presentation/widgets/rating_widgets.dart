import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';

/// widget لعرض تقييم بالنجوم
class RatingStarsDisplay extends StatelessWidget {
  final int rating;
  final int maxRating;
  final double size;

  /// لون النجوم المملوءة. يُترك فارغاً ليأخذ ذهبي التقييم من النسق.
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
    final filled = color ?? context.drd.rating;
    return Row(
      children: List.generate(maxRating, (index) {
        return Icon(
          index < rating ? Icons.star : Icons.star_border,
          size: size,
          // النجمة الفارغة أخفت، فيمكن عدّ المملوءة بلمحة.
          color: index < rating ? filled : context.drd.disabled,
        );
      }),
    );
  }
}

/// widget لعرض شارة التقييم
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
    final tint = color ?? context.drd.rating;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DrdSpacing.sm,
        vertical: DrdSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        borderRadius: DrdRadius.smAll,
        border: Border.all(color: context.drd.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: 16, color: tint),
          const SizedBox(width: 4),
          Text(
            '$rating/5',
            style: TextStyle(
              color: context.colors.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: DrdSpacing.xxs),
            Text(
              label,
              style: TextStyle(color: context.drd.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// widget لاختيار التقييم تفاعلياً
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

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
  }

  @override
  Widget build(BuildContext context) {
    final labels = ['سيء جداً', 'سيء', 'متوسط', 'جيد', 'ممتاز'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            return GestureDetector(
              onTap: () {
                setState(() => _rating = index + 1);
                widget.onRatingChanged(_rating);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  _rating > index ? Icons.star : Icons.star_border,
                  size: 40,
                  color: _rating > index
                      ? context.drd.rating
                      : context.drd.disabled,
                ),
              ),
            );
          }),
        ),
        if (widget.showLabels && _rating > 0) ...[
          const SizedBox(height: 12),
          Text(
            labels[_rating - 1],
            style: TextStyle(fontSize: 14, color: context.drd.muted),
          ),
        ],
      ],
    );
  }
}

/// widget للإظهار ملخص التقييمات
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
    final tint = color ?? context.drd.rating;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'متوسط التقييم',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${averageRating.toStringAsFixed(1)} / 5.0',
                  style: context.text.headlineSmall?.copyWith(
                    color: tint,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Icon(Icons.star, size: 48, color: tint),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'عدد التقييمات',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  totalRatings.toString(),
                  style: context.text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// شريط التقييم الأفقي
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: rating / maxRating,
        backgroundColor: context.colors.surfaceContainerHigh,
        valueColor: AlwaysStoppedAnimation<Color>(color ?? context.drd.rating),
        minHeight: 8,
      ),
    );
  }
}

/// إشعار بالتقييم المعلق
class PendingRatingNotification extends StatelessWidget {
  final String message;
  final VoidCallback onAction;
  final String actionLabel;

  const PendingRatingNotification({
    super.key,
    required this.message,
    required this.onAction,
    this.actionLabel = 'اكمل',
  });

  @override
  Widget build(BuildContext context) {
    return AppBanner.info(
      message: message,
      action: TextButton(onPressed: onAction, child: Text(actionLabel)),
    );
  }
}
