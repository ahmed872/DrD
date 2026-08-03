import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/app_widgets.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _timer;
  Timer? _resendTimer;
  int _resendCountdown = 0;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    // البدء بفحص التفعيل كل 3 ثواني
    _startAutoCheckTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // مؤقّت العدّ التنازلي كان يُنشأ بلا مرجع، فيستمر بعد إغلاق الشاشة
    // ويستدعي `setState` على حالة مُتخلَّص منها.
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startAutoCheckTimer() {
    _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      await _checkEmailVerification();
    });
  }

  Future<void> _checkEmailVerification() async {
    if (_isChecking) return;

    setState(() => _isChecking = true);

    final auth = Provider.of<FirebaseAuthService>(context, listen: false);
    final isVerified = await auth.reloadAndCheckEmailVerification();

    if (mounted && isVerified) {
      _timer?.cancel();
      Navigator.of(context).pushReplacementNamed('/home');
      return;
    }

    if (mounted) {
      setState(() => _isChecking = false);
    }
  }

  Future<void> _resendEmail() async {
    final auth = Provider.of<FirebaseAuthService>(context, listen: false);
    final success = await auth.resendEmailVerification();

    if (!mounted) return;

    if (!success) {
      AppSnack.error(context, auth.errorMessage ?? 'حدث خطأ');
      return;
    }

    AppSnack.success(context, 'تم إعادة إرسال الرسالة بنجاح');

    // تعطيل الزر لمدة 60 ثانية
    setState(() => _resendCountdown = 60);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) timer.cancel();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // `WillPopScope` مهجور منذ Flutter 3.12؛ `PopScope` بديله الذي يعمل مع
    // زر الرجوع في المتصفح أيضاً.
    return PopScope(
      canPop: false,
      child: AppScaffold(
        title: 'تفعيل البريد الإلكتروني',
        showBack: false,
        maxWidth: AppBreakpoints.form,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mark_email_unread_outlined,
                  size: 48,
                  color: context.colors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'فعّل بريدك للمتابعة',
              textAlign: TextAlign.center,
              style: context.texts.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Consumer<FirebaseAuthService>(
              builder: (context, auth, _) {
                return Text(
                  'أرسلنا رسالة تفعيل إلى\n'
                  '${auth.userData?['email'] ?? "بريدك الإلكتروني"}',
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium
                      ?.copyWith(color: tokens.textMuted),
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),

            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.checklist_rounded,
                        size: 19,
                        color: context.colors.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text('خطوات التفعيل', style: context.texts.titleSmall),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _Step(1, 'افتح بريدك الإلكتروني'),
                  const _Step(2, 'ابحث عن رسالة التفعيل من DrD'),
                  const _Step(3, 'اضغط على رابط التفعيل داخل الرسالة'),
                  const _Step(4, 'ستُفتح لك الصفحة الرئيسية تلقائياً'),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // مؤشّر حيّ يوضّح أن التطبيق يفحص التفعيل بنفسه، فلا يظن المستخدم
            // أن عليه الانتظار بلا نهاية.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      _isChecking ? context.colors.primary : tokens.textFaint,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  _isChecking
                      ? 'جارٍ التحقق من التفعيل…'
                      : 'نتابع التفعيل تلقائياً كل ٣ ثوانٍ',
                  style: context.texts.bodySmall
                      ?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            FilledButton(
              onPressed: _isChecking ? null : _checkEmailVerification,
              child: const Text('فعّلت بريدي — ادخل الآن'),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: _resendCountdown > 0 ? null : _resendEmail,
              child: Text(
                _resendCountdown > 0
                    ? 'أعد الإرسال بعد $_resendCountdown ثانية'
                    : 'إعادة إرسال الرسالة',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: _logout,
              style: TextButton.styleFrom(foregroundColor: tokens.textMuted),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final auth = Provider.of<FirebaseAuthService>(context, listen: false);
    final navigator = Navigator.of(context);
    await auth.logout();
    if (!mounted) return;
    navigator.pushReplacementNamed('/');
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: context.texts.labelSmall
                  ?.copyWith(color: context.colors.primary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: context.texts.bodyMedium?.copyWith(color: tokens.textBody),
            ),
          ),
        ],
      ),
    );
  }
}
