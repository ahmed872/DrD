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

  /// منظومة `ratings` القديمة: غير موصولة بأي مسار، وموثَّقة برأس في كل
  /// ملف. لا يمكن التحقّق بصرياً من شاشة لا تُفتح، فلا تُفرض عليها القاعدة.
  const deadRatingFiles = [
    'rating_widgets.dart',
    'doctor_rate_patient_screen.dart',
    'patient_rate_doctor_screen.dart',
  ];

  test('لا نص بلون خلفيته داخل حاوية ملوّنة', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();

      for (final role in fillRoles) {
        // يغطّي الصيغتين: `color: Theme.of(context).colorScheme.X` مباشرةً،
        // و`color: cond ? Theme.of(context).colorScheme.X : …`. الثانية
        // مرّت في المرحلة 5ب فبقيت شارة «نشط» في شاشة مرضى الطبيب بخلفية
        // ونصّ باللون نفسه.
        final fill = RegExp(
          // `[^,;]`: الفاصلة تُنهي وسيط اللون، فلا يقفز التعبير من لون
          // خلفية صحيح إلى `border` بعده ويبلّغ عن عطب غير موجود.
          r'BoxDecoration\(\s*color:[^,;]{0,120}?Theme\.of\(context\)\s*'
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
        // نفس السماح بالشرط الثلاثي هنا: لون النصّ يُكتب غالباً
        // `color: cond ? … : …` تماماً كلون الخلفية.
        final sameRole = RegExp(
          r'color:[^,;]{0,120}?Theme\.of\(context\)\s*\.colorScheme\s*\.' +
              role +
              r'\b',
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

  test('لا محتوى بلون أساسي داخل حاوية بلون الحاوية', () {
    // انحراف رصدته مراجعة المرحلة 10: زرّ «حذف حسابي نهائياً» داخل لوح
    // `errorContainer` كُتب بـ `foregroundColor: error`. القياس يقول إنه
    // ما زال فوق حدّ التباين (5.51:1 مقابل 7.24:1 للدور الصحيح)، فليس
    // عطباً بصرياً اليوم — لكنه زوج غير مضمون: `theme_widgets_test.dart`
    // يقيس `onXContainer/XContainer` وحده، فأي تعديل لاحق على النسق قد
    // يُسقط هذا الاستعمال بلا حارس يلتقطه.
    //
    // الاختباران السابقان لا يلتقطانه: الأول يحرس الخلفيات المملوءة
    // بالدور **الأساسي** (`error`) لا بدور الحاوية (`errorContainer`)،
    // والثاني يحرس غياب `foregroundColor` لا خطأه. الدور الصحيح فوق
    // `XContainer` هو `onXContainer` دائماً.
    //
    // الفحص مقصور على `foregroundColor` عمداً: `border` أو أيقونة تزيينية
    // بلون `error` فوق `errorContainer` استعمال مشروع لا عطب تباين.
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (deadRatingFiles.any(entity.path.endsWith)) continue;
      final source = entity.readAsStringSync();

      for (final role in fillRoles) {
        final fill = RegExp(
          r'BoxDecoration\(\s*color:[^,;]{0,120}?Theme\.of\(context\)\s*'
                  r'\.colorScheme\s*\.' +
              role +
              r'Container\b',
          multiLine: true,
        );
        // حدّ الكلمة هو كل شيء هنا: `errorContainer` يبدأ بـ `error`،
        // فبدونه يُبلَّغ عن كل استعمال صحيح.
        final baseRole = RegExp(
          r'foregroundColor:[^,;]{0,120}?Theme\.of\(context\)\s*'
                  r'\.colorScheme\s*\.' +
              role +
              r'\b(?!Container)',
          multiLine: true,
        );

        for (final match in fill.allMatches(source)) {
          final end = (match.end + 2500).clamp(0, source.length);
          final body = source.substring(match.end, end);
          for (final hit in baseRole.allMatches(body)) {
            final abs = match.end + hit.start;
            final line = '\n'.allMatches(source.substring(0, abs)).length + 1;
            offenders.add(
                '${entity.path}:$line — محتوى $role داخل ${role}Container');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'استعمل `on…Container` لمحتوى لوح `…Container`:\n'
          '${offenders.join('\n')}',
    );
  });

  test('لا زرّ بخلفية معيَّنة ونصّ افتراضي', () {
    // عطب رصدته المراجعة البصرية للمرحلة 6: زرّ «عرض التفاصيل» في شاشة
    // مرضى الطبيب كان يُرسم لوحاً فيروزياً فارغاً. السبب أن
    // `ElevatedButton.styleFrom(backgroundColor: …)` بلا `foregroundColor`
    // يترك المقدّمة على افتراض Material 3 — وهو `colorScheme.primary` —
    // فيصير نصّ primary فوق خلفية primary.
    //
    // ملاحظة على الأداة: التعبير النمطي لا يصلح هنا، لأن `Theme.of(context)`
    // يحوي قوساً مغلقاً فيقطع أي `[^;]*?\)` مبكراً. لذلك نطابق الأقواس عدّاً.
    final offenders = <String>[];
    final opener = RegExp(r'(ElevatedButton|FilledButton)\.styleFrom\(');

    int closeOf(String s, int open) {
      var depth = 0;
      for (var j = open; j < s.length; j++) {
        if (s[j] == '(') depth++;
        if (s[j] == ')') {
          depth--;
          if (depth == 0) return j;
        }
      }
      return -1;
    }

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // منظومة التقييم القديمة غير موصولة بأي مسار وموثّقة كذلك.
      if (deadRatingFiles.any(entity.path.endsWith)) continue;

      final source = entity.readAsStringSync();
      for (final match in opener.allMatches(source)) {
        final open = source.indexOf('(', match.end - 1);
        final end = closeOf(source, open);
        if (end < 0) continue;
        final body = source.substring(open, end + 1);
        if (body.contains('backgroundColor') &&
            !body.contains('foregroundColor')) {
          final line = '\n'.allMatches(source.substring(0, open)).length + 1;
          offenders.add('${entity.path}:$line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'عيِّن `foregroundColor` مع كل `backgroundColor`:\n'
          '${offenders.join('\n')}',
    );
  });
}
