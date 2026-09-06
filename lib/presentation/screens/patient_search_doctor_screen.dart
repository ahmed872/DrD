import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'patient_booking_screen.dart';
import '../../core/utils/app_logger.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';

class PatientSearchDoctorScreen extends StatefulWidget {
  const PatientSearchDoctorScreen({super.key});

  @override
  State<PatientSearchDoctorScreen> createState() =>
      _PatientSearchDoctorScreenState();
}

class _PatientSearchDoctorScreenState extends State<PatientSearchDoctorScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedSpecialty = 0;
  double _selectedRating = 0;
  RangeValues _priceRange = const RangeValues(100, 500);
  bool _availableNow = false;

  final List<String> _specialties = [
    'الكل',
    'عام',
    'قلب',
    'أسنان',
    'عيون',
    'جلدية',
    'أطفال',
  ];

  List<Map<String, dynamic>> _allDoctors = [];
  bool _isLoadingDoctors = true;

  @override
  void initState() {
    super.initState();
    _fetchRealDoctors();
  }

  Future<void> _fetchRealDoctors() async {
    setState(() => _isLoadingDoctors = true);
    try {
      // `doctor_profiles` لا `users`: الإسقاط العام يحمل حقول الدليل وحدها،
      // بينما مستند المستخدم يحمل معه الهاتف والبريد وتاريخ الميلاد — وقواعد
      // Firestore لا تُرشِّح الحقول، فقراءته كانت تسلّمها كاملة لكل مريض.
      //
      // ولا حاجة لشرط `role`: وجود المستند هو الشرط. الخادم لا ينشئه إلا
      // لطبيب معتمَد، ويحذفه فور خفض الدور أو حذف الحساب.
      final snapshot =
          await FirebaseFirestore.instance.collection('doctor_profiles').get();

      final doctors = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'طبيب غير معروف',
          'nameEn': data['nameEn'] ?? 'Unknown Doctor',
          'clinicNameAr': data['clinicNameAr'] ?? data['name'] ?? 'عيادة',
          'clinicNameEn': data['clinicNameEn'] ?? 'Clinic',
          'specialization': data['specialization'] ?? 'عام',
          'specializationEn': data['specializationEn'] ?? 'General',
          'price': (data['price'] ?? 200).toDouble(),
          'clinicLocation': data['clinicLocation'] ?? 'القاهرة',
          'workingDays': data['workingDays'] ?? [],
          'workingHours': data['workingHours'] ?? 'من 9:00 إلى 5:00',
          'sessionDuration': data['sessionDuration'] ?? 30,
          'bookingSystemType': data['bookingSystemType'] ?? 'Individual',
          'maxPatientsPerSlot': data['maxPatientsPerSlot'] ?? 4,
          'bio': data['bio'] ?? 'طبيب متخصص',
          'bioEn': data['bioEn'] ?? 'Specialized Doctor',
          'rating': (data['rating'] ?? 0.0).toDouble(),
          'reviews': data['reviews'] ?? 0,
          'available': true,
          'nextSlot': 'متاح الآن',
          'patients': 0,
          'icon': '👨‍⚕️',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _allDoctors = doctors;
          _isLoadingDoctors = false;
        });
      }
    } catch (e) {
      AppLogger.info('Error fetching doctors: $e');
      if (mounted) {
        setState(() => _isLoadingDoctors = false);
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar.error('حدث خطأ في تحميل الأطباء'),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('البحث عن طبيب')),
      body: Column(
        children: [
          if (_isLoadingDoctors)
            const LinearProgressIndicator(
              minHeight: 2,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _fetchRealDoctors();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSearchBar(),
                      const SizedBox(height: 16),
                      _buildSpecialtyFilter(),
                      const SizedBox(height: 16),
                      _buildAdvancedFilters(),
                      const SizedBox(height: 16),
                      _buildResults(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'ابحث عن اسم الطبيب أو التخصص...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
              )
            : null,
      ),
      onChanged: (value) {
        setState(() {});
      },
    );
  }

  Widget _buildSpecialtyFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'التخصص',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_specialties.length, (index) {
              final isSelected = _selectedSpecialty == index;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(_specialties[index]),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() => _selectedSpecialty = index);
                  },
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الفلاتر المتقدمة',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الحد الأدنى للتقييم',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Slider(
                        value: _selectedRating,
                        onChanged: (value) {
                          setState(() => _selectedRating = value);
                        },
                        min: 0,
                        max: 5,
                        divisions: 10,
                        label: _selectedRating.toStringAsFixed(1),
                      ),
                    ),
                    Text(
                      _selectedRating == 0
                          ? 'الكل'
                          : '${_selectedRating.toStringAsFixed(1)} ⭐',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'نطاق السعر (جنيه)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 8),
                RangeSlider(
                  values: _priceRange,
                  onChanged: (values) {
                    setState(() => _priceRange = values);
                  },
                  min: 100,
                  max: 500,
                  divisions: 8,
                  labels: RangeLabels(
                    '${_priceRange.start.toInt()}',
                    '${_priceRange.end.toInt()}',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 1,
          child: CheckboxListTile(
            title: const Text('متاح الآن فقط'),
            value: _availableNow,
            onChanged: (value) {
              setState(() => _availableNow = value ?? false);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    if (_isLoadingDoctors) {
      return const LoadingView(message: 'جارٍ تحميل الأطباء…');
    }

    List<Map<String, dynamic>> filteredDoctors = _allDoctors;

    if (_selectedSpecialty != 0) {
      filteredDoctors = filteredDoctors
          .where((d) => d['specialization'] == _specialties[_selectedSpecialty])
          .toList();
    }

    if (_searchController.text.isNotEmpty) {
      final searchText = _searchController.text.toLowerCase();
      filteredDoctors = filteredDoctors
          .where((d) =>
              (d['name'] as String).toLowerCase().contains(searchText) ||
              (d['clinicNameAr'] as String)
                  .toLowerCase()
                  .contains(searchText) ||
              (d['specialization'] as String)
                  .toLowerCase()
                  .contains(searchText))
          .toList();
    }

    if (_selectedRating > 0) {
      filteredDoctors =
          filteredDoctors.where((d) => d['rating'] >= _selectedRating).toList();
    }

    filteredDoctors = filteredDoctors
        .where((d) =>
            d['price'] >= _priceRange.start && d['price'] <= _priceRange.end)
        .toList();

    if (_availableNow) {
      filteredDoctors =
          filteredDoctors.where((d) => d['available'] == true).toList();
    }

    if (filteredDoctors.isEmpty) {
      return const EmptyView(
        icon: Icons.search_off,
        title: 'لا توجد نتائج تطابق البحث',
        message: 'جرّب توسيع نطاق السعر أو إزالة بعض المرشّحات.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'النتائج (${filteredDoctors.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 12),
        ...filteredDoctors.map(_buildDoctorCard),
      ],
    );
  }

  Widget _buildDoctorCard(Map<String, dynamic> doctor) {
    String workingDaysText = 'غير محدد';
    final workingDaysDynamic = doctor['workingDays'];
    if (workingDaysDynamic is Map) {
      final activeDays = workingDaysDynamic.entries
          .where((e) => e.value == true)
          .map((e) => e.key.split(' ').first)
          .toList();
      if (activeDays.isNotEmpty) {
        workingDaysText = activeDays.join('، ');
      }
    } else if (workingDaysDynamic is List && workingDaysDynamic.isNotEmpty) {
      workingDaysText = workingDaysDynamic.join('، ');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: DrdSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doctor['clinicNameAr'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        doctor['specialization'],
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(DrdSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer,
                    borderRadius: DrdRadius.smAll,
                  ),
                  child: const Text('👨‍⚕️', style: TextStyle(fontSize: 28)),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                // النجمة الفارغة تُرسم بلون خافت لا بنفس الذهبي: التمييز
                // بالشكل وحده (مصمتة/مفرغة) يضيع على شاشة صغيرة.
                ...List.generate(
                  5,
                  (i) => Icon(
                    i < doctor['rating'].toInt()
                        ? Icons.star
                        : Icons.star_border,
                    color: i < doctor['rating'].toInt()
                        ? context.drd.rating
                        : context.drd.disabled,
                    size: 18,
                  ),
                ),
                const SizedBox(width: DrdSpacing.xs),
                Text(
                  '${doctor['rating']} (${doctor['reviews']} تقييم)',
                  style: context.text.bodySmall?.copyWith(
                    color: context.drd.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              doctor['bio'],
              style: context.text.bodySmall?.copyWith(
                color: context.drd.muted,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(DrdSpacing.xs),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerHigh,
                borderRadius: DrdRadius.smAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                    '📍',
                    'الموقع',
                    doctor['clinicLocation'],
                  ),
                  const SizedBox(height: 6),
                  _buildDetailRow(
                    '🕐',
                    'ساعات العمل',
                    doctor['workingHours'],
                  ),
                  const SizedBox(height: 6),
                  _buildDetailRow(
                    '📅',
                    'أيام العمل',
                    workingDaysText,
                  ),
                  const SizedBox(height: 6),
                  _buildDetailRow(
                    doctor['bookingSystemType'] == 'Grouped' ? '👥' : '⏱️',
                    doctor['bookingSystemType'] == 'Grouped'
                        ? 'نظام الحجز'
                        : 'مدة الجلسة',
                    doctor['bookingSystemType'] == 'Grouped'
                        ? 'أسبقية الحضور (مجمع)'
                        : '${doctor['sessionDuration']} دقيقة',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StatusChip(
                  label: '${doctor['price'].toInt()} جنيه',
                  tone: DrdTone.neutral,
                  icon: Icons.payments_outlined,
                ),
                StatusChip(
                  label: '${doctor['patients']} مريض',
                  tone: DrdTone.info,
                  icon: Icons.people_outline,
                ),
                StatusChip(
                  label: doctor['available'] ? 'متاح الآن' : 'غير متاح',
                  tone: doctor['available'] ? DrdTone.success : DrdTone.neutral,
                  icon: doctor['available']
                      ? Icons.check_circle_outline
                      : Icons.schedule,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PatientBookingScreen(
                        initialDoctorId: doctor['id'],
                      ),
                    ),
                  );
                },
                child: const Text('احجز موعداً'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String emoji, String label, String value) {
    return Row(
      children: [
        Text(
          emoji,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: context.text.labelSmall?.copyWith(
                  color: context.drd.muted,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
