import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/constants/specialties.dart';

/// حارس مفردات التخصّصات.
///
/// ## ما الذي يحرسه
///
/// كانت القائمة مكتوبة ثلاث مرات بثلاث مفردات مختلفة: ما يكتبه الطبيب، وما
/// يُصفّي به المريض، وما تعرضه شاشة الحجز القديمة. والانحراف بينها ليس
/// شكلياً — رقاقة `قلب` كانت تُرجع صفراً دائماً لأن **لا طبيب يستطيع
/// اختيارها**، بينما `نساء` و`باطنية` و`عظام` يختارها الأطباء ولا رقاقة لها،
/// فلا يجدهم المريض إلا بالبحث النصّي.
///
/// ولا يلتقط ذلك محلّل ولا اختبار وحدة: كلا الطرفين صحيح نحوياً، والقائمتان
/// تنحرفان بصمت مع أول إضافة في أحدهما.
void main() {
  test('لا تخصّص مكرّر', () {
    final names = Specialties.arabicNames;
    expect(names.toSet().length, names.length);
  });

  test('لكل تخصّص عربي مقابل إنجليزي غير فارغ', () {
    // `specializationEn` يُخزَّن في مستند الطبيب. تركه فارغاً يكتب حقلاً
    // فارغاً في قاعدة البيانات بدل أن يفشل بوضوح.
    for (final s in Specialties.all) {
      expect(s.ar.trim(), isNotEmpty);
      expect(s.en.trim(), isNotEmpty, reason: 'التخصّص «${s.ar}» بلا مقابل');
      expect(Specialties.englishFor(s.ar), s.en);
    }
  });

  test('«الكل» أول خيارات التصفية وليس تخصّصاً', () {
    // شاشة البحث تتخطّى التصفية عند الفهرس صفر. لو انزاح «الكل» عن مكانه
    // لصار «الكل» تخصّصاً يُصفّى به — فتظهر القائمة فارغة دائماً.
    expect(Specialties.filterOptions.first, Specialties.anySpecialty);
    expect(Specialties.isKnown(Specialties.anySpecialty), isFalse);
    expect(
      Specialties.filterOptions.length,
      Specialties.all.length + 1,
      reason: 'خيارات التصفية = التخصّصات + «الكل»',
    );
  });

  test('كل خيار تصفية (عدا «الكل») تخصّص يستطيع طبيب اختياره', () {
    for (final option in Specialties.filterOptions.skip(1)) {
      expect(Specialties.isKnown(option), isTrue,
          reason: 'رقاقة «$option» لا يقابلها تخصّص — ستُرجع صفراً دائماً');
    }
  });

  test('الشاشتان تشتقّان من المصدر ولا تكتبان قائمة خاصة', () {
    // الحارس البنيوي: قائمة حرفية في أي من الشاشتين تعيد الانحراف نفسه.
    for (final path in [
      'lib/presentation/screens/doctor_settings_screen.dart',
      'lib/presentation/screens/patient_search_doctor_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('Specialties.'),
          reason: '$path لا يشتقّ التخصّصات من المصدر الموحّد');
      // `قلب` كان التخصّص الوهمي الذي بدأ المشكلة.
      expect(source, isNot(contains("'قلب'")),
          reason: '$path يحمل تخصّصاً حرفياً خارج القائمة المعتمدة');
    }
  });
}
