import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'patient_booking_screen.dart';
import '../../core/utils/app_logger.dart';

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
      // الأطباء الموثَّقون فقط — مطابق لما تسمح به `firestore.rules` عند
      // الحجز، حتى لا يظهر في البحث طبيب لا يمكن الحجز عنده.
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'doctor')
          .where('isVerified', isEqualTo: true)
          .get();

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
          SnackBar(
            content: const Text('حدث خطأ في تحميل الأطباء'),
            backgroundColor: Colors.red,
          ),
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
      appBar: AppBar(
        title: const Text('البحث عن طبيب'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0097A7),
        elevation: 1,
      ),
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Colors.grey[50],
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
                  backgroundColor: Colors.grey[100],
                  selectedColor: Colors.blue.shade700,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
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
            activeColor: Colors.blue.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    if (_isLoadingDoctors) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'جاري تحميل الأطباء...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Text(
                '🔍',
                style: TextStyle(fontSize: 48, color: Colors.grey[300]),
              ),
              const SizedBox(height: 16),
              Text(
                'لا توجد نتائج تطابق البحث',
                style: TextStyle(color: Colors.grey[500], fontSize: 16),
              ),
            ],
          ),
        ),
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
        ...filteredDoctors.map((doctor) => _buildDoctorCard(doctor)).toList(),
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

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '👨‍⚕️',
                    style: TextStyle(fontSize: 28),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: Colors.grey[300]),
            const SizedBox(height: 12),
            Row(
              children: [
                ...List.generate(
                  5,
                  (i) => Icon(
                    i < doctor['rating'].toInt()
                        ? Icons.star
                        : Icons.star_border,
                    color: Colors.amber,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${doctor['rating']} (${doctor['reviews']} تقييم)',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              doctor['bio'],
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
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
                _infoChip('💰 ${doctor['price'].toInt()} جنيه', Colors.green),
                _infoChip('👥 ${doctor['patients']} مريض', Colors.blue),
                _infoChip(
                  doctor['available'] ? '✅ متاح الآن' : '⏳ غير متاح',
                  doctor['available'] ? Colors.green : Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
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
                child: const Text(
                  'احجز موعداً',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
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

  Widget _infoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
