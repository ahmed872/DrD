import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/slot_id.dart';
import '../../data/services/booking_service.dart';
import '../providers/firebase_auth_service.dart';

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
          'name': data['name'] ?? 'طبيب غير معروف',
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
  String _selectedSpecialization = 'جميع التخصصات / All';
  String? _selectedDoctorId;
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
    if (widget.initialDoctorId != null) {
      _selectedDoctorId = widget.initialDoctorId;
    }
    _fetchRealDoctors();
    _searchController = TextEditingController();
    _selectedDate = DateTime.now().add(const Duration(days: 1));
  }

  Future<void> _fetchBookedSlots() async {
    if (_selectedDoctorId == null || _selectedDate == null) return;
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
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getFilteredDoctors() {
    return _allDoctors.where((doctor) {
      final matchesSearch = doctor['name']
              .toLowerCase()
              .contains(_searchController.text.toLowerCase()) ||
          doctor['specialization']
              .toLowerCase()
              .contains(_searchController.text.toLowerCase());

      final matchesSpec = _selectedSpecialization == 'جميع التخصصات / All' ||
          doctor['specialization']
              .contains(_selectedSpecialization.split(' / ')[0]);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('احجز موعد'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0097A7),
        elevation: 1,
      ),
      body: _isLoadingDoctors
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildSearchSection(),
                    const SizedBox(height: 24),
                    _buildDoctorListSection(),
                    const SizedBox(height: 24),
                    if (_selectedDoctorId != null) ...[
                      _buildDateTimeSection(_allDoctors
                          .firstWhere((d) => d['id'] == _selectedDoctorId)),
                      const SizedBox(height: 24),
                      _buildReasonSection(),
                      const SizedBox(height: 24),
                      _buildBookButton(),
                      const SizedBox(height: 32),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'ابحث عن طبيب / Search Doctor',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'اسم الطبيب أو التخصص / Doctor name or specialty',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            children: [
              _specChip('جميع التخصصات / All', 'جميع التخصصات / All'),
              const SizedBox(width: 8),
              _specChip('أسنان / Dentistry', 'أسنان / Dentistry'),
              const SizedBox(width: 8),
              _specChip('نساء / Obstetrics', 'نساء / Obstetrics'),
              const SizedBox(width: 8),
              _specChip('جلدية / Dermatology', 'جلدية / Dermatology'),
              const SizedBox(width: 8),
              _specChip('عام / General', 'عام / General Practice'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _specChip(String label, String spec) {
    return FilterChip(
      label: Text(label),
      selected: _selectedSpecialization == spec,
      onSelected: (selected) {
        setState(() {
          _selectedSpecialization = spec;
          _selectedDoctorId = null;
        });
      },
      backgroundColor: Colors.grey[100],
      selectedColor: Colors.blue,
      labelStyle: TextStyle(
        color: _selectedSpecialization == spec ? Colors.white : Colors.black87,
        fontWeight: _selectedSpecialization == spec
            ? FontWeight.bold
            : FontWeight.normal,
      ),
    );
  }

  Widget _buildDoctorListSection() {
    if (_isLoadingDoctors) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final filteredDoctors = _getFilteredDoctors();

    if (filteredDoctors.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.person_search, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                'لم يتم العثور على أطباء',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'الأطباء المتاحون / Available Doctors',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredDoctors.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doctor = filteredDoctors[index];
            final isSelected = _selectedDoctorId == doctor['id'];

            return Card(
              elevation: isSelected ? 4 : 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? Colors.blue : Colors.transparent,
                  width: 2,
                ),
              ),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedDoctorId = doctor['id'];
                    _selectedTime = null;
                  });
                  _fetchBookedSlots();
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                '${doctor['rating']} (${doctor['reviews']})',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  doctor['name'],
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  doctor['nameEn'],
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        doctor['specialization'],
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 8),
                      if (doctor['clinicLocation'] != null &&
                          doctor['clinicLocation'].toString().isNotEmpty) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on,
                                size: 14, color: Colors.orange),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                doctor['clinicLocation'],
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.orange[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        doctor['bio'],
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isSelected ? 'محدد ✓' : 'اختر',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      isSelected ? Colors.green : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Text(
                            '${doctor['price']} جنيه',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDateTimeSection(Map<String, dynamic> doctor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'اختر التاريخ والوقت / Select Date & Time',
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
                  Icon(Icons.calendar_today, color: Colors.blue),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تعذّر التحقق من الأوقات المتاحة.\n'
                    'تأكد من اتصالك بالإنترنت ثم اختر التاريخ مرة أخرى.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[800]),
                  ),
                ),
              ],
            ),
          )
        else if (_hasAppointmentToday)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'لديك موعد محجوز مسبقاً في هذا اليوم.\nYou already have an appointment booked on this date.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.red[800]),
                  ),
                ),
              ],
            ),
          )
        else ...[
          Text(
            'أوقات متاحة / Available Times',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
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
      backgroundColor: Colors.grey[100],
      selectedColor: Colors.green,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildReasonSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'سبب الزيارة / Reason for Visit',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          maxLines: 4,
          onChanged: (value) => setState(() => _consultationReason = value),
          decoration: InputDecoration(
            hintText: 'اشرح سبب الزيارة / Describe your reason for visit',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBookButton() {
    final isComplete = _selectedDoctorId != null &&
        _selectedDate != null &&
        _selectedTime != null &&
        (_consultationReason?.isNotEmpty ?? false);

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: isComplete ? () => _confirmBooking() : null,
        icon: const Icon(Icons.check_circle),
        label: const Text('تأكيد الحجز / Confirm Booking'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[300],
        ),
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
        const SnackBar(
          content: Text('الرجاء اختيار وقت الموعد / Please select a time'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final doctor = _allDoctors.firstWhere((d) => d['id'] == _selectedDoctorId);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد الحجز / Confirm Booking'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              _confirmRow('الطبيب / Doctor', doctor['name']),
              _confirmRow('التخصص / Specialty',
                  doctor['specialization'].split(' / ')[0]),
              _confirmRow(
                'التاريخ / Date',
                DateFormat('EEEE, d MMMM yyyy', 'ar').format(_selectedDate!),
              ),
              _confirmRow('الوقت / Time', _selectedTime ?? ''),
              _confirmRow('السعر / Price', '${doctor['price']} جنيه'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.blue, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'سيصلك تأكيد عبر البريد الإلكتروني\nYou will receive confirmation via email',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء / Cancel'),
          ),
          ElevatedButton(
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

              messenger.showSnackBar(SnackBar(
                content: Text(result.message),
                backgroundColor:
                    result.isSuccess ? Colors.green : Colors.red[700],
              ));

              if (result.isSuccess) {
                navigator.pop();
              } else {
                // الخانة اتحجزت أثناء التأكيد — نُحدّث القائمة فوراً حتى لا
                // يحاول المريض على نفس الوقت مرة أخرى.
                await _fetchBookedSlots();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('تأكيد / Confirm'),
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
                ?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
