import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';

/// حارس نظام الطباعة.
///
/// ## ما الذي يحرسه
///
/// لم يكن للتطبيق خط معرَّف إطلاقاً: النصّ العربي كان يُرسَم بخط النظام
/// الافتراضي — أياً كان على ذلك الجهاز. فيختلف شكل التطبيق بين هاتف وآخر،
/// وتتغيّر معه أطوال الأسطر وارتفاع البطاقات وما إذا كان النصّ يفيض.
///
/// وهذا الصنف من الأعطال صامت تماماً: خط ناقص من `pubspec.yaml` لا يُفشل
/// البناء ولا يظهر في المحلّل — يظهر فقط كنصّ بشكل مختلف على جهاز المستخدم.
void main() {
  const family = 'IBMPlexSansArabic';

  group('ملفات الخط', () {
    test('الأوزان الأربعة موجودة وصالحة', () {
      // النسق يستخدم w400 و w500 و w600 و w700. وزن ناقص يجعل Flutter
      // يصطنعه بالتثخين البرمجي، وهو أسوأ من الوزن الحقيقي بكثير في العربية.
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        final file = File('assets/fonts/IBMPlexSansArabic-$weight.ttf');
        expect(file.existsSync(), isTrue, reason: 'وزن $weight ناقص');

        // ترويسة sfnt صالحة — لا صفحة خطأ HTML حُفظت باسم .ttf.
        final header = file.readAsBytesSync().sublist(0, 4);
        expect(
          header,
          anyOf(
            equals([0x00, 0x01, 0x00, 0x00]),
            equals('true'.codeUnits),
            equals('OTTO'.codeUnits),
          ),
          reason: 'ملف $weight ليس خطاً صالحاً',
        );
      }
    });

    test('الرخصة مرفقة', () {
      // OFL 1.1 تسمح بالتضمين وتشترط إرفاق نصّ الرخصة.
      final licence = File('assets/fonts/OFL.txt');
      expect(licence.existsSync(), isTrue);
      expect(licence.readAsStringSync(), contains('SIL Open Font License'));
    });

    test('pubspec يعلن العائلة بأوزانها', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: $family'));
      for (final weight in [400, 500, 600, 700]) {
        expect(pubspec, contains('weight: $weight'));
      }
    });
  });

  group('النسق يطبّق الخط', () {
    for (final entry
        in {'فاتح': AppTheme.light, 'داكن': AppTheme.dark}.entries) {
      test('${entry.key}: كل أدوار النصّ تستخدم العائلة', () {
        final theme = entry.value;
        expect(theme.textTheme.bodyLarge?.fontFamily, family);

        // الفحص على كل دور: تعريف العائلة في `ThemeData` وحده لا يكفي، لأن
        // `_textTheme` تبني أنماطها صراحةً وتتجاوزه.
        final roles = <String, TextStyle?>{
          'headlineSmall': theme.textTheme.headlineSmall,
          'titleLarge': theme.textTheme.titleLarge,
          'titleMedium': theme.textTheme.titleMedium,
          'titleSmall': theme.textTheme.titleSmall,
          'bodyLarge': theme.textTheme.bodyLarge,
          'bodyMedium': theme.textTheme.bodyMedium,
          'bodySmall': theme.textTheme.bodySmall,
          'labelLarge': theme.textTheme.labelLarge,
          'labelMedium': theme.textTheme.labelMedium,
          'labelSmall': theme.textTheme.labelSmall,
        };
        roles.forEach((name, style) {
          expect(style?.fontFamily, family, reason: '$name بلا عائلة خط');
        });
      });

      test('${entry.key}: الأرقام بعرض ثابت', () {
        // أوقات المواعيد والأسعار تُعرض في أعمدة؛ أرقام متغيّرة العرض تجعل
        // «10:00» و«11:00» بعرضين مختلفين في نفس القائمة.
        final features = entry.value.textTheme.bodyLarge?.fontFeatures ?? [];
        expect(
          features.map((f) => f.feature),
          contains('tnum'),
          reason: 'الأرقام ليست بعرض ثابت',
        );
      });
    }
  });

  test('كل مسار في السلّم متدرّج', () {
    // ملاحظة على شكل الاختبار: أول صياغة له قارنت المقاسات كسلّم خطّي واحد
    // (28 ← 22 ← 17 ← 15 ← 16 …) فرسب عند `bodyLarge`. والخطأ كان في
    // الاختبار لا في النسق: Material يعرّف **مسارات** مستقلة — عنوان، ومتن،
    // وتسمية — ومقاس المتن (16) أكبر من أصغر عنوان (15) عمداً، لأن النصّ
    // المقروء طويلاً يحتاج مقاساً أكبر من عنوان فرعي قصير.
    //
    // الثابت الحقيقي هو تدرّج كل مسار داخل نفسه.
    final t = AppTheme.light.textTheme;
    final tracks = <String, List<double>>{
      'العناوين': [
        t.headlineSmall!.fontSize!,
        t.titleLarge!.fontSize!,
        t.titleMedium!.fontSize!,
        t.titleSmall!.fontSize!,
      ],
      'المتن': [
        t.bodyLarge!.fontSize!,
        t.bodyMedium!.fontSize!,
        t.bodySmall!.fontSize!,
      ],
      'التسميات': [
        t.labelLarge!.fontSize!,
        t.labelMedium!.fontSize!,
        t.labelSmall!.fontSize!,
      ],
    };
    tracks.forEach((name, sizes) {
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], lessThan(sizes[i - 1]),
            reason: 'مسار «$name» غير متدرّج: $sizes');
      }
    });
  });

  test('لا مقاس أصغر من الحد المقروء', () {
    // 12 نقطة هو أصغر ما يبقى مقروءاً للعربية بنقاطها على شاشة هاتف.
    final t = AppTheme.light.textTheme;
    for (final style in [t.bodySmall, t.labelMedium, t.labelSmall]) {
      expect(style!.fontSize, greaterThanOrEqualTo(12));
    }
  });

  test('ارتفاع السطر مناسب للعربية', () {
    // الحروف العربية تحمل نقاطاً فوق وتحت خط الأساس، فارتفاع 1.2 المعتاد
    // في اللاتينية يجعل النقاط تكاد تلامس السطر التالي.
    final theme = AppTheme.light.textTheme;
    expect(theme.bodyLarge!.height, greaterThanOrEqualTo(1.6));
    expect(theme.bodyMedium!.height, greaterThanOrEqualTo(1.6));
    expect(theme.titleLarge!.height, greaterThanOrEqualTo(1.3));
  });
}
