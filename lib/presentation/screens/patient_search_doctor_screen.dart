import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_logger.dart';
import '../widgets/app_widgets.dart';
import 'patient_booking_screen.dart';

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

  /// الفلاتر المتقدّمة مطويّة افتراضياً.
  ///
  /// كانت ثلاث بطاقات فلاتر مفتوحة دائماً تدفع نتائج البحث تحت الطيّة، فيصل
  /// المستخدم للشاشة ولا يرى طبيباً واحداً قبل أن يمرّر.
  bool _filtersOpen = false;

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
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'doctor')
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
        AppSnack.error(context, 'حدث خطأ في تحميل الأطباء');
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredDoctors {
    var doctors = _allDoctors;

    if (_selectedSpecialty != 0) {
      doctors = doctors
          .where((d) => d['specialization'] == _specialties[_selectedSpecialty])
          .toList();
    }

    if (_searchController.text.isNotEmpty) {
      final searchText = _searchController.text.toLowerCase();
      doctors = doctors
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
      doctors = doctors.where((d) => d['rating'] >= _selectedRating).toList();
    }

    doctors = doctors
        .where((d) =>
            d['price'] >= _priceRange.start && d['price'] <= _priceRange.end)
        .toList();

    if (_availableNow) {
      doctors = doctors.where((d) => d['available'] == true).toList();
    }

    return doctors;
  }

  /// عدد الفلاتر النشطة — يظهر كشارة على زر الفلاتر المطويّ حتى لا ينسى
  /// المستخدم أن نتائجه مفلترة.
  int get _activeFilterCount {
    var count = 0;
    if (_selectedRating > 0) count++;
    if (_priceRange.start != 100 || _priceRange.end != 500) count++;
    if (_availableNow) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final doctors = _filteredDoctors;

    return AppScaffold(
      title: 'البحث عن طبيب',
      subtitle: _isLoadingDoctors ? null : '${doctors.length} نتيجة',
      onRefresh: _fetchRealDoctors,
      maxWidth: AppBreakpoints.content,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      headerBottom: AppSearchField(
        controller: _searchController,
        hint: 'اسم الطبيب، العيادة، أو التخصص',
        onChanged: (_) => setState(() {}),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSpecialtyRow(),
          const SizedBox(height: AppSpacing.md),
          _buildFilterPanel(),
          const SizedBox(height: AppSpacing.lg),
          if (_isLoadingDoctors)
            const AppLoader(message: 'جارٍ تحميل الأطباء…')
          else if (doctors.isEmpty)
            EmptyState(
              icon: Icons.search_off_rounded,
              title: 'لا توجد نتائج',
              message: 'جرّب توسيع نطاق السعر أو خفض الحد الأدنى للتقييم.',
              action: _activeFilterCount == 0
                  ? null
                  : OutlinedButton.icon(
                      onPressed: _resetFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('مسح الفلاتر'),
                    ),
            )
          else
            for (final doctor in doctors) ...[
              _DoctorResultCard(
                doctor: doctor,
                onBook: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PatientBookingScreen(initialDoctorId: doctor['id']),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
        ],
      ),
    );
  }

  Widget _buildSpecialtyRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _specialties.length; i++) ...[
            AppChip(
              label: _specialties[i],
              selected: _selectedSpecialty == i,
              onTap: () => setState(() => _selectedSpecialty = i),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterPanel() {
    final tokens = context.tokens;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _filtersOpen = !_filtersOpen),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 19,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text('فلاتر متقدمة', style: context.texts.titleSmall),
                  if (_activeFilterCount > 0) ...[
                    const SizedBox(width: AppSpacing.sm),
                    StatusPill(
                      label: '$_activeFilterCount',
                      color: context.colors.primary,
                      compact: true,
                    ),
                  ],
                  const Spacer(),
                  AnimatedRotation(
                    turns: _filtersOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _filtersOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(color: tokens.border, height: AppSpacing.lg),
                  _filterLabel(
                    'الحد الأدنى للتقييم',
                    _selectedRating == 0
                        ? 'الكل'
                        : '${_selectedRating.toStringAsFixed(1)} نجوم',
                  ),
                  Slider(
                    value: _selectedRating,
                    min: 0,
                    max: 5,
                    divisions: 10,
                    label: _selectedRating.toStringAsFixed(1),
                    onChanged: (value) =>
                        setState(() => _selectedRating = value),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _filterLabel(
                    'نطاق السعر',
                    '${_priceRange.start.toInt()} – '
                        '${_priceRange.end.toInt()} جنيه',
                  ),
                  RangeSlider(
                    values: _priceRange,
                    min: 100,
                    max: 500,
                    divisions: 8,
                    labels: RangeLabels(
                      '${_priceRange.start.toInt()}',
                      '${_priceRange.end.toInt()}',
                    ),
                    onChanged: (values) => setState(() => _priceRange = values),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title:
                        Text('متاح الآن فقط', style: context.texts.bodyMedium),
                    value: _availableNow,
                    onChanged: (value) => setState(() => _availableNow = value),
                  ),
                  if (_activeFilterCount > 0)
                    TextButton.icon(
                      onPressed: _resetFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                      label: const Text('مسح الفلاتر'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterLabel(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.texts.labelMedium),
        Text(
          value,
          style: context.texts.labelMedium
              ?.copyWith(color: context.colors.primary),
        ),
      ],
    );
  }

  void _resetFilters() {
    setState(() {
      _selectedRating = 0;
      _priceRange = const RangeValues(100, 500);
      _availableNow = false;
    });
  }
}

// =============================================================================
// بطاقة النتيجة
// =============================================================================

class _DoctorResultCard extends StatelessWidget {
  const _DoctorResultCard({required this.doctor, required this.onBook});

  final Map<String, dynamic> doctor;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final available = doctor['available'] == true;
    final grouped = doctor['bookingSystemType'] == 'Grouped';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                name: doctor['name']?.toString(),
                icon: Icons.medical_services_rounded,
                size: 50,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctor['clinicNameAr'].toString(),
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
                    const SizedBox(height: AppSpacing.xs),
                    RatingStars(
                      rating: (doctor['rating'] as num).toDouble(),
                      reviews: (doctor['reviews'] as num?)?.toInt(),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: available ? 'متاح' : 'غير متاح',
                color: available ? tokens.success : tokens.warning,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            doctor['bio'].toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodySmall?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.surfaceSunken,
              borderRadius: AppRadius.rMd,
            ),
            child: Column(
              children: [
                _MetaRow(
                  icon: Icons.location_on_outlined,
                  label: 'الموقع',
                  value: doctor['clinicLocation'].toString(),
                ),
                const SizedBox(height: AppSpacing.sm),
                _MetaRow(
                  icon: Icons.schedule_rounded,
                  label: 'ساعات العمل',
                  value: doctor['workingHours'].toString(),
                ),
                const SizedBox(height: AppSpacing.sm),
                _MetaRow(
                  icon: Icons.calendar_month_outlined,
                  label: 'أيام العمل',
                  value: _workingDaysText(doctor['workingDays']),
                ),
                const SizedBox(height: AppSpacing.sm),
                _MetaRow(
                  icon: grouped ? Icons.groups_rounded : Icons.timer_outlined,
                  label: grouped ? 'نظام الحجز' : 'مدة الجلسة',
                  value: grouped
                      ? 'أسبقية الحضور (مجمّع)'
                      : '${doctor['sessionDuration']} دقيقة',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text(
                '${doctor['price'].toInt()}',
                style: context.texts.headlineSmall
                    ?.copyWith(color: tokens.success),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'جنيه',
                style:
                    context.texts.bodySmall?.copyWith(color: tokens.textMuted),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onBook,
                icon: const Icon(Icons.event_available_rounded, size: 18),
                label: const Text('احجز'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _workingDaysText(dynamic workingDays) {
    if (workingDays is Map) {
      final activeDays = workingDays.entries
          .where((e) => e.value == true)
          .map((e) => e.key.toString().split(' ').first)
          .toList();
      if (activeDays.isNotEmpty) return activeDays.join('، ');
    } else if (workingDays is List && workingDays.isNotEmpty) {
      return workingDays.join('، ');
    }
    return 'غير محدد';
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.labelSmall?.copyWith(color: tokens.textBody),
          ),
        ),
      ],
    );
  }
}
