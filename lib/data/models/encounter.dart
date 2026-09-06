import 'package:cloud_firestore/cloud_firestore.dart';

/// سجل زيارة سريرية — الوحدة الأساسية للسجل الطبي.
///
/// **معرّف المستند هو معرّف الموعد.** هذا ليس اختصاراً: هو ما يفرض «سجل
/// واحد لكل زيارة» بنيوياً، ويجعل البحث عن سجل زيارة قراءةً بمعرّف معروف
/// لا استعلاماً.
///
/// ## لماذا اسم الطبيب منسوخ هنا
///
/// المريض يستطيع قراءة مستندات الأطباء، فالنسخ ليس ضرورة أمنية. لكنه ضرورة
/// **معنى**: السجل الطبي يوثّق مَن كتبه وقت كتابته. لو غيّر الطبيب اسمه أو
/// تخصصه لاحقاً وجب أن يبقى السجل شاهداً على ما كان — وهو ما ستحتاجه
/// المرحلة الرابعة حين يشارك المريض نسخة من زيارة بعينها.
class Encounter {
  const Encounter({
    required this.appointmentId,
    required this.patientId,
    required this.doctorId,
    required this.encounterDate,
    required this.diagnosis,
    this.doctorName = '',
    this.doctorSpecialization = '',
    this.clinicalNotes = '',
    this.treatmentPlan = '',
    this.followUpNotes = '',
    this.followUpDate = '',
    this.createdAt,
    this.updatedAt,
  });

  factory Encounter.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data() ?? const <String, dynamic>{};
    String str(String key) => (data[key] ?? '').toString();
    return Encounter(
      // المعرّف مأخوذ من المستند لا من الحقل: هما متطابقان بحكم القاعدة،
      // والمستند هو المرجع.
      appointmentId: snap.id,
      patientId: str('patientId'),
      doctorId: str('doctorId'),
      doctorName: str('doctorName'),
      doctorSpecialization: str('doctorSpecialization'),
      encounterDate: str('encounterDate'),
      diagnosis: str('diagnosis'),
      clinicalNotes: str('clinicalNotes'),
      treatmentPlan: str('treatmentPlan'),
      followUpNotes: str('followUpNotes'),
      followUpDate: str('followUpDate'),
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
    );
  }

  /// معرّف السجل = معرّف الموعد.
  final String appointmentId;
  String get id => appointmentId;

  final String patientId;
  final String doctorId;
  final String doctorName;
  final String doctorSpecialization;

  /// تاريخ الزيارة (yyyy-MM-dd) — من الموعد، لا وقت الكتابة.
  final String encounterDate;

  final String diagnosis;
  final String clinicalNotes;
  final String treatmentPlan;
  final String followUpNotes;
  final String followUpDate;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// هل صُحِّح السجل بعد كتابته؟
  ///
  /// الفارق الزمني لا المساواة: الطابعان يُكتبان في نفس الدفعة عند الإنشاء
  /// وقد يختلفان بميلي ثانية.
  bool get wasEdited {
    final c = createdAt;
    final u = updatedAt;
    if (c == null || u == null) return false;
    return u.difference(c).inSeconds > 1;
  }

  static DateTime? _asDate(Object? value) => switch (value) {
        Timestamp() => value.toDate(),
        DateTime() => value,
        _ => null,
      };
}
