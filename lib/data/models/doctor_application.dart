import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/doctor_application_status.dart';

/// طلب انضمام طبيب — مستند واحد لكل مستخدم، معرّفه هو معرّف المستخدم.
///
/// الحقول مقسومة قسمة تطابق قواعد الأمان:
///   - حقول مقدّم الطلب: يكتبها هو، ويعيد كتابتها عند إعادة التقديم.
///   - حقول المراجعة: يكتبها المشرف وحده، ولا يملك مقدّم الطلب لمسها.
///
/// لا يحمل هذا النموذج نسخة من بيانات المستخدم الحساسة. الاستثناء الوحيد
/// [applicantName]، وهو قرار خصوصية مقصود موثّق في `docs/SECURITY.md`:
/// المشرف يحتاج معرفة من يوافق عليه، وتخزين الاسم هنا أضيق كثيراً من فتح
/// مجموعة `users` كلها لقراءة المشرف.
class DoctorApplication {
  const DoctorApplication({
    required this.applicantId,
    required this.applicantName,
    required this.specialty,
    required this.professionalBio,
    required this.yearsOfExperience,
    required this.status,
    this.applicantNotes = '',
    this.submittedAt,
    this.updatedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
  });

  /// حالة «لم يتقدّم بعد» — ليست مستنداً في قاعدة البيانات.
  factory DoctorApplication.none(String uid) => DoctorApplication(
        applicantId: uid,
        applicantName: '',
        specialty: '',
        professionalBio: '',
        yearsOfExperience: 0,
        status: DoctorApplicationStatus.none,
      );

  factory DoctorApplication.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data() ?? const <String, dynamic>{};
    return DoctorApplication(
      applicantId: (data['applicantId'] ?? snap.id).toString(),
      applicantName: (data['applicantName'] ?? '').toString(),
      specialty: (data['specialty'] ?? '').toString(),
      professionalBio: (data['professionalBio'] ?? '').toString(),
      // القيم الرقمية قد تصل `int` أو `double` من Firestore.
      yearsOfExperience: (data['yearsOfExperience'] as num?)?.toInt() ?? 0,
      applicantNotes: (data['applicantNotes'] ?? '').toString(),
      status: DoctorApplicationStatus.parse(data['status']),
      submittedAt: _asDate(data['submittedAt']),
      updatedAt: _asDate(data['updatedAt']),
      reviewedAt: _asDate(data['reviewedAt']),
      reviewedBy: data['reviewedBy']?.toString(),
      rejectionReason: data['rejectionReason']?.toString(),
    );
  }

  final String applicantId;
  final String applicantName;
  final String specialty;
  final String professionalBio;
  final int yearsOfExperience;
  final String applicantNotes;
  final DoctorApplicationStatus status;

  final DateTime? submittedAt;
  final DateTime? updatedAt;

  // --- حقول المراجعة: للقراءة فقط من جهة العميل ---
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;

  /// سبب الرفض إن كان الطلب مرفوضاً **الآن**.
  ///
  /// المستند يحتفظ بسبب آخر رفض حتى بعد إعادة التقديم — عمداً، حفظاً لسجل
  /// المراجعة. لكن عرضه بينما الطلب قيد المراجعة يخبر الطبيب بأنه مرفوض
  /// وهو ليس كذلك، فالتحقق من الحالة شرط لعرضه.
  String? get activeRejectionReason =>
      status == DoctorApplicationStatus.rejected ? rejectionReason : null;

  static DateTime? _asDate(Object? value) => switch (value) {
        Timestamp() => value.toDate(),
        DateTime() => value,
        _ => null,
      };
}
