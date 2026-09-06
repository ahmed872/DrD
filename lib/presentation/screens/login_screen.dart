import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../providers/firebase_auth_service.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // كان هنا مفتاح `isDoctorRegistrationEnabled` وزرّا اختيار "مريض / طبيب".
  //
  // المفتاح كان مقصوداً به إخفاء تسجيل الأطباء في نسخة المرضى، لكنه لم يكن
  // يحمي شيئاً: قواعد Firestore كانت تقبل `role: 'doctor'` من أي عميل بغض
  // النظر عن قيمته، فأي شخص يصبح طبيباً — يظهر في بحث المرضى، ويُحجز عنده،
  // ويكتب ملاحظات سريرية على مواعيد مرضى حقيقيين.
  //
  // صارت القاعدة على الخادم تقبل `role: 'patient'` وحده، فلم يعد لهذا
  // الاختيار معنى: تركه كان سيعرض زراً يفشل دائماً بخطأ صلاحيات.
  //
  // نظام طلبات الأطباء (تقديم → مراجعة → قبول) لم يُبنَ بعد — لا تُضِف هنا
  // ما يوحي بوجوده. حسابات الأطباء تُفعَّل يدوياً حالياً.

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isLogin = true;
  bool _showPassword = false;
  DateTime? _selectedBirthDate;
  String _selectedGender = 'male'; // 'male' أو 'female'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DrdSpacing.lg,
            vertical: DrdSpacing.xl,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              // Logo وعنوان
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: context.colors.primaryContainer,
                  borderRadius: DrdRadius.lgAll,
                  image: const DecorationImage(
                    image: AssetImage('assets/images/logo.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'نظام حجز المواعيد',
                style: context.text.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _isLogin ? 'تسجيل دخول' : 'إنشاء حساب جديد',
                style: context.text.bodyMedium?.copyWith(
                  color: context.drd.muted,
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
                    child: const Text('نسيت كلمة المرور؟'),
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

                // الدعم: لافتة معلومة بإجراء صريح بدل صندوق كامل قابل
                // للنقر — الصندوق لم يكن يبدو زراً، فكان النقر عليه اكتشافاً
                // بالمصادفة لا خياراً معروضاً.
                AppBanner.info(
                  title: 'للدعم والاستفسارات',
                  message: 'واتساب: +20 109 303 3884',
                  action: TextButton.icon(
                    onPressed: () => _openWhatsApp('+201093033884'),
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: const Text('افتح واتساب'),
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
                    child: FilledButton(
                      onPressed: auth.isLoading ? null : _handleAuth,
                      child: auth.isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                // على سطح الزر المملوء، لا على سطح الصفحة.
                                color: context.colors.onPrimary,
                              ),
                            )
                          : Text(_isLogin ? 'دخول' : 'تسجيل'),
                    ),
                  );
                },
              ),

              // رسالة الخطأ
              Consumer<FirebaseAuthService>(
                builder: (context, auth, _) {
                  if (auth.errorMessage != null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: DrdSpacing.md),
                      child: AppBanner.error(message: auth.errorMessage!),
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
                    style: TextStyle(color: context.drd.muted),
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
                    child: Text(_isLogin ? 'سجل الآن' : 'دخول'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// حقل نص عادي.
  ///
  /// كان هنا نحو أربعين سطراً من `InputDecoration`: أربعة إطارات وحشوة
  /// وأربعة أنماط نصّية، مكرّرة مرة أخرى في حقل كلمة المرور — وباللونين
  /// مختلفين بينهما (فيروزي في أحدهما وأزرق في الآخر عند التركيز). كل ذلك
  /// صار في `inputDecorationTheme`، والحقل هنا يصف ما يطلبه فقط.
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
        prefixIcon: Icon(icon),
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
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off),
          tooltip: _showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
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

      // التسجيل ينشئ حساب مريض دائماً — الدور ليس اختياراً للعميل.
      final signupSuccess = await auth.signupWithPhone(
        normalizedPhone,
        password,
        _nameController.text.trim(),
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

  /// حقل تاريخ الميلاد.
  ///
  /// كان `Container` بحدّ وخلفية بيضاء مكتوبين يدوياً، فبدا مختلفاً عن
  /// الحقول المجاورة له في نفس النموذج — وفي الوضع الليلي كان يبقى أبيض
  /// بينما تُظلم بقية الحقول. `InputDecorator` يستعمل نفس تنسيق الحقول،
  /// فيتطابق الشكل ويتبع الوضعين بلا شرط.
  Widget _buildDateField() {
    final hasDate = _selectedBirthDate != null;

    return InkWell(
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
      borderRadius: DrdRadius.smAll,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'تاريخ الميلاد',
          prefixIcon: Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          hasDate
              ? '${_selectedBirthDate!.day}/${_selectedBirthDate!.month}/${_selectedBirthDate!.year}'
              : 'اختر التاريخ',
          style: hasDate ? null : TextStyle(color: context.drd.disabled),
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
