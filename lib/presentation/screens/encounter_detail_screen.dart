import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/encounter.dart';

/// تفاصيل زيارة واحدة.
///
/// الشاشة نفسها للمريض وللطبيب المؤلِّف — الفرق زرّ التصحيح وحده. المريض
/// **قارئ دائماً**: لا حقل قابل للتحرير هنا، ولا زرّ حفظ، ولا حذف. وقاعدة
/// الأمان ترفض كتابته حتى لو ظهر زرّ بالخطأ.
class EncounterDetailScreen extends StatelessWidget {
  const EncounterDetailScreen({
    super.key,
    required this.encounter,
    this.onEdit,
  });

  final Encounter encounter;

  /// يُمرَّر للطبيب المؤلِّف وحده. `null` للمريض.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(encounter.encounterDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الزيارة'),
        actions: [
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'تصحيح السجل',
              onPressed: onEdit,
            ),
        ],
      ),
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
                    Icon(Icons.medical_services_outlined,
                        color: context.colors.primary),
                    const SizedBox(width: DrdSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            encounter.doctorName.isEmpty
                                ? 'الطبيب المعالِج'
                                : encounter.doctorName,
                            style: context.text.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (encounter.doctorSpecialization.isNotEmpty)
                            Text(
                              encounter.doctorSpecialization,
                              style: context.text.bodySmall
                                  ?.copyWith(color: context.drd.muted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    Icon(Icons.event_outlined,
                        size: 18, color: context.drd.muted),
                    const SizedBox(width: DrdSpacing.xs),
                    Text(
                      date == null
                          ? encounter.encounterDate
                          : DateFormat('d MMMM yyyy', 'ar').format(date),
                      style: context.text.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (encounter.wasEdited) ...[
            const SizedBox(height: DrdSpacing.sm),
            // الشفافية مقصودة: المريض له أن يعرف أن سجله عُدِّل بعد كتابته.
            const AppBanner.info(
              message: 'صُحِّح هذا السجل بعد كتابته.',
            ),
          ],
          const SectionHeader(title: 'التشخيص'),
          _Clinical(text: encounter.diagnosis),
          if (encounter.clinicalNotes.isNotEmpty) ...[
            const SectionHeader(title: 'ملاحظات الكشف'),
            _Clinical(text: encounter.clinicalNotes),
          ],
          if (encounter.treatmentPlan.isNotEmpty) ...[
            const SectionHeader(title: 'العلاج / الوصفة'),
            _Clinical(text: encounter.treatmentPlan),
          ],
          if (encounter.followUpNotes.isNotEmpty ||
              encounter.followUpDate.isNotEmpty) ...[
            const SectionHeader(title: 'المتابعة'),
            if (encounter.followUpNotes.isNotEmpty)
              _Clinical(text: encounter.followUpNotes),
            if (encounter.followUpDate.isNotEmpty) ...[
              const SizedBox(height: DrdSpacing.xs),
              _FollowUpDate(raw: encounter.followUpDate),
            ],
          ],
          const SizedBox(height: DrdSpacing.xxl),
        ],
      ),
    );
  }
}

/// نص سريري — يُعرض كاملاً، بلا اقتطاع.
class _Clinical extends StatelessWidget {
  const _Clinical({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: SelectableText(
        text,
        // ارتفاع سطر أوسع: النص السريري يُقرأ بعناية لا يُمسح بالعين.
        style: context.text.bodyLarge?.copyWith(height: 1.8),
      ),
    );
  }
}

class _FollowUpDate extends StatelessWidget {
  const _FollowUpDate({required this.raw});

  final String raw;

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(raw);
    final label =
        parsed == null ? raw : DateFormat('d MMMM yyyy', 'ar').format(parsed);

    return Row(
      children: [
        Icon(Icons.event_repeat_outlined,
            size: 18, color: context.colors.primary),
        const SizedBox(width: DrdSpacing.xs),
        Text('موعد المتابعة: $label', style: context.text.bodyMedium),
      ],
    );
  }
}
