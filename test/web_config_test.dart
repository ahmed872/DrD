import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس عقد إعدادات Firebase لنسخة الويب.
///
/// ## ما الذي يحرسه
///
/// اسم متغيّر البناء مكتوب في **ثلاثة** أماكن مستقلة:
///
///   - `lib/firebase_options.dart`  — من يقرأه
///   - `tool/build_web.sh`          — من يتحقّق منه قبل البناء
///   - `web_config.example.json`    — ما يملؤه المطوّر
///
/// انحراف حرف واحد بينها يعيد العطل الأصلي بالضبط: بناء ينجح وينتج حزمة
/// تعرض شاشة خطأ لكل زائر. لا يلتقط ذلك محلّل ولا اختبار وحدة، لأن
/// `String.fromEnvironment` باسم خاطئ ليس خطأ ترجمة — بل نصّ فارغ.
void main() {
  late String optionsSource;
  late String buildScript;
  late Map<String, dynamic> exampleConfig;

  setUpAll(() {
    optionsSource = File('lib/firebase_options.dart').readAsStringSync();
    buildScript = File('tool/build_web.sh').readAsStringSync();
    exampleConfig = json.decode(
      File('web_config.example.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  /// المتغيّرات التي يقرأها [DefaultFirebaseOptions.web] بلا قيمة افتراضية.
  ///
  /// `String.fromEnvironment('X')` بلا `defaultValue` هو تحديداً ما ينتج نصاً
  /// فارغاً بصمت، فهذه هي القائمة الإلزامية.
  Set<String> mandatoryDefines() {
    final webBlock = _blockBetween(
      optionsSource,
      'static const FirebaseOptions web = FirebaseOptions(',
      ');',
    );
    final result = <String>{};
    // مطابقة `String.fromEnvironment('NAME')` غير المتبوعة بـ defaultValue.
    final pattern = RegExp(
      r"String\.fromEnvironment\(\s*'([A-Z0-9_]+)'\s*(,\s*defaultValue)?",
    );
    for (final m in pattern.allMatches(webBlock)) {
      if (m.group(2) == null) result.add(m.group(1)!);
    }
    return result;
  }

  test('إعدادات الويب ما زالت تُمرَّر وقت البناء، لا مكتوبة في المصدر', () {
    // ربط نسخة البناء بمشروع Firebase بعينه قرار نشر. لو تحوّلت هذه القيم
    // إلى ثوابت مصدرية، فقدت `tool/build_web.sh` معناه وعاد البناء الصامت.
    expect(mandatoryDefines(), isNotEmpty,
        reason: 'لم تعد أي قيمة ويب إلزامية — راجع استراتيجية الإعداد كاملة');
  });

  test('سكربت البناء يتحقّق من كل متغيّر إلزامي', () {
    final required = _bashArray(buildScript, 'REQUIRED');
    expect(
      required,
      equals(mandatoryDefines()),
      reason: 'قائمة REQUIRED في tool/build_web.sh لا تطابق ما يقرأه '
          'lib/firebase_options.dart — أحدهما تغيّر دون الآخر',
    );
  });

  test('القالب يعرض كل متغيّر إلزامي بقيمة فارغة', () {
    for (final key in mandatoryDefines()) {
      expect(exampleConfig.containsKey(key), isTrue,
          reason: '$key ناقص من web_config.example.json');
      expect(exampleConfig[key], '',
          reason: '$key في القالب يجب أن يبقى فارغاً — القالب يُلتزم في '
              'المستودع، وملؤه بقيمة حقيقية يجعلها ثابتاً مصدرياً');
    }
  });

  test('ملف الإعداد الحقيقي مستثنى من المستودع', () {
    final ignore = File('.gitignore').readAsStringSync();
    expect(ignore, contains('web_config.json'));
  });

  test('السكربت يفشل بدل البناء عند نقص الإعدادات', () {
    // العطل الأصلي كان أن `flutter build web --release` **ينجح** بإعدادات
    // فارغة. هذا الاختبار يثبت أن المسار الموصى به لم يعد يفعل ذلك.
    final result = Process.runSync(
      'bash',
      ['tool/build_web.sh', '--config', 'definitely-not-a-real-file.json'],
      environment: {'FIREBASE_WEB_API_KEY': '', 'FIREBASE_WEB_APP_ID': ''},
      includeParentEnvironment: true,
    );
    expect(result.exitCode, isNot(0),
        reason: 'سكربت البناء نجح رغم غياب الإعدادات');
    expect('${result.stderr}', contains('FIREBASE_WEB_API_KEY'));
  });
}

/// نص ما بين [start] وأول [end] يليه.
String _blockBetween(String source, String start, String end) {
  final from = source.indexOf(start);
  if (from < 0) return '';
  final to = source.indexOf(end, from + start.length);
  return to < 0 ? source.substring(from) : source.substring(from, to);
}

/// عناصر مصفوفة bash معلنة كـ `NAME=(a b c)`.
Set<String> _bashArray(String script, String name) {
  final m = RegExp('$name=\\(([^)]*)\\)').firstMatch(script);
  if (m == null) return {};
  return m
      .group(1)!
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .map((s) => s.replaceAll(RegExp('["\']'), ''))
      .toSet();
}
