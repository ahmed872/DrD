import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس على **الشيفرة نفسها**: لا استعلام مجموعة بلا حدّ.
///
/// المرحلة 7 أغلقت خمس قراءات كانت تنمو بلا سقف — كل مواعيد الطبيب منذ
/// بداية حسابه، وكل مواعيد المريض، ومجموعة الأطباء كاملة في كل فتح للبحث.
/// هذه القراءات لا تفشل ولا تُبطئ شيئاً في بيانات الاختبار، فلا يكشفها
/// اختبار سلوك: تظهر فاتورةً وبطئاً بعد أشهر من التشغيل الحقيقي.
///
/// الحارس نصّي لذلك: أي استعلام على مجموعة ينتهي بـ `get()`/`snapshots()`
/// يجب أن يحمل `limit`، أو يكون قراءة مستند واحد (`doc(...)`)، أو تجميعاً
/// (`count()`) — وهي كلها محدودة بطبيعتها.
void main() {
  test('كل استعلام مجموعة محدود بـ limit', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();

      for (final match in RegExp(r"\.collection\(").allMatches(source)) {
        // سلسلة الاستدعاء: من `.collection(` حتى أول `;` بعده.
        final endIdx = source.indexOf(';', match.start);
        if (endIdx < 0) continue;
        final chain = source.substring(match.start, endIdx);

        // ليست قراءة أصلاً (كتابة/إنشاء مرجع فقط).
        if (!chain.contains('.get()') && !chain.contains('.snapshots()')) {
          continue;
        }
        // مستند واحد أو تجميع — محدود بطبيعته.
        if (chain.contains('.doc(') || chain.contains('.count()')) continue;
        if (chain.contains('.limit(')) continue;

        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${entity.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'استعلام مجموعة بلا `limit` — يقرأ المجموعة كاملة:\n'
          '${offenders.join('\n')}',
    );
  });
}
