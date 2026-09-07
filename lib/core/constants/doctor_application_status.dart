/// حالة طلب الانضمام كطبيب — مصدر الحقيقة الوحيد لآلة الحالات.
///
/// الانتقالات المسموحة، وهي نفسها المكتوبة في `firestore.rules`:
///
///     none      → pending     تقديم الطلب
///     pending   → approved    قبول المشرف
///     pending   → rejected    رفض المشرف (بسبب مكتوب)
///     rejected  → pending     تصحيح وإعادة تقديم
///     approved  → —           نهائية من جهة العميل
///
/// [none] حالة عميل فقط: لا مستند لها في قاعدة البيانات. وجودها في التعداد
/// يجعل الواجهة تتعامل مع «لا طلب» كحالة صريحة بدل `null` متناثر.
library;

enum DoctorApplicationStatus {
  /// لا يوجد طلب — لم يتقدّم المستخدم بعد.
  none('none', 'لم تقدّم طلباً'),

  /// قُدّم وينتظر المراجعة.
  pending('pending', 'قيد المراجعة'),

  /// قُبل، والمستخدم صار طبيباً.
  approved('approved', 'مقبول'),

  /// رُفض، ويمكن تصحيحه وإعادة تقديمه.
  rejected('rejected', 'مرفوض');

  const DoctorApplicationStatus(this.wireValue, this.arabicLabel);

  /// القيمة كما تُكتب في Firestore.
  final String wireValue;

  /// النص المعروض للمستخدم.
  final String arabicLabel;

  /// يحوّل قيمة قادمة من قاعدة البيانات إلى حالة معتمدة.
  ///
  /// القيمة غير المعروفة تُقرأ [pending] لا [approved]: الخطأ في قراءة حالة
  /// غامضة يجب أن يميل إلى «لم يُبتّ فيه» لا إلى منح صلاحية.
  static DoctorApplicationStatus parse(Object? raw) {
    if (raw == null) return DoctorApplicationStatus.none;
    final key = raw.toString().trim().toLowerCase();
    return switch (key) {
      'approved' => DoctorApplicationStatus.approved,
      'rejected' => DoctorApplicationStatus.rejected,
      'pending' => DoctorApplicationStatus.pending,
      'none' || '' => DoctorApplicationStatus.none,
      _ => DoctorApplicationStatus.pending,
    };
  }

  /// هل يستطيع المستخدم تحرير الطلب وإرساله الآن؟
  ///
  /// لا أثناء المراجعة: تعديل الطلب تحت يد المراجع يجعل القرار يقع على نصّ
  /// غير الذي قُرئ. القاعدة على الخادم تفرض هذا أيضاً.
  bool get isEditable =>
      this == DoctorApplicationStatus.none ||
      this == DoctorApplicationStatus.rejected;

  /// هل ينتظر الطلب قراراً؟
  bool get isAwaitingReview => this == DoctorApplicationStatus.pending;

  /// هل مُنحت صلاحية الطبيب؟
  ///
  /// تحذير: هذه قراءة لحالة **الطلب**، لا مصدر الصلاحية. الصلاحية الفعلية
  /// هي `users/{uid}.role == 'doctor'` ويكتبها الخادم وحده. تُستعمل هذه
  /// للعرض فقط، لا لفتح شاشة.
  bool get isApproved => this == DoctorApplicationStatus.approved;
}
