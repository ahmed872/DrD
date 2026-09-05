/// الحالة المعتمدة للموعد — مصدر الحقيقة الوحيد.
///
/// قاعدة البيانات الحالية تحتوي على سبع صيغ مختلفة للحالة كُتبت على مدار
/// تطوير التطبيق (`Booked`, `Scheduled`, `upcoming`, `pending`, ...).
/// هذا الملف يوحّدها دون حذف أو تعديل أي مستند قديم: [AppointmentStatus.parse]
/// يقبل كل الصيغ القديمة ويحوّلها للحالة الصحيحة، بينما الكتابة الجديدة
/// تستخدم [wireValue] فقط.
library;

enum AppointmentStatus {
  /// محجوز وفي انتظار الحضور.
  booked('Booked', 'محجوز'),

  /// المريض حضر والكشف تم.
  completed('Completed', 'مكتمل'),

  /// أُلغي من المريض أو الطبيب.
  cancelled('Cancelled', 'ملغي'),

  /// مرّ الموعد ولم يُسجَّل حضور — بانتظار تأكيد الطبيب.
  pendingConfirmation('PendingConfirmation', 'بانتظار التأكيد'),

  /// المريض لم يحضر.
  noShow('NoShow', 'لم يحضر'),

  /// انتهت صلاحية الموعد قبل الحجز.
  expired('Expired', 'منتهي');

  const AppointmentStatus(this.wireValue, this.arabicLabel);

  /// القيمة التي تُكتب في Firestore.
  final String wireValue;

  /// النص المعروض للمستخدم بالعربية.
  final String arabicLabel;

  /// كل الصيغ القديمة الموجودة فعلياً في قاعدة البيانات، مقابل الحالة الصحيحة.
  ///
  /// المفاتيح كلها بحروف صغيرة لأن المقارنة تتم بعد `toLowerCase()`.
  static const Map<String, AppointmentStatus> _legacyAliases = {
    'booked': AppointmentStatus.booked,
    'scheduled': AppointmentStatus.booked,
    'upcoming': AppointmentStatus.booked,
    'pending': AppointmentStatus.booked,
    'confirmed': AppointmentStatus.booked,
    'completed': AppointmentStatus.completed,
    'done': AppointmentStatus.completed,
    'cancelled': AppointmentStatus.cancelled,
    'canceled': AppointmentStatus.cancelled,
    'pendingconfirmation': AppointmentStatus.pendingConfirmation,
    'noshow': AppointmentStatus.noShow,
    'no_show': AppointmentStatus.noShow,
    'expired': AppointmentStatus.expired,
  };

  /// يحوّل أي قيمة قادمة من Firestore إلى حالة معتمدة.
  ///
  /// القيم غير المعروفة تُعامَل كـ [booked] لأن الموعد المكتوب في قاعدة
  /// البيانات موجود فعلاً؛ إخفاؤه أسوأ من عرضه بحالة افتراضية.
  static AppointmentStatus parse(Object? raw) {
    if (raw == null) return AppointmentStatus.booked;
    final key = raw.toString().trim().toLowerCase().replaceAll(' ', '');
    return _legacyAliases[key] ?? AppointmentStatus.booked;
  }

  /// الحالات التي تشغل خانة زمنية فعلياً وتمنع حجزها مرة أخرى.
  static const Set<AppointmentStatus> occupying = {
    AppointmentStatus.booked,
    AppointmentStatus.completed,
    AppointmentStatus.pendingConfirmation,
  };

  /// كل الصيغ النصية الموجودة في قاعدة البيانات التي تُقرأ كهذه الحالة.
  ///
  /// تُستخدم في استعلامات `whereIn` حتى تلتقط المستندات القديمة أيضاً: استعلام
  /// `where('status', isEqualTo: 'Completed')` يفوّت كل موعد كُتب بصيغة
  /// `completed` أو `done`، وهو ما كان يحدث في شاشة السجل الطبي.
  ///
  /// ملاحظة: `whereIn` في Firestore محدود بـ 30 قيمة، والقوائم هنا أقل بكثير.
  List<String> get allWireValues => <String>{
        wireValue,
        ..._legacyAliases.entries
            .where((e) => e.value == this)
            .map((e) => e.key),
      }.toList(growable: false);

  /// كل الصيغ النصية التي تدل على خانة مشغولة.
  static List<String> get occupyingWireValues => occupying
      .expand((status) => status.allWireValues)
      .toSet()
      .toList(growable: false);

  /// هل الموعد ما زال قائماً (لم يُلغَ ولم ينتهِ)؟
  bool get isActive => this == AppointmentStatus.booked;

  /// هل يمكن للمريض إلغاء هذا الموعد؟
  bool get isCancellable => this == AppointmentStatus.booked;
}
