/// التخصّصات الطبية المعتمدة — مصدر الحقيقة الوحيد.
///
/// ## المشكلة التي يحلّها هذا الملف
///
/// كانت القائمة مكتوبة **ثلاث مرات** بثلاث مفردات مختلفة:
///
///   - شاشة إعدادات الطبيب (ما يُكتَب فعلاً في قاعدة البيانات): ثمانية تخصّصات.
///   - شاشة بحث المريض (ما يُصفّى به): سبعة، منها `قلب` **لا يستطيع أي طبيب
///     اختياره** — فرقاقة تصفية تُرجع صفراً دائماً مهما كان عدد الأطباء.
///   - شاشة الحجز القديمة: خمسة، بصيغة «عربي / English».
///
/// والأثر ليس شكلياً: `نساء` و`باطنية` و`عظام` تخصّصات يستطيع الطبيب اختيارها
/// ولا توجد لها رقاقة تصفية إطلاقاً، فأطباؤها لا يظهرون إلا في «الكل» أو
/// بالبحث النصّي. أي أن المريض الباحث عن طبيب نساء لا يجد طريقاً إليه.
///
/// القائمة هنا واحدة: من يكتب ومن يقرأ يشتقّان منها، فلا يمكن أن تنحرف
/// مفرداتهما مرة أخرى. يحرس ذلك اختبار في test/specialties_test.dart.
library;

/// تخصّص طبي واحد.
class Specialty {
  const Specialty(this.ar, this.en);

  /// الاسم العربي — وهو **القيمة المخزَّنة** في `specialization`.
  ///
  /// المخزَّن عربي لا إنجليزي لأن ذلك ما كتبته النسخ السابقة فعلاً، وتغييره
  /// يتطلّب هجرة بيانات لا مبرّر لها.
  final String ar;

  /// الاسم الإنجليزي — يُخزَّن في `specializationEn` ولا يُعرض في الواجهة
  /// اليوم (التطبيق عربي بالكامل).
  final String en;
}

abstract final class Specialties {
  /// القائمة المعتمدة. أي تخصّص جديد يُضاف هنا وحده.
  static const List<Specialty> all = [
    Specialty('عام', 'General Practice'),
    Specialty('أسنان', 'Dentistry'),
    Specialty('نساء', 'Obstetrics'),
    Specialty('جلدية', 'Dermatology'),
    Specialty('أطفال', 'Pediatrics'),
    Specialty('عيون', 'Ophthalmology'),
    Specialty('باطنية', 'Internal Medicine'),
    Specialty('عظام', 'Orthopedics'),
  ];

  /// الأسماء العربية بالترتيب — للتصفية والعرض.
  static List<String> get arabicNames => all.map((s) => s.ar).toList();

  /// نص رقاقة «كل التخصّصات». ليس تخصّصاً، فلا يُخزَّن ولا يُصفّى به.
  static const String anySpecialty = 'الكل';

  /// الأسماء العربية مسبوقةً بـ«الكل» — الشكل الذي تعرضه شاشة البحث.
  static List<String> get filterOptions => [anySpecialty, ...arabicNames];

  /// الاسم الإنجليزي المقابل، أو نصّ فارغ لتخصّص غير معروف.
  static String englishFor(String arabic) {
    for (final s in all) {
      if (s.ar == arabic) return s.en;
    }
    return '';
  }

  /// هل هذه قيمة تخصّص معتمدة؟
  static bool isKnown(String arabic) => arabicNames.contains(arabic);
}
