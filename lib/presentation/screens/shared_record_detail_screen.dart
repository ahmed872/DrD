import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/medical_share_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/medical_share.dart';
import '../../data/services/medical_share_service.dart';

/// مَن يفتح الشاشة — يغيّر ما تعرضه، لا ما تسمح به.
///
/// الصلاحية تفرضها القاعدة على الخادم؛ هذا يقرّر الصياغة فقط: المريض يرى
/// «شاركتَ مع…» ويستطيع الإلغاء، والطبيب يرى «شاركها معك المريض».
enum ShareViewer { patient, doctor }

/// تفاصيل مشاركة — اللقطة كما التُقطت، لا السجل الحيّ.
class SharedRecordDetailScreen extends StatefulWidget {
  const SharedRecordDetailScreen({
    super.key,
    required this.shareId,
    required this.viewer,
    this.service = const MedicalShareService(),
  });

  final String shareId;
  final ShareViewer viewer;
  final MedicalShareService service;

  @override
  State<SharedRecordDetailScreen> createState() =>
      _SharedRecordDetailScreenState();
}

class _SharedRecordDetailScreenState extends State<SharedRecordDetailScreen> {
  bool _revoking = false;

  bool get _isPatient => widget.viewer == ShareViewer.patient;

  Future<void> _revoke(MedicalShare share) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء المشاركة'),
        content: Text(
          'لن يتمكّن ${share.recipientDoctorName} من الاطلاع على هذه '
          'السجلات بعد الآن.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              foregroundColor: context.colors.onError,
            ),
            child: const Text('إلغاء المشاركة'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _revoking = true);

    final result = await widget.service.revoke(share.id);

    if (!mounted) return;
    setState(() => _revoking = false);

    messenger.showSnackBar(
      result.isSuccess
          ? AppSnackBar.success('تم إلغاء المشاركة.')
          : AppSnackBar.error(result.message ?? 'تعذّر إلغاء المشاركة.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isPatient ? 'تفاصيل المشاركة' : 'سجل مشترك'),
      ),
      body: StreamBuilder<MedicalShare?>(
        stream: widget.service.watchShare(widget.shareId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // للطبيب: الإلغاء يقطع الوصول فوراً، فالخطأ هنا معناه المفهوم
            // «لم تعد لديك صلاحية» لا عطل تقني.
            return EmptyView(
              icon: Icons.visibility_off_outlined,
              title: _isPatient
                  ? 'تعذّر تحميل المشاركة'
                  : 'لم تعد لديك صلاحية الاطلاع',
              message: _isPatient
                  ? 'تحقّق من اتصالك وحاول مرة أخرى.'
                  : 'ألغى المريض هذه المشاركة.',
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }

          final share = snapshot.data;
          if (share == null) {
            return const EmptyView(
              icon: Icons.visibility_off_outlined,
              title: 'لم تعد هذه المشاركة متاحة',
            );
          }

          return ListView(
            padding: DrdSpacing.screen,
            children: [
              const SizedBox(height: DrdSpacing.md),
              _Header(share: share, isPatient: _isPatient),
              if (share.status == MedicalShareStatus.pending) ...[
                const SizedBox(height: DrdSpacing.sm),
                const AppBanner.warning(
                  message: 'جارٍ تجهيز نسخة السجلات. لن يراها الطبيب قبل ذلك.',
                ),
              ],
              if (share.status == MedicalShareStatus.rejected) ...[
                const SizedBox(height: DrdSpacing.sm),
                AppBanner.error(
                  title: 'تعذّرت المشاركة',
                  message:
                      share.rejectionReason ?? 'تعذّر تجهيز السجلات المختارة.',
                ),
              ],
              if (share.status == MedicalShareStatus.revoked) ...[
                const SizedBox(height: DrdSpacing.sm),
                const AppBanner.info(
                  message: 'ألغيت هذه المشاركة، ولم يعد الطبيب يرى السجلات.',
                ),
              ],
              if (share.snapshots.isNotEmpty) ...[
                SectionHeader(
                  title: 'السجلات المشتركة',
                  subtitle: _isPatient
                      ? 'هذه النسخة لا تتغيّر إذا عُدِّل السجل لاحقاً'
                      : 'نسخة من سجل المريض وقت المشاركة',
                ),
                ...share.snapshots.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: DrdSpacing.sm),
                      child: _SnapshotCard(snapshot: s),
                    )),
              ],
              if (_isPatient && share.status.isRevocable) ...[
                const SizedBox(height: DrdSpacing.lg),
                OutlinedButton.icon(
                  onPressed: _revoking ? null : () => _revoke(share),
                  icon: const Icon(Icons.visibility_off_outlined),
                  label: const Text('إلغاء المشاركة'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.error,
                    side: BorderSide(color: context.colors.error),
                  ),
                ),
              ],
              const SizedBox(height: DrdSpacing.xxl),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.share, required this.isPatient});

