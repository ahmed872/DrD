import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/app_logger.dart';

/// خدمة Firebase للمصادقة وتخزين البيانات
class FirebaseAuthService extends ChangeNotifier {
  FirebaseAuthService() {
    // الاستماع لحالة المصادقة بدل قراءتها مرة واحدة.
    //
    // على الويب تحديداً هذا هو الفارق بين أن يبقى المستخدم مسجّل الدخول بعد
    // تحديث الصفحة وأن يُقذف لشاشة تسجيل الدخول في كل مرة: Firebase يستعيد
    // الجلسة من IndexedDB بشكل غير متزامن بعد إقلاع التطبيق، فالقراءة
    // اللحظية وقت الإقلاع ترى `null` دائماً.
    _authSubscription = _firebaseAuth.authStateChanges().listen(
          _onAuthStateChanged,
          onError: (Object e) =>
              AppLogger.error('خطأ في مراقبة حالة الدخول', e),
        );
  }

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSubscription;

  String? _userId;
  Map<String, dynamic>? _userData;
  String? _errorMessage;
  bool _isLoading = false;
  bool _emailVerified = false;

  /// تصبح `true` بعد أول رد من Firebase عن حالة الجلسة.
  ///
  /// شاشة البداية تنتظرها حتى لا تومض شاشة تسجيل الدخول للحظة قبل استعادة
  /// جلسة مستخدم مسجَّل بالفعل.
  bool _sessionRestored = false;
  bool get sessionRestored => _sessionRestored;

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _onAuthStateChanged(User? user) async {
    if (user == null) {
      _userId = null;
      _userData = null;
      _emailVerified = false;
    } else {
      _userId = user.uid;
      _emailVerified = true;
      try {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) _userData = doc.data();
      } catch (e) {
        AppLogger.error('تعذّر تحميل بيانات المستخدم', e);
      }
    }
    _sessionRestored = true;
    notifyListeners();
  }

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

  /// إعادة تحميل بيانات المستخدم الحالي من Firestore.
  ///
  /// استعادة الجلسة نفسها صارت تلقائية عبر المستمع في المُنشئ؛ هذه الدالة
  /// للتحديث اليدوي فقط. الصيغة القديمة كانت تنتظر
  /// `authStateChanges().first` وهو انتظار قد لا ينتهي أبداً لو تعذّر
  /// الاتصال بـ Firebase، فتتجمّد شاشة البداية.
  Future<void> checkSession() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;
    await _onAuthStateChanged(user);
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

      // التسجيل الذاتي للمرضى فقط.
      //
      // الفحص هنا وليس بعد إنشاء الحساب: `firestore.rules` ترفض كتابة مستند
      // بدور غير `patient`، فلو مررنا لأنشأنا حساب مصادقة بلا مستند مقابل —
      // حساب يتيم لا يستطيع صاحبه الدخول به ولا التسجيل من جديد بنفس البريد.
      // الأطباء يُرقَّون إدارياً عبر `scripts/promote_to_doctor.js`.
      if (role != 'patient') {
        _errorMessage = 'حسابات الأطباء تُنشأ من إدارة التطبيق، تواصل معنا';
        _isLoading = false;
        notifyListeners();
        return false;
      }

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

      // التحقق من عدم استخدام رقم الجوال — قراءة مستند واحد بمعرّف معروف،
      // بدل الاستعلام على المجموعة كلها.
      //
      // تكرار البريد الإلكتروني لا يُفحص هنا عمداً: Firebase Auth نفسه يرفضه
      // بـ `email-already-in-use`، وهو فحص موثوق لأنه يجري على الخادم — بينما
      // الفحص المسبق من العميل كان يتطلّب قراءة عامة لكل حسابات المستخدمين.
      final phoneIndexDoc =
          await _firestore.collection('phone_index').doc(cleanedPhone).get();

      if (phoneIndexDoc.exists) {
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

      // فهرس الجوال — هو ما يسمح بتسجيل الدخول بالرقم لاحقاً دون فتح
      // مجموعة `users` للقراءة العامة.
      await _firestore.collection('phone_index').doc(cleanedPhone).set({
        'uid': firebaseUser.uid,
        'email': cleanedEmail,
        'createdAt': FieldValue.serverTimestamp(),
      });

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

      // ترجمة رقم الجوال إلى بريد إلكتروني عبر فهرس مخصّص.
      //
      // الصيغة السابقة كانت تستعلم على مجموعة `users` كاملة قبل تسجيل الدخول،
      // وهو ما يفرض السماح بالقراءة العامة لكل مستندات المستخدمين (الأسماء،
      // الأرقام، تواريخ الميلاد، الأدوار). مجموعة `phone_index` تحتوي على
      // الحد الأدنى فقط — البريد ومعرّف المستخدم — ومعرّف مستندها هو رقم
      // الجوال، فلا يمكن تصفّحها إلا لمن يعرف الرقم أصلاً.
      final email = await _resolveEmailForPhone(cleanedPhone);

      if (email == null || email.isEmpty) {
        // نفس رسالة كلمة المرور الخاطئة عمداً، حتى لا تكشف الواجهة أي
        // الأرقام مسجَّلة لدينا وأيها لا.
        _errorMessage = 'رقم الجوال أو كلمة المرور غير صحيحة';
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

        // بيانات المستخدم تُقرأ الآن *بعد* المصادقة، فتستطيع قواعد الأمان
        // حصر القراءة على صاحب المستند وحده.
        _userId = firebaseUser.uid;
        _emailVerified = true; // تعيينها مفعّلة تلقائياً

        final userDoc =
            await _firestore.collection('users').doc(firebaseUser.uid).get();
        _userData = userDoc.data();

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

      AppLogger.info('📧 Password reset email sent to: $cleanedEmail');
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

  /// تحديث بيانات المريض وحفظها في Firestore.
  ///
  /// كانت هذه الدالة تُعدّل النسخة المحفوظة في الذاكرة فقط وتستدعي
  /// `notifyListeners()`، فتظهر البيانات محدَّثة على الشاشة بينما لم يُكتب
  /// شيء في قاعدة البيانات — ويعود الاسم القديم عند أول تسجيل دخول جديد.
  /// الآن الكتابة تسبق تحديث الذاكرة، وإن فشلت لا تتغير الواجهة.
  Future<bool> updatePatientProfile({
    String? name,
    String? gender,
    DateTime? birthDate,
  }) async {
    if (_userId == null || _userData == null) {
      _errorMessage = 'لا يوجد مستخدم مسجل دخول';
      notifyListeners();
      return false;
    }

    final updates = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) {
      updates['name'] = name.trim();
    }
    if (gender != null) updates['gender'] = gender;
    if (birthDate != null) {
      updates['birthDate'] = birthDate.toIso8601String();
    }

    if (updates.isEmpty) return true;

    try {
      _isLoading = true;
      notifyListeners();

      updates['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('users').doc(_userId).update(updates);

      // `serverTimestamp` قيمة حارسة لا معنى لها محلياً، فلا تُنسخ للذاكرة.
      updates.remove('updatedAt');
      _userData!.addAll(updates);

      _isLoading = false;
      _errorMessage = 'تم حفظ البيانات بنجاح ✅';
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.error('فشل حفظ بيانات المريض', e);
      _isLoading = false;
      _errorMessage = 'تعذّر حفظ البيانات، تأكد من اتصالك بالإنترنت';
      notifyListeners();
      return false;
    }
  }

  // ========== Helper Functions ==========

  /// إيجاد البريد الإلكتروني المرتبط برقم جوال.
  ///
  /// المصدر الوحيد هو `phone_index`: مستند واحد معرّفه رقم الجوال، يحوي
  /// البريد والمعرّف فقط.
  ///
  /// كان هنا مسار احتياطي يستعلم على مجموعة `users` كاملة قبل المصادقة عند
  /// غياب المدخل. حُذف لسببين: أنه يتطلب فتح قراءة `users` لغير المسجَّلين —
  /// أي كشف كل الأسماء والأرقام وتواريخ الميلاد — وأن قواعد الأمان الحالية
  /// ترفضه أصلاً، فهو كود ميت يوحي بأمان هجرة غير موجود.
  ///
  /// هجرة الحسابات القديمة صارت خطوة صريحة تُشغَّل مرة واحدة من Admin SDK:
  ///   node scripts/backfill_phone_index.js --apply
  /// وهي **شرط** قبل نشر هذه النسخة، وإلا تعذّر على الحسابات القديمة الدخول.
  Future<String?> _resolveEmailForPhone(String cleanedPhone) async {
    try {
      final indexDoc =
          await _firestore.collection('phone_index').doc(cleanedPhone).get();
      final indexedEmail = indexDoc.data()?['email'] as String?;
      if (indexedEmail != null && indexedEmail.isNotEmpty) {
        return indexedEmail;
      }
      return null;
    } catch (e) {
      AppLogger.error('تعذّرت قراءة فهرس الجوال', e);
      return null;
    }
  }

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
