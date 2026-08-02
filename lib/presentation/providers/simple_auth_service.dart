import 'package:flutter/material.dart';

/// بيانات وهمية بسيطة جداً
class SimpleAuthService extends ChangeNotifier {
  bool _isLoggedIn = false;
  String? _userId;
  String? _userRole; // 'patient' أو 'doctor'
  String? _userName;

  bool get isLoggedIn => _isLoggedIn;
  String? get userId => _userId;
  String? get userRole => _userRole;
  String? get userName => _userName;

  /// بيانات المستخدمين الثابتة
  final Map<String, Map<String, String>> _users = {
    'patient@test.com': {
      'password': '123456',
      'name': 'أحمد علي',
      'role': 'patient',
    },
    'doctor@test.com': {
      'password': '123456',
      'name': 'د. محمود أحمد',
      'role': 'doctor',
    },
  };

  /// تسجيل دخول
  Future<bool> login(String email, String password) async {
    try {
      print('🔐 Attempting login: $email');
      await Future.delayed(const Duration(milliseconds: 500));

      if (_users.containsKey(email)) {
        final user = _users[email]!;
        if (user['password'] == password) {
          _isLoggedIn = true;
          _userId = email;
          _userRole = user['role'];
          _userName = user['name'];
          print('✅ Login success! Role: $_userRole');
          notifyListeners();
          return true;
        }
      }

      print('❌ Login failed: Invalid credentials');
      return false;
    } catch (e) {
      print('❌ Login error: $e');
      return false;
    }
  }

  /// تسجيل خروج
  Future<void> logout() async {
    _isLoggedIn = false;
    _userId = null;
    _userRole = null;
    _userName = null;
    print('👋 Logged out');
    notifyListeners();
  }

  /// تسجيل حساب جديد
  Future<bool> signup(
      String email, String password, String name, String role) async {
    try {
      print('📝 Attempting signup: $email as $role');
      await Future.delayed(const Duration(milliseconds: 500));

      if (_users.containsKey(email)) {
        print('❌ Signup failed: Email already exists');
        return false;
      }

      _users[email] = {
        'password': password,
        'name': name,
        'role': role,
      };

      _isLoggedIn = true;
      _userId = email;
      _userRole = role;
      _userName = name;
      print('✅ Signup success! Role: $role');
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ Signup error: $e');
      return false;
    }
  }
}
