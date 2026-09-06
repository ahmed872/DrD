import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/doctor_application_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/doctor_application.dart';
import '../../data/services/doctor_application_service.dart';
import '../providers/firebase_auth_service.dart';

/// تفاصيل طلب واحد، وقرار المشرف فيه.
///
/// ما يظهر هنا هو ما كتبه مقدّم الطلب وحده. لا شيء من ملفه الطبي ولا مواعيده
/// ولا بيانات مرضاه — القرار في هذه الشاشة عن مؤهّل مهني، لا عن صحّة شخص.
class AdminApplicationDetailScreen extends StatefulWidget {
  const AdminApplicationDetailScreen({super.key, required this.application});

  final DoctorApplication application;

  @override
  State<AdminApplicationDetailScreen> createState() =>
      _AdminApplicationDetailScreenState();
}

class _AdminApplicationDetailScreenState
    extends State<AdminApplicationDetailScreen> {
  final _service = DoctorApplicationService();
  bool _busy = false;

  DoctorApplication get _app => widget.application;

  Future<void> _approve() async {
    final auth = context.read<FirebaseAuthService>();
    final reviewerId = auth.userId;
    if (reviewerId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('قبول الطلب'),
        content: Text(
          'سيصبح ${_app.applicantName} طبيباً على DrD، ويظهر للمرضى '
          'ويستقبل الحجوزات.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('قبول'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);

    final result = await _service.approve(
      applicationId: _app.applicantId,
      reviewerId: reviewerId,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (result.isSuccess) {
      messenger.showSnackBar(AppSnackBar.success('تم قبول الطلب.'));
      navigator.pop();
    } else {
      messenger.showSnackBar(
        AppSnackBar.error(result.message ?? 'تعذّر قبول الطلب.'),
      );
    }
  }

  Future<void> _reject() async {
    final auth = context.read<FirebaseAuthService>();
    final reviewerId = auth.userId;
    if (reviewerId == null) return;

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectionReasonDialog(),
    );
    if (reason == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);

    final result = await _service.reject(
      applicationId: _app.applicantId,
      reviewerId: reviewerId,
      reason: reason,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (result.isSuccess) {
      messenger.showSnackBar(AppSnackBar.success('تم تسجيل الرفض.'));
      navigator.pop();
    } else {
      messenger.showSnackBar(
        AppSnackBar.error(result.message ?? 'تعذّر رفض الطلب.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitted = _app.submittedAt;
    final reviewed = _app.reviewedAt;

    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الطلب')),
      body: ListView(
        padding: DrdSpacing.screen,
        children: [
          const SizedBox(height: DrdSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _app.applicantName,
                        style: context.text.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    StatusChip.doctorApplication(_app.status),
                  ],
                ),
                const SizedBox(height: DrdSpacing.xs),
                Text(
                  _app.specialty,
                  style: context.text.bodyLarge
                      ?.copyWith(color: context.colors.primary),
                ),
              ],
            ),
          ),
          if (_app.activeRejectionReason != null) ...[
            const SizedBox(height: DrdSpacing.sm),
            AppBanner.error(
              title: 'سبب الرفض المسجَّل',
              message: _app.activeRejectionReason!,
            ),
          ],
          const SectionHeader(title: 'البيانات المهنية'),
          _Field(label: 'سنوات الخبرة', value: '${_app.yearsOfExperience}'),
          _Field(label: 'النبذة المهنية', value: _app.professionalBio),
          if (_app.applicantNotes.isNotEmpty)
            _Field(label: 'ملاحظات مقدّم الطلب', value: _app.applicantNotes),
          const SectionHeader(title: 'سجل الطلب'),
          if (submitted != null)
            _Field(
              label: 'تاريخ التقديم',
              value: DateFormat('d MMMM yyyy — HH:mm', 'ar').format(submitted),
            ),
          if (reviewed != null)
            _Field(
              label: 'تاريخ آخر مراجعة',
              value: DateFormat('d MMMM yyyy — HH:mm', 'ar').format(reviewed),
            ),
          const SizedBox(height: DrdSpacing.lg),
          if (_app.status == DoctorApplicationStatus.pending) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _approve,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('قبول الطلب'),
            ),
            const SizedBox(height: DrdSpacing.sm),
            OutlinedButton.icon(
              onPressed: _busy ? null : _reject,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('رفض الطلب'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.error,
                side: BorderSide(color: context.colors.error),
              ),
            ),
          ] else
            // القرار اتُّخذ. القاعدة على الخادم ترفض مراجعة طلب مبتوت فيه،
            // فعرض الأزرار هنا كان سيَعِد بما لا يمكن تنفيذه.
            AppBanner.info(
              message: _app.status == DoctorApplicationStatus.approved
                  ? 'هذا الطلب مقبول، ولا يمكن الرجوع فيه من التطبيق.'
                  : 'هذا الطلب مرفوض. يمكن لمقدّمه تصحيحه وإعادة تقديمه.',
            ),
          const SizedBox(height: DrdSpacing.xxl),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DrdSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.bodySmall?.copyWith(color: context.drd.muted),
          ),
          const SizedBox(height: DrdSpacing.xxs),
          Text(value, style: context.text.bodyMedium),
        ],
      ),
    );
  }
}

/// حوار سبب الرفض.
///
/// السبب إلزامي، والحدّ الأدنى مفروض في القاعدة أيضاً. الفحص هنا يوفّر على
/// المشرف رحلة ذهاب وعودة إلى الخادم ليكتشف أن سببه قصير.
class _RejectionReasonDialog extends StatefulWidget {
  const _RejectionReasonDialog();

  @override
  State<_RejectionReasonDialog> createState() => _RejectionReasonDialogState();
}

class _RejectionReasonDialogState extends State<_RejectionReasonDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('سبب الرفض'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سيقرأ مقدّم الطلب هذا النص. اكتب ما يمكنه تصحيحه.',
              style: context.text.bodySmall?.copyWith(color: context.drd.muted),
            ),
            const SizedBox(height: DrdSpacing.sm),
            TextFormField(
              controller: _controller,
              maxLines: 4,
              maxLength: DoctorApplicationService.maxRejectionReasonLength,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'مثال: النبذة المهنية لا توضّح مكان الممارسة.',
              ),
              validator: DoctorApplicationService.validateRejectionReason,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('رجوع'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
          child: const Text('تأكيد الرفض'),
        ),
      ],
    );
  }
}
