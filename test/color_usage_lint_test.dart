import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// اختبار على **الشيفرة نفسها**، لا على ودجت.
///
/// اختبارات `theme_widgets_test.dart` تتحقّق أن أزواج النسق نفسها مقروءة
/// (`onPrimary` فوق `primary`...). لكن ذلك لا يمنع الخطأ الذي كشفته المراجعة
/// البصرية في المرحلة 5ب: التحويل الآلي لألوان الوضع الليلي استبدل خلفية
/// الحاوية **ونصّها** بالرمز نفسه، فصار نص `primary` فوق خلفية `primary`
/// بتباين 1.04:1 — أي غير مرئي. سبعة مواضع في خمس شاشات.
///
/// الزوجان مقروءان في النسق، والمشكلة في الاستعمال. فالحارس هنا نصّي:
/// أي `BoxDecoration` يملأ بلون «تأكيد» (primary/secondary/tertiary/error)
/// يجب أن يستعمل `on<اللون>` لمحتواه، لا اللون نفسه.
void main() {
  const fillRoles = ['primary', 'secondary', 'tertiary', 'error'];

  test('لا نص بلون خلفيته داخل حاوية ملوّنة', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();

      for (final role in fillRoles) {
        final fill = RegExp(
          r'BoxDecoration\(\s*color:\s*Theme\.of\(context\)\s*'
                  r'\.colorScheme\s*\.' +
              role +
              r'\b',
          multiLine: true,
        );
        // حدّ الكلمة مهم: `onPrimaryContainer` يحوي `onPrimary` نصّياً،
        // ولولاه لمرّت الحاويةُ المعطوبة لأن نصّاً آخر في نفس النافذة
        // يستعمل نسخة الحاوية.
        final onRole = 'on${role[0].toUpperCase()}${role.substring(1)}';
        final onRolePattern = RegExp(r'\.' + onRole + r'\b');
        final sameRole = RegExp(
          r'color:\s*Theme\.of\(context\)\s*\.colorScheme\s*\.' + role + r'\b',
          multiLine: true,
        );

        for (final match in fill.allMatches(source)) {
          // نافذة تقريبية لجسم الودجت الذي يلي التزيين.
          final end = (match.end + 2500).clamp(0, source.length);
          final body = source.substring(match.end, end);
          if (sameRole.hasMatch(body) && !onRolePattern.hasMatch(body)) {
            final line =
                '\n'.allMatches(source.substring(0, match.start)).length + 1;
            offenders.add('${entity.path}:$line — خلفية $role ونصّ $role');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'استعمل ${fillRoles.map((r) => '${r}Container').join('/')} '
          'للخلفية و`on…Container` للنص:\n${offenders.join('\n')}',
    );
  });
}
