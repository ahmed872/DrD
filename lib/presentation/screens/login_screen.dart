import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_spacing.dart';
import '../widgets/app_widgets.dart';
import '../providers/firebase_auth_service.dart';
import 'forgot_password_screen.dart';

/// الحد الأدنى لطول كلمة المرور عند **تسجيل الدخول**.
///
/// مطابق لحدّ Firebase الافتراضي الذي أُنشئت به الحسابات القائمة. رفعه هنا
/// يمنع أصحابها من الدخول بكلمة صحيحة — عطل لا تشديد.
const int kMinPasswordLengthLogin = 6;

/// الحد الأدنى لطول كلمة المرور عند **إنشاء حساب جديد**.
const int kMinPasswordLengthSignup = 8;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // التسجيل الذاتي كطبيب مغلق.
  //
  // كان هذا المفتاح `true`، فتظهر أزرار «مريض / طبيب» لكل من يفتح شاشة
  // التسجيل — أي أن أي شخص يصنع لنفسه حساب طبيب بضغطة، فيظهر في قائمة
  // الأطباء ويستقبل حجوزات حقيقية ويقرأ أعراض المرضى وأرقامهم.
  //
  // إعادته إلى `true` لن تُنشئ طبيباً بعد الآن: `firestore.rules` ترفض
  // إنشاء أي مستند مستخدم بدور غير `patient`. حسابات الأطباء تُنشأ بترقية
  // إدارية: `node scripts/promote_to_doctor.js --uid=<uid> --apply`.
  static const bool isDoctorRegistrationEnabled = false;

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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      // على شاشة عريضة كان النموذج يمتد 1440 بكسل: حقل هاتف بعرض الشاشة
      // كاملة، و«نسيت كلمة المرور؟» ملتصق بالحافة بعيداً عن حقله.
      body: SingleChildScrollView(
        child: ContentWidthLimit(
          maxWidth: 460,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: AppSpacing.xxl),
                // شاشة الدخول: أقلّ ما يمكن وبثقة. الشعار أصغر (72 بدل
                // 100) والعنوان من سلّم الخطوط لا بمقاسات مكتوبة، والنصّ
                // الثانوي يقول ماذا يفعل المستخدم هنا بدل أن يكرّر عنوان
                // الزرّ الذي تحته.
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    image: const DecorationImage(
                      image: AssetImage('assets/images/logo.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'DrD',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _isLogin
                      ? 'سجّل دخولك لإدارة مواعيدك'
                      : 'أنشئ حسابك في دقيقة',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.xxl),

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
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const ForgotPasswordScreen(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
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
                            transitionDuration:
                                const Duration(milliseconds: 300),
                          ),
                        );
                      },
                      child: Text(
                        'نسيت كلمة المرور؟',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
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
                          activeColor: Theme.of(context).colorScheme.primary,
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
                          activeColor: Theme.of(context).colorScheme.primary,
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
                  //
                  // كانت الخلفية والنص كلاهما `primary` بعد التحويل الآلي
                  // لألوان الوضع الليلي: نصّ فيروزي على خلفية فيروزية بتباين
                  // 1.04:1 — أي غير مرئي عملياً (قياس من لقطة شاشة فعلية).
                  // الزوج primaryContainer/onPrimaryContainer هو الصحيح لسطح
                  // ملوّن خفيف، ويعمل في الوضعين.
                  InkWell(
                    onTap: () {
                      _openWhatsApp('+201093033884');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
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
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    ),
                                    Text(
                                      '+20 109 303 3884',
                                      // رقم لاتيني داخل فقرة عربية: بدون
                                      // عزل اتجاهي تُنقل «+20» إلى آخر السطر.
                                      textDirection: TextDirection.ltr,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
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
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
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
                        // كان اللون أخضر ثابتاً مع نصّ `onPrimary` من الثيم:
                        // في الوضع الليلي صار النص داكناً على أخضر متوسط بتباين
                        // 2.57:1 (قياس فعلي من لقطة الشاشة، لا تقدير).
                        //
                        // ولا يكفي حذف اللونين: `ElevatedButton` في Material 3
                        // زرّ منخفض التأكيد افتراضياً (سطح باهت ونص بلون
                        // primary)، فيفقد زرّ الدخول بروزه تماماً في الوضع
                        // الليلي. نثبّت زوج primary/onPrimary صراحةً — متّسق
                        // مع بقية الشاشة، وعالي التباين في الوضعين.
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: auth.isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              )
                            : Text(
                                _isLogin ? 'دخول' : 'تسجيل',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                      ),
                    );
                  },
                ),

                // رسالة الحالة — خطأً كانت أو نجاحاً.
                //
                // المرحلة 11: كانت قناة واحدة تُعرض دائماً بلوح أحمر، فيظهر
                // نجاح التسجيل بوصفه خطأً. صارتا قناتين بنبرتين، والمكوّن
                // مشترك مع بقية الشاشات (`MessageBanner`).
                Consumer<FirebaseAuthService>(
                  builder: (context, auth, _) {
                    final error = auth.errorMessage;
                    final success = auth.successMessage;
                    if (error == null && success == null) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.lg),
                      child: MessageBanner(
                        message: error ?? success!,
                        tone: error != null
                            ? BannerTone.danger
                            : BannerTone.success,
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // التبديل بين Login و Signup
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isLogin ? 'ليس لديك حساب؟ ' : 'لديك حساب بالفعل؟ ',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
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
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
        // التلميح «+20 1xx xxx xxxx» داخل فقرة عربية كان يُعاد ترتيبه
        // ثنائي الاتجاه فيظهر «1xx xxx xxxx 20+». الأرقام تُقرأ من اليسار.
        hintTextDirection: TextDirection.ltr,
        prefixIcon: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
        ),
        // بلا إطار ولا تعبئة ولا تسمية عائمة محلياً: كلّها في
        // `inputDecorationTheme`. كانت مكرّرة هنا بلون تعبئة أبيض وتسمية
        // بخلفية بيضاء، فظهرت لطخة بيضاء فوق صفحة رمادية تحت كل تسمية.
      ),
      style: TextStyle(
        fontSize: 15,
        color: Theme.of(context).colorScheme.onSurface,
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
          color: Theme.of(context).colorScheme.primary,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _showPassword ? Icons.visibility : Icons.visibility_off,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
      ),
      style: TextStyle(
        fontSize: 15,
        color: Theme.of(context).colorScheme.onSurface,
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

    // ===== كلمة المرور: حدّان لا حدّ واحد (المرحلة 10) =====
    //
    // كان الشرط `< 6` مطبَّقاً على المسارين معاً. رفعه كما هو كان سيقفل
    // الباب في وجه كل حساب قائم كلمته من ستة أحرف — وهو حدّ Firebase
    // الافتراضي الذي أُنشئت به تلك الحسابات فعلاً. الدخول ليس المكان الذي
    // تُفرض فيه سياسة جديدة؛ التسجيل هو.
    //
    // الفرض الحقيقي يبقى على الخادم: سياسة كلمة المرور في Firebase
    // Authentication (Identity Platform) — راجع `docs/RUNBOOK.md`. ما هنا
    // رسالة مبكرة للمستخدم لا حاجز أمني، تماماً كبقية تحققات الواجهة.
    if (password.length < kMinPasswordLengthLogin) {
      _showErrorDialog(
          'كلمة المرور يجب أن تكون $kMinPasswordLengthLogin أحرف على الأقل');
      return;
    }

    if (!_isLogin && password.length < kMinPasswordLengthSignup) {
      _showErrorDialog('اختر كلمة مرور من $kMinPasswordLengthSignup أحرف '
          'على الأقل لحماية حسابك');
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
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.onPrimary,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Icon(
              Icons.calendar_today,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
          ],
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
