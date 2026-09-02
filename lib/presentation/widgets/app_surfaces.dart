import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// أسطح ومكوّنات التركيب المشتركة (المرحلة 6.5).
///
/// كان في التطبيق 62 استعمالاً لـ `Card` و61 لـ `Container(decoration:
/// BoxDecoration(...))` — أي شكلان مختلفان للبطاقة الواحدة، بانحناءات ست
/// وحدود وظلال متفرّقة. النتيجة أن الشاشة الواحدة تحوي ثلاثة أشكال بطاقة
/// بلا سبب، فيغيب الإحساس بأن الواجهة نظام واحد.
///
/// [AppCard] هو الشكل الوحيد المعتمد. ما دونه استثناء يحتاج تبريراً.

/// بطاقة المحتوى القياسية.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.tone,
    this.emphasized = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// خلفية بديلة (للبطاقة البارزة مثلاً). الافتراضي سطح البطاقة.
  final Color? tone;

  /// بطاقة بارزة: بلا حدّ، وبظلّ أوضح قليلاً. تُستعمل لعنصر واحد في
  /// الشاشة على الأكثر — البروز الذي يُمنح لكل شيء لا يبرز شيئاً.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final content = Padding(padding: padding, child: child);

    return Material(
      color: tone ?? scheme.surface,
      elevation: emphasized ? (isDark ? 0 : 2) : (isDark ? 0 : 1),
      shadowColor: const Color(0x14000000),
      surfaceTintColor: Colors.transparent,
      borderRadius: AppRadii.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.cardRadius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: AppRadii.cardRadius,
            border: isDark && tone == null
                ? Border.all(color: scheme.outlineVariant)
                : null,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// عنوان قسم: سطر واحد، بلا زخرفة، مع إجراء اختياري على الطرف المقابل.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// إجراء سريع مضغوط: أيقونة صغيرة وسطر واحد.
///
/// البديل الذي حلّ محلّ شبكة البطاقات العملاقة على الرئيسية: كانت كل
/// بطاقة 165 بكسل ارتفاعاً بأيقونة ضخمة وسطرين، فلا يظهر منها على شاشة
/// الهاتف إلا أربع، ويُدفع كل ما عداها تحت الطيّ.
class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.cardRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// صفّ الإجراءات السريعة داخل بطاقة واحدة.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key, required this.actions});

  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: actions,
      ),
    );
  }
}

/// صفّ تسمية/قيمة داخل بطاقة — بديل موحَّد لعشرات الصفوف المكرّرة.
class InfoLine extends StatelessWidget {
  const InfoLine({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueDirection,
  });

  final IconData icon;
  final String label;
  final String value;

  /// للأرقام اللاتينية داخل نصّ عربي (هاتف، سعر، وقت).
  final TextDirection? valueDirection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  value,
                  textDirection: valueDirection,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
