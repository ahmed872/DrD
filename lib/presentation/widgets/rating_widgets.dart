import 'package:flutter/material.dart';

/// widget لعرض تقييم بالنجوم
class RatingStarsDisplay extends StatelessWidget {
  final int rating;
  final int maxRating;
  final double size;
  final Color color;

  const RatingStarsDisplay({
    super.key,
    required this.rating,
    this.maxRating = 5,
    this.size = 24,
    this.color = Colors.amber,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(maxRating, (index) {
        return Icon(
          index < rating ? Icons.star : Icons.star_border,
          size: size,
          color: color,
        );
      }),
    );
  }
}

/// widget لعرض شارة التقييم
class RatingBadge extends StatelessWidget {
  final int rating;
  final String label;
  final Color color;

  const RatingBadge({
    super.key,
    required this.rating,
    this.label = '',
    this.color = Colors.amber,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            '$rating/5',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 12,
              ),
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
                  color: Colors.amber,
                ),
              ),
            );
          }),
        ),
        if (widget.showLabels && _rating > 0) ...[
          const SizedBox(height: 12),
          Text(
            labels[_rating - 1],
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
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
  final Color color;

  const RatingSummary({
    super.key,
    required this.averageRating,
    required this.totalRatings,
    this.color = Colors.amber,
  });

  @override
  Widget build(BuildContext context) {
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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            Icon(Icons.star, size: 48, color: color),
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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.blue,
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
  final Color color;

  const RatingBar({
    super.key,
    required this.rating,
    this.maxRating = 5,
    this.color = Colors.amber,
  });

  @override
  Widget build(BuildContext context) {

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: rating / maxRating,
        backgroundColor: Colors.grey[300],
        valueColor: AlwaysStoppedAnimation<Color>(color),
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
    return Card(
      color: Colors.orange[50],
      child: ListTile(
        leading: const Icon(Icons.star_half, color: Colors.orange),
        title: Text(message),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
          ),
          onPressed: onAction,
          child: Text(actionLabel),
        ),
      ),
    );
  }
}
