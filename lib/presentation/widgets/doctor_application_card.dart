import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../data/services/doctor_application_service.dart';
import 'app_surfaces.dart';
import 'app_widgets.dart';

/// مدخل الانضمام كطبيب وحالته — على رئيسية المريض.
///
/// ## المشكلة التي يحلّها
///
/// شاشة `DoctorApplicationScreen` كانت موجودة وكاملة، ومسارها مُعرَّف في
/// `home_screen` (`case 'doctor_application'`) — **لكن لا شيء في التطبيق
/// كلّه كان يستدعيه**. أي أن التقديم كطبيب لم يكن ممكناً عملياً: لا زرّ،
/// ولا قائمة، ولا رابط. ظهر ذلك في الاختبار اليدوي على جهاز حقيقي بوصفه
/// «تسجيل الأطباء غير متاح».
///
/// وحتى لو وصل المستخدم إليها وأرسل طلبه، لم يكن يرى بعدها شيئاً على
/// الرئيسية: لا تأكيد ولا حالة — راجع `DoctorApplicationService` لماذا.
///
/// ## ما هذا وما ليس هو
///
/// عرضٌ لا تفويض. البطاقة تقرأ مستند الطلب الخاص بصاحبه فقط، ولا تكتب
/// شيئاً، ولا تمنح أي صلاحية. القرار يبقى للإدارة عبر
/// `approveDoctor`/`rejectDoctor`، والدور يكتبه الخادم وحده.
class DoctorApplicationCard extends StatelessWidget {
  const DoctorApplicationCard({
    super.key,
    required this.uid,
    required this.onOpen,
    DoctorApplicationService? service,
  }) : _service = service;

  final String uid;

  /// يفتح شاشة الطلب (إرسال، أو مراجعة، أو إعادة تقديم).
  final VoidCallback onOpen;

  final DoctorApplicationService? _service;

  @override
  Widget build(BuildContext context) {
    final service = _service ?? DoctorApplicationService();
    return StreamBuilder<DoctorApplicationSnapshot>(
      stream: service.watch(uid),
      builder: (context, snapshot) {
        // قبل وصول البيانات لا نعرض شيئاً: وميض بطاقة ثم اختفاؤها أسوأ من
        // ظهورها متأخرة بجزء من الثانية.
        if (!snapshot.hasData) return const SizedBox.shrink();
        return _card(context, snapshot.data!);
      },
    );
  }

  Widget _card(BuildContext context, DoctorApplicationSnapshot app) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final (
      IconData icon,
      Color iconColor,
      String title,
      String body,
      String action,
      StatusTone? tone,
    ) = switch (app.status) {
      // الدعوة لا الإعلان: سطر هادئ في آخر الرئيسية، لا لافتة تلاحق كل
      // مريض بعرضٍ لا يعنيه.
      DoctorApplicationStatus.none => (
          Icons.medical_services_outlined,
          scheme.primary,
          'هل أنت طبيب؟',
          'قدّم طلب انضمام لتستقبل حجوزات المرضى عبر DrD.',
          'تقديم طلب',
          null,
        ),
      DoctorApplicationStatus.pending => (
          Icons.hourglass_top_outlined,
          scheme.secondary,
          'طلبك قيد المراجعة',
          'سيتم مراجعة طلبك من إدارة DrD قبل تفعيل حساب الطبيب. '
              'حسابك يعمل كحساب مريض حتى ذلك الحين.',
          'عرض الطلب',
          StatusTone.info,
        ),
      DoctorApplicationStatus.rejected => (
          Icons.info_outline,
          scheme.error,
          'لم يُقبل طلبك',
          app.rejectionReason.isEmpty
              ? 'يمكنك تعديل بياناتك وإعادة التقديم.'
              : 'السبب: ${app.rejectionReason}',
          'تعديل وإعادة التقديم',
          StatusTone.danger,
        ),
      DoctorApplicationStatus.approved => (
          Icons.verified_outlined,
          scheme.tertiary,
          'تم قبولك كطبيب',
          'سجّل الخروج ثم الدخول لتظهر لوحة الطبيب.',
          'عرض التفاصيل',
          StatusTone.success,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: AppCard(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(title, style: text.titleMedium),
                ),
                // الحالة نصّاً وشارةً معاً، لا لوناً وحده — شرط الوصول.
                if (tone != null)
                  StatusChip(label: _statusLabel(app.status), tone: tone),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(body, style: text.bodySmall),
            if (app.specialization.isNotEmpty &&
                app.status != DoctorApplicationStatus.none) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('التخصص: ${app.specialization}', style: text.bodySmall),
            ],
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: onOpen,
                child: Text(action),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(DoctorApplicationStatus status) =>
      switch (status) {
        DoctorApplicationStatus.pending => 'قيد المراجعة',
        DoctorApplicationStatus.approved => 'مقبول',
        DoctorApplicationStatus.rejected => 'مرفوض',
        DoctorApplicationStatus.none => '',
      };
}
