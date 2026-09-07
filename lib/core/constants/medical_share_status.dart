/// حالة مشاركة سجل طبي — آلة الحالات كاملةً.
///
/// الانتقالات المسموحة، وهي نفسها المكتوبة في `firestore.rules`:
///
///     (لا شيء) → pending      المريض يطلب المشاركة
///     pending  → active       الخادم بنى اللقطة وتحقّق من الملكية
///     pending  → rejected     الخادم رفض (سجل غير مملوك أو غير موجود)
///     pending  → revoked      المريض عدل قبل التفعيل
///     active   → revoked      المريض ألغى
///
/// ما لا يحدث: العودة من `revoked` أو `rejected` إلى النشاط. إعادة
/// المشاركة **حدث موافقة جديد** بمستند جديد، حفظاً لسجل ما وافق عليه
/// المريض ومتى.
library;

enum MedicalShareStatus {
  /// طُلبت، ولم يبنِ الخادم اللقطة بعد. الطبيب لا يرى شيئاً.
  pending('pending', 'قيد التجهيز'),

  /// نشطة — الطبيب يرى اللقطة.
  active('active', 'نشطة'),

  /// ألغاها المريض. الوصول انقطع فوراً.
  revoked('revoked', 'ملغاة'),

  /// رفضها الخادم — سجل غير مملوك أو غير موجود.
  rejected('rejected', 'تعذّرت');

  const MedicalShareStatus(this.wireValue, this.arabicLabel);

  final String wireValue;
  final String arabicLabel;

  /// يحوّل قيمة قادمة من قاعدة البيانات.
  ///
  /// القيمة غير المعروفة تُقرأ [pending] لا [active]: الخطأ في قراءة حالة
  /// غامضة يجب أن يميل إلى منع الوصول لا منحه.
  static MedicalShareStatus parse(Object? raw) {
    final key = (raw ?? '').toString().trim().toLowerCase();
    return switch (key) {
      'active' => MedicalShareStatus.active,
      'revoked' => MedicalShareStatus.revoked,
      'rejected' => MedicalShareStatus.rejected,
      _ => MedicalShareStatus.pending,
    };
  }

  /// هل يستطيع المريض إلغاءها الآن؟
  bool get isRevocable =>
      this == MedicalShareStatus.active || this == MedicalShareStatus.pending;

  /// هل يراها الطبيب المستقبِل؟ — تطابق شرط القاعدة تماماً.
  bool get isVisibleToRecipient => this == MedicalShareStatus.active;
}
