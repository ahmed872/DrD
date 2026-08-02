/// نموذج التقييم - يحتوي على تقييمات الطبيب للمريض وتقييمات المريض للطبيب
class Rating {
  final String id;
  final String appointmentId;
  final String fromUserId; // المقيِّم (الطبيب أو المريض)
  final String toUserId; // المُقيَّم عليه (المريض أو الطبيب)
  final String ratingType; // 'doctor_to_patient' أو 'patient_to_doctor'

  // تقييم الطبيب للمريض - حالة صحية
  final int? healthConditionRating; // 1-5 تقييم للحالة الصحية
  final String?
      healthConditionComment; // تعليق على الحالة الصحية (السبب من وجهة نظر الطبيب)

  // تقييم المريض للطبيب - جودة الخدمة
  final int? serviceRating; // 1-5 تقييم جودة الخدمة
  final String? serviceComment; // تعليق على الخدمة

  final DateTime createdAt;
  final DateTime? updatedAt;

  const Rating({
    required this.id,
    required this.appointmentId,
    required this.fromUserId,
    required this.toUserId,
    required this.ratingType,
    this.healthConditionRating,
    this.healthConditionComment,
    this.serviceRating,
    this.serviceComment,
    required this.createdAt,
    this.updatedAt,
  });

  /// معرفة ما إذا كان هذا التقييم مكتملاً
  bool get isComplete {
    if (ratingType == 'doctor_to_patient') {
      return healthConditionRating != null;
    } else {
      return serviceRating != null;
    }
  }

  /// نسخ التقييم مع تحديث بعض الحقول
  Rating copyWith({
    String? id,
    String? appointmentId,
    String? fromUserId,
    String? toUserId,
    String? ratingType,
    int? healthConditionRating,
    String? healthConditionComment,
    int? serviceRating,
    String? serviceComment,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Rating(
      id: id ?? this.id,
      appointmentId: appointmentId ?? this.appointmentId,
      fromUserId: fromUserId ?? this.fromUserId,
      toUserId: toUserId ?? this.toUserId,
      ratingType: ratingType ?? this.ratingType,
      healthConditionRating:
          healthConditionRating ?? this.healthConditionRating,
      healthConditionComment:
          healthConditionComment ?? this.healthConditionComment,
      serviceRating: serviceRating ?? this.serviceRating,
      serviceComment: serviceComment ?? this.serviceComment,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
