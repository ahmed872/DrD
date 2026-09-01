// ⚠️ ميزة مكتملة لكنها **غير موصولة بأي مسار تنقّل** (مراجعة المرحلة 5ب).
//
// منظومة `ratings` غير منظومة `reviews`:
//   - `reviews` = المراجعة العلنية للطبيب (نجوم + تعليق) التي يكتبها المريض
//     من «مواعيدي». صارت في المرحلة 4 من الخادم وحده (`functions/reviews.js`).
//   - `ratings` = تقييم خاص ثنائي الاتجاه: `patient_to_doctor` لجودة الخدمة،
//     و`doctor_to_patient` **للحالة الصحية للمريض** — أي بيانات طبية.
//
// الحزمة كاملة (كيان + مستودع + مزوّد + شاشتان + عناصر عرض) وقواعد
// Firestore تغطّي المجموعة منذ المرحلة 0، لكن لا شاشة تفتح هاتين الشاشتين.
// لم تُحذف في المرحلة 5ب عن قصد: حذف ميزة مصمَّمة ليس من عمل مرحلة UX،
// ووصلها يحتاج قراراً منتجياً أولاً (من يرى التقييم الصحي؟ ومتى؟)، ثم
// تشديد قاعدة الإنشاء في `firestore.rules` — فهي اليوم تسمح لأي مستخدم
// مسجَّل بكتابة `doctor_to_patient` باسمه دون التحقق من أنه طبيب فعلاً.
// التفاصيل في تقرير المرحلة 5ب، القسمان «م» و«ت».
//
// لهذا السبب أيضاً بقيت ألوانها الثابتة كما هي: لا يمكن التحقق بصرياً من
// شاشة لا تُفتح، وتعديلها بلا اختبار يضيف مخاطرة بلا فائدة.
import 'package:flutter/material.dart';
import '../../domain/entities/rating.dart';
import '../../domain/repositories/rating_repository.dart';
import '../../data/repositories/firestore_rating_repository.dart';
import '../../core/utils/app_logger.dart';

/// Provider لإدارة حالة التقييمات
class RatingProvider with ChangeNotifier {
  final RatingRepository _repository = FirestoreRatingRepository();

  Map<String, Rating> _ratings = {}; // appointmentId -> Rating
  List<Rating> _patientRatings = [];
  List<Rating> _doctorRatings = [];
  List<Rating> _pendingRatings = [];

  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Rating> get patientRatings => _patientRatings;
  List<Rating> get doctorRatings => _doctorRatings;
  List<Rating> get pendingRatings => _pendingRatings;
  int get pendingRatingsCount => _pendingRatings.length;

  /// الحصول على تقييم معين
  Rating? getRating(String appointmentId, String ratingType) {
    final key = '$appointmentId-$ratingType';
    return _ratings[key];
  }

  /// جلب تقييم من قاعدة البيانات
  Future<Rating?> fetchRating(String appointmentId, String ratingType) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final rating = await _repository.getRating(appointmentId, ratingType);

      if (rating != null) {
        final key = '$appointmentId-$ratingType';
        _ratings[key] = rating;
      }

