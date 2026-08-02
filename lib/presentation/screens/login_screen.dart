import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/firebase_auth_service.dart';
import 'forgot_password_screen.dart';
import 'email_verification_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // مفتاح التحكم بنسخة التطبيق:
  // true = النسخة الخاصة بك لتسجيل الأطباء
  // false = النسخة التي سيتم نشرها للمرضى فقط
  static const bool isDoctorRegistrationEnabled = true;

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String _role = 'patient';
  bool _isLogin = true;
  bool _showPassword = false;
  DateTime? _selectedBirthDate;
  String _selectedGender = 'male'; // 'male' أو 'female'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              // Logo وعنوان
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                  image: const DecorationImage(
                    image: AssetImage('assets/images/logo.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'نظام حجز المواعيد',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _isLogin ? 'تسجيل دخول' : 'إنشاء حساب جديد',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 40),

              // رقم الجوال
              _buildTextField(
                controller: _phoneController,
                label: 'رقم الجوال',
                hint: '+20 1xx xxx xxxx',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              // كلمة المرور
              _buildPasswordField(
                controller: _passwordController,
                label: 'كلمة المرور',
              ),
              const SizedBox(height: 16),

              // زر نسيت كلمة المرور (في حالة الدخول فقط)
              if (_isLogin)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  const ForgotPasswordScreen(),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                            const begin = Offset(1.0, 0.0);
                            const end = Offset.zero;
                            const curve = Curves.easeInOutCubic;
                            var tween = Tween(begin: begin, end: end)
                                .chain(CurveTween(curve: curve));
                            return SlideTransition(
                              position: animation.drive(tween),
                              child: child,
                            );
                          },
                          transitionDuration: const Duration(milliseconds: 300),
                        ),
                      );
                    },
                    child: const Text(
                      'نسيت كلمة المرور؟',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF0097A7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // الاسم (للتسجيل فقط)
              if (!_isLogin) ...[
                _buildTextField(
                  controller: _nameController,
                  label: 'الاسم الكامل',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 16),

                // البريد الإلكتروني
                _buildTextField(
                  controller: _emailController,
                  label: 'البريد الإلكتروني',
                  hint: 'example@email.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),

                // تاريخ الميلاد
                _buildDateField(),
                const SizedBox(height: 16),

                // اختيار الدور (في نسخة الأدمن فقط)
                if (isDoctorRegistrationEnabled) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Radio<String>(
                        value: 'patient',
                        groupValue: _role,
                        activeColor: const Color(0xFF0097A7),
                        onChanged: (value) {
                          setState(() {
                            _role = value!;
                          });
                        },
                      ),
                      const Text('مريض'),
                      const SizedBox(width: 16),
                      Radio<String>(
                        value: 'doctor',
                        groupValue: _role,
                        activeColor: const Color(0xFF0097A7),
                        onChanged: (value) {
                          setState(() {
                            _role = value!;
                          });
                        },
                      ),
                      const Text('طبيب'),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // معلومة عن الدعم (زر WhatsApp)
                InkWell(
                  onTap: () {
                    _openWhatsApp('+201093033884');
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0097A7).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF0097A7).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: const Color(0xFF0097A7),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'للدعم والاستفسارات',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: const Color(0xFF0097A7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    'اتصل بنا عبر واتس: ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  Text(
                                    '+20 109 303 3884',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF0097A7),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: const Color(0xFF0097A7),
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ملاحظة: المرضى فقط يمكنهم التسجيل
              // الأطباء يدخلون برقم وكلمة مرور موجودة بالفعل

              // زر التسجيل/الدخول
              Consumer<FirebaseAuthService>(
                builder: (context, auth, _) {
                  return SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: auth.isLoading ? null : _handleAuth,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF2E7D32), // أخضر احترافي
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: auth.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text(
                              _isLogin ? 'دخول' : 'تسجيل',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  );
                },
              ),

              // رسالة الخطأ
              Consumer<FirebaseAuthService>(
                builder: (context, auth, _) {
                  if (auth.errorMessage != null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                auth.errorMessage!,
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              const SizedBox(height: 24),

              // التبديل بين Login و Signup
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isLogin ? 'ليس لديك حساب؟ ' : 'لديك حساب بالفعل؟ ',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLogin = !_isLogin;
                      });
                      // تنظيف الحقول
                      _phoneController.clear();
                      _passwordController.clear();
                      _nameController.clear();
                    },
                    child: Text(
                      _isLogin ? 'سجل الآن' : 'دخول',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0097A7),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(
          icon,
          color: const Color(0xFF0097A7),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF0097A7),
            width: 2,
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: TextStyle(
          color: Colors.grey[700],
          fontWeight: FontWeight.w500,
          backgroundColor: Colors.white,
        ),
        hintStyle: TextStyle(
          color: Colors.grey[400],
          fontSize: 13,
        ),
      ),
      style: TextStyle(
        fontSize: 15,
        color: Colors.grey[800],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      obscureText: !_showPassword,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          Icons.lock_outline,
          color: const Color(0xFF0097A7),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _showPassword ? Icons.visibility : Icons.visibility_off,
            color: Colors.grey[600],
          ),
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF1565C0),
            width: 2,
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: TextStyle(
          color: Colors.grey[700],
          fontWeight: FontWeight.w500,
          backgroundColor: Colors.white,
        ),
      ),
      style: TextStyle(
        fontSize: 15,
        color: Colors.grey[800],
      ),
    );
  }

  void _handleAuth() async {
    final auth = context.read<FirebaseAuthService>();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    // التحقق من صحة رقم الجوال
    if (!_isValidPhoneNumber(phone)) {
      _showErrorDialog(
          'رقم الجوال غير صحيح.\nالصيغة الصحيحة: +201XXXXXXXXX أو 01XXXXXXXXX');
      return;
    }

    if (phone.isEmpty || password.isEmpty) {
      _showErrorDialog('الرجاء ملء جميع الحقول');
      return;
    }

    // التحقق من كلمة المرور
    if (password.length < 6) {
      _showErrorDialog('كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }

    // Normalize phone number to ensure consistent format across login and signup
    final normalizedPhone = auth.normalizePhoneNumber(phone);

    if (_isLogin) {
      // تسجيل الدخول المباشر
      final success = await auth.login(normalizedPhone, password);
      if (success && mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else {
      // عملية التسجيل المباشرة
      if (_nameController.text.isEmpty) {
        _showErrorDialog('الرجاء إدخال الاسم');
        return;
      }

      if (_emailController.text.isEmpty) {
        _showErrorDialog('الرجاء إدخال البريد الإلكتروني');
        return;
      }

      if (_selectedBirthDate == null) {
        _showErrorDialog('الرجاء اختيار تاريخ الميلاد');
        return;
      }

      // التسجيل المباشر بدون OTP
      final signupSuccess = await auth.signupWithPhone(
        normalizedPhone,
        password,
        _nameController.text.trim(),
        _role, // الدور المحدد (مريض أو طبيب في النسخة الخاصة)
        birthDate: _selectedBirthDate,
        gender: _selectedGender,
        email: _emailController.text.trim(),
      );

      if (signupSuccess && mounted) {
        // الذهاب إلى شاشة تفعيل البريد الإلكتروني
        Navigator.of(context).pushReplacementNamed(
          '/home',
        );
      }
    }
  }

  bool _isValidPhoneNumber(String phone) {
    // تنظيف الرقم
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');

    // قبول صيغ متعددة للأرقام المصرية:
    // +201XXXXXXXXX (بصيغة دولية، 13 رقم)
    // 01XXXXXXXXX (صيغة محلية، 11 رقم)
    if (cleaned.startsWith('20')) {
      return cleaned.length == 12; // 20 + 10 أرقام
    } else if (cleaned.startsWith('01')) {
      return cleaned.length == 11; // 01 + 9 أرقام
    }
    return false;
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    // إزالة الرموز غير الضرورية من رقم الهاتف
    String cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');

    // إنشاء رابط WhatsApp
    final url = 'https://wa.me/$cleanedNumber?text=مرحباً، أحتاج إلى دعم';

    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          _showErrorDialog('لا يمكن فتح WhatsApp. تأكد من تثبيت التطبيق.');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('خطأ في محاولة فتح WhatsApp: $e');
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تنبيه'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField() {
    return GestureDetector(
      onTap: () async {
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: DateTime(2000),
          firstDate: DateTime(1950),
          lastDate: DateTime.now(),
        );
        if (pickedDate != null) {
          setState(() => _selectedBirthDate = pickedDate);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تاريخ الميلاد',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedBirthDate != null
                      ? '${_selectedBirthDate!.day}/${_selectedBirthDate!.month}/${_selectedBirthDate!.year}'
                      : 'اختر التاريخ',
                  style: TextStyle(
                    fontSize: 14,
                    color: _selectedBirthDate != null
                        ? Colors.grey[800]
                        : Colors.grey[500],
                  ),
                ),
              ],
            ),
            Icon(
              Icons.calendar_today,
              color: const Color(0xFF0097A7),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الجنس',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildGenderButton('ذكر', 'male'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGenderButton('أنثى', 'female'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGenderButton(String label, String value) {
    final isSelected = _selectedGender == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedGender = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0097A7) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF0097A7) : Colors.grey[300]!,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}
