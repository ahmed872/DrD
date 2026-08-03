import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
// `intl` يصدّر صنفاً باسم `TextDirection` يحجب الصنف الأصلي من Flutter،
// فيفشل `TextDirection.ltr` المستخدم لعرض الأوقات بالأرقام اللاتينية.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_logger.dart';
import '../../data/services/booking_service.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/app_widgets.dart';

class DoctorScheduleScreen extends StatefulWidget {
  const DoctorScheduleScreen({super.key});

  @override
  State<DoctorScheduleScreen> createState() => _DoctorScheduleScreenState();
}

class _DoctorScheduleScreenState extends State<DoctorScheduleScreen> {
  final BookingService _bookingService = BookingService();

  late DateTime _selectedDate;
  int _selectedFilterIndex = 0; // 0: اليوم, 1: الغد, 2: هذا الأسبوع, 3: مخصص
  int _selectedStatusFilter = 0; // 0: قيد الانتظار, 1: مكتملة
  List<Map<String, dynamic>> _appointments = [];
  bool _isLoading = false;
  String? _errorMessage;

  static const List<String> _pendingStatuses = [
    'pending',
    'Booked',
    'Scheduled',
    'upcoming',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _fetchAppointments();
  }

  Future<void> _fetchAppointments() async {
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<FirebaseAuthService>(context, listen: false);

      if (auth.userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // جلب جميع المواعيد للطبيب فقط (بدون composite index)
      Query query = FirebaseFirestore.instance
          .collection('appointments')
          .where('doctorId', isEqualTo: auth.userId);

      final snapshot = await query.get();

      // فلترة الوقت والفرز في Dart بدلاً من Firestore
      final allAppointments = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'patientName': data['patientName'] ?? 'مريض غير معروف',
          'time': data['startTime'] ?? data['time'] ?? '00:00',
          'duration': data['duration'] ?? 30,
          'status': data['status'] ?? 'pending',
          'phone': data['patientPhone'] ?? '',
          'reason': data['reason'] ?? '',
          'notes': data['notes'] ?? '',
          'appointmentDate': data['appointmentDate'] ?? '',
          'doctorId': data['doctorId'] ?? '',
          'patientId': data['patientId'] ?? '',
        };
      }).toList();

      // الآن فلترة حسب التاريخ المختار
      _appointments = allAppointments.where((apt) {
        final apptDate = apt['appointmentDate'] as String;

        if (_selectedFilterIndex == 0) {
          // اليوم فقط
          final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
          return apptDate == today;
        } else if (_selectedFilterIndex == 1) {
          // الغد
          final tomorrow = DateFormat('yyyy-MM-dd')
              .format(DateTime.now().add(const Duration(days: 1)));
          return apptDate == tomorrow;
        } else if (_selectedFilterIndex == 2) {
          // هذا الأسبوع
          final now = DateTime.now();
          final startOfWeek = now.subtract(Duration(days: now.weekday % 7));
          final endOfWeek = startOfWeek.add(const Duration(days: 6));

          try {
            final apptDateTime = DateFormat('yyyy-MM-dd').parse(apptDate);
            return apptDateTime
                    .isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
                apptDateTime.isBefore(endOfWeek.add(const Duration(days: 1)));
          } catch (_) {
            return false;
          }
        }

        // تاريخ مخصّص اختاره الطبيب من التقويم.
        //
        // كان هذا الفرع يُرجع `false` دائماً، فيختار الطبيب تاريخاً من
        // التقويم وتظهر له شاشة فارغة مهما كان عدد المواعيد فيه.
        return apptDate == DateFormat('yyyy-MM-dd').format(_selectedDate);
      }).toList();

      // الفرز حسب الوقت
      _appointments.sort((a, b) => a['time'].compareTo(b['time']));

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      AppLogger.info('Error fetching appointments: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذّر تحميل المواعيد. تأكد من اتصالك بالإنترنت.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _appointments
        .where((apt) => _pendingStatuses.contains(apt['status']))
        .toList();
    final completed =
        _appointments.where((apt) => apt['status'] == 'Completed').toList();

    final visible = _selectedStatusFilter == 0 ? pending : completed;

    return AppScaffold(
      title: 'جدول المواعيد',
      subtitle: _rangeLabel,
      onRefresh: _fetchAppointments,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      actions: [
        IconButton(
          onPressed: () => _selectDate(context),
          icon: const Icon(Icons.calendar_month_outlined),
          color: Colors.white,
          tooltip: 'اختر تاريخاً',
        ),
      ],
      headerBottom: AppSegmented(
        labels: [
          'قيد الانتظار (${pending.length})',
          'مكتملة (${completed.length})',
        ],
        selectedIndex: _selectedStatusFilter,
        onChanged: (i) => setState(() => _selectedStatusFilter = i),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            NoticeBox.danger(
              message: _errorMessage!,
              action: TextButton(
                onPressed: _fetchAppointments,
                child: const Text('إعادة'),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          _buildRangeChips(),
          const SizedBox(height: AppSpacing.lg),
          if (_isLoading)
            const AppLoader(message: 'جارٍ تحميل الجدول…')
          else if (visible.isEmpty)
            EmptyState(
              icon: _selectedStatusFilter == 0
                  ? Icons.event_busy_rounded
                  : Icons.task_alt_rounded,
              title: _selectedStatusFilter == 0
                  ? 'لا توجد مواعيد قيد الانتظار'
                  : 'لا توجد مواعيد مكتملة',
              message: 'جرّب فترة أخرى، أو اختر تاريخاً من التقويم بالأعلى.',
            )
          else
            for (final appointment in visible) ...[
              _AppointmentCard(
                appointment: appointment,
                onComplete: () => _completeAppointment(appointment['id']),
                onCancel: () => _cancelAppointment(appointment['id']),
                onCall: () => _call(appointment['phone'].toString()),
                onNote: () => _showAddNoteDialog(
                  appointment['id'],
                  appointment['notes']?.toString() ?? '',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
        ],
      ),
    );
  }

  String get _rangeLabel => switch (_selectedFilterIndex) {
        0 => 'مواعيد اليوم',
        1 => 'مواعيد الغد',
        2 => 'مواعيد هذا الأسبوع',
        _ => DateFormat('EEEE، d MMMM yyyy', 'ar').format(_selectedDate),
      };

  Widget _buildRangeChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, label) in const [
            (0, 'اليوم'),
            (1, 'الغد'),
            (2, 'هذا الأسبوع'),
          ]) ...[
            AppChip(
              label: label,
              selected: _selectedFilterIndex == i,
              onTap: () {
                setState(() {
                  _selectedFilterIndex = i;
                  _selectedDate = i == 1
                      ? DateTime.now().add(const Duration(days: 1))
                      : DateTime.now();
                });
                _fetchAppointments();
              },
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          AppChip(
            label: _selectedFilterIndex == 3
                ? DateFormat('d MMMM', 'ar').format(_selectedDate)
                : 'تاريخ محدّد',
            selected: _selectedFilterIndex == 3,
            onTap: () => _selectDate(context),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // الإجراءات
  // ===========================================================================

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
      helpText: 'اختر تاريخ الجدول',
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedFilterIndex = 3; // تاريخ مخصّص
      });
      await _fetchAppointments();
    }
  }

  Future<void> _call(String phone) async {
    if (phone.trim().isEmpty) {
      AppSnack.info(context, 'لا يوجد رقم هاتف مسجّل لهذا المريض');
      return;
    }
    final uri = Uri.parse('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) AppSnack.error(context, 'تعذّر فتح تطبيق الاتصال');
    }
  }

  Future<void> _completeAppointment(String appointmentId) async {
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appointmentId)
          .update({'status': 'Completed'});

      await _fetchAppointments();

      if (mounted) {
        AppSnack.success(
            context, 'تم إنهاء الموعد، نتمنى للمريض الشفاء العاجل');
      }
    } catch (e) {
      if (mounted) AppSnack.error(context, 'تعذّر إنهاء الموعد');
    }
  }

  Future<void> _cancelAppointment(String appointmentId) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'إلغاء الموعد',
      message: 'سيُلغى الموعد ويصبح الوقت متاحاً لمريض آخر.',
      confirmLabel: 'تأكيد الإلغاء',
      cancelLabel: 'تراجع',
      destructive: true,
    );

    if (!confirmed) return;

    try {
      // عبر BookingService حتى يُحرَّر قفل الخانة مع تغيير الحالة في معاملة
      // واحدة، فيستطيع مريض آخر حجز الوقت الذي أخلاه الطبيب.
      await _bookingService.cancel(appointmentId: appointmentId);

      await _fetchAppointments();

      if (mounted) AppSnack.success(context, 'تم إلغاء الموعد');
    } catch (e) {
      if (mounted) AppSnack.error(context, 'تعذّر إلغاء الموعد');
    }
  }

  Future<void> _showAddNoteDialog(
    String appointmentId,
    String currentNote,
  ) async {
    final noteController = TextEditingController(text: currentNote);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: ctx.colors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.edit_note_rounded,
            color: ctx.colors.primary,
            size: 26,
          ),
        ),
        title: const Text('ملاحظة طبية', textAlign: TextAlign.center),
        content: TextField(
          controller: noteController,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'التشخيص، العلاج، أو أي ملاحظة يراها المريض في سجلّه…',
            floatingLabelBehavior: FloatingLabelBehavior.never,
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('حفظ'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (saved != true) {
      noteController.dispose();
      return;
    }

    final note = noteController.text.trim();
    noteController.dispose();

    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appointmentId)
          .update({'notes': note});
      await _fetchAppointments();
      if (mounted) AppSnack.success(context, 'تم حفظ الملاحظة');
    } catch (e) {
      // كان هذا الخطأ يُبتلع بصمت: تفشل الكتابة ويظن الطبيب أن ملاحظته
      // حُفظت.
      if (mounted) AppSnack.error(context, 'تعذّر حفظ الملاحظة');
    }
  }
}

