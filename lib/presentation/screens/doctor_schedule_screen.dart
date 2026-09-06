import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../data/services/booking_service.dart';
import '../providers/firebase_auth_service.dart';
import '../../core/constants/appointment_status.dart';
import '../../core/utils/app_logger.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/encounter.dart';
import '../../data/services/encounter_service.dart';
import 'doctor_encounter_screen.dart';
import 'encounter_detail_screen.dart';

class DoctorScheduleScreen extends StatefulWidget {
  const DoctorScheduleScreen({super.key});

  @override
  State<DoctorScheduleScreen> createState() => _DoctorScheduleScreenState();
}

class _DoctorScheduleScreenState extends State<DoctorScheduleScreen> {
  final EncounterService _encounters = const EncounterService();

  final BookingService _bookingService = BookingService();

  late DateTime _selectedDate;
  int _selectedFilterIndex = 0; // 0: اليوم, 1: الغد, 2: هذا الأسبوع, -1: مخصص
  int _selectedStatusFilter = 0; // 0: All, 1: Pending, 2: Completed
  List<Map<String, dynamic>> _appointments = [];
  bool _isLoading = false;
  String? _errorMessage;
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldMessenger = ScaffoldMessenger.of(context);
    });
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
          'patientName': data['patientName'] ?? 'Unknown',
          'patientNameEn': data['patientNameEn'] ?? 'Unknown',
          'time': data['startTime'] ?? data['time'] ?? '00:00',
          'duration': data['duration'] ?? 30,
          'status': data['status'] ?? AppointmentStatus.booked.wireValue,
          'phone': data['patientPhone'] ?? '-',
          'reason': data['reason'] ?? 'Consultation',
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
        return false;
      }).toList();

      // الفرز حسب الوقت
      _appointments.sort((a, b) => a['time'].compareTo(b['time']));

      if (mounted) setState(() => _isLoading = false);
      if (mounted) setState(() => _errorMessage = null);
    } catch (e) {
      AppLogger.info('Error fetching appointments: $e');
      final errorMsg = 'خطأ في الاتصال: ${e.toString().substring(0, 50)}...';

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = errorMsg;
        });

        // إظهار SnackBar مع Dismiss button وDuration
        _scaffoldMessenger?.hideCurrentSnackBar();
        _scaffoldMessenger?.showSnackBar(
          AppSnackBar.error(
            errorMsg,
            action: SnackBarAction(
              label: 'أعد المحاولة',
              onPressed: _fetchAppointments,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // فصل المواعيد القادمة عن المكتملة.
    //
    // كانت المقارنة هنا نصّية مباشرة على أربع صيغ مكتوبة يدوياً، فأي موعد
    // مخزَّن بصيغة أخرى (`confirmed` مثلاً) كان يختفي من القائمتين معاً.
    // `AppointmentStatus.parse` هو المرجع الوحيد لتفسير الحالة وهو يعرف كل
    // الصيغ التاريخية.
    final pendingAppointments = _appointments
        .where((apt) => AppointmentStatus.parse(apt['status']).isActive)
        .toList();

    final completedAppointments = _appointments
        .where((apt) =>
            AppointmentStatus.parse(apt['status']) ==
            AppointmentStatus.completed)
        .toList();

    final appointmentsToShow = _selectedStatusFilter == 0
        ? pendingAppointments
        : completedAppointments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('جدول المواعيد'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchAppointments,
              child: Column(
                children: [
                  // ✅ عرض رسالة الخطأ إذا كانت موجودة
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.all(DrdSpacing.sm),
                      child: AppBanner.error(
                        message: _errorMessage!,
                        action: TextButton(
                          onPressed: _fetchAppointments,
                          child: const Text('أعد المحاولة / Retry'),
                        ),
                        onDismiss: () => setState(() => _errorMessage = null),
                      ),
                    ),
                  // ✅ Tabs للفصل بين المواعيد القادمة والمكتملة
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: context.colors.surface,
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildTab(
                            'المواعيد المكتملة (${completedAppointments.length})',
                            1,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTab(
                            'المواعيد القادمة (${pendingAppointments.length})',
                            0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _buildDateSection(),
                            const SizedBox(height: 24),
                            _buildAppointmentsList(appointmentsToShow),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTab(String title, int index) {
    final isSelected = _selectedStatusFilter == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedStatusFilter = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? context.colors.primary : context.drd.border,
              width: isSelected ? 3 : DrdSizes.hairline,
            ),
          ),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? context.colors.primary : context.drd.muted,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildDateSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'اختر التاريخ / Select Date',
              style: context.text.titleSmall?.copyWith(
                color: context.drd.muted,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true, // لأننا RTL
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('اليوم'),
                    selected: _selectedFilterIndex == 0,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedFilterIndex = 0;
                          _selectedDate = DateTime.now();
                        });
                        _fetchAppointments();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('الغد'),
                    selected: _selectedFilterIndex == 1,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedFilterIndex = 1;
                          _selectedDate = DateTime.now().add(
                            const Duration(days: 1),
                          );
                        });
                        _fetchAppointments();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('هذا الأسبوع'),
                    selected: _selectedFilterIndex == 2,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedFilterIndex = 2;
                        });
                        _fetchAppointments();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _selectDate(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: context.drd.border),
                  borderRadius: DrdRadius.smAll,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.calendar_today, color: context.colors.primary),
                    Text(
                      _selectedFilterIndex == 2
                          ? 'مواعيد هذا الأسبوع'
                          : DateFormat(
                              'EEEE, d MMMM yyyy',
                              'ar',
                            ).format(_selectedDate),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentsList(List<Map<String, dynamic>> appointments) {
    if (appointments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.calendar_today, size: 64, color: context.drd.disabled),
              const SizedBox(height: DrdSpacing.md),
              Text(
                'لا توجد مواعيد',
                style: context.text.titleSmall?.copyWith(
                  color: context.drd.muted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'No appointments',
                style: context.text.bodyMedium?.copyWith(
                  color: context.drd.disabled,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Text(
          '\ مواعيد / \ Appointments',
          style: context.text.bodySmall?.copyWith(color: context.drd.muted),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: appointments.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final appointment = appointments[index];
            return _buildAppointmentCard(appointment);
          },
        ),
      ],
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    final isPending = AppointmentStatus.parse(appointment['status']).isActive;

    return InkWell(
      onTap: () {
        _showAppointmentDetailsDialog(appointment);
      },
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 2,
        // الموعد القائم يستحق حدّاً أوضح؛ المكتمل يتراجع بصرياً.
        shape: RoundedRectangleBorder(
          borderRadius: DrdRadius.lgAll,
          side: BorderSide(
            color: isPending ? context.colors.primary : context.drd.border,
            width: DrdSizes.hairline,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  StatusChip.appointment(
                    AppointmentStatus.parse(appointment['status']),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '🕐 ${appointment['time']}',
                        style: context.text.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              _infoRow(
                icon: Icons.person,
                label: 'المريض / Patient',
                value: appointment['patientName'],
                valueEn: appointment['patientNameEn'],
              ),
              const SizedBox(height: 12),
              _infoRow(
                icon: Icons.phone,
                label: 'الهاتف / Phone',
                value: appointment['phone'],
              ),
              const SizedBox(height: 12),
              _infoRow(
                icon: Icons.medical_services,
                label: 'السبب / Reason',
                value: appointment['reason'],
              ),
              const SizedBox(height: 12),
              if (appointment['notes'] != null &&
                  appointment['notes'].isNotEmpty)
                _infoRow(
                  icon: Icons.note_alt,
                  label: 'ملاحظات / Notes',
                  value: appointment['notes'],
                ),
              const SizedBox(height: 16),
              if (isPending)
                _buildActionButtons(appointment)
              else
                _buildCompletedActions(appointment),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    String? valueEn,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                label,
                style: context.text.bodySmall?.copyWith(
                  color: context.drd.muted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        const SizedBox(width: DrdSpacing.sm),
        Icon(icon, color: context.drd.muted, size: 20),
      ],
    );
  }

  /// إجراءات الزيارة المكتملة.
  ///
  /// يتدفّق مع مستند السجل، فيعرف إن كانت الزيارة موثَّقة أصلاً ويعرض
  /// «عرض السجل» بدل «إضافة سجل الزيارة». هذا ما يمنع إنشاء سجل ثانٍ
  /// بالخطأ — والضمان الحقيقي أن معرّف السجل هو معرّف الموعد، فلا مكان
  /// لسجلين أصلاً.
  Widget _buildCompletedActions(Map<String, dynamic> appointment) {
    final appointmentId = appointment['id'] as String;

    return StreamBuilder<Encounter?>(
      stream: _encounters.watchForAppointment(appointmentId),
      builder: (context, snapshot) {
        final existing = snapshot.data;
        final loading = snapshot.connectionState == ConnectionState.waiting;

        return Row(
          children: [
            Expanded(
              child: existing == null
                  ? FilledButton.icon(
                      onPressed: loading
                          ? null
                          : () => _openEncounterForm(appointment),
                      icon: const Icon(Icons.note_add_outlined),
                      label: const Text('إضافة سجل الزيارة'),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EncounterDetailScreen(
                            encounter: existing,
                            onEdit: () => _openEncounterForm(
                              appointment,
                              existing: existing,
                            ),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('عرض السجل'),
                    ),
            ),
          ],
        );
      },
    );
  }

  /// يفتح نموذج توثيق الزيارة.
  ///
  /// اسم الطبيب وتخصصه يُنسخان في السجل ليبقى شاهداً على مَن كتبه وقت
  /// كتابته — وهو ما تحتاجه المشاركة في المرحلة الرابعة.
  Future<void> _openEncounterForm(
    Map<String, dynamic> appointment, {
    Encounter? existing,
  }) async {
    final auth = context.read<FirebaseAuthService>();
    final doctorId = auth.userId;
    if (doctorId == null) return;

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorEncounterScreen(
          appointmentId: appointment['id'] as String,
          patientId: (appointment['patientId'] ?? '') as String,
          patientName: (appointment['patientName'] ?? '') as String,
          doctorId: doctorId,
          doctorName: auth.userName ?? '',
          doctorSpecialization:
              (auth.userData?['specialization'] ?? '').toString(),
          encounterDate: (appointment['appointmentDate'] ?? '') as String,
          existing: existing,
        ),
      ),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> appointment) {
    // ✅ التحقق من إمكانية إلغاء الموعد
    final appointmentDateStr = appointment['appointmentDate'] as String;
    final appointmentTimeStr = appointment['time'] as String;

    DateTime appointmentDate;
    try {
      appointmentDate = DateTime.parse(appointmentDateStr);
    } catch (e) {
      appointmentDate = DateTime.now();
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final apptDay = DateTime(
        appointmentDate.year, appointmentDate.month, appointmentDate.day);

    // التحقق من أن الموعد لم يمضِ
    bool canCancel = apptDay.isAfter(today) ||
        (apptDay.isAtSameMomentAs(today) &&
            _timeHasNotPassed(appointmentTimeStr, now));

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _completeAppointment(appointment['id']),
            icon: const Icon(Icons.check),
            label: const Text('إنهاء / Complete'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed:
                canCancel ? () => _cancelAppointment(appointment['id']) : null,
            icon: const Icon(Icons.close),
            label: const Text('إلغاء / Cancel'),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  canCancel ? context.colors.error : context.drd.disabled,
            ),
          ),
        ),
      ],
    );
  }

  // ✅ دالة مساعدة للتحقق من أن الوقت لم يمضِ بعد
  bool _timeHasNotPassed(String timeStr, DateTime now) {
    try {
      final timeParts = timeStr.split(':');
      if (timeParts.length >= 2) {
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final apptTime = DateTime(now.year, now.month, now.day, hour, minute);
        return now.isBefore(apptTime);
      }
    } catch (e) {
      return true; // في حالة الخطأ، اسمح بالإلغاء للأمان
    }
    return true;
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _selectedFilterIndex = -1; // -1 يعني تاريخ مخصص تم اختياره من النتيجة
      });
      await _fetchAppointments();
    }
  }

  Future<void> _completeAppointment(String appointmentId) async {
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appointmentId)
          .update({'status': AppointmentStatus.completed.wireValue});

      await _fetchAppointments();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنهاء الموعد، نتمنى للمريض الشفاء العاجل'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar.error('خطأ: $e'),
        );
      }
    }
  }

  Future<void> _cancelAppointment(String appointmentId) async {
    try {
      // عبر BookingService حتى يُحرَّر قفل الخانة مع تغيير الحالة في معاملة
      // واحدة، فيستطيع مريض آخر حجز الوقت الذي أخلاه الطبيب.
      await _bookingService.cancel(appointmentId: appointmentId);

      await _fetchAppointments();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تم إلغاء الموعد / Cancelled'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar.error('خطأ: $e'),
        );
      }
    }
  }

  void _showAppointmentDetailsDialog(Map<String, dynamic> appointment) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // الرأس
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      'تفاصيل الموعد / Details',
                      style: context.text.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 16),

                // معلومات المريض
                _detailsRow(
                  icon: Icons.person,
                  label: 'المريض',
                  value: appointment['patientName'] ?? 'غير محدد',
                ),
                const SizedBox(height: 12),

                // الهاتف
                _detailsRow(
                  icon: Icons.phone,
                  label: 'الهاتف',
                  value: appointment['phone'] ?? 'غير محدد',
                ),
                const SizedBox(height: 12),

                // التاريخ والوقت
                _detailsRow(
                  icon: Icons.calendar_today,
                  label: 'التاريخ',
                  value: appointment['appointmentDate'] ??
                      appointment['date'] ??
                      'غير محدد',
                ),
                const SizedBox(height: 12),

                _detailsRow(
                  icon: Icons.access_time,
                  label: 'الوقت',
                  value: appointment['time'] ?? 'غير محدد',
                ),
                const SizedBox(height: 12),

                // السبب
                if (appointment['reason'] != null &&
                    appointment['reason'].toString().isNotEmpty &&
                    appointment['reason'].toString() != 'Consultation')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'السبب / Reason',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.drd.muted,
                            ),
                          ),
                          const SizedBox(width: DrdSpacing.xs),
                          Icon(Icons.description,
                              size: 18, color: context.drd.muted),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceContainerHigh,
                          borderRadius: DrdRadius.smAll,
                        ),
                        child: Text(
                          appointment['reason'].toString(),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),

                // ملاحظات الطبيب
                if (appointment['notes'] != null &&
                    appointment['notes'].toString().isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'ملاحظات الطبيب / Notes',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.drd.muted,
                            ),
                          ),
                          const SizedBox(width: DrdSpacing.xs),
                          Icon(Icons.note, size: 18, color: context.drd.muted),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.drd.infoContainer,
                          borderRadius: DrdRadius.smAll,
                        ),
                        child: Text(
                          appointment['notes'].toString(),
                          style: TextStyle(color: context.drd.onInfoContainer),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),

                // الحالة
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    StatusChip.appointment(
                      AppointmentStatus.parse(appointment['status']),
                    ),
                    const SizedBox(width: DrdSpacing.sm),
                    Text(
                      'الحالة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: context.drd.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // زر الإغلاق
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const RoundedRectangleBorder(
                        borderRadius: DrdRadius.mdAll,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق / Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailsRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: context.drd.muted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: DrdSpacing.sm),
        Icon(icon, color: context.drd.muted, size: 20),
      ],
    );
  }
}
