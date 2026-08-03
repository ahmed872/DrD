import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// مكوّنات الواجهة المشتركة.
///
/// قبل الملف ده كانت كل شاشة بتبني بطاقاتها وأزرارها وشرائحها من الصفر
/// بألوان مكتوبة بالإيد (471 استدعاء لـ `Colors.*`)، فالنتيجة إن كل شاشة
/// شكلها مختلف شوية عن اللي جنبها — وده أول حاجة بتوحي إن المنتج مش جاهز.
/// المكوّنات دي هي المفردات البصرية الموحّدة للتطبيق كله.

/// عنوان صغير فوق المقاطع.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.labelSmall);
  }
}

/// بطاقة أساسية — حدّ رفيع بدل الظل الثقيل.
///
/// الظلال الكبيرة بتبان قديمة وبتتعب العين على الشاشات الصغيرة؛ الحدّ
/// الرفيع بيفصل المحتوى بهدوء ويشتغل صح في الوضع الليلي كمان.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.onTap,
    this.accent,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  /// شريط لوني رفيع على حافة البطاقة — يشفّر الحالة بالشكل مش بالنص وحده.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (accent != null) Container(width: 4, color: accent),
            Expanded(child: Padding(padding: padding, child: child)),
          ],
        ),
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: content,
      ),
    );
  }
}

/// شريحة حالة صغيرة.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// الحرف الأول من اسم الطبيب في مربّع ملوّن.
///
/// أفضل من أيقونة شخص رمادية موحّدة: بيدّي كل طبيب هوية بصرية يفتكرها
/// المريض، من غير ما نحتاج صور حقيقية مش موجودة أصلاً.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar(this.name, {super.key, this.size = 52});

  final String name;
  final double size;

  static const _palette = [
    Color(0xFF00838F),
    Color(0xFF3D6CB9),
    Color(0xFF7A5AA8),
    Color(0xFF1E7A46),
    Color(0xFFB5651D),
    Color(0xFFA8446B),
  ];

  @override
  Widget build(BuildContext context) {
    final clean = name.replaceAll(RegExp(r'^(د\.|د|دكتور)\s*'), '').trim();
    final letter = clean.isNotEmpty ? clean.characters.first : '؟';
    // اللون مشتق من الاسم، فيثبت لنفس الطبيب في كل الشاشات.
    final color = _palette[name.hashCode.abs() % _palette.length];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * .42,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// حالة فارغة — أيقونة ونص وزر اختياري.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Gap.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            if (action != null) ...[const SizedBox(height: Gap.xl), action!],
          ],
        ),
      ),
    );
  }
}

/// صف بيانات: تسمية على جهة وقيمة على الجهة التانية.
class DataRow2 extends StatelessWidget {
  const DataRow2(this.label, this.value,
      {super.key, this.valueColor, this.bold = false});

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.bodySmall),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: t.bodyMedium?.copyWith(
                fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// وقت معروض بأرقام متساوية العرض — يُستخدم في كل مكان يظهر فيه وقت.
class TimeText extends StatelessWidget {
  const TimeText(this.time, {super.key, this.style});

  /// الوقت بصيغة `HH:mm`.
  final String time;
  final TextStyle? style;

  /// تحويل 24 ساعة إلى صيغة عربية مقروءة: `14:30` ← `2:30 م`.
  ///
  /// المرضى مابيقروش نظام الـ24 ساعة، والعرض بصيغتهم بيقلّل أخطاء الحضور.
  static String format(String raw) {
    final parts = raw.split(':');
    if (parts.length < 2) return raw;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1].padLeft(2, '0');
    final period = h >= 12 ? 'م' : 'ص';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      format(time),
      style: (style ?? Theme.of(context).textTheme.titleMedium)
          ?.copyWith(fontFeatures: kTabularFigures),
    );
  }
}

/// فاصل رفيع بمسافات متسقة.
class ThinDivider extends StatelessWidget {
  const ThinDivider({super.key, this.vertical = Gap.md});

  final double vertical;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: vertical),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}
