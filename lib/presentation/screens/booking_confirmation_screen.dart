import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_spacing.dart';
import '../widgets/app_widgets.dart';
import 'patient_my_appointments_screen.dart';

/// تأكيد نجاح الحجز.
///
/// كان الحجز الناجح ينتهي بـ SnackBar يختفي بعد ثوانٍ، والمريض يعود لقائمة
/// الأطباء بلا أثر مرئي لما فعله. الحجز أهم لحظة في التطبيق، ويستحق شاشة
/// تُثبت ما حدث وتقول ما التالي.
class BookingConfirmationScreen extends StatelessWidget {
  const BookingConfirmationScreen({
    super.key,
    required this.doctorName,
    required this.specialization,
    required this.date,
    required this.startTime,
    required this.price,
    this.appointmentId,
    this.alreadyBooked = false,
  });

  final String doctorName;
  final String specialization;

  /// `yyyy-MM-dd`.
  final String date;

  /// `HH:mm`.
  final String startTime;
  final Object? price;
  final String? appointmentId;

  /// الطلب وصل الخادم مرتين وأُعيد نفس الموعد — نجاح، لا خطأ.
  final bool alreadyBooked;

  String get _displayTime {
    final parts = startTime.split(':');
    if (parts.length != 2) return startTime;
    var hour = int.tryParse(parts[0]) ?? 0;
    final period = hour >= 12 ? 'م' : 'ص';
    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour -= 12;
    }
    return '$hour:${parts[1]} $period';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsedDate = DateTime.tryParse(date);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تم تأكيد الحجز'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ContentWidthLimit(
          child: SingleChildScrollView(
            padding: AppSpacing.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xl),
                Icon(
                  Icons.check_circle,
                  size: 88,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  alreadyBooked ? 'هذا الموعد محجوز لك بالفعل' : 'تم حجز موعدك',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'نتمنى لك دوام الصحة والعافية',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Card(
                  child: Padding(
                    padding: AppSpacing.card,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DetailRow(
                          label: 'الطبيب',
                          value: doctorName,
                          icon: Icons.person_outline,
                        ),
                        DetailRow(
                          label: 'التخصص',
                          value: specialization,
                          icon: Icons.medical_services_outlined,
                        ),
                        DetailRow(
                          label: 'التاريخ',
                          value: parsedDate == null
                              ? date
                              : DateFormat('EEEE d MMMM yyyy', 'ar')
                                  .format(parsedDate),
                          icon: Icons.calendar_today_outlined,
                        ),
                        DetailRow(
                          label: 'الوقت',
                          value: _displayTime,
                          icon: Icons.access_time,
                        ),
                        if (price != null)
                          DetailRow(
                            label: 'سعر الكشف',
                            value: '$price جنيه',
                            icon: Icons.payments_outlined,
                          ),
                        const SizedBox(height: AppSpacing.sm),
                        const Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: StatusChip(
                            label: 'محجوز',
                            tone: StatusTone.info,
                            icon: Icons.event_available,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: AppSpacing.card,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: AppRadii.cardRadius,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_active_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'سيصلك تذكير قبل الموعد بساعة',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const PatientMyAppointmentsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.event_note_outlined),
                  label: const Text('عرض مواعيدي'),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('العودة للرئيسية'),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
