import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/simple_auth_service.dart';

class LoginScreenSimple extends StatefulWidget {
  const LoginScreenSimple({super.key});

  @override
  State<LoginScreenSimple> createState() => _LoginScreenSimpleState();
}

class _LoginScreenSimpleState extends State<LoginScreenSimple> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  String _selectedRole = 'patient'; // مريض أو طبيب
  bool _isLogin = true; // true = login, false = signup
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              // Logo
              const Icon(Icons.local_hospital, size: 80, color: Colors.blue),
              const SizedBox(height: 20),
              Text(
                'نظام حجز المواعيد',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
              ),
              const SizedBox(height: 40),

              // Email
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),

              // Password
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),

              // Name (only for signup)
              if (!_isLogin)
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'الاسم الكامل',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              if (!_isLogin) const SizedBox(height: 16),

              // Role selector (only for signup)
              if (!_isLogin)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('اختر دورك:',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile(
                            title: const Text('طبيب'),
                            value: 'doctor',
                            groupValue: _selectedRole,
                            onChanged: (value) {
                              setState(() => _selectedRole = value!);
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile(
                            title: const Text('مريض'),
                            value: 'patient',
                            groupValue: _selectedRole,
                            onChanged: (value) {
                              setState(() => _selectedRole = value!);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              if (!_isLogin) const SizedBox(height: 16),

              // Login/Signup Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleAuth,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Text(_isLogin ? 'دخول' : 'تسجيل'),
                ),
              ),
              const SizedBox(height: 16),

              // Toggle between login and signup
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _emailController.clear();
                    _passwordController.clear();
                    _nameController.clear();
                  });
                },
                child: Text(
                  _isLogin ? 'ليس لديك حساب؟ سجل الآن' : 'لديك حساب؟ سجل دخول',
                  style: const TextStyle(color: Colors.blue),
                ),
              ),
              const SizedBox(height: 24),

              // Test credentials hint
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'بيانات الاختبار:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'مريض: patient@test.com / 123456',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontSize: 12),
                    ),
                    const Text(
                      'طبيب: doctor@test.com / 123456',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleAuth() async {
    final email = _emailController.text;
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء ملء جميع الحقول')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = context.read<SimpleAuthService>();
      bool success;

      if (_isLogin) {
        success = await auth.login(email, password);
        if (!success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('البريد أو كلمة المرور غير صحيحة')),
            );
          }
        }
      } else {
        final name = _nameController.text;
        if (name.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الرجاء إدخال الاسم')),
          );
          setState(() => _isLoading = false);
          return;
        }

        success = await auth.signup(email, password, name, _selectedRole);
        if (!success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('البريد موجود بالفعل')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}
