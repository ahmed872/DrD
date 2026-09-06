import 'package:flutter/material.dart';

import '../constants/appointment_status.dart';
import '../constants/doctor_application_status.dart';
import '../theme/design_tokens.dart';
import 'drd_tone.dart';

/// رقاقة حالة صغيرة — نغمة وأيقونة ونص.
///
/// كانت حالة الموعد تُرسم في كل شاشة بطريقتها: نص ملوّن هنا، `Container`
/// بحواف مستديرة هناك، ولون أخضر لـ«مكتمل» في شاشة وأزرق في أخرى. الرقاقة
/// هنا هي الشكل الوحيد لعرض حالة.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  /// يبني الرقاقة من حالة موعد — الطريقة المفضّلة، فلا تختار الشاشة نغمة
  /// بنفسها ولا تكتب النص العربي يدوياً.
  StatusChip.appointment(AppointmentStatus status, {super.key})
      : label = status.arabicLabel,
        tone = _toneOf(status),
        icon = _iconOf(status);

  final String label;
  final DrdTone tone;

  /// يبني الرقاقة من حالة طلب انضمام طبيب.
  StatusChip.doctorApplication(DoctorApplicationStatus status, {super.key})
      : label = status.arabicLabel,
        tone = _applicationToneOf(status),
        icon = _applicationIconOf(status);

  /// أيقونة بديلة عن أيقونة النغمة، حين تشترك حالتان في نغمة واحدة.
  final IconData? icon;

  /// النغمة الدلالية لكل حالة.
  ///
  /// «ملغي» و«منتهٍ» محايدتان لا خطأ: الإلغاء تصرّف مشروع من المريض، وصبغه
  /// بالأحمر يجعل شاشة المواعيد تبدو كسجل أعطال.
  static DrdTone _toneOf(AppointmentStatus status) => switch (status) {
        AppointmentStatus.booked => DrdTone.info,
        AppointmentStatus.completed => DrdTone.success,
        AppointmentStatus.pendingConfirmation => DrdTone.warning,
        AppointmentStatus.noShow => DrdTone.error,
        AppointmentStatus.cancelled => DrdTone.neutral,
        AppointmentStatus.expired => DrdTone.neutral,
      };

  /// أيقونة لكل حالة على حدة.
  ///
  /// «ملغي» و«منتهٍ» يتشاركان النغمة المحايدة، فلو اعتمدنا على أيقونة النغمة
  /// وحدها لبدت الحالتان متطابقتين تماماً.
  static IconData _iconOf(AppointmentStatus status) => switch (status) {
        AppointmentStatus.booked => Icons.event_available_outlined,
        AppointmentStatus.completed => Icons.check_circle_outline,
        AppointmentStatus.pendingConfirmation => Icons.schedule,
        AppointmentStatus.noShow => Icons.person_off_outlined,
        AppointmentStatus.cancelled => Icons.cancel_outlined,
        AppointmentStatus.expired => Icons.history_toggle_off,
      };

  /// نغمة حالة الطلب.
  ///
  /// «قيد المراجعة» تحذير لا معلومة: هي الحالة الوحيدة التي تنتظر فعلاً من
  /// أحد — من المشرف في شاشته، ومن الطبيب صبراً في شاشته.
  static DrdTone _applicationToneOf(DoctorApplicationStatus status) =>
      switch (status) {
        DoctorApplicationStatus.none => DrdTone.neutral,
        DoctorApplicationStatus.pending => DrdTone.warning,
        DoctorApplicationStatus.approved => DrdTone.success,
        DoctorApplicationStatus.rejected => DrdTone.error,
      };

  static IconData _applicationIconOf(DoctorApplicationStatus status) =>
      switch (status) {
        DoctorApplicationStatus.none => Icons.help_outline,
        DoctorApplicationStatus.pending => Icons.hourglass_empty,
        DoctorApplicationStatus.approved => Icons.verified_outlined,
        DoctorApplicationStatus.rejected => Icons.cancel_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final style = tone.resolve(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DrdSpacing.xs,
        vertical: DrdSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: style.container,
        borderRadius: DrdRadius.smAll,
        border: Border.all(
          color: style.accent.withValues(alpha: 0.35),
          width: DrdSizes.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? style.icon, size: 14, color: style.accent),
          const SizedBox(width: DrdSpacing.xxs),
          Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: style.onContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
