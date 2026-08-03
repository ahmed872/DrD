/// مكتبة العناصر المشتركة.
///
/// كانت كل شاشة تبني بطاقتها وشريط حالتها وحالة الفراغ الخاصة بها بألوان
/// مكتوبة يدوياً، فاختلف شكل نفس العنصر بين شاشة وأخرى. كل ما هنا يقرأ ألوانه
/// من النسق، فيتبع الوضع الليلي وأي تغيير مستقبلي في هوية التطبيق تلقائياً.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

// =============================================================================
// الهيكل والتخطيط
// =============================================================================

/// رأس متدرّج بلون العلامة يعلو الصفحة.
///
/// الشريط المسطّح المصمت الذي كان مستخدماً يجعل كل الشاشات متشابهة وبلا عمق.
/// التدرّج هنا هو العنصر الذي يمنح التطبيق شخصيته البصرية.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.bottom,
    this.showBack = true,
    this.maxWidth = AppBreakpoints.content,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;

  /// محتوى إضافي يُرسم أسفل العنوان داخل نفس المساحة المتدرّجة.
  final Widget? bottom;

  final bool showBack;

  /// نفس حدّ عرض جسم الصفحة، حتى لا يمتد حقل البحث داخل الرأس على كامل
  /// عرض شاشة سطح المكتب بينما المحتوى تحته محصور.
  final double maxWidth;

  static const double _barHeight = kToolbarHeight;

  /// ارتفاع منطقة `bottom`.
  ///
  /// `PreferredSizeWidget` يجب أن يعلن ارتفاعه قبل البناء، ولا سبيل لقياس
  /// عنصر عشوائي مسبقاً. لذلك تُحجز مساحة ثابتة ويُقيَّد بها المحتوى: بدون
  /// ذلك يفيض الرأس ويختفي جسم الصفحة بالكامل خلف شريط الخطأ.
  static const double _bottomHeight = 54;

  @override
  Size get preferredSize {
    var height = _barHeight;
    if (subtitle != null) height += 22;
    if (bottom != null) height += _bottomHeight + AppSpacing.lg;
    return Size.fromHeight(height);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      decoration: BoxDecoration(
        gradient: tokens.brandGradient,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.xl),
        ),
        boxShadow: tokens.shadowMd,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              automaticallyImplyLeading: showBack,
              leading: leading,
              actions: actions,
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: context.texts.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (bottom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: SizedBox(height: _bottomHeight, child: bottom),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// يحصر المحتوى في عرض مقروء ويوسّطه.
///
/// التطبيق يُفتح من المتصفح على سطح المكتب أيضاً. بدون هذا الحدّ يمتد النموذج
/// على كامل عرض الشاشة فتصير حقول الإدخال أشرطة بطول متر.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.content,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// هيكل الصفحة القياسي: رأس متدرّج + جسم محصور العرض.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.headerBottom,
    this.maxWidth = AppBreakpoints.content,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.scrollable = true,
    this.floatingActionButton,
    this.bottomBar,
    this.onRefresh,
    this.showBack = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final Widget? headerBottom;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final bool scrollable;
  final Widget? floatingActionButton;
  final Widget? bottomBar;
  final Future<void> Function()? onRefresh;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    Widget body = PageBody(
      maxWidth: maxWidth,
      padding: padding,
      child: child,
    );

    if (scrollable) {
      body = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: body,
      );
    }

    if (onRefresh != null) {
      body = RefreshIndicator(
        onRefresh: onRefresh!,
        color: context.colors.primary,
        backgroundColor: context.tokens.surfaceRaised,
        child: body,
      );
    }

    return Scaffold(
      appBar: AppHeader(
        title: title,
        subtitle: subtitle,
        actions: actions,
        bottom: headerBottom,
        showBack: showBack,
        maxWidth: maxWidth,
      ),
      body: SafeArea(top: false, child: body),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar,
    );
  }
}

// =============================================================================
// البطاقات والأقسام
// =============================================================================

