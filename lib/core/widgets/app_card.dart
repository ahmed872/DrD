import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// بطاقة محتوى — سطح بحدّ شعري وحشوة قياسية.
///
/// النسق يرسم `Card` بلا ظل وبحدّ شعري، لكن كل شاشة كانت تلفّه بحشوة
/// مختلفة (12، 16، 20، أحياناً بلا حشوة أصلاً). [AppCard] يثبّت الحشوة
/// ومنطقة اللمس معاً.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = DrdSpacing.card,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// حين يُمرَّر، تصبح البطاقة قابلة للنقر مع أثر لمس مقصوص على الاستدارة.
  final VoidCallback? onTap;

  /// وصف البطاقة لقارئ الشاشة حين لا يكفي محتواها.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);

    return Card(
      // القصّ ضروري: بدونه يتجاوز أثر اللمس الحواف المستديرة فيظهر مربّعاً.
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: DrdRadius.lgAll,
              child: Semantics(
                button: true,
                label: semanticLabel,
                child: content,
              ),
            ),
    );
  }
}
