import '../../domain/entities/rating.dart';

/// واجهة Firestore Repository للتقييمات
abstract class RatingRepository {
  /// الحصول على تقييم معين
  Future<Rating?> getRating(String appointmentId, String ratingType);

  /// حفظ تقييم جديد
  Future<void> saveRating(Rating rating);

  /// تحديث تقييم موجود
  Future<void> updateRating(Rating rating);

  /// الحصول على جميع تقييمات مريض معين (من الطبيب)
  Future<List<Rating>> getPatientHealthRatings(String patientId);

  /// الحصول على جميع تقييمات طبيب معين (من المرضى)
  Future<List<Rating>> getDoctorServiceRatings(String doctorId);

  /// الحصول على تقييمات الطبيب للمرضى في تاريخ معين
  Future<List<Rating>> getDoctorTodayRatingsNeeded(
      String doctorId, DateTime date);

  /// معرفة ما إذا كان المريض بحاجة إلى تقييم من الطبيب
  Future<bool> isPatientNeedsRating(String appointmentId);

  /// حذف تقييم
  Future<void> deleteRating(String appointmentId, String ratingType);
}
