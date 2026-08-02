import 'package:flutter/material.dart';

/// خدمة مصادقة محلية للتطوير بدون Firebase
class LocalAuthService extends ChangeNotifier {
  String? _userId;
  Map<String, dynamic>? _userData;
  String? _errorMessage;
  bool _isLoading = false;
  String? _pendingPhoneNumber;
  String? _generatedOTP;
  DateTime? _otpExpiryTime;

  String? get userId => _userId;
  Map<String, dynamic>? get userData => _userData;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _userId != null;
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

  /// حسابات تجريبية محلية مع أرقام جوال مصرية
  static const Map<String, Map<String, String>> _demoAccounts = {
    '201001234567': {
      'password': '123456',
      'name': 'محمد علي',
      'role': 'patient',
      'phone': '201001234567',
    },
    '201005555555': {
      'password': '123456',
      'name': 'د. فاطمة محمد',
      'role': 'doctor',
      'phone': '201005555555',
    },
    '01001234567': {
      'password': '123456',
      'name': 'محمد علي',
      'role': 'patient',
      'phone': '01001234567',
    },
    '01005555555': {
      'password': '123456',
      'name': 'د. فاطمة محمد',
      'role': 'doctor',
      'phone': '01005555555',
    },
  };

  /// إرسال OTP إلى رقم الجوال
  Future<bool> sendOTP(String phoneNumber) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // محاكاة تأخير الشبكة
      await Future.delayed(const Duration(milliseconds: 1200));

      // تنظيف الرقم
      String cleanedPhone = _normalizePhoneNumber(phoneNumber);

      // التحقق من أن الرقم موجود أو جديد
      // (في الإنتاج سيتم التحقق عبر Firebase)

      // توليد رمز OTP عشوائي
      _generatedOTP = _generateOTP();
      _otpExpiryTime = DateTime.now().add(const Duration(minutes: 10));
      _pendingPhoneNumber = cleanedPhone;

      // في الإنتاج: إرسال OTP عبر Firebase SMS
      print('🔐 OTP Code: $_generatedOTP (هذا للاختبار فقط)');
      print('📱 Sending to: $cleanedPhone');

      _isLoading = false;
      _errorMessage = 'تم إرسال رمز التحقق إلى رقمك ✅';
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'خطأ في إرسال رمز التحقق: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// التحقق من OTP وتسجيل الدخول
  Future<bool> verifyOTP(String phoneNumber, String otp) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // محاكاة تأخير الشبكة
      await Future.delayed(const Duration(milliseconds: 800));

      String cleanedPhone = _normalizePhoneNumber(phoneNumber);

      // التحقق من انتهاء الصلاحية
      if (_otpExpiryTime == null || DateTime.now().isAfter(_otpExpiryTime!)) {
        _errorMessage = 'انتهت صلاحية الرمز. الرجاء طلب رمز جديد';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // التحقق من الرمز
      if (_generatedOTP != otp) {
        _errorMessage = 'رمز التحقق غير صحيح';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // البحث عن الحساب
      if (!_demoAccounts.containsKey(cleanedPhone)) {
        _errorMessage = 'المستخدم غير موجود. الرجاء التسجيل أولاً';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final account = _demoAccounts[cleanedPhone]!;

      // تسجيل دخول ناجح
      _userId = cleanedPhone;
      _userData = {
        'phone': cleanedPhone,
        'name': account['name'],
        'role': account['role'],
      };

      _generatedOTP = null;
      _otpExpiryTime = null;
      _pendingPhoneNumber = null;

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'خطأ في التحقق: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// تسجيل حساب جديد برقم جوال
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

      // محاكاة تأخير الشبكة
      await Future.delayed(const Duration(milliseconds: 800));

      String cleanedPhone = _normalizePhoneNumber(phoneNumber);
      String cleanedEmail = email?.trim().toLowerCase() ?? '';

      // التحقق من الرقم المكرر
      if (_demoAccounts.containsKey(cleanedPhone)) {
        _errorMessage = 'رقم الجوال مستخدم بالفعل';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // التحقق من البيانات
      if (name.isEmpty) {
        _errorMessage = 'الاسم مطلوب';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (password.length < 6) {
        _errorMessage = 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // التحقق من صحة البريد الإلكتروني (إن وُجد)
      if (cleanedEmail.isNotEmpty && !_isValidEmail(cleanedEmail)) {
        _errorMessage = 'البريد الإلكتروني غير صحيح';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // تسجيل ناجح
      _userId = cleanedPhone;
      _userData = {
        'phone': cleanedPhone,
        'email': cleanedEmail,
        'name': name,
        'role': role,
        if (birthDate != null) 'birthDate': birthDate.toIso8601String(),
        if (gender != null) 'gender': gender,
      };

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'خطأ في التسجيل: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// تسجيل الخروج
  Future<void> logout() async {
    _userId = null;
    _userData = null;
    _errorMessage = null;
    _generatedOTP = null;
    _otpExpiryTime = null;
    _pendingPhoneNumber = null;
    notifyListeners();
  }

  /// تحديث بيانات المريض (Profile Update)
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

  /// تنظيف وتحويل رقم الجوال إلى صيغة موحدة (مصري)
  String _normalizePhoneNumber(String phone) {
    // إزالة جميع الأحرف غير الأرقام
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');

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

  /// توليد رمز OTP عشوائي (6 أرقام)
  String _generateOTP() {
    return (100000 + DateTime.now().microsecond % 900000).toString();
  }

  bool _isValidEmail(String email) {
    // Regex بسيط للتحقق من صحة البريد الإلكتروني
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }
}
