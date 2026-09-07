import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// يمنع عودة الألوان الحرفية إلى الشاشات.
///
/// المرحلة الأولى أزالت 543 لوناً مكتوباً يدوياً من طبقة العرض. بلا هذا
/// الاختبار سيعود أوّلها مع أوّل شاشة جديدة، ثم الباقي خلفه: هكذا تراكمت
/// في المرة الأولى — لا بقرار، بل بغياب ما يقول لا.
///
/// القاعدة: اللون يأتي من `Theme.of(context)` أو من `context.drd`.
/// التعريفات الخام تعيش في `lib/core/theme/` وحدها.
void main() {
  test('لا ألوان حرفية في طبقة العرض', () {
    // `Colors.x`، `Colors.x.shade400`، `Colors.x[50]`، و`Color(0xFF...)`.
    final literal = RegExp(r'\bColors\.[a-zA-Z]|\bColor\(0x[0-9a-fA-F]+\)');

    final offenders = <String>[];
    final dir = Directory('lib/presentation');

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // `Colors.transparent` ليس لوناً بل إلغاء للون — تستعمله Material
        // لإطفاء صبغة السطح.
        if (line.contains('Colors.transparent')) continue;
        if (literal.hasMatch(line)) {
          offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'اقرأ اللون من النسق بدل كتابته:\n${offenders.join('\n')}',
    );
  });

  test('اللوحة الخام لا تُقرأ من الشاشات مباشرة', () {
    // `DrdPalette` تحمل قيم الوضعين معاً؛ قراءتها في شاشة تعني لوناً لا
    // يتبع الوضع الليلي. الشاشات تقرأ `context.colors` و`context.drd`.
    final offenders = <String>[];

    for (final entity
        in Directory('lib/presentation').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('DrdPalette.')) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'استعمل context.colors أو context.drd:\n${offenders.join('\n')}',
    );
  });
}
