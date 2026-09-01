/// حالة حساب الطبيب كما تراها الواجهة.
///
/// الحالة موزّعة على ثلاثة حقول في `users/{uid}` يكتبها الخادم وحده
/// (`functions/admin.js`): `role` و`isVerified` و`disabled`، ويصفها
/// `verificationStatus` وصفاً. كل شاشة كانت تعيد استنتاجها بنفسها — أو لا
/// تستنتجها إطلاقاً فتعرض للطبيب الموقوف أدوات لا تعمل.
///
/// هذا الملف يوحّد الاستنتاج في دالة خالصة قابلة للاختبار، ولا يقرّر شيئاً
/// أمنياً: الحجز عند طبيب موقوف مرفوض على الخادم أصلاً منذ المرحلة 2
/// (`fetchBookableDoctor`)، وهذه الحالة للعرض ولتعطيل أدوات لا معنى لها.
library;

enum DoctorAccountState {
  /// ليس طبيباً — مريض أو حساب لم يُرقَّ بعد.
  notADoctor,

  /// قدّم طلب توثيق وينتظر مراجعة الإدارة.
  pending,

  /// رُفض طلبه — يستطيع إعادة التقديم.
  rejected,

  /// موثَّق لكن موقوف مؤقتاً؛ لا يستقبل حجوزات جديدة.
  suspended,

  /// طبيب نشط وقابل للحجز.
  active;

  /// هل يظهر له جدول ومرضى وحجوزات قادمة؟
  bool get hasClinicAccess =>
      this == DoctorAccountState.active || this == DoctorAccountState.suspended;

  /// هل يستقبل حجوزات جديدة الآن؟
  bool get acceptsNewBookings => this == DoctorAccountState.active;

  String get arabicLabel => switch (this) {
        DoctorAccountState.notADoctor => 'حساب مريض',
        DoctorAccountState.pending => 'قيد المراجعة',
        DoctorAccountState.rejected => 'طلب مرفوض',
        DoctorAccountState.suspended => 'حساب موقوف',
        DoctorAccountState.active => 'موثَّق ونشط',
      };

  /// شرح موجّه للطبيب: ماذا يعني هذا، وما التالي.
  String get arabicDescription => switch (this) {
        DoctorAccountState.notADoctor =>
          'لم تُفعَّل ميزات الطبيب على هذا الحساب بعد',
        DoctorAccountState.pending =>
          'طلبك قيد المراجعة من الإدارة. سنبلغك فور اتخاذ القرار، ولا يمكن '
              'للمرضى الحجز عندك حتى ذلك الحين.',
        DoctorAccountState.rejected =>
          'لم يُقبل طلبك. يمكنك تعديل بياناتك وإعادة التقديم.',
        DoctorAccountState.suspended =>
          'حسابك موقوف مؤقتاً: لا تصلك حجوزات جديدة، ومواعيدك القائمة كما هي. '
              'تواصل مع الإدارة لمعرفة التفاصيل.',
        DoctorAccountState.active => 'حسابك نشط ويستقبل الحجوزات',
      };
}

/// يستنتج حالة الحساب من مستند المستخدم.
///
/// الترتيب مقصود: الإيقاف يسبق التوثيق في الأولوية لأن الطبيب الموقوف يبقى
/// `isVerified: true` — تمييز متعمَّد في المرحلة 2 بين «غير موثَّق» و«موثَّق
/// لكن موقوف». عرضه كـ«نشط» لأنه موثَّق كان سيجعله ينتظر حجوزات لا تأتي.
DoctorAccountState doctorAccountStateFrom(Map<String, dynamic>? userData) {
  final data = userData ?? const {};
  if (data['role'] != 'doctor') {
    // متقدّم لم يُقبل بعد يبقى `role: 'patient'`؛ حالة طلبه هي ما يميّزه.
    final applicationStatus = data['verificationStatus'];
    if (applicationStatus == 'pending') return DoctorAccountState.pending;
    if (applicationStatus == 'rejected') return DoctorAccountState.rejected;
    return DoctorAccountState.notADoctor;
  }

  if (data['disabled'] == true) return DoctorAccountState.suspended;
  if (data['isVerified'] != true) return DoctorAccountState.pending;
  return DoctorAccountState.active;
}
