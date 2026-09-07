import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'book_appointment_screen.dart';
import '../../core/utils/app_logger.dart';
import '../../core/constants/specialties.dart';
import '../../core/utils/safe_field.dart';
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
  /// حدود الشريط، مشتقّة من أسعار الأطباء المعروضين فعلاً.
  ///
  /// كانت مثبَّتة على 100–500، وكان المرشِّح يُسقط كل ما خرج عنها. فطبيب
  /// بسعر 80 أو 600 لا يظهر لأي مريض، **ولا وسيلة لإظهاره**: الشريط نفسه
  /// لا يصل إلى قيمته. والأسوأ أن `price` يقرأ بـ `fallback: 0` عند غياب
  /// الحقل أو فساده، فأي طبيب بلا سعر كان يسقط من الدليل صامتاً.
  RangeValues? _priceBounds;

  /// اختيار المريض داخل [_priceBounds]. `null` يعني «لم تصل الأسعار بعد».
  RangeValues? _priceRange;
  bool _availableNow = false;

  // المصدر الموحّد — راجع lib/core/constants/specialties.dart.
  //
  // كانت القائمة مكتوبة هنا يدوياً وتحوي `قلب` — تخصّص لا يستطيع أي طبيب
  // اختياره، فالرقاقة تُرجع صفراً دائماً — بينما `نساء` و`باطنية` و`عظام`
  // يختارها الأطباء ولا رقاقة لها، فلا يجدهم المريض إلا بالبحث النصّي.
  final List<String> _specialties = Specialties.filterOptions;

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
          // القراءة دفاعية عمداً — راجع lib/core/utils/safe_field.dart.
          // كان `(data['price'] ?? 200).toDouble()` يرمي على قيمة نصّية،
          // والاستثناء يقع داخل `map()` على كل الأطباء فتفرغ القائمة **لكل**
          // المرضى بسبب مستند واحد معطوب. القاعدة تمنع كتابة قيمة كهذه اليوم،
          // لكنها لا تصلح ما كُتب قبلها.
          'id': doc.id,
          'name': safeString(data['name'],
              fallback: 'طبيب غير معروف', maxLength: 100),
          'clinicNameAr': safeString(data['clinicNameAr'],
              fallback: safeString(data['name'], fallback: 'عيادة'),
              maxLength: 120),
          'specialization': safeString(data['specialization'],
              fallback: 'عام', maxLength: 80),
          'price': safeDouble(data['price'], fallback: 0),
          'clinicLocation': safeString(data['clinicLocation'],
              fallback: 'غير محدّد', maxLength: 200),
          'workingDays': data['workingDays'] is Map ? data['workingDays'] : {},
          'workingHours': safeString(data['workingHours'],
              fallback: 'غير محدّدة', maxLength: 100),
          'sessionDuration':
              safeInt(data['sessionDuration'], fallback: 30, min: 5, max: 240),
          'bookingSystemType':
              data['bookingSystemType'] == 'Grouped' ? 'Grouped' : 'Individual',
          'maxPatientsPerSlot':
              safeInt(data['maxPatientsPerSlot'], fallback: 4, min: 1, max: 50),
          'bio':
              safeString(data['bio'], fallback: 'طبيب متخصص', maxLength: 1000),
          'rating': safeDouble(data['rating'], fallback: 0).clamp(0, 5),
          'reviews': safeInt(data['reviews'], fallback: 0, min: 0),
          'available': true,
          'nextSlot': 'متاح الآن',
          'patients': 0,
          'icon': '👨‍⚕️',
        };
      }).toList();

      // حدود السعر تُحسب من النتيجة لا تُفترض، ويُفتح المدى كاملاً افتراضياً
      // كي لا يُخفي المرشِّح أحداً قبل أن يلمسه المريض.
      final prices = doctors.map((d) => d['price'] as double).toList()..sort();
      final bounds = prices.isEmpty
          ? null
          // RangeSlider يرفض min == max، وهو ما يحدث حين يتساوى سعر كل
          // الأطباء أو حين يكون الطبيب واحداً.
          : RangeValues(
              prices.first.floorToDouble(),
              prices.last.ceilToDouble() > prices.first.floorToDouble()
                  ? prices.last.ceilToDouble()
                  : prices.first.floorToDouble() + 1,
            );

      if (mounted) {
        setState(() {
          _allDoctors = doctors;
          _priceBounds = bounds;
          _priceRange = bounds;
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
        _buildPriceFilter(),
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

  /// مرشِّح السعر.
  ///
  /// القيم مكتوبة تحت الشريط دائماً، لا في فقاعة تظهر أثناء السحب وحده:
  /// المريض يحتاج أن يعرف الحدّين **قبل** أن يقرّر السحب، لا بعده.
  Widget _buildPriceFilter() {
    final bounds = _priceBounds;
    final range = _priceRange;

    // لا شريط قبل وصول الأسعار، ولا شريط حين يتساوى سعر الجميع: مرشِّح لا
    // يُرشِّح شيئاً يشغل مساحة ويوحي بخيار غير موجود.
    if (bounds == null || range == null) return const SizedBox.shrink();

    String egp(double value) => '${value.round()} جنيه';

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'نطاق السعر',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                Text(
                  '${egp(range.start)} — ${egp(range.end)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.colors.primary,
                  ),
                ),
              ],
            ),
            RangeSlider(
              values: range,
              min: bounds.start,
              max: bounds.end,
              // خطوة لكل 25 جنيهاً، وبحدّ أقصى معقول: `divisions` كبيرة على
              // مدى واسع تُنتج شريطاً لا يستقر تحت الإصبع.
              divisions: (((bounds.end - bounds.start) / 25).round())
                  .clamp(1, 40),
              labels: RangeLabels(egp(range.start), egp(range.end)),
              onChanged: (values) => setState(() => _priceRange = values),
            ),
            // طرفا المدى: يشرحان إلى أين يصل الشريط أصلاً.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  egp(bounds.start),
                  style: TextStyle(fontSize: 11, color: context.drd.muted),
                ),
                Text(
                  egp(bounds.end),
                  style: TextStyle(fontSize: 11, color: context.drd.muted),
                ),
              ],
            ),
          ],
        ),
      ),
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

    final priceRange = _priceRange;
    if (priceRange != null) {
      filteredDoctors = filteredDoctors.where((d) {
        final price = d['price'] as double;
        return price >= priceRange.start && price <= priceRange.end;
      }).toList();
    }

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
                      builder: (context) => BookAppointmentScreen(
                        doctorId: doctor['id'] as String,
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
