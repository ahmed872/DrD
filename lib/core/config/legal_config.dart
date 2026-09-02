/// روابط المستندات القانونية — سياسة الخصوصية وشروط الاستخدام.
///
/// ## لماذا ثابت فارغ لا رابط جاهز
///
/// التطبيق يجمع بيانات صحية: مواعيد عند أطباء بتخصصات معلنة، وسبب زيارة
/// يكتبه المريض بنفسه. ونشره على المتاجر يشترط سياسة خصوصية منشورة تصف ما
/// يُجمع ولماذا وكيف يُحذف. تلك السياسة نصّ قانوني تكتبه جهة مسؤولة، ولا
/// يجوز أن يخترعه الكود.
///
/// فالمكتوب هنا هو **الوصلة** لا النص: املأ [privacyPolicyUrl] بعنوان
/// السياسة المنشورة قبل الإطلاق، فيظهر مدخلها في إعدادات المريض تلقائياً.
/// ما دام فارغاً لا يُعرض شيء — رابط مكسور أسوأ من غيابه، ووجود المدخل
/// بلا وجهة يوحي بامتثال لم يحدث.
///
/// المحتوى الواجب توفّره في تلك السياسة مستخرَج من الكود نفسه في
/// `docs/PRIVACY.md` — جرد فعلي لما يُجمع ويُحفَظ ويُحذف، لا قالب عام.
class LegalConfig {
  const LegalConfig._();

  /// عنوان سياسة الخصوصية المنشورة. فارغ = لم تُنشر بعد (حاجز إطلاق).
  static const String privacyPolicyUrl = '';

  /// عنوان شروط الاستخدام المنشورة. فارغ = لا يُعرض مدخلها.
  static const String termsOfServiceUrl = '';

  /// هل توجد وجهة صالحة لعرضها للمستخدم؟
  ///
  /// `https` حصراً: رابط غير مشفَّر لمستند قانوني يفتح باب تعديله في
  /// الطريق، ورابط بصيغة أخرى (`javascript:` مثلاً) ليس مستنداً أصلاً.
  static bool isPublishable(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  static bool get hasPrivacyPolicy => isPublishable(privacyPolicyUrl);

  static bool get hasTermsOfService => isPublishable(termsOfServiceUrl);
}
