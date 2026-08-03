import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/slot_id.dart';
import '../../data/services/booking_service.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/app_widgets.dart';

class PatientBookingScreen extends StatefulWidget {
  final String? initialDoctorId;

  const PatientBookingScreen({super.key, this.initialDoctorId});

  @override
  State<PatientBookingScreen> createState() => _PatientBookingScreenState();
}

class _PatientBookingScreenState extends State<PatientBookingScreen> {
  final BookingService _bookingService = BookingService();

  List<Map<String, dynamic>> _allDoctors = [];
  bool _isLoadingDoctors = true;

  Future<void> _fetchRealDoctors() async {
    setState(() => _isLoadingDoctors = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'doctor')
          .get();
      _allDoctors = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'طبيب غير معروف',
          'nameEn': data['nameEn'] ?? 'Unknown Doctor',
          'specialization': data['specialization'] ?? 'عام',
          'rating': (data['rating'] ?? 0.0).toDouble(),
          'reviews': data['reviews'] ?? 0,
          'price': data['price'] ?? 0,
          'availability': true,
          'sessionDuration': data['sessionDuration'] ?? 30,
          'maxPatientsPerSlot': data['maxPatientsPerSlot'] ?? 4,
          'bookingSystemType': data['bookingSystemType'] ?? 'Individual',
          'workingHours': data['workingHours'] ?? '09:00 AM - 05:00 PM',
          'bio': data['bio'] ?? '',
          'bioEn': data['bioEn'] ?? '',
          'clinicLocation': data['clinicLocation'] ?? '',
          'workingDays': data['workingDays'] ?? {},
        };
      }).toList();
    } catch (e) {
      AppLogger.error('تعذّر جلب قائمة الأطباء', e);
    }
    if (mounted) setState(() => _isLoadingDoctors = false);
    if (_selectedDoctorId != null) {
      _fetchBookedSlots();
    }
  }

  late TextEditingController _searchController;
  late TextEditingController _reasonController;
  String _selectedSpecialization = _allSpecializations;
  String? _selectedDoctorId;
  DateTime? _selectedDate;
  String? _selectedTime;
  String? _consultationReason;

  static const String _allSpecializations = 'الكل';

  /// الوقت (`HH:mm`) → عدد الحجوزات القائمة فيه.
  Map<String, int> _bookedSlots = {};
  bool _isLoadingSlots = false;
  bool _hasAppointmentToday = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDoctorId != null) {
      _selectedDoctorId = widget.initialDoctorId;
    }
    _fetchRealDoctors();
    _searchController = TextEditingController();
    _reasonController = TextEditingController();
    _selectedDate = DateTime.now().add(const Duration(days: 1));
  }

  Future<void> _fetchBookedSlots() async {
    if (_selectedDoctorId == null || _selectedDate == null) return;
    setState(() {
      _isLoadingSlots = true;
      _bookedSlots.clear();
      _hasAppointmentToday = false;
      _selectedTime = null;
    });

    try {
      final auth = Provider.of<FirebaseAuthService>(context, listen: false);

      // الاستعلامان يعتمدان الآن على BookingService، وهو نفس المصدر الذي
      // يستخدمه الحجز — فلا تختلف الواجهة عمّا ستقبله قاعدة البيانات.
      final taken = await _bookingService.bookedCountsFor(
        doctorId: _selectedDoctorId!,
        date: _selectedDate!,
      );
      final patientAlreadyBooked = await _bookingService.hasAppointmentOnDate(
        doctorId: _selectedDoctorId!,
        patientId: auth.userId ?? '',
        date: _selectedDate!,
      );

      if (mounted) {
        setState(() {
          _bookedSlots = taken;
          _hasAppointmentToday = patientAlreadyBooked;
        });
      }
    } catch (e) {
      AppLogger.error('تعذّر جلب الخانات المحجوزة', e);
    } finally {
      if (mounted) setState(() => _isLoadingSlots = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getFilteredDoctors() {
    final query = _searchController.text.toLowerCase();
    return _allDoctors.where((doctor) {
      final matchesSearch =
          doctor['name'].toString().toLowerCase().contains(query) ||
              doctor['specialization'].toString().toLowerCase().contains(query);

      final matchesSpec = _selectedSpecialization == _allSpecializations ||
          doctor['specialization'].toString().contains(_selectedSpecialization);

      return matchesSearch && matchesSpec;
    }).toList();
  }

  List<String> _getAvailableTimeSlots(Map<String, dynamic> doctor) {
    if (_selectedDate != null) {
      final dynamic workingDaysDynamic = doctor['workingDays'];
      if (workingDaysDynamic != null && workingDaysDynamic is Map) {
        Map<String, dynamic> workingDays =
            Map<String, dynamic>.from(workingDaysDynamic);
        String arabicDay = DateFormat('EEEE', 'ar').format(_selectedDate!);
        bool isWorkingDay = true;
        for (final entry in workingDays.entries) {
          if (entry.key.contains(arabicDay)) {
            isWorkingDay = entry.value == true;
            break;
          }
        }
        if (!isWorkingDay) return [];
      }
    }

    String bookingSystemType = doctor['bookingSystemType'] ?? 'Individual';
    int duration = doctor['sessionDuration'] ?? 30;
    if (bookingSystemType == 'Grouped') {
      duration = 60; // 1 hour groups
    }
    String workingHours = doctor['workingHours'] ?? '09:00 AM - 05:00 PM';

    List<String> defaultSlots = [
      '09:00',
      '09:30',
      '10:00',
      '10:30',
      '11:00',
      '11:30',
      '14:00',
      '14:30',
      '15:00',
      '15:30',
      '16:00',
      '16:30',
    ];

    try {
      final parts = workingHours.split('-');
      if (parts.length != 2) return defaultSlots;

      final startStr = parts[0].trim();
      final endStr = parts[1].trim();

      TimeOfDay parseTime(String timeStr) {
        String cleanTime = timeStr.trim();
        final isPM = cleanTime.toUpperCase().contains('PM');
        final isAM = cleanTime.toUpperCase().contains('AM');

        String justTime = cleanTime
            .toUpperCase()
            .replaceAll('AM', '')
            .replaceAll('PM', '')
            .trim();
        final hm = justTime.split(':');
        int hour = int.tryParse(hm[0]) ?? 0;
        int minute = hm.length > 1 ? (int.tryParse(hm[1]) ?? 0) : 0;

        if (isPM && hour != 12) {
          hour += 12;
        } else if (isAM && hour == 12) {
          hour = 0;
        }
        return TimeOfDay(hour: hour, minute: minute);
      }

      final startTime = parseTime(startStr);
      final endTime = parseTime(endStr);

      List<String> slots = [];
      DateTime current = DateTime(2000, 1, 1, startTime.hour, startTime.minute);
      DateTime end = DateTime(2000, 1, 1, endTime.hour, endTime.minute);

      if (end.isBefore(current) || end.isAtSameMomentAs(current)) {
        end = end.add(const Duration(days: 1));
      }

      while (current.isBefore(end)) {
        String formattedHour = current.hour.toString().padLeft(2, '0');
        String formattedMinute = current.minute.toString().padLeft(2, '0');
        slots.add('$formattedHour:$formattedMinute');
        current = current.add(Duration(minutes: duration));
      }

      return slots.isEmpty ? defaultSlots : slots;
    } catch (e) {
      return defaultSlots;
    }
  }

  // ===========================================================================
  // الواجهة
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final selectedDoctor = _selectedDoctorId == null
        ? null
        : _allDoctors.cast<Map<String, dynamic>?>().firstWhere(
              (d) => d?['id'] == _selectedDoctorId,
              orElse: () => null,
            );

    return AppScaffold(
      title: 'حجز موعد',
      subtitle: 'اختر الطبيب، ثم الوقت المناسب لك',
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      onRefresh: _fetchRealDoctors,
      child: _isLoadingDoctors
          ? const AppLoader(message: 'جارٍ تحميل الأطباء…')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // خطوات مرقّمة بدل قائمة أقسام متساوية الوزن. المريض يعرف
                // الآن أين هو في العملية وكم بقي — وهو ما كان غائباً تماماً.
                _StepHeader(
                  step: 1,
                  title: 'اختر الطبيب',
                  done: _selectedDoctorId != null,
                ),
                _buildSearchSection(),
                const SizedBox(height: AppSpacing.lg),
                _buildDoctorList(),
                if (selectedDoctor != null) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  _StepHeader(
                    step: 2,
                    title: 'اختر التاريخ والوقت',
                    done: _selectedTime != null,
                  ),
                  _buildDateTimeSection(selectedDoctor),
                  const SizedBox(height: AppSpacing.xxl),
                  _StepHeader(
                    step: 3,
                    title: 'سبب الزيارة',
                    done: (_consultationReason ?? '').trim().isNotEmpty,
                  ),
                  _buildReasonSection(),
                  const SizedBox(height: AppSpacing.xxl),
                  _buildSummaryAndBook(selectedDoctor),
                ],
              ],
            ),
    );
  }

  Widget _buildSearchSection() {
    const specs = [
      _allSpecializations,
      'أسنان',
      'نساء',
      'جلدية',
      'عام',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: _searchController,
          hint: 'ابحث باسم الطبيب أو التخصص',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final spec in specs) ...[
                AppChip(
                  label: spec,
                  selected: _selectedSpecialization == spec,
                  onTap: () => setState(() {
                    _selectedSpecialization = spec;
                    _selectedDoctorId = null;
                  }),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDoctorList() {
    final doctors = _getFilteredDoctors();

    if (doctors.isEmpty) {
      return const EmptyState(
        icon: Icons.person_search_rounded,
        title: 'لم نجد أطباء مطابقين',
        message: 'جرّب اسماً آخر أو اختر «الكل» من التخصصات.',
      );
    }

    return Column(
      children: [
        for (final doctor in doctors) ...[
          _DoctorCard(
            doctor: doctor,
            selected: _selectedDoctorId == doctor['id'],
            onTap: () {
              setState(() {
                _selectedDoctorId = doctor['id'];
                _selectedTime = null;
              });
              _fetchBookedSlots();
            },
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }

  Widget _buildDateTimeSection(Map<String, dynamic> doctor) {
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          onTap: () => _selectDate(context, doctor),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.12),
                  borderRadius: AppRadius.rMd,
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  color: context.colors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تاريخ الزيارة',
                      style: context.texts.bodySmall
                          ?.copyWith(color: tokens.textMuted),
                    ),
                    Text(
                      DateFormat('EEEE، d MMMM yyyy', 'ar')
                          .format(_selectedDate!),
                      style: context.texts.titleSmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit_calendar_outlined, color: tokens.textMuted),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_isLoadingSlots)
          const AppLoader(compact: true, message: 'جارٍ فحص الأوقات المتاحة…')
        else if (_hasAppointmentToday)
          const NoticeBox.warning(
            title: 'لديك موعد بالفعل',
            message: 'عندك موعد محجوز مع هذا الطبيب في نفس اليوم. اختر يوماً '
                'آخر أو راجع صفحة «مواعيدي».',
          )
        else
          _buildTimeSlots(doctor),
      ],
    );
  }

  Widget _buildTimeSlots(Map<String, dynamic> doctor) {
    final String sysType = doctor['bookingSystemType'] ?? 'Individual';
    final int maxPerSlot = (sysType == 'Grouped')
        ? ((doctor['maxPatientsPerSlot'] as num?)?.toInt() ?? 4)
        : 1;

    final slots = _getAvailableTimeSlots(doctor).where((time) {
      // التوحيد ضروري: الخانات المولّدة بصيغة `HH:mm` والمحجوزة قادمة من
      // قاعدة البيانات بصيغ متعددة.
      final booked = _bookedSlots[SlotId.normalizeTime(time)] ?? 0;
      return booked < maxPerSlot;
    }).toList();

    if (slots.isEmpty) {
      return const NoticeBox.info(
        message: 'لا توجد أوقات متاحة في هذا اليوم. جرّب تاريخاً آخر.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'الأوقات المتاحة',
          style: context.texts.labelMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final time in slots)
              AppChip(
                label: _formatTime(time),
                subtitle: sysType == 'Grouped'
                    ? 'باقي ${maxPerSlot - (_bookedSlots[SlotId.normalizeTime(time)] ?? 0)}'
                    : null,
                selected: _selectedTime == time,
                onTap: () => setState(() => _selectedTime = time),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildReasonSection() {
    return TextField(
      controller: _reasonController,
      maxLines: 4,
      onChanged: (value) => setState(() => _consultationReason = value),
      style:
          context.texts.bodyMedium?.copyWith(color: context.tokens.textStrong),
      decoration: const InputDecoration(
        hintText: 'اكتب باختصار سبب الزيارة أو الأعراض التي تشعر بها…',
        floatingLabelBehavior: FloatingLabelBehavior.never,
      ),
    );
  }

  /// ملخّص الحجز + الزر. عرض الاختيارات قبل الضغط يمنع أشهر خطأ في التطبيقات
  /// الطبية: تأكيد موعد في اليوم أو الوقت الخطأ.
  Widget _buildSummaryAndBook(Map<String, dynamic> doctor) {
    final tokens = context.tokens;
    final isComplete = _selectedDoctorId != null &&
        _selectedDate != null &&
        _selectedTime != null &&
        (_consultationReason?.trim().isNotEmpty ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              InfoRow(
                label: 'الطبيب',
                value: doctor['name'].toString(),
                icon: Icons.person_rounded,
              ),
              Divider(color: tokens.border, height: AppSpacing.lg),
              InfoRow(
                label: 'التاريخ',
                value: DateFormat('EEEE، d MMMM', 'ar').format(_selectedDate!),
                icon: Icons.calendar_today_rounded,
              ),
              Divider(color: tokens.border, height: AppSpacing.lg),
              InfoRow(
                label: 'الوقت',
                value: _selectedTime == null
                    ? 'لم يُحدَّد بعد'
                    : _formatTime(_selectedTime!),
                icon: Icons.access_time_rounded,
                valueColor: _selectedTime == null ? tokens.textFaint : null,
              ),
              Divider(color: tokens.border, height: AppSpacing.lg),
              InfoRow(
                label: 'سعر الكشف',
                value: '${doctor['price']} جنيه',
                icon: Icons.payments_outlined,
                valueColor: tokens.success,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: isComplete ? _confirmBooking : null,
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('تأكيد الحجز'),
        ),
        if (!isComplete) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'أكمل الخطوات الثلاث لتفعيل زر التأكيد',
            textAlign: TextAlign.center,
            style: context.texts.bodySmall?.copyWith(color: tokens.textFaint),
          ),
        ],
      ],
    );
  }

  /// تحويل `HH:mm` إلى صيغة 12 ساعة بالعربية.
  static String _formatTime(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return time;
    var h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1].split('\n')[0];
    final period = h >= 12 ? 'م' : 'ص';
    if (h == 0) {
      h = 12;
    } else if (h > 12) {
      h -= 12;
    }
    return '$h:$m $period';
  }

  // ===========================================================================
  // المنطق
  // ===========================================================================

  Future<void> _selectDate(
      BuildContext context, Map<String, dynamic> doctor) async {
    final dynamic workingDaysDynamic = doctor['workingDays'];
    Map<String, dynamic>? workingDays;

    if (workingDaysDynamic is Map) {
      workingDays = Map<String, dynamic>.from(workingDaysDynamic);
    } else if (workingDaysDynamic is List) {
      // Ignore list since we rely on the Map format now
      workingDays = null;
    }

    bool isDaySelectable(DateTime val) {
      if (workingDays == null || workingDays.isEmpty) return true;

      bool hasAnyWorkingDay = false;
      for (var value in workingDays.values) {
        if (value == true) {
          hasAnyWorkingDay = true;
          break;
        }
      }
      // Failsafe: if no true days exist, don't block all days.
      if (!hasAnyWorkingDay) return true;

      String arabicDay = DateFormat('EEEE', 'ar').format(val);
      for (final entry in workingDays.entries) {
        if (entry.key.contains(arabicDay)) {
          return entry.value == true;
        }
      }
      return true;
    }

    // Find the first available day for the initialDate to prevent the
    // DatePicker from crashing if _selectedDate is not a working day.
    DateTime initialDate = _selectedDate ?? DateTime.now();

    if (!isDaySelectable(initialDate)) {
      bool found = false;
      for (int i = 0; i < 30; i++) {
        DateTime searchDay = DateTime.now().add(Duration(days: i));
        if (isDaySelectable(searchDay)) {
          initialDate = searchDay;
          found = true;
          break;
        }
      }

      if (!found) {
        initialDate = DateTime.now();
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      locale: const Locale('ar'),
      helpText: 'اختر تاريخ الزيارة',
      selectableDayPredicate: isDaySelectable,
    );

    if (picked != null && picked != _selectedDate) {
      if (mounted) setState(() => _selectedDate = picked);
      _fetchBookedSlots();
    }
  }

  void _confirmBooking() {
    if (_selectedTime == null) {
      AppSnack.error(context, 'الرجاء اختيار وقت الموعد');
      return;
    }

    final doctor = _allDoctors.firstWhere((d) => d['id'] == _selectedDoctorId);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ConfirmSheet(
        doctor: doctor,
        date: _selectedDate!,
        time: _selectedTime!,
        timeLabel: _formatTime(_selectedTime!),
        onConfirm: () => _submitBooking(dialogContext, doctor),
      ),
    );
  }

  Future<void> _submitBooking(
    BuildContext dialogContext,
    Map<String, dynamic> doctor,
  ) async {
    showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final auth = Provider.of<FirebaseAuthService>(context, listen: false);
    final navigator = Navigator.of(context);
    // يُلتقط قبل الانتظار: بعد `await` قد يكون `dialogContext` قد أُزيل من
    // الشجرة، فتصبح قراءته منه خطأ.
    final dialogNavigator = Navigator.of(dialogContext);

    // نظام المجموعات يسمح بأكثر من مريض في نفس الساعة؛ النظام الفردي سعته
    // مريض واحد فقط.
    final int capacity =
        (doctor['bookingSystemType'] ?? 'Individual') == 'Grouped'
            ? ((doctor['maxPatientsPerSlot'] as num?)?.toInt() ?? 4)
            : 1;

    final result = await _bookingService.book(
      doctorId: doctor['id'].toString(),
      patientId: auth.userId!,
      date: _selectedDate!,
      time: _selectedTime!,
      capacity: capacity,
      appointmentData: {
        'patientName': auth.userName,
        'patientPhone': auth.userPhone,
        'doctorName': doctor['name'],
        'doctorNameEn': doctor['nameEn'],
        'doctorSpecialization': doctor['specialization'] ?? '',
        'reason': _consultationReason,
        'price': doctor['price'],
      },
    );

    if (!mounted) return;

    // إغلاق مؤشر التحميل ثم نافذة التأكيد.
    dialogNavigator.pop();
    dialogNavigator.pop();

    if (result.isSuccess) {
      AppSnack.success(context, result.message);
      navigator.pop();
    } else {
      AppSnack.error(context, result.message);
      // الخانة اتحجزت أثناء التأكيد — نُحدّث القائمة فوراً حتى لا يحاول
      // المريض على نفس الوقت مرة أخرى.
      await _fetchBookedSlots();
    }
  }
}

