import 'package:cloud_firestore/cloud_firestore.dart';

/// حالة طلب الانضمام كطبيب، كما يراها **صاحب الطلب**.
///
/// ## لماذا تُقرأ من `doctorApplications` لا من `users`
///
/// `doctorAccountStateFrom` يستنتج الحالة من `users/{uid}`، وهو الصحيح
/// لحساب طبيب قائم. لكنه لا يرى المتقدّم: لا شيء يكتب
/// `verificationStatus: 'pending'` على مستند المستخدم عند التقديم — ولا
/// يمكنه، فالحقل محميّ في `firestore.rules` ولا تعمل أي دالة عند الإرسال.
/// و`rejectDoctor` لا يكتبه أيضاً.
///
/// النتيجة قبل هذا الملف: المتقدّم يرسل طلبه ثم **لا يرى شيئاً** — لا حالة
/// ولا تأكيد. وهو ما ظهر في الاختبار اليدوي على جهاز حقيقي.
///
/// المصدر الصحيح لحالة الطلب هو مستند الطلب نفسه، وصاحبه يقرأه بحكم
/// القواعد (`doctorApplications/{uid}` → `allow read: if isUser(uid)`).
/// فلا تغيير في القواعد ولا في الدوال ولا حقل جديد.
enum DoctorApplicationStatus {
  /// لا طلب — مريض عادي لم يتقدّم بعد.
  none,

  /// أُرسل وينتظر قرار الإدارة.
  pending,

  /// قُبل الطلب. قد يسبق ظهورَ الدور الجديد في الجلسة الحالية.
  approved,

  /// رُفض — يمكن التعديل وإعادة التقديم.
  rejected;

  static DoctorApplicationStatus parse(Object? raw) => switch (raw) {
        'pending' => DoctorApplicationStatus.pending,
        'approved' => DoctorApplicationStatus.approved,
        'rejected' => DoctorApplicationStatus.rejected,
        _ => DoctorApplicationStatus.none,
      };

  /// هل هناك طلب قائم يمنع تقديم طلب جديد؟
  bool get isSubmitted => this != DoctorApplicationStatus.none;
}

/// لقطة طلب — الحالة وما يلزم لعرضها.
class DoctorApplicationSnapshot {
  const DoctorApplicationSnapshot({
    required this.status,
    this.specialization = '',
    this.note = '',
    this.rejectionReason = '',
    this.submittedAt,
  });

  /// لا طلب: الحالة الافتراضية قبل وصول أي بيانات، وبعد التأكد من الغياب.
  static const DoctorApplicationSnapshot empty =
      DoctorApplicationSnapshot(status: DoctorApplicationStatus.none);

  final DoctorApplicationStatus status;
  final String specialization;
  final String note;
  final String rejectionReason;
  final DateTime? submittedAt;

  /// يبني اللقطة من مستند Firestore.
  ///
  /// كل حقل يُقرأ دفاعياً: مستندات الطلبات كُتبت عبر إصدارات مختلفة من
  /// التطبيق، وحقل مفقود يجب أن يعطي نصاً فارغاً لا انهياراً في الواجهة.
  factory DoctorApplicationSnapshot.fromMap(Map<String, dynamic>? data) {
    if (data == null) return empty;
    final submitted = data['submittedAt'];
    return DoctorApplicationSnapshot(
      status: DoctorApplicationStatus.parse(data['status']),
      specialization: (data['specialization'] ?? '').toString().trim(),
      note: (data['note'] ?? '').toString().trim(),
      rejectionReason: (data['rejectionReason'] ?? '').toString().trim(),
      submittedAt: submitted is Timestamp ? submitted.toDate() : null,
    );
  }
}

/// قراءة حالة طلب الانضمام لصاحبه.
///
/// قراءة فقط — لا تكتب شيئاً. إرسال الطلب يبقى في
/// `DoctorApplicationScreen`، والقرار يبقى على الخادم وحده
/// (`approveDoctor`/`rejectDoctor` في `functions/admin.js`).
class DoctorApplicationService {
  DoctorApplicationService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('doctorApplications').doc(uid);

  /// بثّ حالة الطلب. خطأ البثّ (صلاحية، شبكة) يُعامَل كـ«لا طلب» حتى لا
  /// تنهار الرئيسية بسبب بطاقة ثانوية.
  Stream<DoctorApplicationSnapshot> watch(String uid) => _ref(uid)
      .snapshots()
      .map((doc) => DoctorApplicationSnapshot.fromMap(doc.data()))
      .handleError((_) => DoctorApplicationSnapshot.empty);
}