  final MedicalShare share;
  final bool isPatient;

  @override
  Widget build(BuildContext context) {
    // الطبيب يرى المريض، والمريض يرى الطبيب.
    final title = isPatient ? share.recipientDoctorName : share.patientName;
    final subtitle =
        isPatient ? share.recipientDoctorSpecialization : 'شاركها معك المريض';
    final created = share.createdAt;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  isPatient
                      ? Icons.medical_services_outlined
                      : Icons.person_outline,
                  color: context.colors.primary),
              const SizedBox(width: DrdSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? '—' : title,
                      style: context.text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: context.text.bodySmall
                            ?.copyWith(color: context.drd.muted),
                      ),
                  ],
                ),
              ),
              StatusChip.medicalShare(share.status),
            ],
          ),
          if (created != null) ...[
            const Divider(),
            Row(
              children: [
                Icon(Icons.event_outlined, size: 18, color: context.drd.muted),
                const SizedBox(width: DrdSpacing.xs),
                Text(
                  'شُوركت في ${DateFormat('d MMMM yyyy', 'ar').format(created)}',
                  style: context.text.bodyMedium,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// لقطة سجل واحد.
///
/// تُميَّز صراحةً بأنها **نسخة شاركها المريض**، لا سجل ألّفه القارئ — حتى
/// لا يظنّ الطبيب المستقبِل أنه يملك تعديلها أو أنها من كشفه.
class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.snapshot});

  final SharedEncounterSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(snapshot.encounterDate);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  snapshot.doctorName.isEmpty
                      ? 'الطبيب المعالِج'
                      : snapshot.doctorName,
                  style: context.text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                date == null
                    ? snapshot.encounterDate
                    : DateFormat('d MMM yyyy', 'ar').format(date),
                style:
                    context.text.bodySmall?.copyWith(color: context.drd.muted),
              ),
            ],
          ),
          if (snapshot.doctorSpecialization.isNotEmpty)
            Text(
              snapshot.doctorSpecialization,
              style: context.text.bodySmall?.copyWith(color: context.drd.muted),
            ),
          const Divider(),
          _Field(label: 'التشخيص', value: snapshot.diagnosis),
          if (snapshot.clinicalNotes.isNotEmpty)
            _Field(label: 'ملاحظات الكشف', value: snapshot.clinicalNotes),
          if (snapshot.treatmentPlan.isNotEmpty)
            _Field(label: 'العلاج / الوصفة', value: snapshot.treatmentPlan),
          if (snapshot.followUpNotes.isNotEmpty)
            _Field(label: 'المتابعة', value: snapshot.followUpNotes),
          if (snapshot.followUpDate.isNotEmpty)
            _Field(label: 'موعد المتابعة', value: snapshot.followUpDate),
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
          SelectableText(
            value,
            style: context.text.bodyLarge?.copyWith(height: 1.8),
          ),
        ],
      ),
    );
  }
}
