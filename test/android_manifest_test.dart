import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس إعدادات نسخة الإصدار على أندرويد.
///
/// ## لماذا اختبار على ملفات البناء؟
///
/// عطلان في هذا المشروع كانا يمنعان نسخة الإصدار من العمل تماماً، ولا يظهر
/// أيّ منهما أثناء التطوير:
///
///   1. `INTERNET` كان معلناً في `src/debug` و`src/profile` فقط. نسخة الإصدار
///      تدمج `src/main` وحده، فكانت تُثبَّت وتفتح ثم تفشل في كل نداء إلى
///      Firebase. و`flutter run` يدمج بيان التصحيح، فيبدو كل شيء سليماً.
///
///   2. `signingConfig` كان يشير إلى مفتاح التصحيح، فتُنتَج حزمة يرفضها
///      Google Play.
///
/// الاثنان أعطال **إعداد** لا أعطال كود، فلا يلتقطهما اختبار وحدة ولا محلّل
/// ولا اختبار واجهة. هذا الملف هو المكان الوحيد الذي يستطيع منع عودتهما.
void main() {
  final manifestDir = Directory('android/app/src/main');

  group('بيان أندرويد الرئيسي', () {
    late String manifest;

    setUpAll(() {
      final file = File('${manifestDir.path}/AndroidManifest.xml');
      expect(file.existsSync(), isTrue,
          reason: 'بيان أندرويد الرئيسي غير موجود في ${file.path}');
      manifest = file.readAsStringSync();
    });

    // قراءة بالتعبير النمطي عمداً بدل مُحلِّل XML: الحزمة الوحيدة المتاحة
    // (`xml`) اعتمادية عابرة لا يعلنها pubspec، والاعتماد عليها يجعل هذا
    // الحارس نفسه هشّاً. الشكل المطلوب ثابت وبسيط، فالتعبير النمطي كافٍ.
    List<String> permissions() => RegExp(
          r'<uses-permission\s[^>]*android:name\s*=\s*"([^"]+)"',
        ).allMatches(manifest).map((m) => m.group(1)!).toList();

    test('يُعلن إذن INTERNET', () {
      expect(
        permissions(),
        contains('android.permission.INTERNET'),
        reason: 'بدون هذا الإذن لا تصل نسخة الإصدار إلى Firebase إطلاقاً، '
            'والعطل لا يظهر أثناء التطوير لأن بيان التصحيح يحمل الإذن.',
      );
    });

    test('لا يطلب أذونات زائدة', () {
      // كل إذن إضافي يظهر للمستخدم في المتجر ويحتاج تبريراً. التطبيق لا يقرأ
      // جهات اتصال ولا موقعاً ولا كاميرا، فوجود أي منها يعني خطأً أو تسرّباً
      // من حزمة خارجية.
      const allowed = {
        'android.permission.INTERNET',
      };
      expect(
        permissions().toSet().difference(allowed),
        isEmpty,
        reason: 'أذونات غير مبرَّرة في بيان الإصدار',
      );
    });
  });

  group('إعداد توقيع الإصدار', () {
    late String gradle;

    setUpAll(() {
      final file = File('android/app/build.gradle.kts');
      expect(file.existsSync(), isTrue);
      gradle = file.readAsStringSync();
    });

    test('نسخة الإصدار لا تُوقَّع بمفتاح التصحيح', () {
      // الصيغة التي كانت هنا: signingConfig = signingConfigs.getByName("debug")
      // داخل كتلة release. مفتاح التصحيح مشترك ومعروف، وGoogle Play يرفض
      // الحزم الموقَّعة به.
      final releaseBlock = _blockAfter(gradle, 'release {');
      expect(
        releaseBlock,
        isNot(contains('getByName("debug")')),
        reason: 'كتلة release ما زالت تشير إلى مفتاح التصحيح',
      );
    });

    test('التوقيع يُقرأ من ملف خارج المستودع', () {
      // المفتاح وكلمات مروره لا تُلتزم أبداً. الإعداد يقرأها من
      // android/key.properties، وهو مستثنى في .gitignore.
      expect(gradle, contains('key.properties'));
      final ignore = File('.gitignore').readAsStringSync();
      expect(ignore, contains('android/key.properties'));
      expect(ignore, contains('*.jks'));
      expect(ignore, contains('*.keystore'));
    });

    test('لا مفتاح ولا كلمة مرور ملتزَمة في المستودع', () {
      expect(File('android/key.properties').existsSync(), isFalse,
          reason: 'ملف مفاتيح التوقيع موجود في شجرة العمل — لا يجوز التزامه');
      final keystores = Directory('android')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.jks') || f.path.endsWith('.keystore'))
          .toList();
      expect(keystores, isEmpty,
          reason: 'مخزن مفاتيح داخل المستودع: ${keystores.map((f) => f.path)}');
    });
  });
}

/// يستخرج نص الكتلة التي تبدأ عند [marker] حتى قوسها المغلق المقابل.
String _blockAfter(String source, String marker) {
  final start = source.indexOf(marker);
  if (start < 0) return '';
  var depth = 0;
  for (var i = start + marker.length - 1; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return source.substring(start);
}
