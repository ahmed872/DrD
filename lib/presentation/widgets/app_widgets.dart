/// مكوّنات مشتركة تُبنى من ألوان النسق لا من ألوان ثابتة.
///
/// الحالات الثلاث — فارغ، خطأ، تحميل — كانت تُكتب من جديد في كل شاشة، فاختلف
/// شكلها ونصّها ولونها، وبعض القوائم لم يكن لها حالة فارغة إطلاقاً فتظهر
/// شاشة بيضاء بلا تفسير. المكوّنات هنا تجعل الحالة الافتراضية صحيحة بلا جهد.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';

/// حالة فارغة: أيقونة، عنوان، شرح، وإجراء اختياري.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// حالة خطأ قابلة لإعادة المحاولة.
///
/// [message] يجب أن يكون نصاً عربياً جاهزاً للعرض — راجع
/// `core/utils/error_messages.dart`؛ لا تمرّر هنا رمز خطأ ولا نص استثناء.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.cloud_off,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// تحميل بسياق: مؤشّر مع نص يشرح ما ينتظره المستخدم.
class LoadingStateView extends StatelessWidget {
  const LoadingStateView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// هيكل عظمي لبطاقة أثناء التحميل.
///
/// أصدق من مؤشّر دوّار في منتصف شاشة فارغة: يُظهر شكل المحتوى القادم فيبدو
/// الانتظار أقصر، ويمنع القفزة البصرية عند وصول البيانات.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 96});

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadii.cardRadius,
      ),
    );
  }
}

/// قائمة هياكل عظمية.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3, this.itemHeight = 96});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.page,
      child: Column(
        children: List.generate(
          count,
          (_) => SkeletonCard(height: itemHeight),
        ),
      ),
    );
  }
}

/// دلالة الحالة — تحدّد اللون من النسق بدل تثبيت أخضر/أحمر يدوياً.
enum StatusTone { neutral, info, success, warning, danger }

/// شارة حالة صغيرة (محجوز، مكتمل، ملغي، موثَّق...).
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // الألوان من `ColorScheme` فتتبدّل مع الوضع الليلي تلقائياً، ويبقى
    // التباين بين النص وخلفيته مضموناً في الوضعين.
    final (Color background, Color foreground) = switch (tone) {
      StatusTone.neutral => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant
        ),
      StatusTone.info => (scheme.primaryContainer, scheme.onPrimaryContainer),
      StatusTone.success => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer
        ),
      StatusTone.warning => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer
        ),
      StatusTone.danger => (scheme.errorContainer, scheme.onErrorContainer),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.chipRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: AppSpacing.xs + 2),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// عنوان قسم مع إجراء اختياري على الطرف المقابل.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// نجوم التقييم — للعرض أو للاختيار.
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.size = 18,
    this.onChanged,
  });

  final double rating;
  final double size;

  /// عند تمريرها تصبح النجوم قابلة للاختيار (1..5).
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final interactive = onChanged != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final filled = index < rating.round();
        final star = Icon(
          filled ? Icons.star_rounded : Icons.star_border_rounded,
          size: interactive ? size * 1.8 : size,
          color: filled ? AppColors.rating : scheme.outline,
        );

        if (!interactive) return star;

        return Semantics(
          button: true,
          label: '${index + 1} من 5',
          selected: filled,
          child: InkWell(
            onTap: () => onChanged!(index + 1),
            borderRadius: AppRadii.chipRadius,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: star,
            ),
          ),
        );
      }),
    );
  }
}

/// سطر «تسمية: قيمة» متّسق داخل بطاقات التفاصيل.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// أيقونة «رجوع» تتبع اتجاه الكتابة.
///
/// في واجهة عربية يشير سهم الرجوع إلى اليمين. `Icons.arrow_back` يُعكس
/// تلقائياً في بعض السياقات ولا يُعكس في أخرى (داخل `Row` مبني يدوياً مثلاً)،
/// فالاعتماد عليه وحده أنتج أسهماً تشير للاتجاه الخاطئ في عدة شاشات.
IconData directionalBackIcon(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
        ? Icons.arrow_forward
        : Icons.arrow_back;

/// أيقونة «التالي/فتح» تتبع اتجاه الكتابة.
IconData directionalForwardIcon(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
        ? Icons.arrow_back_ios_new
        : Icons.arrow_forward_ios;

/// سهم «التالي/فتح» جاهزاً للرسم.
///
/// [directionalForwardIcon] وحدها لا تكفي: Flutter يعكس أيقونات الأسهم
/// تلقائياً في السياق العربي، فينعكس الاختيار مرّة ثانية ويعود السهم
/// مشيراً إلى الخلف. رُصد ذلك في لقطات المرحلة 6.5: سهم «>» في كل بطاقة
/// موعد بينما اتجاه القراءة من اليمين إلى اليسار.
///
/// الحلّ هنا أن نختار الشكل بأنفسنا ونمنع الانعكاس بفرض سياق `ltr` على
/// الأيقونة وحدها — لا على المحتوى حولها.
class DirectionalForwardIcon extends StatelessWidget {
  const DirectionalForwardIcon({super.key, this.size = 16, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Icon(
      isRtl ? Icons.chevron_left : Icons.chevron_right,
      textDirection: TextDirection.ltr,
      size: size,
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}
