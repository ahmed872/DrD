import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import 'drd_tone.dart';

/// حالة التحميل.
///
/// عنوان اختياري لأن دوّارة عارية لا تخبر المستخدم بما يُنتظَر — وعلى شاشة
/// حجز طبي الفرق بين «جارٍ التحميل» و«جارٍ تأكيد الحجز» مهم.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: DrdSpacing.md),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(
                color: context.drd.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// حالة «لا يوجد شيء هنا» — **ليست** حالة خطأ.
///
/// التفريق بين الاثنتين هو الغرض من وجودهما منفصلتين: «لا يوجد مرضى» يعني
/// أن الطلب نجح وكانت النتيجة فارغة، بينما «تعذّر التحميل» يعني أننا لا
/// نعرف. عرض الأولى مكان الثانية يخفي عن الطبيب أن بياناته لم تصل أصلاً.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;

  /// إجراء يخرج المستخدم من الفراغ: «ابحث عن طبيب»، «أضف موعداً».
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final drd = context.drd;
    final text = context.text;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DrdSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: DrdSpacing.xxl, color: drd.disabled),
            const SizedBox(height: DrdSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (message != null) ...[
              const SizedBox(height: DrdSpacing.xs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: drd.muted),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: DrdSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// حالة الفشل، مع طريق للخروج منها.
///
/// [onRetry] ليس اختيارياً بلا سبب: شاشة خطأ بلا زر إعادة محاولة تترك
/// المستخدم أمام طريق مسدود، وحلّه الوحيد إغلاق التطبيق.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.title = 'تعذّر تحميل البيانات',
    this.onRetry,
    this.retryLabel = 'إعادة المحاولة',
  });

  /// ما الذي فشل، بلغة المستخدم لا بلغة الاستثناء.
  final String message;
  final String title;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final style = DrdTone.error.resolve(context);
    final text = context.text;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DrdSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: DrdSpacing.xxl, color: style.accent),
            const SizedBox(height: DrdSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: DrdSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: context.drd.muted),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: DrdSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(retryLabel),
                // العرض الطبيعي لا العريض: النسق يفرض ارتفاعاً كاملاً على
                // الأزرار، وزر بعرض الشاشة داخل حالة خطأ يبدو كإجراء أساسي.
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, DrdSizes.touchTarget),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