// =============================================================================
// بطاقة الموعد
// =============================================================================

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.onComplete,
    required this.onCancel,
    required this.onCall,
    required this.onNote,
  });

  final Map<String, dynamic> appointment;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final VoidCallback onCall;
  final VoidCallback onNote;

  static const List<String> _pendingStatuses = [
    'pending',
    'Booked',
    'Scheduled',
    'upcoming',
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isPending = _pendingStatuses.contains(appointment['status']);
    final statusColor = isPending ? tokens.warning : tokens.success;

    final reason = appointment['reason']?.toString() ?? '';
    final notes = appointment['notes']?.toString() ?? '';
    final phone = appointment['phone']?.toString() ?? '';

    return AppCard(
      accent: statusColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // الوقت هو أهم معلومة في جدول الطبيب — يأخذ أبرز موضع وأكبر حجم.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: AppRadius.rMd,
                  border:
                      Border.all(color: statusColor.withValues(alpha: 0.24)),
                ),
                child: Text(
                  appointment['time'].toString(),
                  textDirection: TextDirection.ltr,
                  style:
                      context.texts.titleMedium?.copyWith(color: statusColor),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment['patientName'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall,
                    ),
                    Text(
                      '${appointment['duration']} دقيقة',
                      style: context.texts.bodySmall
                          ?.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: isPending ? 'قيد الانتظار' : 'مكتملة',
                color: statusColor,
                compact: true,
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _Detail(
              icon: Icons.description_outlined,
              label: 'سبب الزيارة',
              value: reason,
            ),
          ],
          if (phone.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _Detail(
              icon: Icons.phone_outlined,
              label: 'الهاتف',
              value: phone,
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
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
                  Text(
                    'ملاحظاتك',
                    style: context.texts.labelSmall
                        ?.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(notes, style: context.texts.bodySmall),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (isPending)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onComplete,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('إنهاء'),
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.success,
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _IconAction(
                  icon: Icons.phone_rounded,
                  tooltip: 'اتصال بالمريض',
                  onTap: onCall,
                ),
                const SizedBox(width: AppSpacing.sm),
                _IconAction(
                  icon: Icons.close_rounded,
                  tooltip: 'إلغاء الموعد',
                  color: tokens.danger,
                  onTap: onCancel,
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: onNote,
              icon: const Icon(Icons.edit_note_rounded, size: 19),
              label: Text(
                notes.isEmpty ? 'إضافة ملاحظة طبية' : 'تعديل الملاحظة',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: tokens.textMuted),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: context.texts.labelSmall?.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: context.texts.bodySmall?.copyWith(color: tokens.textBody),
          ),
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = color ?? context.colors.primary;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: base.withValues(alpha: 0.1),
        borderRadius: AppRadius.rMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.rMd,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppRadius.rMd,
              border: Border.all(color: base.withValues(alpha: 0.24)),
            ),
            child: Icon(icon, color: base, size: 20),
          ),
        ),
      ),
    );
  }
}
