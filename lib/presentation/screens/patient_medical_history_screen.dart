import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/app_widgets.dart';

class PatientMedicalHistoryScreen extends StatefulWidget {
  const PatientMedicalHistoryScreen({super.key});

  @override
  State<PatientMedicalHistoryScreen> createState() =>
      _PatientMedicalHistoryScreenState();
}

class _PatientMedicalHistoryScreenState
    extends State<PatientMedicalHistoryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _medicalRecords = [];

  @override
  void initState() {
    super.initState();
    _fetchMedicalHistory();
  }

  Future<void> _fetchMedicalHistory() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // We'll fetch completed appointments as the medical history
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('patientId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'Completed')
          .get();

      List<Map<String, dynamic>> records = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        records.add({
          'id': doc.id,
          'date': data['appointmentDate'] ?? '',
          'doctor': data['doctorName'] ?? '',
          'specialization': data['doctorSpecialization'] ?? '',
          'reasonAr': data['reason'] ?? '',
          'diagnosisAr': data['diagnosisAr'] ?? '',
          'prescriptionAr': data['prescriptionAr'] ?? '',
          'notesAr': data['notesAr'] ?? data['notes'] ?? '',
        });
      }

      // Sort by date descending
      records
          .sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

      if (!mounted) return;
      setState(() {
        _medicalRecords = records;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnack.error(context, 'خطأ في جلب السجل الطبي');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'السجل الطبي',
      subtitle: _isLoading ? null : '${_medicalRecords.length} زيارة مكتملة',
      onRefresh: _fetchMedicalHistory,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      child: _isLoading
          ? const AppLoader(message: 'جارٍ تحميل سجلّك…')
          : _medicalRecords.isEmpty
              ? const EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'لا يوجد سجل طبي بعد',
                  message: 'بعد أول زيارة مكتملة، ستجد تفاصيلها هنا: التشخيص '
                      'والوصفة وملاحظات الطبيب.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _medicalRecords.length; i++)
                      _TimelineEntry(
                        record: _medicalRecords[i],
                        isLast: i == _medicalRecords.length - 1,
                      ),
                  ],
                ),
    );
  }
}

/// عنصر في خط زمني رأسي.
///
/// السجل الطبي تسلسل زمني بطبيعته، والخط الواصل يوضّح ذلك فوراً — على عكس
/// بطاقات منفصلة لا يظهر منها أي ترتيب.
class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.record, required this.isLast});

  final Map<String, dynamic> record;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 13,
                height: 13,
                margin: const EdgeInsets.only(top: AppSpacing.xl),
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.colors.primary.withValues(alpha: 0.25),
                    width: 4,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: tokens.border),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: _RecordCard(record: record),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final diagnosis = record['diagnosisAr']?.toString() ?? '';
    final prescription = record['prescriptionAr']?.toString() ?? '';
    final reason = record['reasonAr']?.toString() ?? '';
    final notes = record['notesAr']?.toString() ?? '';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record['doctor'].toString().isEmpty
                          ? 'زيارة'
                          : record['doctor'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall,
                    ),
                    Text(
                      _formatDate(record['date'].toString()),
                      style: context.texts.bodySmall
                          ?.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: 'مكتملة',
                color: tokens.success,
                icon: Icons.check_rounded,
                compact: true,
              ),
            ],
          ),
          Divider(color: tokens.border, height: AppSpacing.xxl),
          _Field(
            icon: Icons.help_outline_rounded,
            label: 'سبب الزيارة',
            value: reason,
            color: context.colors.primary,
          ),
          _Field(
            icon: Icons.medical_information_outlined,
            label: 'التشخيص',
            value: diagnosis,
            color: tokens.warning,
          ),
          _Field(
            icon: Icons.medication_outlined,
            label: 'الوصفة الطبية',
            value: prescription,
            color: tokens.success,
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: tokens.surfaceSunken,
                borderRadius: AppRadius.rMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.sticky_note_2_outlined,
                        size: 15,
                        color: tokens.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'ملاحظات الطبيب',
                        style: context.texts.labelSmall
                            ?.copyWith(color: tokens.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(notes, style: context.texts.bodySmall),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.isEmpty ? 'بدون تاريخ' : raw;
    return DateFormat('EEEE، d MMMM yyyy', 'ar').format(parsed);
  }
}

/// حقل في بطاقة السجل. الحقل الفارغ يظهر بنص رمادي صريح («لم يُسجَّل») بدل
/// إخفائه: غياب التشخيص معلومة في حدّ ذاته للمريض.
class _Field extends StatelessWidget {
  const _Field({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final empty = value.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: empty ? tokens.textFaint : color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.texts.labelSmall
                      ?.copyWith(color: tokens.textMuted),
                ),
                Text(
                  empty ? 'لم يُسجَّل' : value,
                  style: context.texts.bodyMedium?.copyWith(
                    color: empty ? tokens.textFaint : tokens.textBody,
                    fontStyle: empty ? FontStyle.italic : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
