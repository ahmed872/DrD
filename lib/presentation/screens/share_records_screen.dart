import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/encounter.dart';
import '../../data/services/medical_share_service.dart';

/// اختيار الطبيب ومراجعة ما سيُشارك قبل التأكيد.
///
/// خطوتان في شاشة واحدة: مَن، ثم ماذا. الفصل إلى شاشتين يخفي أحدهما عن
/// الآخر لحظة القرار — والمريض يوافق على الاثنين معاً لا على كلٍّ وحده.
class ShareRecordsScreen extends StatefulWidget {
  const ShareRecordsScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.encounters,
    this.service = const MedicalShareService(),
  });

  final String patientId;
  final String patientName;

  /// السجلات المختارة من شاشة السجل الطبي.
  final List<Encounter> encounters;

  final MedicalShareService service;

  @override
  State<ShareRecordsScreen> createState() => _ShareRecordsScreenState();
}

class _ShareRecordsScreenState extends State<ShareRecordsScreen> {
  late Future<List<DirectoryDoctor>> _doctors;
  DirectoryDoctor? _selected;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _doctors = widget.service.fetchApprovedDoctors(excludeId: widget.patientId);
  }

  Future<void> _confirm() async {
    final recipient = _selected;
    if (recipient == null) return;

    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد المشاركة'),
        content: Text(
          'سيتمكّن ${recipient.name} من الاطلاع على '
          '${widget.encounters.length} من سجلاتك الطبية.\n\n'
          'يمكنك إلغاء المشاركة في أي وقت.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مشاركة'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _sharing = true);

    final result = await widget.service.createShare(
      patientId: widget.patientId,
      patientName: widget.patientName,
      recipient: recipient,
      encounterIds: widget.encounters.map((e) => e.id).toList(),
    );

    if (!mounted) return;
    setState(() => _sharing = false);

    if (result.isSuccess) {
      messenger.showSnackBar(
        AppSnackBar.success('تمت المشاركة. يمكنك إلغاؤها في أي وقت.'),
      );
      navigator.pop(true);
    } else {
      messenger.showSnackBar(
        AppSnackBar.error(result.message ?? 'تعذّرت المشاركة.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مشاركة سجلات طبية')),
      body: FutureBuilder<List<DirectoryDoctor>>(
        future: _doctors,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(
              message: 'تعذّر تحميل قائمة الأطباء. تحقّق من اتصالك.',
              onRetry: () => setState(_load),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }

          final doctors = snapshot.data ?? const <DirectoryDoctor>[];
          if (doctors.isEmpty) {
            return const EmptyView(
              icon: Icons.medical_services_outlined,
              title: 'لا يوجد أطباء متاحون للمشاركة',
              message: 'حاول مرة أخرى لاحقاً.',
            );
          }

          return ListView(
            padding: DrdSpacing.screen,
            children: [
              const SizedBox(height: DrdSpacing.md),

              // ما سيُشارَك — قبل اختيار الطبيب، لا بعده.
              const SectionHeader(
                title: 'السجلات المختارة',
                subtitle: 'هذه وحدها ما سيراه الطبيب',
              ),
              ...widget.encounters.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: DrdSpacing.xs),
                    child: _RecordRow(encounter: e),
                  )),

              const SectionHeader(title: 'اختر الطبيب'),
              ...doctors.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: DrdSpacing.xs),
                    child: _DoctorOption(
                      doctor: d,
                      selected: _selected?.id == d.id,
                      onTap: () => setState(() => _selected = d),
                    ),
                  )),

              const SizedBox(height: DrdSpacing.md),
              // وعد لا يتجاوز ما تفرضه القاعدة فعلاً.
              const AppBanner.info(
                message: 'سيطّلع الطبيب على نسخة من السجلات التي اخترتها فقط. '
                    'لن يرى بقية سجلاتك ولا مواعيدك، ولن يتغيّر ما يراه إذا '
                    'عُدِّل السجل لاحقاً.',
              ),

              const SizedBox(height: DrdSpacing.lg),
              FilledButton(
                onPressed: (_selected == null || _sharing) ? null : _confirm,
                child: _sharing
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.onPrimary,
                        ),
                      )
                    : Text(_selected == null
                        ? 'اختر طبيباً للمتابعة'
                        : 'مشاركة مع ${_selected!.name}'),
              ),
              const SizedBox(height: DrdSpacing.xxl),
            ],
          );
        },
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.encounter});

  final Encounter encounter;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(encounter.encounterDate);
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.description_outlined, color: context.drd.muted, size: 20),
          const SizedBox(width: DrdSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  encounter.diagnosis,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium,
                ),
                Text(
                  date == null
                      ? encounter.encounterDate
                      : DateFormat('d MMMM yyyy', 'ar').format(date),
                  style: context.text.bodySmall
                      ?.copyWith(color: context.drd.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// خيار طبيب — الاختيار يُقرأ بالحدّ والأيقونة معاً، لا باللون وحده.
class _DoctorOption extends StatelessWidget {
  const _DoctorOption({
    required this.doctor,
    required this.selected,
    required this.onTap,
  });

  final DirectoryDoctor doctor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: DrdRadius.lgAll,
        side: BorderSide(
          color: selected ? context.colors.primary : context.drd.border,
          width: selected ? 2 : DrdSizes.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: DrdSpacing.card,
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? context.colors.primary : context.drd.muted,
              ),
              const SizedBox(width: DrdSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctor.name.isEmpty ? 'طبيب' : doctor.name,
                      style: context.text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (doctor.specialization.isNotEmpty)
                      Text(
                        doctor.specialization,
                        style: context.text.bodySmall
                            ?.copyWith(color: context.drd.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
