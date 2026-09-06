import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// عنوان قسم داخل صفحة.
///
/// كانت العناوين تُكتب كـ `Text` بأحجام وأوزان مرتجلة — 15 و16 و18 وbold
/// أحياناً وw600 أحياناً. العنوان هنا شكل واحد، والتسلسل البصري يصبح
/// قابلاً للقراءة.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(
      top: DrdSpacing.lg,
      bottom: DrdSpacing.sm,
    ),
  });

  final String title;

  /// سطر شارح اختياري — يُكتب حين لا يكفي العنوان وحده.
  final String? subtitle;

  /// إجراء على يسار العنوان: «عرض الكل»، مرشِّح.
  final Widget? trailing;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final text = context.text;

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: DrdSpacing.xxs),
                  Text(
                    subtitle!,
                    style: text.bodySmall?.copyWith(color: context.drd.muted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