/// بطاقة موحّدة: سطح مرتفع، حدّ رفيع، ظلّ ناعم.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.selected = false,
    this.accent,
    this.margin,
    this.borderRadius = AppRadius.rLg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// يبرز البطاقة بحدّ ملوّن — يُستعمل للاختيار الحالي في القوائم.
  final bool selected;

  /// شريط لوني رفيع على حافة البطاقة، لتمييز الحالة دون ضجيج.
  final Color? accent;

  final EdgeInsetsGeometry? margin;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final primary = context.colors.primary;

    Widget content = Padding(padding: padding, child: child);

    if (accent != null) {
      // `Stack` وليس `Row(stretch)`: الصف الممتد يطلب ارتفاعاً لا نهائياً من
      // أبنائه داخل عمود غير محدود الارتفاع، فتنهار البطاقة وتختفي الشاشة
      // بالكامل. الـ Stack يأخذ حجمه من المحتوى ويمدّ الشريط على ارتفاعه.
      content = Stack(
        children: [
          content,
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: accent!),
          ),
        ],
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: borderRadius,
        border: Border.all(
          color: selected ? primary : tokens.border,
          width: selected ? 1.6 : 1,
        ),
        boxShadow: selected ? tokens.shadowMd : tokens.shadowSm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: content,
        ),
      ),
    );
  }
}

/// عنوان قسم مع سطر شرح اختياري وإجراء على الطرف.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.12),
                borderRadius: AppRadius.rSm,
              ),
              child: Icon(icon, size: 17, color: context.colors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.titleMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: context.texts.bodySmall
                        ?.copyWith(color: tokens.textMuted),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// صف «تسمية ← قيمة» بمحاذاة سليمة في الاتجاه من اليمين لليسار.
class InfoRow extends StatelessWidget {
  const InfoRow({
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
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: tokens.textMuted),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(
            label,
            style: context.texts.bodyMedium?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: context.texts.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor ?? tokens.textStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// الشارات والحالات
// =============================================================================

/// شارة حالة بيضاوية: خلفية هادئة + نص بنفس العائلة اللونية.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.background,
    this.icon,
    this.compact = false,
  });

  final String label;
  final Color color;
  final Color? background;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.13),
        borderRadius: AppRadius.rPill,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 12 : 14, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style:
                (compact ? context.texts.labelSmall : context.texts.labelMedium)
                    ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// لوحة تنبيه ملوّنة: معلومة، تحذير، خطأ، أو نجاح.
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.message,
    required this.tone,
    this.title,
    this.icon,
    this.action,
  });

  const NoticeBox.info({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.info_outline_rounded,
    this.action,
  }) : tone = NoticeTone.info;

  const NoticeBox.warning({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.warning_amber_rounded,
    this.action,
  }) : tone = NoticeTone.warning;

  const NoticeBox.danger({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.error_outline_rounded,
    this.action,
  }) : tone = NoticeTone.danger;

  const NoticeBox.success({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.check_circle_outline_rounded,
    this.action,
  }) : tone = NoticeTone.success;

  final String message;
  final String? title;
  final NoticeTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final (Color fg, Color bg) = switch (tone) {
      NoticeTone.info => (tokens.info, tokens.infoSoft),
      NoticeTone.warning => (tokens.warning, tokens.warningSoft),
      NoticeTone.danger => (tokens.danger, tokens.dangerSoft),
      NoticeTone.success => (tokens.success, tokens.successSoft),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: context.texts.titleSmall?.copyWith(color: fg),
                  ),
                Text(
                  message,
                  style: context.texts.bodySmall?.copyWith(
                    color: tokens.textBody,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

enum NoticeTone { info, warning, danger, success }

/// حالة الفراغ: أيقونة هادئة، سبب واضح، وإجراء يخرج المستخدم منها.
///
/// الرسالة وحدها لا تكفي — المستخدم الذي يرى «لا توجد مواعيد» يحتاج زراً
/// يأخذه للحجز، وإلا وقف في طريق مسدود.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.09),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 42, color: context.colors.primary),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.texts.titleMedium,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style:
                    context.texts.bodyMedium?.copyWith(color: tokens.textMuted),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// مؤشّر تحميل موحّد مع نص اختياري.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.message, this.compact = false});

  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: compact ? AppSpacing.xl : AppSpacing.xxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: compact ? 24 : 34,
              height: compact ? 24 : 34,
              child: const CircularProgressIndicator(strokeWidth: 3),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                message!,
                style: context.texts.bodySmall
                    ?.copyWith(color: context.tokens.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// عناصر تفاعلية
// =============================================================================

/// شريحة اختيار موحّدة (تخصّص، وقت، فلتر).
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final primary = context.colors.primary;

    final fg = !enabled
        ? tokens.textFaint
        : selected
            ? context.colors.onPrimary
            : tokens.textBody;

    return Material(
      color: !enabled
          ? tokens.surfaceSunken
          : selected
              ? primary
              : tokens.surfaceRaised,
      borderRadius: AppRadius.rPill,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: AppRadius.rPill,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rPill,
            border: Border.all(
              color: selected ? primary : tokens.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: context.texts.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: context.texts.labelSmall?.copyWith(
                    color: selected
                        ? context.colors.onPrimary.withValues(alpha: 0.85)
                        : tokens.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مبدّل شرائح أفقي (المواعيد القادمة / السابقة).
class AppSegmented extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        borderRadius: AppRadius.rPill,
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = i == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: selected ? tokens.surfaceRaised : Colors.transparent,
                  borderRadius: AppRadius.rPill,
                  boxShadow: selected ? tokens.shadowSm : null,
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: context.texts.labelMedium?.copyWith(
                    color: selected ? context.colors.primary : tokens.textMuted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// حقل إدخال موحّد. يعتمد على `inputDecorationTheme` ولا يعيد تعريف الألوان.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.maxLines = 1,
    this.onChanged,
    this.textInputAction,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      onChanged: onChanged,
      textInputAction: textInputAction,
      enabled: enabled,
      style:
          context.texts.bodyLarge?.copyWith(color: context.tokens.textStrong),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        suffixIcon: suffix,
      ),
    );
  }
}

/// حقل بحث بيضاوي بلا تسمية عائمة.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: context.texts.bodyMedium?.copyWith(color: tokens.textStrong),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 21),
        filled: true,
        fillColor: tokens.surfaceRaised,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.rPill,
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.rPill,
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.rPill,
          borderSide: BorderSide(color: context.colors.primary, width: 1.6),
        ),
      ),
    );
  }
}

