import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import 'drd_tone.dart';

/// رسالة ثابتة داخل الصفحة — نجاح أو تحذير أو خطأ أو معلومة.
///
/// تُستعمل حين تكون الرسالة جزءاً من الصفحة يبقى ما بقيت (تحذير «حسابك غير
/// مُفعَّل»، خطأ تحميل مع زر إعادة محاولة). للرسائل العابرة استعمل
/// [AppSnackBar].
///
/// الرسالة تحمل أيقونة دائماً — الشكل هو ما يُميّز نجاحاً من خطأ لمن لا
/// يميّز الأحمر من الأخضر.
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.tone,
    required this.message,
    this.title,
    this.action,
    this.onDismiss,
  });

  const AppBanner.success({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.onDismiss,
  }) : tone = DrdTone.success;

  const AppBanner.warning({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.onDismiss,
  }) : tone = DrdTone.warning;

  const AppBanner.error({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.onDismiss,
  }) : tone = DrdTone.error;

  const AppBanner.info({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.onDismiss,
  }) : tone = DrdTone.info;

  final DrdTone tone;

  /// نص الرسالة. يُكتب بلغة المستخدم لا بلغة النظام: «تعذّر حفظ الموعد»
  /// لا «خطأ 500».
  final String message;

  /// عنوان قصير اختياري فوق الرسالة.
  final String? title;

  /// إجراء واحد على الأكثر — إعادة محاولة، فتح إعدادات.
  final Widget? action;

  /// حين يُمرَّر، يظهر زر إغلاق.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final style = tone.resolve(context);
    final text = context.text;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DrdSpacing.sm),
        decoration: BoxDecoration(
          color: style.container,
          borderRadius: DrdRadius.smAll,
          border: Border.all(
            color: style.accent.withValues(alpha: 0.35),
            width: DrdSizes.hairline,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(style.icon, size: 20, color: style.accent),
            const SizedBox(width: DrdSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: text.titleSmall?.copyWith(
                        color: style.onContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: DrdSpacing.xxs),
                  ],
                  Text(
                    message,
                    style: text.bodyMedium?.copyWith(color: style.onContainer),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: DrdSpacing.xs),
                    action!,
                  ],
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: style.onContainer,
                onPressed: onDismiss,
                tooltip: 'إغلاق',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(DrdSpacing.xxs),
              ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// الرسائل العابرة
// ===========================================================================

/// شريط رسالة مؤقت بنغمة دلالية.
///
/// الخلفية **ليست** ملوّنة: النسق يرسم الشريط بالسطح المعكوس، والنغمة تظهر
/// في الأيقونة وحدها. خلفية حمراء كاملة تصبغ ربع الشاشة لتقول ما تقوله
/// أيقونة بعرض 20 بكسل.
///
/// تُبنى بلا `BuildContext` عمداً: أغلب مواضع الاستدعاء تأتي بعد `await`،
/// وتمرير سياق عبر فجوة غير متزامنة هو ما يُنتج تحذير
/// `use_build_context_synchronously`. الألوان تُحلّ داخل [_SnackBarContent]
/// وقت الرسم.
abstract final class AppSnackBar {
  static SnackBar success(String message, {SnackBarAction? action}) =>
      _build(DrdTone.success, message, action, const Duration(seconds: 4));

  static SnackBar warning(String message, {SnackBarAction? action}) =>
      _build(DrdTone.warning, message, action, const Duration(seconds: 5));

  /// أطول عمراً من البقية: رسالة الفشل هي التي يحتاج المستخدم قراءتها فعلاً.
  static SnackBar error(String message, {SnackBarAction? action}) =>
      _build(DrdTone.error, message, action, const Duration(seconds: 6));

  static SnackBar info(String message, {SnackBarAction? action}) =>
      _build(DrdTone.info, message, action, const Duration(seconds: 4));

  static SnackBar _build(
    DrdTone tone,
    String message,
    SnackBarAction? action,
    Duration duration,
  ) {
    return SnackBar(
      content: _SnackBarContent(tone: tone, message: message),
      action: action,
      duration: duration,
    );
  }
}

class _SnackBarContent extends StatelessWidget {
  const _SnackBarContent({required this.tone, required this.message});

  final DrdTone tone;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          tone.resolve(context).icon,
          size: 20,
          color: tone.onInverseSurface(context),
        ),
        const SizedBox(width: DrdSpacing.xs),
        Expanded(child: Text(message)),
      ],
    );
  }
}

/// اختصار الاستدعاء المتزامن: `context.showSuccess('تم الحفظ')`.
///
/// بعد `await` استعمل مُرسِلاً مُلتقَطاً قبل الانتظار:
/// `messenger.showSnackBar(AppSnackBar.error(...))`.
extension AppMessenger on BuildContext {
  void showSuccess(String message, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(this).showSnackBar(
        AppSnackBar.success(message, action: action),
      );

  void showWarning(String message, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(this).showSnackBar(
        AppSnackBar.warning(message, action: action),
      );

  void showError(String message, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(this).showSnackBar(
        AppSnackBar.error(message, action: action),
      );

  void showInfo(String message, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(this).showSnackBar(
        AppSnackBar.info(message, action: action),
      );
}
