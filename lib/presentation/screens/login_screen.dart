import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/ui_kit.dart';
import 'forgot_password_screen.dart';

/// شاشة تسجيل الدخول وإنشاء الحساب.
///
/// أول شاشة يشوفها أي حد — وأول حكم على المنتج بيتكوّن منها. أُعيد بناؤها
/// حول ثلاث حاجات:
///
/// 1. **الشعار كبير** بدل مربّع صغير على خلفية رمادية.
/// 2. **التبديل بين «دخول» و«حساب جديد» صار شريحتين واضحتين** بدل زر نصّي
///    مدفون تحت الفورم كان بيخلي المستخدم مش عارف هو في أنهي وضع.
/// 3. **الحقول تظهر بالتدريج**: وضع الدخول بيعرض حقلين بس، والفورم الطويل
///    اللي بيطلب اسم وبريد وتاريخ ميلاد بيظهر في وضع التسجيل فقط.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// مفتاح التحكم بنسخة التطبيق:
  /// true = نسختك لتسجيل الأطباء · false = نسخة المرضى
  static const bool isDoctorRegistrationEnabled = true;

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  String _role = 'patient';
  bool _isLogin = true;
  bool _showPassword = false;
  DateTime? _selectedBirthDate;
  String _selectedGender = 'male';

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<FirebaseAuthService>();
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // على شاشة كمبيوتر الفورم بيفضل بعرض الموبايل بدل ما يتمدّد
            // على الشاشة كلها ويبان غير مقصود.
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding:
                  const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.xxl),
              children: [
                const SizedBox(height: Gap.lg),
                const _Brand(),
                const SizedBox(height: Gap.xxl),
                _ModeSwitch(
                  isLogin: _isLogin,
                  onChanged: (v) => setState(() => _isLogin = v),
                ),
                const SizedBox(height: Gap.xl),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                    LengthLimitingTextInputFormatter(15),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'رقم الجوال',
                    hintText: '01xxxxxxxxx',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: Gap.md),
                TextField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
                if (_isLogin)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen()),
                      ),
                      child: const Text('نسيت كلمة المرور؟'),
                    ),
                  ),
                if (!_isLogin) ...[
                  const SizedBox(height: Gap.md),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: Gap.md),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      hintText: 'example@email.com',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: Gap.md),
                  _BirthDateField(
                    value: _selectedBirthDate,
                    onPick: (d) => setState(() => _selectedBirthDate = d),
                  ),
                  const SizedBox(height: Gap.lg),
                  _SegmentedChoice(
                    label: 'النوع',
                    value: _selectedGender,
                    options: const {'male': 'ذكر', 'female': 'أنثى'},
                    onChanged: (v) => setState(() => _selectedGender = v),
                  ),
                  if (isDoctorRegistrationEnabled) ...[
                    const SizedBox(height: Gap.lg),
                    _SegmentedChoice(
                      label: 'نوع الحساب',
                      value: _role,
                      options: const {'patient': 'مريض', 'doctor': 'طبيب'},
                      onChanged: (v) => setState(() => _role = v),
                    ),
                  ],
                ],
                const SizedBox(height: Gap.xl),
                if (auth.errorMessage != null) ...[
                  _Message(text: auth.errorMessage!),
                  const SizedBox(height: Gap.md),
                ],
                FilledButton(
                  onPressed: auth.isLoading ? null : _handleAuth,
                  child: auth.isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(_isLogin ? 'تسجيل الدخول' : 'إنشاء الحساب'),
                ),
                const SizedBox(height: Gap.xl),
                Center(
                  child: TextButton.icon(
                    onPressed: () => _openWhatsApp('+201093033884'),
                    icon: Icon(Icons.support_agent,
                        size: 19, color: scheme.onSurfaceVariant),
                    style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant),
                    label: const Text('تواصل مع الدعم'),
                  ),
                ),
                const SizedBox(height: Gap.sm),
                Center(child: Text('DrD', style: t.labelSmall)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════ المنطق — كما هو دون تغيير ═══════════════

  void _handleAuth() async {
    final auth = context.read<FirebaseAuthService>();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    if (phone.isEmpty || password.isEmpty) {
      _showErrorDialog('الرجاء ملء جميع الحقول');
      return;
    }

    if (!_isValidPhoneNumber(phone)) {
      _showErrorDialog('رقم الجوال غير صحيح.\nالصيغة الصحيحة: 01XXXXXXXXX');
      return;
    }

    // الحد الأدنى 8 محارف: التطبيق يحمي بيانات طبية. الشرط يسري على
    // الحسابات الجديدة فقط — القائمة تدخل بكلمات مرورها الحالية.
    if (password.length < 8) {
      _showErrorDialog('كلمة المرور يجب أن تكون 8 أحرف على الأقل');
      return;
    }

    final normalizedPhone = auth.normalizePhoneNumber(phone);

    if (_isLogin) {
      final success = await auth.login(normalizedPhone, password);
      if (success && mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      _showErrorDialog('الرجاء إدخال الاسم');
      return;
    }
    if (_emailController.text.trim().isEmpty) {
      _showErrorDialog('الرجاء إدخال البريد الإلكتروني');
      return;
    }
    if (_selectedBirthDate == null) {
      _showErrorDialog('الرجاء اختيار تاريخ الميلاد');
      return;
    }

    final ok = await auth.signupWithPhone(
      normalizedPhone,
      password,
      _nameController.text.trim(),
      _role,
      birthDate: _selectedBirthDate,
      gender: _selectedGender,
      email: _emailController.text.trim(),
    );

    if (ok && mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  bool _isValidPhoneNumber(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('20')) return cleaned.length == 12;
    if (cleaned.startsWith('01')) return cleaned.length == 11;
    return false;
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final url = Uri.parse('https://wa.me/$cleaned?text=مرحباً، أحتاج إلى دعم');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _showErrorDialog('تعذّر فتح واتساب على جهازك');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تنبيه'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
        ],
      ),
    );
  }
}

