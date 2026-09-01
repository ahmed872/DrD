import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../data/services/patient_home_service.dart';
import '../screens/patient_booking_screen.dart';
import '../screens/patient_medical_history_screen.dart';
import '../screens/patient_my_appointments_screen.dart';
import '../screens/patient_search_doctor_screen.dart';
import 'app_surfaces.dart';
import 'app_widgets.dart';
import 'next_appointment_card.dart';

/// محتوى الصفحة الرئيسية للمريض، بالترتيب المقصود:
///
///   الموعد القادم → البحث عن طبيب → إجراءات سريعة → بقيّة المواعيد
///
/// قبل ذلك كان الترتيب: بطاقة تعرض هاتف المستخدم ونوع حسابه، ثم شبكة من
/// خمس بطاقات متماثلة الوزن — لا شيء فيها يقول للمريض «هذا ما يخصّك الآن».
class PatientHomeSection extends StatefulWidget {
  const PatientHomeSection({
    super.key,
    required this.patientId,
    this.service,
  });

  final String patientId;

  /// للاختبار.
  final PatientHomeService? service;

  @override
  State<PatientHomeSection> createState() => _PatientHomeSectionState();
}

class _PatientHomeSectionState extends State<PatientHomeSection> {
  late Future<PatientHomeSummary> _future;
  final DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PatientHomeSummary> _load() =>
      (widget.service ?? PatientHomeService()).load(widget.patientId);

  void _go(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen))
        .then((_) {
      if (mounted) setState(() => _future = _load());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<PatientHomeSummary>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SkeletonCard(height: 168);
            }
            if (snapshot.hasError) {
              return ErrorStateView(
                message: 'تعذّر تحميل مواعيدك. تحقّق من اتصالك.',
                onRetry: () => setState(() => _future = _load()),
              );
            }
            final summary = snapshot.data!;
            final next = summary.next;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (next == null)
                  NoUpcomingAppointmentCard(
                    onSearch: () => _go(const PatientSearchDoctorScreen()),
                  )
                else
                  NextAppointmentCard(
                    appointment: next,
                    now: _now,
                    onTap: () => _go(const PatientMyAppointmentsScreen()),
                  ),
                const SizedBox(height: AppSpacing.xl),
                _searchCta(context),
                const SizedBox(height: AppSpacing.xl),
                _quickActions(context),
                if (summary.upcoming.length > 1) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  SectionTitle(
                    title: 'مواعيد قادمة',
                    actionLabel: 'الكل',
                    onAction: () => _go(const PatientMyAppointmentsScreen()),
                  ),
                  for (final appointment in summary.upcoming.skip(1).take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: AppointmentListTile(
                        appointment: appointment,
                        now: _now,
                        onTap: () => _go(const PatientMyAppointmentsScreen()),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  /// الفعل الأساسي للمريض في هذا التطبيق. يستحقّ زرّاً بعرض الشاشة لا
  /// بطاقةً في شبكة بين أربع بطاقات متساوية الوزن.
  Widget _searchCta(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => _go(const PatientSearchDoctorScreen()),
      icon: const Icon(Icons.search),
      label: const Text('ابحث عن طبيب واحجز'),
    );
  }

  Widget _quickActions(BuildContext context) {
    return QuickActionsRow(
      actions: [
        QuickAction(
          icon: Icons.event_note,
          label: 'مواعيدي',
          onTap: () => _go(const PatientMyAppointmentsScreen()),
        ),
        QuickAction(
          icon: Icons.add_circle_outline,
          label: 'حجز موعد',
          onTap: () => _go(const PatientBookingScreen()),
        ),
        QuickAction(
          icon: Icons.folder_open,
          label: 'السجل الطبي',
          onTap: () => _go(const PatientMedicalHistoryScreen()),
        ),
      ],
    );
  }
}
