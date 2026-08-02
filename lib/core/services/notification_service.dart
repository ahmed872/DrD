import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// فئة مساعدة لإدارة البيانات والإشعارات
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  /// إرسال إشعار للطبيب عن مريض يحتاج تقييم
  Future<void> notifyDoctorAboutPendingRating({
    required String doctorId,
    required String patientName,
    required String appointmentId,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'doctorId': doctorId,
        'type': 'pending_patient_rating',
        'patientName': patientName,
        'appointmentId': appointmentId,
        'title': 'تقييم مريض معلق',
        'message': 'لديك مريض ($patientName) ينتظر تقييم حالته الصحية',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      print('✅ تم إرسال إشعار للطبيب');
    } catch (e) {
      print('❌ خطأ في إرسال الإشعار: $e');
    }
  }

  /// إرسال إشعار للمريض عن تقييم الطبيب
  Future<void> notifyPatientAboutDoctorRating({
    required String patientId,
    required String doctorName,
    required int healthRating,
  }) async {
    try {
      final ratingText = _getRatingText(healthRating);
      await _firestore.collection('notifications').add({
        'patientId': patientId,
        'type': 'doctor_rated_patient',
        'doctorName': doctorName,
        'rating': healthRating,
        'title': 'تقييم من الطبيب',
        'message': 'قيّمك الدكتور $doctorName: $ratingText',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      print('✅ تم إرسال إشعار للمريض');
    } catch (e) {
      print('❌ خطأ في إرسال الإشعار: $e');
    }
  }

  /// إرسال إشعار للطبيب عن تقييم المريض
  Future<void> notifyDoctorAboutPatientRating({
    required String doctorId,
    required String patientName,
    required int serviceRating,
  }) async {
    try {
      final ratingText = _getRatingText(serviceRating);
      await _firestore.collection('notifications').add({
        'doctorId': doctorId,
        'type': 'patient_rated_doctor',
        'patientName': patientName,
        'rating': serviceRating,
        'title': 'تقييم من مريض',
        'message': 'قيّمك المريض $patientName: $ratingText',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      print('✅ تم إرسال إشعار للطبيب');
    } catch (e) {
      print('❌ خطأ في إرسال الإشعار: $e');
    }
  }

  /// جلب إشعارات المستخدم
  Stream<List<DocumentSnapshot>> getUserNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('doctorId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((event) => event.docs);
  }

  /// وضع علامة على الإشعار كمقروء
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
    } catch (e) {
      print('❌ خطأ في تحديث الإشعار: $e');
    }
  }

  /// حذف إشعار
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
    } catch (e) {
      print('❌ خطأ في حذف الإشعار: $e');
    }
  }

  /// الحصول على عدد الإشعارات غير المقروءة
  Future<int> getUnreadNotificationsCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('doctorId', isEqualTo: userId)
          .where('read', isEqualTo: false)
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      print('❌ خطأ في عد الإشعارات: $e');
      return 0;
    }
  }

  /// الحصول على نص التقييم بناءً على الرقم
  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return '⭐ سيء جداً';
      case 2:
        return '⭐⭐ سيء';
      case 3:
        return '⭐⭐⭐ متوسط';
      case 4:
        return '⭐⭐⭐⭐ جيد';
      case 5:
        return '⭐⭐⭐⭐⭐ ممتاز';
      default:
        return 'غير محدد';
    }
  }
}

/// فئة مساعدة لتحسين البيانات والمعالجة
class DataValidationService {
  /// التحقق من صحة البيانات الأساسية
  static String? validatePhoneNumber(String phone) {
    if (phone.isEmpty) return 'رقم الهاتف مطلوب';
    if (phone.length < 10) return 'رقم الهاتف قصير جداً';
    if (!RegExp(r'^\+?[0-9]{10,}$').hasMatch(phone)) {
      return 'رقم الهاتف غير صحيح';
    }
    return null;
  }

  static String? validateEmail(String email) {
    if (email.isEmpty) return 'البريد الإلكتروني مطلوب';
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      return 'البريد الإلكتروني غير صحيح';
    }
    return null;
  }

  static String? validateName(String name) {
    if (name.isEmpty) return 'الاسم مطلوب';
    if (name.length < 2) return 'الاسم قصير جداً';
    if (name.length > 100) return 'الاسم طويل جداً';
    return null;
  }

  static String? validatePassword(String password) {
    if (password.isEmpty) return 'كلمة المرور مطلوبة';
    if (password.length < 6) return 'كلمة المرور قصيرة جداً (أقل من 6 أحرف)';
    return null;
  }

  static String? validateComment(String comment) {
    if (comment.isEmpty) return 'التعليق مطلوب';
    if (comment.length < 10) return 'التعليق قصير جداً (أقل من 10 أحرف)';
    if (comment.length > 500) return 'التعليق طويل جداً (أكثر من 500 حرف)';
    return null;
  }
}

/// فئة مساعدة لمعالجة الأخطاء والسجلات
class LoggerService {
  static void logSuccess(String message) {
    print('✅ $message');
  }

  static void logError(String message,
      {dynamic error, StackTrace? stackTrace}) {
    print('❌ $message');
    if (error != null) print('   Error: $error');
    if (stackTrace != null) print('   StackTrace: $stackTrace');
  }

  static void logWarning(String message) {
    print('⚠️  $message');
  }

  static void logInfo(String message) {
    print('ℹ️  $message');
  }
}