/// صورة رمزية دائرية بحرف أول أو أيقونة.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.name,
    this.icon,
    this.size = 46,
    this.color,
  });

  final String? name;
  final IconData? icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = color ?? context.colors.primary;
    final initial = (name ?? '').trim().isEmpty
        ? null
        : (name ?? '').trim().characters.first;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            base.withValues(alpha: 0.18),
            base.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: base.withValues(alpha: 0.22)),
      ),
      child: initial != null
          ? Text(
              initial,
              style: context.texts.titleMedium?.copyWith(
                color: base,
                fontSize: size * 0.4,
              ),
            )
          : Icon(icon ?? Icons.person_rounded, color: base, size: size * 0.5),
    );
  }
}

/// بطاقة إحصائية صغيرة (رقم + تسمية).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = color ?? context.colors.primary;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: base.withValues(alpha: 0.12),
              borderRadius: AppRadius.rSm,
            ),
            child: Icon(icon, size: 18, color: base),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: context.texts.headlineSmall?.copyWith(color: base),
          ),
          Text(
            label,
            style: context.texts.bodySmall?.copyWith(color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}

/// نجوم التقييم للعرض فقط.
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.size = 15,
    this.reviews,
  });

  final double rating;
  final double size;
  final int? reviews;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size + 3, color: tokens.gold),
        const SizedBox(width: 3),
        Text(
          rating.toStringAsFixed(1),
          style: context.texts.labelMedium?.copyWith(
            color: tokens.textStrong,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (reviews != null) ...[
          const SizedBox(width: 3),
          Text(
            '($reviews)',
            style: context.texts.labelSmall?.copyWith(color: tokens.textMuted),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// رسائل مؤقتة
// =============================================================================

/// رسائل الحالة أسفل الشاشة بشكل موحّد.
///
/// كانت الشاشات تمرّر `Colors.red` و`Colors.green` مباشرة لكل `SnackBar`،
/// فاختلفت درجة الأحمر بين شاشة وأخرى وبقيت كما هي في الوضع الليلي.
class AppSnack {
  const AppSnack._();

  static void success(BuildContext context, String message) => _show(
      context, message, context.tokens.success, Icons.check_circle_rounded);

  static void error(BuildContext context, String message) =>
      _show(context, message, context.tokens.danger, Icons.error_rounded);

  static void info(BuildContext context, String message) =>
      _show(context, message, context.tokens.info, Icons.info_rounded);

  static void _show(
    BuildContext context,
    String message,
    Color color,
    IconData icon,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

/// نافذة تأكيد موحّدة. تُرجع `true` عند الموافقة.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  String cancelLabel = 'إلغاء',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final tokens = ctx.tokens;
      final accent = destructive ? tokens.danger : ctx.colors.primary;

      return AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon ??
                (destructive
                    ? Icons.warning_amber_rounded
                    : Icons.help_outline_rounded),
            color: accent,
            size: 26,
          ),
        ),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: ctx.texts.bodyMedium,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(cancelLabel),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(confirmLabel),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
  return result ?? false;
}
