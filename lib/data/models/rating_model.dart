import '../../domain/entities/rating.dart';

/// نموذج البيانات للتقييم - يتم تحويله من/إلى JSON من Firebase
class RatingModel extends Rating {
  const RatingModel({
    required String id,
    required String appointmentId,
    required String fromUserId,
    required String toUserId,
    required String ratingType,
    int? healthConditionRating,
    String? healthConditionComment,
    int? serviceRating,
    String? serviceComment,
    required DateTime createdAt,
    DateTime? updatedAt,
  }) : super(
          id: id,
          appointmentId: appointmentId,
          fromUserId: fromUserId,
          toUserId: toUserId,
          ratingType: ratingType,
          healthConditionRating: healthConditionRating,
          healthConditionComment: healthConditionComment,
          serviceRating: serviceRating,
          serviceComment: serviceComment,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

  /// تحويل من Firestore JSON
  factory RatingModel.fromJson(Map<String, dynamic> json, String docId) {
    return RatingModel(
      id: docId,
      appointmentId: json['appointmentId'] ?? '',
      fromUserId: json['fromUserId'] ?? '',
      toUserId: json['toUserId'] ?? '',
      ratingType: json['ratingType'] ?? '',
      healthConditionRating: json['healthConditionRating'],
      healthConditionComment: json['healthConditionComment'],
      serviceRating: json['serviceRating'],
      serviceComment: json['serviceComment'],
      createdAt: json['createdAt'] is String
          ? DateTime.parse(json['createdAt'])
          : (json['createdAt']?.toDate() ?? DateTime.now()),
      updatedAt: json['updatedAt'] is String
          ? DateTime.parse(json['updatedAt'])
          : json['updatedAt']?.toDate(),
    );
  }

  /// تحويل إلى Firestore JSON
  Map<String, dynamic> toJson() {
    return {
      'appointmentId': appointmentId,
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'ratingType': ratingType,
      'healthConditionRating': healthConditionRating,
      'healthConditionComment': healthConditionComment,
      'serviceRating': serviceRating,
      'serviceComment': serviceComment,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  /// تحديث التقييم مع إرجاع نموذج جديد
  RatingModel updateWith({
    int? healthConditionRating,
    String? healthConditionComment,
    int? serviceRating,
    String? serviceComment,
  }) {
    return RatingModel(
      id: id,
      appointmentId: appointmentId,
      fromUserId: fromUserId,
      toUserId: toUserId,
      ratingType: ratingType,
      healthConditionRating:
          healthConditionRating ?? this.healthConditionRating,
      healthConditionComment:
          healthConditionComment ?? this.healthConditionComment,
      serviceRating: serviceRating ?? this.serviceRating,
      serviceComment: serviceComment ?? this.serviceComment,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