      _isLoading = false;
      notifyListeners();
      return rating;
    } catch (e) {
      _errorMessage = 'خطأ في جلب التقييم: $e';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// حفظ أو تحديث تقييم الطبيب للمريض
  Future<bool> ratePatientHealth({
    required String appointmentId,
    required String doctorId,
    required String patientId,
    required int healthRating,
    required String healthComment,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // التحقق من صحة البيانات
      if (appointmentId.isEmpty || doctorId.isEmpty || patientId.isEmpty) {
        _errorMessage = 'البيانات غير كاملة';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (healthRating < 1 || healthRating > 5) {
        _errorMessage = 'التقييم يجب أن يكون بين 1 و 5';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (healthComment.trim().isEmpty) {
        _errorMessage = 'يجب إدخال وصف الحالة الصحية';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // جلب التقييم القديم إن وجد
      final existing = await _repository.getRating(
        appointmentId,
        'doctor_to_patient',
      );

      final rating = Rating(
        id: existing?.id ?? '',
        appointmentId: appointmentId,
        fromUserId: doctorId,
        toUserId: patientId,
        ratingType: 'doctor_to_patient',
        healthConditionRating: healthRating,
        healthConditionComment: healthComment,
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (existing == null) {
        await _repository.saveRating(rating);
      } else {
        await _repository.updateRating(rating);
      }

      final key = '$appointmentId-doctor_to_patient';
      _ratings[key] = rating;

      _isLoading = false;
      _errorMessage = '✅ تم حفظ التقييم بنجاح';
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'خطأ في حفظ التقييم: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// حفظ أو تحديث تقييم المريض للطبيب
  Future<bool> rateDoctorService({
    required String appointmentId,
    required String patientId,
    required String doctorId,
    required int serviceRating,
    required String serviceComment,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // التحقق من صحة البيانات
      if (appointmentId.isEmpty || patientId.isEmpty || doctorId.isEmpty) {
        _errorMessage = 'البيانات غير كاملة';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (serviceRating < 1 || serviceRating > 5) {
        _errorMessage = 'التقييم يجب أن يكون بين 1 و 5';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (serviceComment.trim().isEmpty) {
        _errorMessage = 'يجب إدخال ملاحظتك عن الخدمة';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // جلب التقييم القديم إن وجد
      final existing = await _repository.getRating(
        appointmentId,
        'patient_to_doctor',
      );

      final rating = Rating(
        id: existing?.id ?? '',
        appointmentId: appointmentId,
        fromUserId: patientId,
        toUserId: doctorId,
        ratingType: 'patient_to_doctor',
        serviceRating: serviceRating,
        serviceComment: serviceComment,
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (existing == null) {
        await _repository.saveRating(rating);
      } else {
        await _repository.updateRating(rating);
      }

      final key = '$appointmentId-patient_to_doctor';
      _ratings[key] = rating;

      _isLoading = false;
      _errorMessage = '✅ تم حفظ تقييمك بنجاح';
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'خطأ في حفظ التقييم: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// جلب جميع تقييمات المريض من الأطباء
  Future<void> fetchPatientRatings(String patientId) async {
    try {
      _isLoading = true;
      notifyListeners();

      _patientRatings = await _repository.getPatientHealthRatings(patientId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'خطأ في جلب التقييمات: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// جلب جميع تقييمات الطبيب من المرضى
  Future<void> fetchDoctorRatings(String doctorId) async {
    try {
      _isLoading = true;
      notifyListeners();

      _doctorRatings = await _repository.getDoctorServiceRatings(doctorId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'خطأ في جلب التقييمات: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// جلب التقييمات المطلوبة للطبيب (المرضى الذين لم يتم تقييمهم)
  Future<void> fetchPendingRatings(String doctorId) async {
    try {
      _isLoading = true;
      notifyListeners();

      _pendingRatings = await _repository.getDoctorTodayRatingsNeeded(
        doctorId,
        DateTime.now(),
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'خطأ في جلب التقييمات المطلوبة: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// معرفة عدد تقييمات الطبيب المعلقة
  Future<int> getPendingRatingsCount(String doctorId) async {
    try {
      _pendingRatings = await _repository.getDoctorTodayRatingsNeeded(
        doctorId,
        DateTime.now(),
      );
      return _pendingRatings.length;
    } catch (e) {
      AppLogger.error('❌ خطأ في حساب التقييمات المعلقة: $e');
      return 0;
    }
  }

  /// حساب متوسط تقييم المريض
  double getPatientAverageRating() {
    if (_patientRatings.isEmpty) return 0;

    final ratings = _patientRatings
        .where((r) => r.healthConditionRating != null)
        .map((r) => r.healthConditionRating!.toDouble())
        .toList();

    if (ratings.isEmpty) return 0;
    return ratings.reduce((a, b) => a + b) / ratings.length;
  }

  /// حساب متوسط تقييم الطبيب
  double getDoctorAverageRating() {
    if (_doctorRatings.isEmpty) return 0;

    final ratings = _doctorRatings
        .where((r) => r.serviceRating != null)
        .map((r) => r.serviceRating!.toDouble())
        .toList();

    if (ratings.isEmpty) return 0;
    return ratings.reduce((a, b) => a + b) / ratings.length;
  }

  /// حذف تقييم
  Future<bool> deleteRating(String appointmentId, String ratingType) async {
    try {
      await _repository.deleteRating(appointmentId, ratingType);

      final key = '$appointmentId-$ratingType';
      _ratings.remove(key);

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'خطأ في حذف التقييم: $e';
      return false;
    }
  }

  /// مسح الأخطاء
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// مسح الحالة
  void clear() {
    _ratings.clear();
    _patientRatings.clear();
    _doctorRatings.clear();
    _pendingRatings.clear();
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }
}
