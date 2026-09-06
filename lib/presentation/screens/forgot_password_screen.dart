import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firebase_auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _emailSent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('استرجاع كلمة المرور'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            children: [
              // أيقونة وعنوان
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: context.colors.primaryContainer,
                  borderRadius: DrdRadius.lgAll,
                ),
                child: const Icon(
                  Icons.lock_reset,
                  size: 60,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'استرجاع كلمة المرور',
                style: context.text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'سيتم إرسال رابط تغيير كلمة المرور إلى بريدك الإلكتروني',
                style: context.text.bodyMedium?.copyWith(
                  color: context.drd.muted,
                ),
              ),
              const SizedBox(height: 32),

              // رسالة الخطأ
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: DrdSpacing.md),
                  child: AppBanner.error(message: _errorMessage!),
                ),

              // حقل البريد الإلكتروني فقط
              if (!_emailSent)
                _buildTextField(
                  controller: _emailController,
                  label: 'البريد الإلكتروني',
                  hint: 'example@email.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),

              // رسالة النجاح بعد إرسال الرابط
              if (_emailSent)
                const AppBanner.success(
                  title: 'تم إرسال الرابط بنجاح',
                  message: 'تحقق من بريدك الإلكتروني واضغط على الرابط '
                      'لتغيير كلمة المرور.',
                ),

              const SizedBox(height: 24),

              // الزر الرئيسي
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _emailSent ? null : _handleReset,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'إرسال رابط تغيير كلمة المرور',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // زر الإلغاء
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleReset() async {
    final auth = Provider.of<FirebaseAuthService>(context, listen: false);

    setState(() => _errorMessage = null);

    // التحقق من البريد الإلكتروني
    if (_emailController.text.isEmpty) {
      setState(() => _errorMessage = 'الرجاء إدخال البريد الإلكتروني');
      return;
    }

    // إرسال رابط تغيير كلمة المرور من Firebase
    final success =
        await auth.sendPasswordResetEmail(_emailController.text.trim());
    if (success && mounted) {
      setState(() => _emailSent = true);
    } else if (mounted) {
      setState(() => _errorMessage = auth.errorMessage ?? 'فشل إرسال الرابط');
    }
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
        prefixIcon: Icon(icon),
      ),
    );
  }
}
