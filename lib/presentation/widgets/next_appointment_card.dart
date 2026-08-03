import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'ui_kit.dart';

/// بطاقة الموعد القادم مع عدّاد حي.
///
/// دي أهم بطاقة في التطبيق كله، ومقصود إنها أبرز عنصر على الشاشة.
///
/// السبب: المنتج مش «قائمة مواعيد» — هو وعد إنك تعرف دقيقتك فمتقعدش
/// تستنى في العيادة. العدّاد هو تجسيد الوعد ده، فلازم يكون أول حاجة
/// العين تقع عليها، بأرقام كبيرة متساوية العرض متهتزّش وهي بتعدّ.
class NextAppointmentCard extends StatefulWidget {
  const NextAppointmentCard({
    super.key,
    required this.doctorName,
    required this.startsAt,
    required this.timeLabel,
    this.specialization,
    this.onTap,
  });

  final String doctorName;
  final DateTime startsAt;

  /// الوقت بصيغة `HH:mm` كما هو مخزَّن.
  final String timeLabel;
  final String? specialization;
  final VoidCallback? onTap;

  @override
  State<NextAppointmentCard> createState() => _NextAppointmentCardState();
}

class _NextAppointmentCardState extends State<NextAppointmentCard> {
  Timer? _timer;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    // ثانية واحدة: العدّاد بالثواني هو اللي بيخلّي البطاقة تبان حيّة.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    final left = widget.startsAt.difference(DateTime.now());
    if (!mounted) return;
    setState(() => _left = left.isNegative ? Duration.zero : left);
    if (left.isNegative) _timer?.cancel();
  }

  /// نص العدّاد — يتغيّر شكله حسب قرب الموعد.
  ///
  /// عرض «باقي 03:12:45» لموعد بعد أسبوع بلا معنى، وعرض «باقي 5 أيام»
  /// لموعد بعد نصف ساعة بيضيّع الإحساس بالإلحاح.
  (String, String) get _display {
    if (_left == Duration.zero) return ('دورك الآن', 'اتوجّه للعيادة');
    final d = _left.inDays;
    final h = _left.inHours % 24;
    final m = _left.inMinutes % 60;
    final s = _left.inSeconds % 60;

    if (d > 0) {
      return (
        '$d ${d == 1 ? "يوم" : "أيام"}${h > 0 ? " و $h ساعة" : ""}',
        'باقي على موعدك'
      );
    }
    if (_left.inHours > 0) {
      return (
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
        'باقي على موعدك'
      );
    }
    return (
      '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
      'دقائق قليلة — استعد'
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (value, label) = _display;
    // آخر ساعة قبل الموعد بتاخد لوناً مختلفاً — الإلحاح متشفّر في اللون
    // مش في النص وحده.
    final urgent = _left.inHours < 1;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.lg),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: urgent
                  ? const [Color(0xFF0E6E5C), Color(0xFF0A3F38)]
                  : const [AppColors.brand, AppColors.brandDeep],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      urgent
                          ? Icons.notifications_active
                          : Icons.event_available,
                      size: 17,
                      color: Colors.white.withValues(alpha: .85),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: t.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: .85),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  value,
                  style: t.displaySmall?.copyWith(
                    color: Colors.white,
                    fontFeatures: kTabularFigures,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: Gap.md),
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: .18),
                ),
                const SizedBox(height: Gap.md),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.doctorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleMedium?.copyWith(color: Colors.white),
                          ),
                          if (widget.specialization?.isNotEmpty ?? false)
                            Text(
                              widget.specialization!,
                              style: t.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: .78),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Gap.md, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Text(
                        TimeText.format(widget.timeLabel),
                        style: t.titleMedium?.copyWith(
                          color: Colors.white,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