/// الشعار واسم التطبيق.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            image: const DecorationImage(
              image: AssetImage('assets/images/logo.png'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
        Text('DrD', style: t.headlineMedium?.copyWith(letterSpacing: -.5)),
        const SizedBox(height: 2),
        Text('احجز موعدك بدقيقته، ومتستناش في العيادة',
            textAlign: TextAlign.center, style: t.bodySmall),
      ],
    );
  }
}

/// شريحتان للتبديل بين الدخول والتسجيل.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.isLogin, required this.onChanged});

  final bool isLogin;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          _tab(context, 'تسجيل دخول', isLogin, () => onChanged(true)),
          _tab(context, 'حساب جديد', !isLogin, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _tab(
      BuildContext context, String label, bool active, VoidCallback tap) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// اختيار من خيارين بشرائح — أوضح من أزرار الراديو الصغيرة.
class _SegmentedChoice extends StatelessWidget {
  const _SegmentedChoice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label),
        const SizedBox(height: Gap.sm),
        Row(
          children: [
            for (final e in options.entries) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(e.key),
                  child: Container(
                    // 52 بكسل: مساحة لمس مريحة لكبار السن.
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == e.key
                          ? scheme.primary.withValues(alpha: .10)
                          : scheme.surface,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(
                        color: value == e.key
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: value == e.key ? 1.8 : 1,
                      ),
                    ),
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: value == e.key
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              if (e.key != options.keys.last) const SizedBox(width: Gap.md),
            ],
          ],
        ),
      ],
    );
  }
}

/// حقل تاريخ الميلاد.
class _BirthDateField extends StatelessWidget {
  const _BirthDateField({required this.value, required this.onPick});

  final DateTime? value;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = value == null
        ? 'اختر تاريخ ميلادك'
        : '${value!.day}/${value!.month}/${value!.year}';

    return InkWell(
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime(now.year - 25),
          firstDate: DateTime(1920),
          lastDate: now,
          locale: const Locale('ar', 'EG'),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'تاريخ الميلاد',
          prefixIcon: Icon(Icons.cake_outlined),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            color: value == null ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// رسالة من خدمة المصادقة — نجاح أو خطأ حسب المحتوى.
class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // الخدمة بتستخدم نفس الحقل للنجاح والخطأ، وبتعلّم النجاح بعلامة ✅.
    final ok = text.contains('✅');
    final color = ok ? AppColors.success : AppColors.danger;

    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
              size: 19, color: color),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              text.replaceAll('✅', '').trim(),
              style: TextStyle(fontSize: 13.5, height: 1.55, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
