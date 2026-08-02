import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// خدمة Firebase للمصادقة وتخزين البيانات
class FirebaseAuthService extends ChangeNotifier {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _userId;
  Map<String, dynamic>? _userData;
  String? _errorMessage;
  bool _isLoading = false;
  bool _emailVerified = false;

  String? get userId => _userId;
  Map<String, dynamic>? get userData => _userData;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _userId != null;
  bool get emailVerified => _emailVerified;
  String? get userRole => _userData?['role'];
  String? get userName => _userData?['name'];
  String? get userPhone => _userData?['phone'];
  String? get userGender => _userData?['gender'];

  DateTime? get userBirthDate {
    final dateStr = _userData?['birthDate'];
    if (dateStr != null) {
      return DateTime.tryParse(dateStr);
    }
    return null;
  }

  /// التسجيل (إنشاء حساب جديد) مع Firebase Auth و Email Verification
  Future<void> checkSession() async {
    try {
      final user = await _firebaseAuth.authStateChanges().first;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          _userId = user.uid;
          _userData = doc.data();
          _emailVerified = true;
          notifyListeners();
        }
      }
    } catch (e) {
      print('Error checking session: $e');
    }
  }

  Future<bool> signupWithPhone(
    String phoneNumber,
    String password,
    String name,
    String role, {
    DateTime? birthDate,
    String? gender,
    String? email,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      String cleanedPhone = normalizePhoneNumber(phoneNumber);
      String cleanedEmail = email?.trim().toLowerCase() ?? '';

      // التحقق من صحة البريد الإلكتروني
      if (cleanedEmail.isEmpty) {
        _errorMessage = 'البريد الإلكتروني مطلوب';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (!_isValidEmail(cleanedEmail)) {
        _errorMessage = 'البريد الإلكتروني غير صحيح';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // التحقق من عدم وجود المستخدم بالفعل (بالبريد الإلكتروني)
      final existingEmail = await _firestore
          .collection('users')
          .where('email', isEqualTo: cleanedEmail)
          .get();

      if (existingEmail.docs.isNotEmpty) {
        _errorMessage = 'البريد الإلكتروني مستخدم بالفعل';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // التحقق من عدم وجود المستخدم بالفعل (برقم الجوال)
      final existingPhone = await _firestore
          .collection('users')
          .where('phone', isEqualTo: cleanedPhone)
          .get();

      if (existingPhone.docs.isNotEmpty) {
        _errorMessage = 'رقم الجوال مستخدم بالفعل';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // إنشاء حساب في Firebase Authentication
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: cleanedEmail,
        password: password,
      );

      final firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        _errorMessage = 'فشل إنشاء الحساب';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // تم تعطيل إرسال رسالة تفعيل الإيميل بناءً على طلبك
      // await firebaseUser.sendEmailVerification();

      // حفظ بيانات المستخدم في Firestore
      final newUser = {
        'phone': cleanedPhone,
        'email': cleanedEmail,
        'name': name,
        'role': role,
        'birthDate': birthDate?.toIso8601String(),
        'gender': gender,
        'emailVerified': true, // تعيينها مفعّلة تلقائياً
        'createdAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('users').doc(firebaseUser.uid).set(newUser);

      _userId = firebaseUser.uid;
      _userData = newUser;
      _emailVerified = true;

      _isLoading = false;
      _errorMessage = 'تم إنشاء الحساب! تحقق من بريدك الإلكتروني لتفعيله ✅';
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'خطأ في التسجيل: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// تسجيل الدخول برقم وكلمة سر مع التحقق من البريد الإلكتروني
  Future<bool> login(String phoneNumber, String password) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      String cleanedPhone = normalizePhoneNumber(phoneNumber);

      // البحث عن المستخدم برقم الجوال
      final userQuery = await _firestore
          .collection('users')
          .where('phone', isEqualTo: cleanedPhone)
          .get();

      if (userQuery.docs.isEmpty) {
        _errorMessage = 'رقم الجوال أو كلمة المرور غير صحيحة';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final userData = userQuery.docs.first.data();
      final email = userData['email'] as String?;

      if (email == null || email.isEmpty) {
        _errorMessage = 'البريد الإلكتروني غير محفوظ';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // محاولة تسجيل الدخول عبر Firebase Authentication
      try {
        final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        final firebaseUser = userCredential.user;

        if (firebaseUser == null) {
          _errorMessage = 'فشل تسجيل الدخول';
          _isLoading = false;
          notifyListeners();
          return false;
        }

        // تم إلغاء شرط التحقق من الإيميل
        /*
        if (!firebaseUser.emailVerified) {
          _errorMessage =
              '⚠️ يجب تفعيل بريدك الإلكتروني أولاً!\nتحقق من رسالة البريد المرسلة إليك.';
          await _firebaseAuth.signOut();
          _isLoading = false;
          notifyListeners();
          return false;
        }
        */

        // تحديث بيانات المستخدم
        _userId = firebaseUser.uid;
        _userData = userData;
        _emailVerified = true; // تعيينها مفعّلة تلقائياً

        _isLoading = false;
        notifyListeners();
        return true;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' ||
            e.code == 'wrong-password' ||
            e.code == 'invalid-credential') {
          _errorMessage = 'رقم الجوال أو كلمة المرور غير صحيحة';
        } else if (e.code == 'user-disabled') {
          _errorMessage = 'تم تعطيل هذا الحساب';
        } else if (e.code == 'invalid-email') {
          _errorMessage = 'صيغة البريد الإلكتروني غير صحيحة';
        } else {
          _errorMessage =
              'خطأ الدخول: يرجى التأكد من صحة البيانات'; // رسالة أبسط بدون أكواد انجليزي
        }
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'خطأ في تسجيل الدخول: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// تحديث حالة المستخدم من Firebase (للتحقق من emailVerified)
  Future<bool> reloadAndCheckEmailVerification() async {
    try {
      _isLoading = true;
      notifyListeners();

      final user = _firebaseAuth.currentUser;

      if (user == null) {
        _errorMessage = 'المستخدم غير موجود';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // إعادة تحميل بيانات المستخدم من Firebase
      await user.reload();

      // التحقق من تفعيل البريد
      _emailVerified = user.emailVerified;

      if (_emailVerified) {
        // تحديث Firestore ليعكس الحالة الجديدة
        await _firestore.collection('users').doc(user.uid).update({
          'emailVerified': true,
        });

        if (_userData != null) {
          _userData!['emailVerified'] = true;
        }

        _errorMessage = 'تم تفعيل البريد الإلكتروني بنجاح! ✅';
      }

      _isLoading = false;
      notifyListeners();
      return _emailVerified;
    } catch (e) {
      _errorMessage = 'خطأ في التحقق: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// إعادة إرسال رسالة تفعيل الإيميل
  Future<bool> resendEmailVerification() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final user = _firebaseAuth.currentUser;

      if (user == null) {
        _errorMessage = 'المستخدم غير موجود';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (user.emailVerified) {
        _errorMessage = 'البريد الإلكتروني مفعل بالفعل';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await user.sendEmailVerification();

      _errorMessage = 'تم إعادة إرسال رسالة التفعيل ✅';
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'خطأ في إعادة الإرسال: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// إرسال لينك تغيير كلمة المرور عبر Firebase
  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      String cleanedEmail = email.trim().toLowerCase();

      // التحقق من صحة البريد الإلكتروني
      if (!_isValidEmail(cleanedEmail)) {
        _errorMessage = 'البريد الإلكتروني غير صحيح';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // إرسال لينك تغيير كلمة المرور من Firebase
      await _firebaseAuth.sendPasswordResetEmail(email: cleanedEmail);

      _isLoading = false;
      _errorMessage =
          'تم إرسال لينك تغيير كلمة المرور إلى $cleanedEmail ✅\nتحقق من بريدك الإلكتروني';
      notifyListeners();

      print('📧 Password reset email sent to: $cleanedEmail');
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' ||
          e.code == 'invalid-email' ||
          e.code == 'invalid-credential') {
        _errorMessage = 'البريد الإلكتروني غير مسجل أو غير صحيح';
      } else {
        _errorMessage = 'هناك خطأ ما، حاول مرة أخرى'; // بدل الرسائل الأجنبية
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'خطأ في إرسال البريد: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// تسجيل الخروج

  Future<void> logout() async {
    await _firebaseAuth.signOut();
    _userId = null;
    _userData = null;
    _emailVerified = false;
    notifyListeners();
  }

  /// تحديث كلمة المرور
  Future<bool> updatePassword(String email, String newPassword) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      String cleanedEmail = email.trim().toLowerCase();

      final currentUser = _firebaseAuth.currentUser;
      if (currentUser != null && currentUser.email == cleanedEmail) {
        await currentUser.updatePassword(newPassword);
        _isLoading = false;
        _errorMessage = 'تم تحديث كلمة المرور بنجاح';
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'يجب تسجيل الدخول بنفس الحساب لتحديث كلمة المرور';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'خطأ في تحديث كلمة المرور: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// تحديث بيانات المريض
  Future<bool> updatePatientProfile({
    String? name,
    String? gender,
    DateTime? birthDate,
  }) async {
    try {
      if (_userData == null) {
        _errorMessage = 'لا يوجد مستخدم مسجل دخول';
        return false;
      }

      if (name != null && name.isNotEmpty) {
        _userData!['name'] = name;
      }

      if (gender != null) {
        _userData!['gender'] = gender;
      }

      if (birthDate != null) {
        _userData!['birthDate'] = birthDate.toIso8601String();
      }

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'خطأ في تحديث البيانات: $e';
      return false;
    }
  }

  // ========== Helper Functions ==========

  String normalizePhoneNumber(String phone) {
    // إزالة المسافات والشُرط والـ +
    String cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');

    // إزالة الأصفار الزائدة من البداية
    // 00201... → 201...
    // 01... → 201...
    // 0201... → 201...
    if (cleaned.startsWith('00')) {
      cleaned = cleaned.substring(2); // إزالة 00
    }
    if (cleaned.startsWith('0')) {
      cleaned = cleaned.substring(1); // إزالة 0 الأول
    }

    // التأكد من وجود رمز الدولة 20
    if (!cleaned.startsWith('20')) {
      cleaned = '20$cleaned';
    }

    return cleaned;
  }

  bool _isValidEmail(String email) {
    // Regex بسيط للتحقق من صحة البريد الإلكتروني
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }
}
