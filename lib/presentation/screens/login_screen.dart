import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/app_widgets.dart';
import 'forgot_password_screen.dart';

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

  static const String _supportPhone = '+201093033884';

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String _role = 'patient';
  bool _isLogin = true;
  bool _showPassword = false;
  DateTime? _selectedBirthDate;
  final String _selectedGender = 'male'; // 'male' أو 'female'

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      body: DecoratedBox(
        // تدرّج العلامة يملأ أعلى الشاشة، والبطاقة البيضاء تطفو فوقه. هذا هو
        // الفارق بين «نموذج على خلفية رمادية» وواجهة لها هوية.
        decoration: BoxDecoration(gradient: tokens.brandGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: AppBreakpoints.form),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xxl,
                  ),
                  child: Column(
                    children: [
                      _buildBrand(),
                      const SizedBox(height: AppSpacing.xxl),
                      _buildFormCard(),
                      const SizedBox(height: AppSpacing.xl),
                      _buildSupportCard(),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrand() {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            image: const DecorationImage(
              image: AssetImage('assets/images/logo.png'),
              fit: BoxFit.cover,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'DrD — حجز مواعيد الأطباء',
          textAlign: TextAlign.center,
          style: context.texts.titleLarge?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'احجز موعدك في وقت محدد، واستغنِ عن الانتظار',
          textAlign: TextAlign.center,
          style: context.texts.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: AppRadius.rXl,
        boxShadow: tokens.shadowLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // مبدّل الدخول/التسجيل في أعلى البطاقة: الحالة الحالية صارت ظاهرة
          // بدل رابط نصّي صغير في الأسفل لم يكن أحد ينتبه له.
          AppSegmented(
            labels: const ['تسجيل دخول', 'حساب جديد'],
            selectedIndex: _isLogin ? 0 : 1,
            onChanged: (i) {
              setState(() => _isLogin = i == 0);
              _phoneController.clear();
              _passwordController.clear();
              _nameController.clear();
              _emailController.clear();
            },
          ),
          const SizedBox(height: AppSpacing.xl),

          AppTextField(
            controller: _phoneController,
            label: 'رقم الجوال',
            hint: '01XXXXXXXXX',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.lg),

          AppTextField(
            controller: _passwordController,
            label: 'كلمة المرور',
            hint: '6 أحرف على الأقل',
            icon: Icons.lock_outline_rounded,
            obscureText: !_showPassword,
            suffix: IconButton(
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
              tooltip:
                  _showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
            ),
          ),

          if (_isLogin)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _openForgotPassword,
                child: const Text('نسيت كلمة المرور؟'),
              ),
            ),

          if (!_isLogin) ...[
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _nameController,
              label: 'الاسم الكامل',
              icon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _emailController,
              label: 'البريد الإلكتروني',
              hint: 'example@email.com',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.lg),
            _buildDateField(),
            if (isDoctorRegistrationEnabled) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildRolePicker(),
            ],
          ],

          const SizedBox(height: AppSpacing.xl),

          Consumer<FirebaseAuthService>(
            builder: (context, auth, _) {
              return FilledButton(
                onPressed: auth.isLoading ? null : _handleAuth,
                child: auth.isLoading
                    ? const SizedBox(
                        height: 21,
                        width: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Text(_isLogin ? 'دخول' : 'إنشاء الحساب'),
              );
            },
          ),

          Consumer<FirebaseAuthService>(
            builder: (context, auth, _) {
              if (auth.errorMessage == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: NoticeBox.danger(message: auth.errorMessage!),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRolePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('نوع الحساب', style: context.texts.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _roleTile(
                value: 'patient',
                label: 'مريض',
                icon: Icons.personal_injury_outlined,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _roleTile(
                value: 'doctor',
                label: 'طبيب',
                icon: Icons.medical_services_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _roleTile({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final tokens = context.tokens;
    final selected = _role == value;
    final primary = context.colors.primary;

    return Material(
      color: selected ? primary.withValues(alpha: 0.08) : tokens.surfaceSunken,
      borderRadius: AppRadius.rMd,
      child: InkWell(
        onTap: () => setState(() => _role = value),
        borderRadius: AppRadius.rMd,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rMd,
            border: Border.all(
              color: selected ? primary : tokens.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 24,
                color: selected ? primary : tokens.textMuted,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: context.texts.labelMedium?.copyWith(
                  color: selected ? primary : tokens.textBody,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateField() {
    final tokens = context.tokens;
    final hasDate = _selectedBirthDate != null;

    return InkWell(
      onTap: _pickBirthDate,
      borderRadius: AppRadius.rMd,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'تاريخ الميلاد',
          prefixIcon: Icon(Icons.cake_outlined, size: 20),
        ),
        child: Text(
          hasDate
              ? '${_selectedBirthDate!.day}/${_selectedBirthDate!.month}/'
                  '${_selectedBirthDate!.year}'
              : 'اختر التاريخ',
          style: context.texts.bodyLarge?.copyWith(
            color: hasDate ? tokens.textStrong : tokens.textFaint,
          ),
        ),
      ),
    );
  }

  Widget _buildSupportCard() {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: AppRadius.rLg,
      child: InkWell(
        onTap: () => _openWhatsApp(_supportPhone),
        borderRadius: AppRadius.rLg,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rLg,
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              const Icon(Icons.support_agent_rounded,
                  color: Colors.white, size: 24),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تحتاج مساعدة؟',
                      style: context.texts.titleSmall
                          ?.copyWith(color: Colors.white),
                    ),
                    Text(
                      'كلّمنا على واتساب — $_supportPhone',
                      style: context.texts.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthDate ?? DateTime(2000),
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
      helpText: 'اختر تاريخ ميلادك',
    );
    if (picked != null) setState(() => _selectedBirthDate = picked);
  }

  void _handleAuth() async {
    final auth = context.read<FirebaseAuthService>();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    // التحقق من صحة رقم الجوال
    if (!_isValidPhoneNumber(phone)) {
      _showErrorDialog(
        'رقم الجوال غير صحيح.\nالصيغة الصحيحة: +201XXXXXXXXX أو 01XXXXXXXXX',
      );
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
        Navigator.of(context).pushReplacementNamed('/home');
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
      builder: (ctx) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: ctx.tokens.dangerSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.error_outline_rounded,
            color: ctx.tokens.danger,
            size: 26,
          ),
        ),
        title: const Text('تنبيه', textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
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
