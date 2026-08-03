import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/app_widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _emailSent = false;
  bool _isSending = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'استرجاع كلمة المرور',
      maxWidth: AppBreakpoints.form,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.md),
          _buildIcon(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            _emailSent ? 'تفقّد بريدك' : 'نسيت كلمة المرور؟',
            textAlign: TextAlign.center,
            style: context.texts.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _emailSent
                ? 'أرسلنا رابط تغيير كلمة المرور إلى '
                    '${_emailController.text.trim()}'
                : 'اكتب بريدك الإلكتروني وسنرسل لك رابطاً لتعيين كلمة مرور '
                    'جديدة.',
            textAlign: TextAlign.center,
            style: context.texts.bodyMedium
                ?.copyWith(color: context.tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.xxl),
          if (_errorMessage != null) ...[
            NoticeBox.danger(message: _errorMessage!),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (_emailSent)
            const NoticeBox.success(
              title: 'تم إرسال الرابط',
              message: 'افتح بريدك واضغط على الرابط لتعيين كلمة مرور جديدة. '
                  'لو لم تجد الرسالة، راجع مجلد الرسائل غير المرغوب فيها.',
            )
          else
            AppTextField(
              controller: _emailController,
              label: 'البريد الإلكتروني',
              hint: 'example@email.com',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
            ),
          const SizedBox(height: AppSpacing.xl),
          if (!_emailSent)
            FilledButton(
              onPressed: _isSending ? null : _handleReset,
              child: _isSending
                  ? const SizedBox(
                      height: 21,
                      width: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text('إرسال الرابط'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('العودة لتسجيل الدخول'),
            ),
          const SizedBox(height: AppSpacing.md),
          if (!_emailSent)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    return Center(
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _emailSent
              ? Icons.mark_email_read_outlined
              : Icons.lock_reset_rounded,
          size: 44,
          color: context.colors.primary,
        ),
      ),
    );
  }

  Future<void> _handleReset() async {
    final auth = Provider.of<FirebaseAuthService>(context, listen: false);

    setState(() => _errorMessage = null);

    // التحقق من البريد الإلكتروني
    if (_emailController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'الرجاء إدخال البريد الإلكتروني');
      return;
    }

    setState(() => _isSending = true);

    // إرسال رابط تغيير كلمة المرور من Firebase
    final success =
        await auth.sendPasswordResetEmail(_emailController.text.trim());

    if (!mounted) return;
    setState(() {
      _isSending = false;
      if (success) {
        _emailSent = true;
      } else {
        _errorMessage = auth.errorMessage ?? 'فشل إرسال الرابط';
      }
    });
  }
}
