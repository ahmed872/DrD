import 'package:flutter/material.dart';

import '../../core/constants/doctor_application_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/doctor_application.dart';

/// بطاقة حالة طلب الانضمام على الصفحة الرئيسية.
///
/// تظهر للمريض وحده، وتبقى **هادئة**: هي دعوة جانبية لمن يصادف أن يكون
/// طبيباً، لا إجراء رئيسياً. من يفتح التطبيق ليحجز موعداً يجب أن يجد الحجز
/// أولاً، لا دعوة للتوظيف.
class DoctorApplicationCard extends StatelessWidget {
  const DoctorApplicationCard({
    super.key,
    required this.application,
    required this.onApply,
    this.isActivating = false,
  });

  final DoctorApplication application;

  /// يفتح شاشة الطلب — للتقديم أو للتصحيح بعد الرفض.
  final VoidCallback onApply;

  /// قُبل الطلب لكن ترقية الحساب لم تصل بعد.
  ///
  /// نافذة قصيرة بين تسجيل القرار وكتابة الصلاحية على الخادم. عرضها
  /// صراحةً أصدق من عرض «يمكنك الآن استخدام أدوات الطبيب» بينما الأدوات
  /// لم تُفتح بعد.
  final bool isActivating;

  @override
  Widget build(BuildContext context) {
    return switch (application.status) {
      DoctorApplicationStatus.none => _Invitation(onApply: onApply),
      DoctorApplicationStatus.pending => const _Pending(),
      DoctorApplicationStatus.rejected =>
        _Rejected(application: application, onEdit: onApply),
      DoctorApplicationStatus.approved => _Approved(activating: isActivating),
    };
  }
}

/// لا يوجد طلب — الدعوة.
class _Invitation extends StatelessWidget {
  const _Invitation({required this.onApply});

  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.medical_services_outlined,
                  color: context.colors.primary, size: 22),
              const SizedBox(width: DrdSpacing.xs),
              Text(
                'هل أنت طبيب؟',
                style: context.text.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: DrdSpacing.xs),
          Text(
            'يمكنك تقديم طلب للانضمام إلى DrD كطبيب.',
            style: context.text.bodyMedium?.copyWith(color: context.drd.muted),
          ),
          const SizedBox(height: DrdSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              onPressed: onApply,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, DrdSizes.touchTarget),
              ),
              child: const Text('تقديم طلب'),
            ),
          ),
        ],
      ),
    );
  }
}

/// الطلب قيد المراجعة.
class _Pending extends StatelessWidget {
  const _Pending();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip.doctorApplication(DoctorApplicationStatus.pending),
              const SizedBox(width: DrdSpacing.xs),
              Expanded(
                child: Text(
                  'طلبك قيد المراجعة',
                  style: context.text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: DrdSpacing.xs),
          Text(
            'سيتم مراجعة طلبك من إدارة DrD قبل تفعيل حساب الطبيب.',
            style: context.text.bodyMedium?.copyWith(color: context.drd.muted),
          ),
        ],
      ),
    );
  }
}

/// الطلب مرفوض — والسبب معروض ليُصحَّح.
class _Rejected extends StatelessWidget {
  const _Rejected({required this.application, required this.onEdit});

  final DoctorApplication application;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final reason = application.activeRejectionReason;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip.doctorApplication(DoctorApplicationStatus.rejected),
              const SizedBox(width: DrdSpacing.xs),
              Expanded(
                child: Text(
                  'تم رفض الطلب',
                  style: context.text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: DrdSpacing.sm),
          // السبب هو الجزء المفيد الوحيد في الرفض — يُعرض كاملاً، لا مقتطعاً.
          if (reason != null && reason.isNotEmpty)
            AppBanner.error(title: 'سبب الرفض', message: reason)
          else
            Text(
              'لم يُسجَّل سبب للرفض. تواصل مع إدارة DrD.',
              style:
                  context.text.bodyMedium?.copyWith(color: context.drd.muted),
            ),
          const SizedBox(height: DrdSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: onEdit,
              child: const Text('تعديل وإعادة التقديم'),
            ),
          ),
        ],
      ),
    );
  }
}

/// الطلب مقبول.
class _Approved extends StatelessWidget {
  const _Approved({required this.activating});

  final bool activating;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip.doctorApplication(DoctorApplicationStatus.approved),
              const SizedBox(width: DrdSpacing.xs),
              Expanded(
                child: Text(
                  'تم قبول طلبك كطبيب',
                  style: context.text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: DrdSpacing.xs),
          Text(
            activating
                ? 'جارٍ تفعيل حسابك… قد يستغرق ذلك لحظات.'
                : 'يمكنك الآن استخدام أدوات الطبيب من هذه الصفحة.',
            style: context.text.bodyMedium?.copyWith(color: context.drd.muted),
          ),
        ],
      ),
    );
  }
}
