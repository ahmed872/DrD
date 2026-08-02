import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/firebase_auth_service.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _timer;
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
    }

    if (mounted) {
      setState(() => _isChecking = false);
    }
  }

  Future<void> _resendEmail() async {
    final auth = Provider.of<FirebaseAuthService>(context, listen: false);
    final success = await auth.resendEmailVerification();

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إعادة إرسال الرسالة بنجاح ✅'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // تعطيل الزر لمدة 60 ثانية
        setState(() => _resendCountdown = 60);
        Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {
              _resendCountdown--;
              if (_resendCountdown <= 0) {
                timer.cancel();
              }
            });
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auth.errorMessage ?? 'حدث خطأ'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // منع الرجوع للخلف
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // أيقونة البريد
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0097A7).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mail_outline,
                      size: 70,
                      color: Color(0xFF0097A7),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // العنوان
                  Text(
                    'تفعيل البريد الإلكتروني',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[900],
                        ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  // الوصف
                  Consumer<FirebaseAuthService>(
                    builder: (context, auth, _) {
                      return Text(
                        'تم إرسال رسالة تفعيل إلى:\n${auth.userData?['email'] ?? "بريدك الإلكتروني"}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 15,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // رسالة التعليمات
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0097A7).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF0097A7).withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: const Color(0xFF0097A7),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'خطوات التفعيل:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF0097A7),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '1. افتح بريدك الإلكتروني\n2. ابحث عن رسالة من HEL DOC\n3. انقر على رابط التفعيل\n4. ستتم إعادة توجيهك تلقائياً',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 14,
                            height: 1.8,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // حالة الفحص
                  if (_isChecking)
                    Column(
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(
                            const Color(0xFF0097A7).withOpacity(0.7),
                          ),
                          strokeWidth: 2.5,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'جاري التحقق من التفعيل...',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: Colors.grey[400],
                          size: 40,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'يتم البحث عن التفعيل...',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 40),

                  // زر تفعيل يدوي
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isChecking ? null : _checkEmailVerification,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0097A7),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: Colors.grey[300],
                      ),
                      child: _isChecking
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Text(
                              'تم التفعيل، ادخل الآن',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // زر إعادة الإرسال
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _resendCountdown > 0 ? null : _resendEmail,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _resendCountdown > 0
                              ? Colors.grey[300]!
                              : const Color(0xFF0097A7),
                          width: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _resendCountdown > 0
                            ? 'أعد الإرسال بعد $_resendCountdown ثانية'
                            : 'إعادة إرسال الرسالة',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _resendCountdown > 0
                              ? Colors.grey[500]
                              : const Color(0xFF0097A7),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // زر الخروج
                  TextButton(
                    onPressed: () async {
                      final auth = Provider.of<FirebaseAuthService>(context,
                          listen: false);
                      final navigator = Navigator.of(context);
                      await auth.logout();
                      if (!mounted) return;
                      navigator.pushReplacementNamed('/');
                    },
                    child: const Text(
                      'الخروج',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
