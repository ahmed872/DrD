import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/medical_share_status.dart';

/// لقطة سجل طبي واحد داخل مشاركة — **ثابتة بعد إنشائها**.
///
/// يكتبها الخادم وحده، ولا يملك المريض ولا الطبيب المستقبِل ولا الطبيب
/// المؤلِّف تعديلها. تعديل السجل الأصلي لاحقاً لا يغيّرها: الموافقة انصبّت
/// على هذا النصّ بعينه.
class SharedEncounterSnapshot {
  const SharedEncounterSnapshot({
    required this.encounterId,
    required this.encounterDate,
    required this.diagnosis,
    this.doctorName = '',
    this.doctorSpecialization = '',
    this.clinicalNotes = '',
    this.treatmentPlan = '',
    this.followUpNotes = '',
    this.followUpDate = '',
    this.sourceUpdatedAt,
  });

  factory SharedEncounterSnapshot.fromMap(Map<String, dynamic> m) {
    String str(String k) => (m[k] ?? '').toString();
    return SharedEncounterSnapshot(
      encounterId: str('encounterId'),
      encounterDate: str('encounterDate'),
      diagnosis: str('diagnosis'),
      doctorName: str('doctorName'),
      doctorSpecialization: str('doctorSpecialization'),
      clinicalNotes: str('clinicalNotes'),
      treatmentPlan: str('treatmentPlan'),
      followUpNotes: str('followUpNotes'),
      followUpDate: str('followUpDate'),
      sourceUpdatedAt: _asDate(m['sourceUpdatedAt']),
    );
  }

  final String encounterId;
  final String encounterDate;
  final String diagnosis;
  final String doctorName;
  final String doctorSpecialization;
  final String clinicalNotes;
  final String treatmentPlan;
  final String followUpNotes;
  final String followUpDate;

  /// نسخة السجل وقت الالتقاط — يبقى معروفاً ما شُورك بالضبط.
  final DateTime? sourceUpdatedAt;
}

/// حدث موافقة واحد: مريض شارك سجلات بعينها مع طبيب بعينه في وقت بعينه.
///
/// المستند غير قابل لإعادة الكتابة: المستقبِل والسجلات واللقطة وتاريخ
/// الإنشاء ثابتة بحكم القاعدة. الحقل الوحيد الذي يتغيّر هو الحالة، ونحو
/// الإلغاء فقط.
class MedicalShare {
  const MedicalShare({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.recipientDoctorId,
    required this.recipientDoctorName,
    required this.recipientDoctorSpecialization,
    required this.encounterIds,
    required this.status,
    this.snapshots = const [],
    this.createdAt,
    this.activatedAt,
    this.revokedAt,
    this.rejectionReason,
  });

  factory MedicalShare.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data() ?? const <String, dynamic>{};
    String str(String k) => (data[k] ?? '').toString();

    final raw = (data['snapshots'] as List<dynamic>?) ?? const [];
    return MedicalShare(
      id: snap.id,
      patientId: str('patientId'),
      patientName: str('patientName'),
      recipientDoctorId: str('recipientDoctorId'),
      recipientDoctorName: str('recipientDoctorName'),
      recipientDoctorSpecialization: str('recipientDoctorSpecialization'),
      encounterIds: ((data['encounterIds'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      status: MedicalShareStatus.parse(data['status']),
      snapshots: raw
          .whereType<Map<String, dynamic>>()
          .map(SharedEncounterSnapshot.fromMap)
          .toList(growable: false),
      createdAt: _asDate(data['createdAt']),
      activatedAt: _asDate(data['activatedAt']),
      revokedAt: _asDate(data['revokedAt']),
      rejectionReason: data['rejectionReason']?.toString(),
    );
  }

  final String id;
  final String patientId;

  /// اسم المريض، منسوخ عند الإنشاء.
  ///
  /// الطبيب المستقبِل **لا يستطيع قراءة مستند المريض** — قاعدة `users`
  /// تسمح بقراءة المستخدم لنفسه ومستندات الأطباء وحدها. نسخ الاسم هنا أضيق
  /// كثيراً من توسيع تلك القاعدة، ولا يكشف هاتفاً ولا بريداً ولا تاريخ
  /// ميلاد.
  final String patientName;

  final String recipientDoctorId;
  final String recipientDoctorName;
  final String recipientDoctorSpecialization;

  /// ما طلب المريض مشاركته. اللقطات تُبنى منه على الخادم.
  final List<String> encounterIds;

  final MedicalShareStatus status;
  final List<SharedEncounterSnapshot> snapshots;

  final DateTime? createdAt;
  final DateTime? activatedAt;
  final DateTime? revokedAt;
  final String? rejectionReason;

  /// عدد السجلات المشمولة — من اللقطات إن وُجدت، وإلا من الطلب.
  int get recordCount =>
      snapshots.isNotEmpty ? snapshots.length : encounterIds.length;
}

DateTime? _asDate(Object? value) => switch (value) {
      Timestamp() => value.toDate(),
      DateTime() => value,
      _ => null,
    };
