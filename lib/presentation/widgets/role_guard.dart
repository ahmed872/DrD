import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/doctor_account_state.dart';
import '../../core/theme/app_spacing.dart';
import '../providers/firebase_auth_service.dart';
import 'app_widgets.dart';

/// حارس دور على مستوى الشاشة.
///
/// ## ما هذا وما ليس هو
///
/// **ليس** طبقة صلاحيات. الصلاحية تُفرض على الخادم وحده: Custom Claims في
/// دوال الإدارة، و`firestore.rules` على كل قراءة وكتابة. مستخدم يتجاوز هذا
/// الحارس لا يحصل على شيء — استعلاماته تُرفض.
///
/// وظيفته أن تكون الواجهة **متّسقة** مع تلك الصلاحيات: قبله كانت شاشات
/// الإدارة مفتوحة لأي شيفرة تصل إليها، وحمايتها الوحيدة أن الزرّ المؤدي إليها
/// مخفي. زرّ مخفي ليس حاجزاً — أي تنقّل برمجي أو خطأ في مسار يفتحها، فيرى
/// المستخدم شاشة تفشل استعلاماتها بلا تفسير. هذا الحارس يعرض رسالة مفهومة
/// بدل ذلك.
class RoleGuard extends StatelessWidget {
  const RoleGuard({
    super.key,
    required this.child,
    this.requireAdmin = false,
    this.requireDoctorClinicAccess = false,
    this.requirePatient = false,
  });

  final Widget child;

  /// يستلزم Custom Claim `admin: true` في رمز المصادقة.
  final bool requireAdmin;

  /// يستلزم حساب طبيب له عيادة (نشط أو موقوف) — لا متقدّماً ولا مريضاً.
  final bool requireDoctorClinicAccess;

  final bool requirePatient;

  @override
  Widget build(BuildContext context) {
    return Consumer<FirebaseAuthService>(
      builder: (context, auth, _) {
        if (!auth.sessionRestored) {
          return const Scaffold(
            body: LoadingStateView(message: 'جارٍ التحقق من الجلسة…'),
          );
        }

        if (!auth.isLoggedIn) {
          return const _BlockedScreen(
            icon: Icons.lock_outline,
            title: 'يلزم تسجيل الدخول',
            message: 'سجّل الدخول للوصول إلى هذه الصفحة',
          );
        }

        if (requireAdmin && !auth.isAdmin) {
          return const _BlockedScreen(
            icon: Icons.shield_outlined,
            title: 'صفحة إدارية',
            message: 'هذه الصفحة متاحة لفريق الإدارة فقط',
          );
        }

        if (requireDoctorClinicAccess) {
          final state = doctorAccountStateFrom(auth.userData);
          if (!state.hasClinicAccess) {
            return _BlockedScreen(
              icon: Icons.medical_information_outlined,
              title: 'صفحة خاصة بالأطباء',
              message: state.arabicDescription,
            );
          }
        }

        if (requirePatient && auth.userRole != 'patient') {
          return const _BlockedScreen(
            icon: Icons.person_outline,
            title: 'صفحة خاصة بالمرضى',
            message: 'هذه الصفحة متاحة لحسابات المرضى',
          );
        }

        return child;
      },
    );
  }
}

/// شاشة «لا صلاحية» — مخرج واضح بدل شاشة تفشل استعلاماتها بصمت.
class _BlockedScreen extends StatelessWidget {
  const _BlockedScreen({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('غير متاح')),
      body: SafeArea(
        child: ContentWidthLimit(
          child: Padding(
            padding: AppSpacing.page,
            child: EmptyState(
              icon: icon,
              title: title,
              message: message,
              actionLabel: 'رجوع',
              onAction: () {
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                } else {
                  navigator.pushReplacementNamed('/home');
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط حالة حساب الطبيب.
///
/// يجيب فوراً عن السؤال الذي لم تكن أي شاشة تجيبه: هل حسابي يستقبل حجوزات
/// الآن؟ الطبيب الموقوف كان يرى لوحته كاملة بلا أي إشارة إلى أن المرضى لا
/// يرونه، فينتظر حجوزات لن تصل.
class DoctorStatusBanner extends StatelessWidget {
  const DoctorStatusBanner({super.key, required this.state, this.onAction});

  final DoctorAccountState state;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    if (state == DoctorAccountState.active) {
      // الحالة الطبيعية لا تستحق شريطاً دائماً يزاحم المحتوى.
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (Color background, Color foreground, IconData icon) = switch (state) {
      DoctorAccountState.pending => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          Icons.hourglass_top,
        ),
      DoctorAccountState.rejected => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.report_gmailerrorred_outlined,
        ),
      DoctorAccountState.suspended => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.pause_circle_outline,
        ),
      _ => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.info_outline,
        ),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: AppSpacing.card,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: foreground),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  state.arabicLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            state.arabicDescription,
            style: theme.textTheme.bodySmall?.copyWith(color: foreground),
          ),
          if (onAction != null && state == DoctorAccountState.rejected) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonal(
              onPressed: onAction,
              child: const Text('تعديل الطلب وإعادة التقديم'),
            ),
          ],
        ],
      ),
    );
  }
}
