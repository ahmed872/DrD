import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/slot_id.dart';
import '../../data/services/booking_service.dart';
import '../providers/firebase_auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';

/// حجز موعد عند طبيب **مُختار مسبقاً**.
///
/// ## لماذا صارت تشترط الطبيب
///
/// كانت هذه الشاشة تحمل رحلة كاملة ثانية: بحث بالاسم، ورقائق تخصّصات، وقائمة
/// أطباء — بجانب كونها وجهة زرّ «احجز موعداً» في شاشة البحث. فالمريض القادم من
/// البحث بعد أن اختار طبيبه كان يصل إلى شاشة عنوانها «احجز موعد» وفيها **صندوق
/// بحث ثانٍ وقائمة أطباء ثانية**، طبيبُه محدَّد فيها سلفاً.
///
/// ولم تكن الازدواجية شكلية: كانت الشاشتان تحملان مفردات تخصّصات مختلفة،
/// وتسحبان `doctor_profiles` كاملة، وتُصانان منفصلتين.
///
/// الآن رحلة واحدة: البحث يكتشف، وهذه تحجز. و`doctorId` مطلوب لا اختياري،
/// فلا يمكن الوصول إليها بلا طبيب — الشرط مفروض في النوع لا بالاتفاق.
class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key, required this.doctorId});

  /// الطبيب الذي اختاره المريض في شاشة البحث.
  final String doctorId;

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final BookingService _bookingService = BookingService();

  /// بيانات الطبيب المختار وحده — لا القائمة كلها.
  Map<String, dynamic>? _doctor;
  bool _isLoadingDoctor = true;
  bool _doctorLoadFailed = false;

  /// قراءة مستند واحد بمعرّف معروف.
  ///
  /// كانت الشاشة تسحب `doctor_profiles` كاملة ثم تُصفّيها في Dart لتعرض طبيباً
  /// واحداً. القراءة الآن بحجم ثابت مهما نما الدليل.
  Future<void> _fetchDoctor() async {
    setState(() {
      _isLoadingDoctor = true;
      _doctorLoadFailed = false;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('doctor_profiles')
          .doc(widget.doctorId)
          .get();

      if (!snap.exists) {
        // ملف عام غير موجود = طبيب خُفض دوره أو حُذف حسابه بعد فتح البحث.
        if (mounted) {
          setState(() {
            _isLoadingDoctor = false;
            _doctorLoadFailed = true;
          });
        }
        return;
      }

      final data = snap.data()!;
      _doctor = {
        'id': snap.id,
        'name': data['name'] ?? 'طبيب',
        'specialization': data['specialization'] ?? 'عام',
        'price': data['price'] ?? 0,
        'sessionDuration': data['sessionDuration'] ?? 30,
        'maxPatientsPerSlot': data['maxPatientsPerSlot'] ?? 4,
        'bookingSystemType': data['bookingSystemType'] ?? 'Individual',
        'workingHours': data['workingHours'] ?? '09:00 - 17:00',
        'workingDays': data['workingDays'] ?? {},
        'clinicLocation': data['clinicLocation'] ?? '',
      };
    } catch (e, st) {
      AppLogger.error('تعذّر تحميل بيانات الطبيب', e, st);
      if (mounted) setState(() => _doctorLoadFailed = true);
    }
    if (!mounted) return;
    setState(() => _isLoadingDoctor = false);
    _fetchBookedSlots();
  }

  DateTime? _selectedDate;
  String? _selectedTime;
  String? _consultationReason;

  /// الوقت (`HH:mm`) → إشغال الخانة، مقروءاً من مجموعة `slots`.
  Map<String, SlotAvailability> _slotAvailability = {};
  bool _isLoadingSlots = false;
  bool _hasAppointmentToday = false;

  /// فشل تحميل الإشغال.
  ///
  /// بدون هذه الراية كانت الشاشة تعرض كل الأوقات متاحة عند فشل الاستعلام —
  /// وهو بالضبط ما كان يحدث في الإنتاج. عرض "غير متاح مؤقتاً" أصدق من عرض
  /// أوقات لا نعرف حالتها.
  bool _slotsLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _fetchDoctor();
    _selectedDate = DateTime.now().add(const Duration(days: 1));
  }

  Future<void> _fetchBookedSlots() async {
    if (_selectedDate == null) return;
    setState(() {
      _isLoadingSlots = true;
      _slotAvailability.clear();
      _slotsLoadFailed = false;
      _hasAppointmentToday = false;
      _selectedTime = null;
    });

    try {
      final auth = Provider.of<FirebaseAuthService>(context, listen: false);

      // الإشغال يُقرأ من `slots` — المجموعة التي يقرأها الحجز نفسه — بدل
      // `appointments` التي كانت قاعدة الأمان ترفض استعلامها للمريض.
      final availability = await _bookingService.availabilityFor(
        doctorId: widget.doctorId,
        date: _selectedDate!,
      );
      final patientAlreadyBooked = await _bookingService.hasAppointmentOnDate(
        doctorId: widget.doctorId,
        patientId: auth.userId ?? '',
        date: _selectedDate!,
      );

      if (mounted) {
        setState(() {
          _slotAvailability = availability;
          _hasAppointmentToday = patientAlreadyBooked;
        });
      }
    } catch (e, s) {
      AppLogger.error('تعذّر جلب حالة الخانات', e, s);
      if (mounted) setState(() => _slotsLoadFailed = true);
    } finally {
      if (mounted) setState(() => _isLoadingSlots = false);
    }
  }

  @override
  void dispose() {
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حجز موعد')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoadingDoctor) {
      return const LoadingView(message: 'جارٍ تحميل مواعيد الطبيب...');
    }

    if (_doctorLoadFailed || _doctor == null) {
      return ErrorView(
        title: 'تعذّر فتح صفحة الحجز',
        message: 'قد يكون الطبيب لم يعد متاحاً للحجز. '
            'عُد إلى البحث واختر طبيباً آخر.',
        onRetry: _fetchDoctor,
      );
    }

    final doctor = _doctor!;
    return SingleChildScrollView(
      child: Padding(
        padding: DrdSpacing.screen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDoctorHeader(doctor),
            const SizedBox(height: DrdSpacing.lg),
            _buildDateTimeSection(doctor),
            const SizedBox(height: DrdSpacing.lg),
            _buildReasonSection(),
            const SizedBox(height: DrdSpacing.lg),
            _buildBookButton(),
            const SizedBox(height: DrdSpacing.xl),
          ],
        ),
      ),
    );
  }

  /// تذكير هادئ بمن يحجز المريض عنده.
  ///
  /// المريض وصل هنا بعد أن اختار طبيبه في البحث، فلا حاجة لإعادة عرض بطاقته
  /// كاملة — سطران يؤكّدان أنه في المكان الصحيح ويكفيان.
  Widget _buildDoctorHeader(Map<String, dynamic> doctor) {
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.medical_services_outlined, color: context.colors.primary),
          const SizedBox(width: DrdSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doctor['name'],
                  style: context.text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  doctor['specialization'],
                  style: context.text.bodySmall
                      ?.copyWith(color: context.drd.muted),
                ),
              ],
            ),
          ),
          if ((doctor['price'] ?? 0) > 0)
            Text(
              '${(doctor['price'] as num).toInt()} جنيه',
              style: context.text.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  Widget _buildDateTimeSection(Map<String, dynamic> doctor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'اختر التاريخ والوقت',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: InkWell(
              onTap: () => _selectDate(context, doctor),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Icons.calendar_today, color: context.colors.primary),
                  Text(
                    DateFormat('EEEE, d MMMM', 'ar').format(_selectedDate!),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_isLoadingSlots)
          const Center(child: CircularProgressIndicator())
        else if (_slotsLoadFailed)
          // لا تُعرض أوقات لا نعرف حالتها: عرضها متاحةً بينما قد تكون محجوزة
          // هو بالضبط الخطأ الذي كان يقع فيه هذا الملف.
          const AppBanner.warning(
            title: 'تعذّر التحقق من الأوقات المتاحة',
            message: 'تأكد من اتصالك بالإنترنت ثم اختر التاريخ مرة أخرى.',
          )
        else if (_hasAppointmentToday)
          // ليس خطأً: الموعد القائم حقيقة عن حساب المريض، لا فشل إجراء.
          const AppBanner.warning(
            message: 'لديك موعد محجوز مسبقاً في هذا اليوم.\n'
                'You already have an appointment booked on this date.',
          )
        else ...[
          Text(
            'أوقات متاحة',
            style: context.text.bodySmall?.copyWith(color: context.drd.muted),
          ),
          const SizedBox(height: DrdSpacing.xs),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: _getAvailableTimeSlots(doctor)
                .map((time) {
                  final String sysType =
                      doctor['bookingSystemType'] ?? 'Individual';
                  final int maxPerSlot = (sysType == 'Grouped')
                      ? ((doctor['maxPatientsPerSlot'] as num?)?.toInt() ?? 4)
                      : 1;
                  // التوحيد ضروري: الخانات المولّدة بصيغة `HH:mm` والمحجوزة
                  // قادمة من قاعدة البيانات بصيغ متعددة.
                  final slot = _slotAvailability[SlotId.normalizeTime(time)];
                  final int bookedCount = slot?.booked ?? 0;
                  // السعة المسجَّلة على الخانة هي المرجع — وهي نفسها التي
                  // تفرضها المعاملة وقاعدة الأمان. إن لم يوجد مستند خانة بعد
                  // فلا أحد حجز، والمرجع إعدادات الطبيب الحالية.
                  final int effectiveCapacity = slot?.capacity ?? maxPerSlot;

                  if (bookedCount >= effectiveCapacity) {
                    return const SizedBox.shrink();
                  }

                  return _buildTimeSlot(
                    time,
                    sysType == 'Grouped'
                        ? (effectiveCapacity - bookedCount)
                        : null,
                  );
                })
                .where((widget) => widget is! SizedBox)
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildTimeSlot(String time, int? remaining) {
    final isSelected = _selectedTime == time;
    String formattedTime = time;
    final parts = time.split(':');
    if (parts.length == 2) {
      int h = int.tryParse(parts[0]) ?? 0;
      final m = parts[1].split('\n')[0]; // strip anything extra
      final period = h >= 12 ? 'م' : 'ص';
      if (h == 0)
        h = 12;
      else if (h > 12) h -= 12;
      formattedTime = '${h.toString()}:$m $period';
    }

    final displayLabel = remaining != null
        ? '$formattedTime\n(باقي $remaining مكان)'
        : formattedTime;
    return chip(
      label: displayLabel,
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedTime = time);
      },
    );
  }

  Widget chip({
    required String label,
    required bool selected,
    required Function(bool) onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildReasonSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'سبب الزيارة',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          maxLines: 4,
          onChanged: (value) => setState(() => _consultationReason = value),
          decoration: const InputDecoration(
            hintText: 'اشرح سبب الزيارة',
          ),
        ),
      ],
    );
  }

  Widget _buildBookButton() {
    final isComplete = _selectedDate != null &&
        _selectedTime != null &&
        (_consultationReason?.isNotEmpty ?? false);

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: isComplete ? _confirmBooking : null,
        icon: const Icon(Icons.check_circle),
        label: const Text('تأكيد الحجز'),
      ),
    );
  }

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
      if (!hasAnyWorkingDay)
        return true; // Failsafe: if no true days exist, don't block all days.

      String arabicDay = DateFormat('EEEE', 'ar').format(val);
      for (final entry in workingDays.entries) {
        if (entry.key.contains(arabicDay)) {
          return entry.value == true;
        }
      }
      return true;
    }

    // Find the first available day for the initialDate
    // to prevent the DatePicker from crashing if _selectedDate is not a working day.
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
        selectableDayPredicate: isDaySelectable);

    if (picked != null && picked != _selectedDate) {
      if (mounted) setState(() => _selectedDate = picked);
      _fetchBookedSlots();
    }
  }

  void _confirmBooking() {
    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar.warning('الرجاء اختيار وقت الموعد'),
      );
      return;
    }

    final doctor = _doctor!;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد الحجز'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              _confirmRow('الطبيب', doctor['name']),
              _confirmRow('التخصص', doctor['specialization'].split(' / ')[0]),
              _confirmRow(
                'التاريخ',
                DateFormat('EEEE, d MMMM yyyy', 'ar').format(_selectedDate!),
              ),
              _confirmRow('الوقت', _selectedTime ?? ''),
              _confirmRow('السعر', '${doctor['price']} جنيه'),
              const SizedBox(height: 12),
              const AppBanner.info(
                message: 'سيصلك تأكيد عبر البريد الإلكتروني\n'
                    'You will receive confirmation via email',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              showDialog(
                context: dialogContext,
                barrierDismissible: false,
                builder: (_) =>
                    const Center(child: CircularProgressIndicator()),
              );

              final auth =
                  Provider.of<FirebaseAuthService>(context, listen: false);
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

              // نظام المجموعات يسمح بأكثر من مريض في نفس الساعة؛ النظام
              // الفردي سعته مريض واحد فقط.
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
              Navigator.pop(dialogContext);
              Navigator.pop(dialogContext);

              messenger.showSnackBar(
                result.isSuccess
                    ? AppSnackBar.success(result.message)
                    : AppSnackBar.error(result.message),
              );

              if (result.isSuccess) {
                navigator.pop();
              } else {
                // الخانة اتحجزت أثناء التأكيد — نُحدّث القائمة فوراً حتى لا
                // يحاول المريض على نفس الوقت مرة أخرى.
                await _fetchBookedSlots();
              }
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: context.drd.muted),
          ),
        ],
      ),
    );
  }
}