// =============================================================================
// عناصر الشاشة
// =============================================================================

/// رأس خطوة مرقّم يتحوّل إلى علامة صح عند اكتمالها.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.title,
    required this.done,
  });

  final int step;
  final String title;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = done ? tokens.success : context.colors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: done
                ? Icon(Icons.check_rounded, size: 16, color: color)
                : Text(
                    '$step',
                    style: context.texts.labelMedium?.copyWith(color: color),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(title, style: context.texts.titleMedium),
        ],
      ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({
    required this.doctor,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> doctor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final location = doctor['clinicLocation']?.toString() ?? '';
    final bio = doctor['bio']?.toString() ?? '';

    return AppCard(
      selected: selected,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                name: doctor['name']?.toString(),
                icon: Icons.medical_services_rounded,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctor['name'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall,
                    ),
                    Text(
                      doctor['specialization'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall
                          ?.copyWith(color: context.colors.primary),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: context.colors.primary,
                  size: 22,
                )
              else
                RatingStars(
                  rating: (doctor['rating'] as num).toDouble(),
                  reviews: (doctor['reviews'] as num?)?.toInt(),
                ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              bio,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(color: tokens.textMuted),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (location.isNotEmpty) ...[
                Icon(
                  Icons.location_on_outlined,
                  size: 15,
                  color: tokens.textMuted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall
                        ?.copyWith(color: tokens.textMuted),
                  ),
                ),
              ] else
                const Spacer(),
              const SizedBox(width: AppSpacing.sm),
              StatusPill(
                label: '${doctor['price']} جنيه',
                color: tokens.success,
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// نافذة مراجعة الحجز قبل الإرسال.
class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.doctor,
    required this.date,
    required this.time,
    required this.timeLabel,
    required this.onConfirm,
  });

  final Map<String, dynamic> doctor;
  final DateTime date;
  final String time;
  final String timeLabel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.event_available_rounded,
          color: context.colors.primary,
          size: 26,
        ),
      ),
      title: const Text('تأكيد الحجز', textAlign: TextAlign.center),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoRow(label: 'الطبيب', value: doctor['name'].toString()),
            InfoRow(
              label: 'التخصص',
              value: doctor['specialization'].toString().split(' / ')[0],
            ),
            InfoRow(
              label: 'التاريخ',
              value: DateFormat('EEEE، d MMMM yyyy', 'ar').format(date),
            ),
            InfoRow(label: 'الوقت', value: timeLabel),
            InfoRow(
              label: 'السعر',
              value: '${doctor['price']} جنيه',
              valueColor: tokens.success,
            ),
            const SizedBox(height: AppSpacing.md),
            const NoticeBox.info(
              message: 'ستجد الموعد في صفحة «مواعيدي»، ويمكنك إلغاؤه قبل '
                  'موعده.',
            ),
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('تراجع'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: FilledButton(
                onPressed: onConfirm,
                child: const Text('تأكيد'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
