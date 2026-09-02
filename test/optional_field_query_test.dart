import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس على **الشيفرة نفسها**: لا استعلام يسأل عن غياب حقل بـ `== false`.
///
/// المساواة في Firestore لا تطابق غياب الحقل. فاستعلام
/// `where('disabled', isEqualTo: false)` لا يُرجع المستندات التي لا تحمل
/// `disabled` إطلاقاً — وهي هنا الأغلبية: الحقل أُضيف في المرحلة 2، ولا
/// سكربت الترحيل يكتبه (`grandfather_doctors.js` يقتصر على `isVerified`).
///
/// رصدت مراجعة المرحلة 10 أثر ذلك على المحاكي: لوحة الإدارة تعرض «أطباء
/// نشطون: 0» بينما خمسة أطباء موثَّقين يستقبلون الحجوزات فعلاً. لا اختبار
/// سلوكي يلتقطه لأن بيانات الاختبار تُكتب كاملة الحقول دائماً.
///
/// بقية النظام يعامل الغياب بصوابه: القواعد بـ `get('disabled', false)`،
/// والخادم بـ `disabled === true`. القاعدة هنا تُبقي العميل على نفس
/// الانضباط: اسأل عن الحالة **الموجبة** (`== true`) واطرحها، لا عن
/// نفيها.
void main() {
  /// حقول اختيارية أُضيفت بعد أن كانت هناك بيانات — غيابها يعني القيمة
  /// الافتراضية لا الاستبعاد.
  const optionalFields = ['disabled', 'isVerified', 'verificationStatus'];

  test('لا استعلام يطابق غياب حقل اختياري بـ isEqualTo: false', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // التعليقات تشرح هذا الفخّ بالاسم في أكثر من ملف، فلولا تجريدها
      // لسقط الحارس على شرحه لا على استعمال حقيقي.
      final source = entity
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

      for (final field in optionalFields) {
        final pattern = RegExp(
          "where\\(\\s*'$field'\\s*,\\s*isEqualTo:\\s*false\\s*\\)",
        );
        for (final match in pattern.allMatches(source)) {
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          offenders.add('${entity.path}:$line — $field == false');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'المستندات التي لا تحمل الحقل لن تُطابَق. اسأل عن `== true` '
          'واطرح النتيجة:\n${offenders.join('\n')}',
    );
  });
}
