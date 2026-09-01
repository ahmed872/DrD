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
  ///
  /// المرحلة 6: الموقوف لم يعد ضمنهم. كانت المرحلة 5ب تُبقي له وصول العيادة
  /// للقراءة، لأن مواعيده القائمة تبقى قائمة. لكن مصفوفة الحالات المعتمدة
  /// تحصر الموقوف في «الحالة + إجراءات الحساب المسموحة»، وذلك أسلم: شاشات
  /// العيادة تحمل أزرار كتابة (إنهاء موعد، ملاحظة، فتح خانة) لا معنى لها
  /// لحساب قرّرت الإدارة إيقافه، وإظهارها معطَّلةً أو عاملةً كلاهما مُربك.
  ///
  /// وهذا عرضٌ لا تفويض: الخادم يرفض الحجز عند الموقوف أصلاً
  /// (`fetchBookableDoctor`)، وقواعد Firestore هي التي تحرس الكتابة.
  bool get hasClinicAccess => this == DoctorAccountState.active;

  /// هل يستقبل حجوزات جديدة الآن؟
  bool get acceptsNewBookings => this == DoctorAccountState.active;

  /// إجراءات الحساب (الإعدادات، الدعم، تسجيل الخروج) تبقى متاحة لكل من
  /// يملك حساب طبيب — بما فيهم الموقوف: عليه أن يصل إلى بياناته وإلى
  /// الدعم ليعرف سبب الإيقاف.
  bool get hasAccountActions =>
      this == DoctorAccountState.active || this == DoctorAccountState.suspended;

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
