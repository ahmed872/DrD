import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/rating_model.dart';
import '../../domain/repositories/rating_repository.dart';
import '../../domain/entities/rating.dart';
import '../../core/utils/app_logger.dart';

/// تنفيذ Firestore لـ Rating Repository
class FirestoreRatingRepository implements RatingRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _ratingsCollection = 'ratings';

  @override
  Future<Rating?> getRating(String appointmentId, String ratingType) async {
    try {
      final query = await _firestore
          .collection(_ratingsCollection)
          .where('appointmentId', isEqualTo: appointmentId)
          .where('ratingType', isEqualTo: ratingType)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;

      return RatingModel.fromJson(
        query.docs.first.data(),
        query.docs.first.id,
      );
    } catch (e) {
      AppLogger.error('❌ خطأ في الحصول على التقييم: $e');
      return null;
    }
  }

  @override
  Future<void> saveRating(Rating rating) async {
    try {
      final doc = _firestore.collection(_ratingsCollection).doc();
      final model = RatingModel(
        id: doc.id,
        appointmentId: rating.appointmentId,
        fromUserId: rating.fromUserId,
        toUserId: rating.toUserId,
        ratingType: rating.ratingType,
        healthConditionRating: rating.healthConditionRating,
        healthConditionComment: rating.healthConditionComment,
        serviceRating: rating.serviceRating,
        serviceComment: rating.serviceComment,
        createdAt: rating.createdAt,
        updatedAt: rating.updatedAt,
      );

      await doc.set(model.toJson());
      AppLogger.success('✅ تم حفظ التقييم بنجاح');
    } catch (e) {
      AppLogger.error('❌ خطأ في حفظ التقييم: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateRating(Rating rating) async {
    try {
      final query = await _firestore
          .collection(_ratingsCollection)
          .where('appointmentId', isEqualTo: rating.appointmentId)
          .where('ratingType', isEqualTo: rating.ratingType)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        await saveRating(rating);
        return;
      }

      final docId = query.docs.first.id;
      final model = RatingModel(
        id: docId,
        appointmentId: rating.appointmentId,
        fromUserId: rating.fromUserId,
        toUserId: rating.toUserId,
        ratingType: rating.ratingType,
        healthConditionRating: rating.healthConditionRating,
        healthConditionComment: rating.healthConditionComment,
        serviceRating: rating.serviceRating,
        serviceComment: rating.serviceComment,
        createdAt: rating.createdAt,
        updatedAt: DateTime.now(),
      );

      await _firestore
          .collection(_ratingsCollection)
          .doc(docId)
          .update(model.toJson());

      AppLogger.success('✅ تم تحديث التقييم بنجاح');
    } catch (e) {
      AppLogger.error('❌ خطأ في تحديث التقييم: $e');
      rethrow;
    }
  }

  @override
  Future<List<Rating>> getPatientHealthRatings(String patientId) async {
    try {
      final query = await _firestore
          .collection(_ratingsCollection)
          .where('toUserId', isEqualTo: patientId)
          .where('ratingType', isEqualTo: 'doctor_to_patient')
          .orderBy('createdAt', descending: true)
          .get();

      return query.docs
          .map((doc) => RatingModel.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      AppLogger.error('❌ خطأ في الحصول على تقييمات المريض: $e');
      return [];
    }
  }

  @override
  Future<List<Rating>> getDoctorServiceRatings(String doctorId) async {
    try {
      final query = await _firestore
          .collection(_ratingsCollection)
          .where('toUserId', isEqualTo: doctorId)
          .where('ratingType', isEqualTo: 'patient_to_doctor')
          .orderBy('createdAt', descending: true)
          .get();

      return query.docs
          .map((doc) => RatingModel.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      AppLogger.error('❌ خطأ في الحصول على تقييمات الطبيب: $e');
      return [];
    }
  }

  @override
  Future<List<Rating>> getDoctorTodayRatingsNeeded(
    String doctorId,
    DateTime date,
  ) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final query = await _firestore
          .collection(_ratingsCollection)
          .where('fromUserId', isEqualTo: doctorId)
          .where('ratingType', isEqualTo: 'doctor_to_patient')
          .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
          .where('createdAt', isLessThan: endOfDay)
          .where('healthConditionRating', isEqualTo: null)
          .get();

      return query.docs
          .map((doc) => RatingModel.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      AppLogger.error('❌ خطأ في الحصول على التقييمات المطلوبة: $e');
      return [];
    }
  }

  @override
  Future<bool> isPatientNeedsRating(String appointmentId) async {
    try {
      final existing = await getRating(appointmentId, 'doctor_to_patient');
      return existing == null || !existing.isComplete;
    } catch (e) {
      AppLogger.error('❌ خطأ في التحقق من التقييم: $e');
      return false;
    }
  }

  @override
  Future<void> deleteRating(String appointmentId, String ratingType) async {
    try {
      final query = await _firestore
          .collection(_ratingsCollection)
          .where('appointmentId', isEqualTo: appointmentId)
          .where('ratingType', isEqualTo: ratingType)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        await _firestore
            .collection(_ratingsCollection)
            .doc(query.docs.first.id)
            .delete();
        AppLogger.success('✅ تم حذف التقييم بنجاح');
      }
    } catch (e) {
      AppLogger.error('❌ خطأ في حذف التقييم: $e');
      rethrow;
    }
  }
}
