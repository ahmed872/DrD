import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_spacing.dart';
import '../../data/services/availability_service.dart';
import '../../data/services/booking_service.dart';
import '../widgets/app_widgets.dart';
import '../widgets/slot_picker.dart';

/// نقل موعد قائم إلى وقت آخر عند نفس الطبيب.
///
/// `rescheduleAppointment` موجودة على الخادم منذ المرحلة 1ب — بمعاملة ذرّية
/// تحرّر الخانة القديمة وتحجز الجديدة وتربط المستندين — لكن لم يكن لها أي
/// واجهة إطلاقاً، فكان المريض الذي لا يناسبه موعده مضطراً للإلغاء ثم الحجز
/// من جديد، ومعه خطر ألا يجد مكاناً بعد أن ترك مكانه.
class RescheduleAppointmentScreen extends StatefulWidget {
  const RescheduleAppointmentScreen({
    super.key,
    required this.appointmentId,
    required this.doctorId,
    required this.doctorName,
    required this.currentDate,
    required this.currentTime,
    this.currentSlotId,
  });

  final String appointmentId;
  final String doctorId;
  final String doctorName;

  /// `yyyy-MM-dd`.
  final String currentDate;

  /// `HH:mm`.
  final String currentTime;
  final String? currentSlotId;

  @override
  State<RescheduleAppointmentScreen> createState() =>
      _RescheduleAppointmentScreenState();
}

class _RescheduleAppointmentScreenState
    extends State<RescheduleAppointmentScreen> {
  final BookingService _bookingService = BookingService();
  final SlotPickerController _pickerController = SlotPickerController();

  AvailabilitySlot? _selectedSlot;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _pickerController.dispose();
    super.dispose();
  }

  String get _currentDisplay {
    final parsed = DateTime.tryParse(widget.currentDate);
    final dateLabel = parsed == null
        ? widget.currentDate
        : DateFormat('EEEE d MMMM', 'ar').format(parsed);
    return '$dateLabel — ${_formatTime(widget.currentTime)}';
  }

  static String _formatTime(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return time;
    var hour = int.tryParse(parts[0]) ?? 0;
    final period = hour >= 12 ? 'م' : 'ص';
    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour -= 12;
    }
    return '$hour:${parts[1]} $period';
  }

  Future<void> _confirm() async {
    final slot = _selectedSlot;
    if (slot == null) return;

    final parsed = DateTime.parse(slot.date);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد تغيير الموعد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DetailRow(
              label: 'الموعد الحالي',
              value: _currentDisplay,
              icon: Icons.event_busy_outlined,
            ),
            DetailRow(
              label: 'الموعد الجديد',
              value: '${DateFormat('EEEE d MMMM', 'ar').format(parsed)}'
                  ' — ${slot.displayTime}',
              icon: Icons.event_available_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'سيُلغى موعدك الحالي ويُحجز الجديد مكانه.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final result = await _bookingService.reschedule(
      appointmentId: widget.appointmentId,
      newDate: DateTime.parse(slot.date),
      newTime: slot.startTime,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    messenger.showSnackBar(SnackBar(
      content: Text(result.message),
      backgroundColor: result.isSuccess
          ? Theme.of(context).colorScheme.tertiary
          : Theme.of(context).colorScheme.error,
    ));

    if (result.isSuccess) {
      navigator.pop(true);
      return;
    }

    // سباق على الخانة: شخص آخر حجزها بين العرض والتأكيد. نعيد تحميل التوفّر
    // ونُبقي المريض في نفس الشاشة ليختار بديلاً — لا نُخرجه بخطأ نهائي.
    setState(() => _selectedSlot = null);
    _pickerController.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('تغيير الموعد')),
      body: SafeArea(
        child: ContentWidthLimit(
          child: SingleChildScrollView(
            padding: AppSpacing.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: AppSpacing.card,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DetailRow(
                          label: 'الطبيب',
                          value: widget.doctorName,
                          icon: Icons.person_outline,
                        ),
                        DetailRow(
                          label: 'موعدك الحالي',
                          value: _currentDisplay,
                          icon: Icons.schedule,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'اختر الموعد الجديد'),
                SlotPicker(
                  doctorId: widget.doctorId,
                  controller: _pickerController,
                  selectedSlot: _selectedSlot,
                  excludeSlotId: widget.currentSlotId,
                  onSlotSelected: (slot) =>
                      setState(() => _selectedSlot = slot),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (_selectedSlot != null)
                  Container(
                    padding: AppSpacing.card,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: AppRadii.card,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_available,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'الموعد الجديد: '
                            '${DateFormat('EEEE d MMMM', 'ar').format(
                              DateTime.parse(_selectedSlot!.date),
                            )}'
                            ' — ${_selectedSlot!.displayTime}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed:
                      _selectedSlot == null || _isSubmitting ? null : _confirm,
                  icon: _isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.swap_horiz),
                  label: Text(
                    _isSubmitting
                        ? 'جارٍ تغيير الموعد…'
                        : 'تأكيد الموعد الجديد',
                  ),
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
