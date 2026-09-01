import '../widgets/role_guard.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../data/services/booking_service.dart';
import '../providers/firebase_auth_service.dart';
import '../../core/utils/app_logger.dart';

class DoctorScheduleScreen extends StatefulWidget {
  const DoctorScheduleScreen({super.key});

  @override
  State<DoctorScheduleScreen> createState() => _DoctorScheduleScreenState();
}

class _DoctorScheduleScreenState extends State<DoctorScheduleScreen> {
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
          'status': data['status'] ?? 'pending',
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
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'أعد المحاولة',
              textColor: Theme.of(context).colorScheme.onPrimary,
              onPressed: _fetchAppointments,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // الحارس يجعل الشاشة متّسقة مع صلاحية الخادم: من ليس طبيباً له عيادة
    // (نشط أو موقوف) يرى رسالة مفهومة بدل استعلامات تُرفض بلا تفسير.
    return RoleGuard(
      requireDoctorClinicAccess: true,
      child: Builder(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context) {
    // ✅ فصل المواعيد القادمة عن المكتملة
    final pendingAppointments = _appointments
        .where((apt) =>
            apt['status'] == 'pending' ||
            apt['status'] == 'Booked' ||
            apt['status'] == 'Scheduled' ||
            apt['status'] == 'upcoming')
        .toList();

    final completedAppointments =
        _appointments.where((apt) => apt['status'] == 'Completed').toList();

    final appointmentsToShow = _selectedStatusFilter == 0
        ? pendingAppointments
        : completedAppointments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('جدول المواعيد'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchAppointments,
              child: Column(
                children: [
                  // ✅ عرض رسالة الخطأ إذا كانت موجودة
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        border: Border.all(
                            color: Theme.of(context).colorScheme.error),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: _fetchAppointments,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: Text(
                                      'أعد المحاولة / Retry',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () =>
                                setState(() => _errorMessage = null),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  // ✅ Tabs للفصل بين المواعيد القادمة والمكتملة
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Theme.of(context).colorScheme.onPrimary,
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
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              width: isSelected ? 3 : 1,
            ),
          ),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
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
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                  border:
                      Border.all(color: Theme.of(context).colorScheme.primary),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.calendar_today,
                        color: Theme.of(context).colorScheme.primary),
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
              Icon(Icons.calendar_today,
                  size: 64,
                  color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: 16),
              Text(
                'لا توجد مواعيد',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'No appointments',
                style: TextStyle(
                    fontSize: 14, color: Theme.of(context).colorScheme.outline),
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
          style: Theme.of(
            context,
          )
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
    final isPending = (appointment['status'] == 'pending' ||
        appointment['status'] == 'Booked' ||
        appointment['status'] == 'Scheduled' ||
        appointment['status'] == 'upcoming');
    final statusColor = isPending
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.tertiary;
    final statusLabel = isPending ? 'قيد الانتظار' : 'مكتملة';

    return InkWell(
      onTap: () {
        _showAppointmentDetailsDialog(appointment);
      },
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: statusColor.withOpacity(0.3), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      border: Border.all(color: statusColor, width: 1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isPending
                              ? Icons.schedule
                              : Icons.check_circle_outline,
                          color: statusColor,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '🕐 ${appointment['time']}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        const SizedBox(width: 12),
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
      ],
    );
  }

  Widget _buildCompletedActions(Map<String, dynamic> appointment) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showAddNoteDialog(
              appointment['id'],
              appointment['doctorNote'] ?? appointment['notes'] ?? '',
            ),
            icon: const Icon(Icons.edit_note),
            label: const Text('إضافة ملاحظة طبيب / Add Note'),
            style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddNoteDialog(
    String appointmentId,
    String currentNote,
  ) async {
    final TextEditingController noteController = TextEditingController(
      text: currentNote,
    );
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'ملاحظة طبية / Medical Note',
            textAlign: TextAlign.right,
          ),
          content: TextField(
            controller: noteController,
            maxLines: 4,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              hintText: 'اكتب ملاحظاتك الطبية هنا...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إلغاء',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await FirebaseFirestore.instance
                      .collection('appointments')
                      .doc(appointmentId)
                      .update({'notes': noteController.text.trim()});
                  await _fetchAppointments();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم حفظ الملاحظة بنجاح'),
                      backgroundColor: Theme.of(context).colorScheme.tertiary,
                    ),
                  );
                } catch (e) {}
              },
              child: const Text('حفظ / Save'),
            ),
          ],
        );
      },
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.tertiary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
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
              foregroundColor: canCancel
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
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
          .update({'status': 'Completed'});

      await _fetchAppointments();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إنهاء الموعد، نتمنى للمريض الشفاء العاجل',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            ),
            backgroundColor: Theme.of(context).colorScheme.tertiary,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('تعذّر إتمام العملية، حاول مرة أخرى'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _cancelAppointment(String appointmentId) async {
    try {
      // عبر BookingService حتى يُحرَّر قفل الخانة مع تغيير الحالة في معاملة
      // واحدة، فيستطيع مريض آخر حجز الوقت الذي أخلاه الطبيب.
      //
      // `cancelAsDoctor` — لا `cancel` — لأن `cancelAppointment` على الخادم
      // مخصّصة للمريض صاحب الموعد وحده.
      await _bookingService.cancelAsDoctor(appointmentId: appointmentId);

      await _fetchAppointments();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cancel,
                    color: Theme.of(context).colorScheme.onPrimary),
                SizedBox(width: 8),
                Text('✅ تم إلغاء الموعد / Cancelled'),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('تعذّر إتمام العملية، حاول مرة أخرى'),
              backgroundColor: Theme.of(context).colorScheme.error),
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
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
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
                  valueColor: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),

                // الهاتف
                _detailsRow(
                  icon: Icons.phone,
                  label: 'الهاتف',
                  value: appointment['phone'] ?? 'غير محدد',
                  valueColor: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),

                // التاريخ والوقت
                _detailsRow(
                  icon: Icons.calendar_today,
                  label: 'التاريخ',
                  value: appointment['appointmentDate'] ??
                      appointment['date'] ??
                      'غير محدد',
                  valueColor: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(height: 12),

                _detailsRow(
                  icon: Icons.access_time,
                  label: 'الوقت',
                  value: appointment['time'] ?? 'غير محدد',
                  valueColor: Theme.of(context).colorScheme.error,
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.description,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: Text(
                          appointment['reason'].toString(),
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest),
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.note,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        child: Text(
                          appointment['notes'].toString(),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),

                // الحالة
                _detailsRow(
                  icon: Icons.check_circle,
                  label: 'الحالة',
                  value: _getStatusLabel(appointment['status']),
                  valueColor: _getStatusColor(appointment['status']),
                ),
                const SizedBox(height: 20),

                // زر الإغلاق
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'إغلاق / Close',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
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
    required Color valueColor,
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            size: 20),
      ],
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
      case 'Booked':
      case 'Scheduled':
      case 'upcoming':
        return 'قيد الانتظار';
      case 'Completed':
        return 'مكتملة';
      case 'Cancelled':
        return 'ملغاة';
      case 'Rejected':
        return 'مرفوضة';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
      case 'Booked':
      case 'Scheduled':
      case 'upcoming':
        return Theme.of(context).colorScheme.secondary;
      case 'Completed':
        return Theme.of(context).colorScheme.tertiary;
      case 'Cancelled':
        return Theme.of(context).colorScheme.error;
      case 'Rejected':
        return Theme.of(context).colorScheme.error;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }
}
