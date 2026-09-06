import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/encounter.dart';
import '../../data/services/encounter_service.dart';

/// نموذج توثيق زيارة.
///
/// النموذج قصير عمداً. يُملأ بعد كشف، والطبيب واقف: كل حقل إضافي هنا يعني
/// سجلاً لا يُكتب أصلاً. التشخيص وحده مطلوب — البقية اختيارية لأن ليست كل
/// زيارة تنتهي بوصفة أو متابعة.
class DoctorEncounterScreen extends StatefulWidget {
  const DoctorEncounterScreen({
    super.key,
    required this.appointmentId,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    required this.doctorSpecialization,
    required this.encounterDate,
    this.existing,
    this.service = const EncounterService(),
  });

  final String appointmentId;
  final String patientId;
  final String patientName;
  final String doctorId;
  final String doctorName;
  final String doctorSpecialization;

  /// تاريخ الزيارة (yyyy-MM-dd) — من الموعد، لا اليوم.
  final String encounterDate;

  /// السجل القائم عند التصحيح.
  final Encounter? existing;

  final EncounterService service;

  @override
  State<DoctorEncounterScreen> createState() => _DoctorEncounterScreenState();
}

class _DoctorEncounterScreenState extends State<DoctorEncounterScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _diagnosis;
  late final TextEditingController _notes;
  late final TextEditingController _treatment;
  late final TextEditingController _followUp;

  DateTime? _followUpDate;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _diagnosis = TextEditingController(text: e?.diagnosis ?? '');
    _notes = TextEditingController(text: e?.clinicalNotes ?? '');
    _treatment = TextEditingController(text: e?.treatmentPlan ?? '');
    _followUp = TextEditingController(text: e?.followUpNotes ?? '');
    final raw = e?.followUpDate ?? '';
    if (raw.isNotEmpty) _followUpDate = DateTime.tryParse(raw);
  }

  @override
  void dispose() {
    _diagnosis.dispose();
    _notes.dispose();
    _treatment.dispose();
    _followUp.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // المُرسِل والمُوجِّه يُلتقطان قبل الانتظار.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    final result = await widget.service.save(
      appointmentId: widget.appointmentId,
      patientId: widget.patientId,
      doctorId: widget.doctorId,
      doctorName: widget.doctorName,
      doctorSpecialization: widget.doctorSpecialization,
      encounterDate: widget.encounterDate,
      diagnosis: _diagnosis.text,
      clinicalNotes: _notes.text,
      treatmentPlan: _treatment.text,
      followUpNotes: _followUp.text,
      followUpDate: _followUpDate == null
          ? ''
          : DateFormat('yyyy-MM-dd').format(_followUpDate!),
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result.isSuccess) {
      // حفظ ناجح لا يُعرض كخطأ.
      messenger.showSnackBar(
        AppSnackBar.success('تم حفظ سجل الزيارة بنجاح.'),
      );
      navigator.pop(true);
    } else {
      messenger.showSnackBar(
        AppSnackBar.error(result.message ?? 'تعذّر حفظ سجل الزيارة.'),
      );
    }
  }

  Future<void> _pickFollowUpDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUpDate ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => _followUpDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'تصحيح سجل الزيارة' : 'سجل الزيارة'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: DrdSpacing.screen,
          children: [
            const SizedBox(height: DrdSpacing.md),

            // مَن ومتى — حتى لا يُكتب سجل على المريض الخطأ.
            AppCard(
              child: Row(
                children: [
                  Icon(Icons.person_outline, color: context.colors.primary),
                  const SizedBox(width: DrdSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.patientName.isEmpty
                              ? 'المريض'
                              : widget.patientName,
                          style: context.text.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'زيارة ${widget.encounterDate}',
                          style: context.text.bodySmall
                              ?.copyWith(color: context.drd.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_isEdit) ...[
              const SizedBox(height: DrdSpacing.sm),
              const AppBanner.info(
                message: 'تصحيح السجل يحفظ نسخة مما كان عليه قبل التعديل.',
              ),
            ],

            const SectionHeader(title: 'التشخيص'),
            TextFormField(
              controller: _diagnosis,
              textInputAction: TextInputAction.next,
              maxLength: EncounterService.maxDiagnosisLength,
              decoration: const InputDecoration(
                hintText: 'مثال: التهاب لوزتين حاد',
                prefixIcon: Icon(Icons.medical_information_outlined),
              ),
              validator: EncounterService.validateDiagnosis,
            ),

            const SectionHeader(title: 'ملاحظات الكشف'),
            TextFormField(
              controller: _notes,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'الأعراض، القياسات، ما لاحظته أثناء الكشف.',
                alignLabelWithHint: true,
              ),
              validator: EncounterService.validateNotes,
            ),

            const SectionHeader(title: 'العلاج / الوصفة'),
            TextFormField(
              controller: _treatment,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'الدواء والجرعة والمدة.',
                alignLabelWithHint: true,
              ),
              validator: EncounterService.validateNotes,
            ),

            const SectionHeader(title: 'المتابعة'),
            TextFormField(
              controller: _followUp,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'تعليمات للمريض، ومتى يعود.',
                alignLabelWithHint: true,
              ),
              validator: EncounterService.validateFollowUpNotes,
            ),
            const SizedBox(height: DrdSpacing.sm),
            InkWell(
              onTap: _pickFollowUpDate,
              borderRadius: DrdRadius.smAll,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'موعد المتابعة (اختياري)',
                  prefixIcon: const Icon(Icons.event_outlined),
                  suffixIcon: _followUpDate == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'إزالة',
                          onPressed: () => setState(() => _followUpDate = null),
                        ),
                ),
                child: Text(
                  _followUpDate == null
                      ? 'بلا موعد متابعة'
                      : DateFormat('d MMMM yyyy', 'ar').format(_followUpDate!),
                  style: _followUpDate == null
                      ? TextStyle(color: context.drd.disabled)
                      : null,
                ),
              ),
            ),

            const SizedBox(height: DrdSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.onPrimary,
                      ),
                    )
                  : Text(_isEdit ? 'حفظ التصحيح' : 'حفظ السجل'),
            ),
            const SizedBox(height: DrdSpacing.xxl),
          ],
        ),
      ),
    );
  }
}
