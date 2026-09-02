import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/app_logger.dart';
import '../../data/services/availability_service.dart';
import '../../data/services/booking_service.dart';
import '../widgets/app_widgets.dart';
import '../widgets/slot_picker.dart';
import 'booking_confirmation_screen.dart';

class PatientBookingScreen extends StatefulWidget {
  final String? initialDoctorId;

  const PatientBookingScreen({super.key, this.initialDoctorId});

  @override
  State<PatientBookingScreen> createState() => _PatientBookingScreenState();
}

class _PatientBookingScreenState extends State<PatientBookingScreen> {
  /// سقف قائمة اختيار الطبيب في شاشة الحجز.
  /// البحث الكامل بترقيم صفحات في `PatientSearchDoctorScreen`.
  static const int _doctorPickerCap = 100;

  final BookingService _bookingService = BookingService();

  List<Map<String, dynamic>> _allDoctors = [];
  bool _isLoadingDoctors = true;

  Future<void> _fetchRealDoctors() async {
    setState(() => _isLoadingDoctors = true);
    try {
      // الأطباء الموثَّقون فقط. القواعد ترفض الحجز عند غيرهم، فعرضهم في
      // القائمة كان سيُنتج فشلاً غامضاً عند الضغط على «تأكيد».
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'doctor')
          .where('isVerified', isEqualTo: true)
          // المرحلة 7: قائمة اختيار لا فهرس كامل. بلا سقف كانت تقرأ
          // مجموعة الأطباء كلها في كل فتح للشاشة. الترتيب بالاسم يجعل
          // السقف قطعاً مستقرّاً لا عيّنة عشوائية.
          .orderBy('name')
          .limit(_doctorPickerCap)
          .get();

      // المرحلة 2: طبيب موقوف (`disabled: true`) يبقى `isVerified: true`
      // فيمرّ من الاستعلام أعلاه، لكن `bookAppointment` سيرفضه
      // (`doctor-disabled`) — فيُستبعَد هنا قبل أن يصل المريض لشاشة التأكيد
      // ويُفاجأ برفض غامض. لا فلترة `disabled` داخل الاستعلام نفسه عمداً:
      // Firestore تستبعد أي مستند بلا الحقل من `isEqualTo: false`، فتختفي
      // كل الحسابات القديمة قبل هذه المرحلة.
      final visibleDocs =
          snapshot.docs.where((doc) => doc.data()['disabled'] != true);

      _allDoctors = visibleDocs.map((doc) {
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
  }

  late TextEditingController _searchController;
  String _selectedSpecialization = 'جميع التخصصات';
  String? _selectedDoctorId;

  /// الخانة المختارة كما وصفها الخادم — لا تاريخ ولا وقت يبنيهما التطبيق.
  AvailabilitySlot? _selectedSlot;
  final SlotPickerController _slotPickerController = SlotPickerController();
  String? _consultationReason;
  bool _isBooking = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDoctorId != null) {
      _selectedDoctorId = widget.initialDoctorId;
    }
    _fetchRealDoctors();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _slotPickerController.dispose();
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

      final matchesSpec = _selectedSpecialization == 'جميع التخصصات' ||
          doctor['specialization']
              .contains(_selectedSpecialization.split(' / ')[0]);

      return matchesSearch && matchesSpec;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('احجز موعد'),
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
          'ابحث عن طبيب',
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
            hintText: 'اسم الطبيب أو التخصص',
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
              _specChip('جميع التخصصات', 'جميع التخصصات'),
              const SizedBox(width: 8),
              _specChip('أسنان', 'أسنان'),
              const SizedBox(width: 8),
              _specChip('نساء', 'نساء'),
              const SizedBox(width: 8),
              _specChip('جلدية', 'جلدية'),
              const SizedBox(width: 8),
              _specChip('عام', 'عام'),
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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      selectedColor: Theme.of(context).colorScheme.primary,
      labelStyle: TextStyle(
        color: _selectedSpecialization == spec
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurface,
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
              Icon(Icons.person_search,
                  size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                'لم يتم العثور على أطباء',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          'الأطباء المتاحون',
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
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: InkWell(
                onTap: () {
                  // تغيير الطبيب يُسقط الخانة المختارة: خانة طبيب لا تصلح
                  // لطبيب آخر، و`SlotPicker` يعيد التحميل من تلقائه.
                  setState(() {
                    _selectedDoctorId = doctor['id'];
                    _selectedSlot = null;
                  });
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
                              Icon(Icons.star,
                                  color: Theme.of(context).colorScheme.tertiary,
                                  size: 18),
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
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
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
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 8),
                      if (doctor['clinicLocation'] != null &&
                          doctor['clinicLocation'].toString().isNotEmpty) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on,
                                size: 14,
                                color: Theme.of(context).colorScheme.secondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                doctor['clinicLocation'],
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.tertiary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Text(
                            '${doctor['price']} جنيه',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.tertiary,
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

  /// اختيار الموعد من التوفّر الحقيقي على الخادم.
  ///
  /// كان هنا مولّد خانات محلي يقرأ `workingHours` و`sessionDuration` ويستعلم
  /// Firestore عن المحجوز — نسخة ثانية من منطق الجدول لا تعرف الاستراحات ولا
  /// الإجازات ولا استثناءات التواريخ التي أضافتها المرحلة 1ب، فتعرض أوقاتاً
  /// يرفضها الخادم عند التأكيد.
  Widget _buildDateTimeSection(Map<String, dynamic> doctor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'اختر الموعد'),
        SlotPicker(
          doctorId: doctor['id'].toString(),
          controller: _slotPickerController,
          selectedSlot: _selectedSlot,
          onSlotSelected: (slot) => setState(() => _selectedSlot = slot),
        ),
      ],
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
          decoration: InputDecoration(
            hintText: 'اشرح سبب زيارتك باختصار',
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
        _selectedSlot != null &&
        (_consultationReason?.trim().isNotEmpty ?? false);

    return FilledButton.icon(
      onPressed: isComplete && !_isBooking ? _confirmBooking : null,
      icon: _isBooking
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.check_circle_outline),
      label: Text(_isBooking ? 'جارٍ تأكيد الحجز…' : 'تأكيد الحجز'),
    );
  }

  /// مراجعة أخيرة ثم تأكيد.
  ///
  /// كل ما يُعرض هنا للقراءة فقط: السعر والطبيب والوقت تأتي من الخادم، ولا
  /// حقل منها قابل للتحرير — إرسالها من العميل توقّف منذ المرحلة 1أ.
  void _confirmBooking() {
    final slot = _selectedSlot;
    if (slot == null) return;

    final doctor = _allDoctors.firstWhere((d) => d['id'] == _selectedDoctorId);
    final parsedDate = DateTime.parse(slot.date);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مراجعة الحجز'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DetailRow(
                label: 'الطبيب',
                value: doctor['name'].toString(),
                icon: Icons.person_outline,
              ),
              DetailRow(
                label: 'التخصص',
                value: doctor['specialization'].toString().split(' / ').first,
                icon: Icons.medical_services_outlined,
              ),
              DetailRow(
                label: 'التاريخ',
                value: DateFormat('EEEE d MMMM yyyy', 'ar').format(parsedDate),
                icon: Icons.calendar_today_outlined,
              ),
              DetailRow(
                label: 'الوقت',
                value: slot.displayTime,
                icon: Icons.access_time,
              ),
              DetailRow(
                label: 'سعر الكشف',
                value: '${doctor['price']} جنيه',
                icon: Icons.payments_outlined,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _submitBooking(doctor, slot);
            },
            child: const Text('تأكيد الحجز'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitBooking(
      Map<String, dynamic> doctor, AvailabilitySlot slot) async {
    setState(() => _isBooking = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final result = await _bookingService.book(
      doctorId: doctor['id'].toString(),
      date: DateTime.parse(slot.date),
      time: slot.startTime,
      reason: _consultationReason,
    );

    if (!mounted) return;
    setState(() => _isBooking = false);

    if (result.isSuccess) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => BookingConfirmationScreen(
            doctorName: doctor['name'].toString(),
            specialization:
                doctor['specialization'].toString().split(' / ').first,
            date: slot.date,
            startTime: slot.startTime,
            price: doctor['price'],
            appointmentId: result.appointmentId,
            alreadyBooked: result.duplicate,
          ),
        ),
      );
      if (mounted) navigator.pop();
      return;
    }

    messenger.showSnackBar(SnackBar(
      content: Text(result.message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));

    // الخانة قد تكون امتلأت بين العرض والتأكيد — نعيد تحميل التوفّر بدل
    // ترك المريض أمام وقت لم يعد موجوداً.
    if (result.failure == BookingFailure.slotTaken ||
        result.failure == BookingFailure.slotInThePast) {
      setState(() => _selectedSlot = null);
      _slotPickerController.refresh();
    }
  }
}
