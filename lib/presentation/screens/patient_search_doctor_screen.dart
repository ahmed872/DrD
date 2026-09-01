import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/app_surfaces.dart';
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
  static const double _kPriceMin = 100;
  static const double _kPriceMax = 500;
  RangeValues _priceRange = const RangeValues(_kPriceMin, _kPriceMax);
  bool _availableNow = false;

  /// الفلاتر المتقدّمة مطويّة افتراضياً.
  bool _filtersExpanded = false;

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

  // ===== المرحلة 7: ترقيم صفحات الأطباء =====
  //
  // كان الاستعلام يقرأ **مجموعة الأطباء كاملة** في كل مرة تُفتح فيها
  // الشاشة. التكلفة تنمو مع عدد أطباء المنصّة كلها لا مع ما يراه المريض.
  //
  // الفلترة (تخصص، تقييم، سعر، نصّ) تقع على العميل بحكم التصميم القائم،
  // فتقييد القراءة يعني أن الفلاتر تعمل على المحمَّل فقط. لذلك لا يُخفى
  // ذلك: زرّ «تحميل المزيد» ظاهر ما بقيت صفحات، والعدّاد يقول «من أصل
  // المحمَّل». إسقاط نتيجة بصمت أسوأ من تكلفة القراءة.
  static const int _pageSize = 25;
  DocumentSnapshot<Map<String, dynamic>>? _lastDoctorDoc;
  bool _hasMoreDoctors = false;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _fetchRealDoctors();
  }

  Future<void> _fetchRealDoctors({bool loadMore = false}) async {
    setState(() {
      if (loadMore) {
        _isLoadingMore = true;
      } else {
        _isLoadingDoctors = true;
        _lastDoctorDoc = null;
      }
    });
    try {
      // الأطباء الموثَّقون فقط — مطابق لما تسمح به `firestore.rules` عند
      // الحجز، حتى لا يظهر في البحث طبيب لا يمكن الحجز عنده.
      // الترتيب بالاسم يعطي صفحات مستقرّة (مؤشّر لا إزاحة).
      // الفهرس `role + isVerified + name` مُعلَن في `firestore.indexes.json`.
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'doctor')
          .where('isVerified', isEqualTo: true)
          .orderBy('name')
          .limit(_pageSize);
      if (loadMore && _lastDoctorDoc != null) {
        query = query.startAfterDocument(_lastDoctorDoc!);
      }
      final snapshot = await query.get();

      // المرحلة 2: طبيب موقوف (`disabled: true`) يبقى `isVerified: true` —
      // تمييز متعمَّد بين «غير موثَّق» و«موثَّق لكن موقوف مؤقتاً» (راجع
      // `functions/admin.js`). لا فلترة على `disabled` في الاستعلام نفسه
      // عمداً: الأطباء القدامى ليس لديهم الحقل إطلاقاً، و
      // `where('disabled', isEqualTo: false)` في Firestore يستبعد أي مستند
      // بلا الحقل بدل معاملته كـ false — فيختفي كل طبيب سابق للمرحلة 2 من
      // البحث. الفلترة هنا بعد القراءة على نفس البيانات الحقيقية تتجنّب هذا.
      final visibleDocs =
          snapshot.docs.where((doc) => doc.data()['disabled'] != true);

      final doctors = visibleDocs.map((doc) {
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
          if (loadMore) {
            _allDoctors = [..._allDoctors, ...doctors];
          } else {
            _allDoctors = doctors;
          }
          // المؤشّر من **المستندات** لا من المرشَّح بعد إسقاط الموقوفين،
          // وإلا انقطع التسلسل عند صفحة كلّها موقوفون.
          if (snapshot.docs.isNotEmpty) _lastDoctorDoc = snapshot.docs.last;
          _hasMoreDoctors = snapshot.docs.length == _pageSize;
          _isLoadingDoctors = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      AppLogger.info('Error fetching doctors: $e');
      if (mounted) {
        setState(() {
          _isLoadingDoctors = false;
          _isLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('حدث خطأ في تحميل الأطباء'),
            backgroundColor: Theme.of(context).colorScheme.error,
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
                child: ContentWidthLimit(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // الترتيب هنا يقرّر متى يرى المريض أول طبيب.
                        // كان: بحث + تخصصات + ثلاث بطاقات فلترة كاملة العرض
                        // (تقييم، سعر، متاح الآن) — نحو 1100 بكسل قبل أول
                        // نتيجة، أي شاشتان كاملتان من الضبط قبل أي محتوى.
                        // الفلاتر المتقدّمة صارت خلف زرّ يظهر عدد المفعَّل
                        // منها، والنتائج تبدأ مباشرة بعد شرائح التخصص.
                        _buildSearchBar(),
                        const SizedBox(height: AppSpacing.lg),
                        _buildSpecialtyFilter(),
                        const SizedBox(height: AppSpacing.md),
                        _buildFilterToggle(),
                        if (_filtersExpanded) ...[
                          const SizedBox(height: AppSpacing.md),
                          _buildAdvancedFilters(),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        _buildResults(),
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                    ),
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
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                // كان `right` هنا و`left` في شاشة مرضى الطبيب — صفّا رقائق
                // متشابهان بتباعد معكوس. الشكل الاتجاهي يوحّدهما.
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: FilterChip(
                  label: Text(_specialties[index]),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() => _selectedSpecialty = index);
                  },
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface,
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

  /// عدد الفلاتر المتقدّمة المفعَّلة — يُعرض على الزرّ حتى لا تختفي
  /// فلترة نشطة خلف قسم مطويّ فيحتار المريض لِمَ النتائج قليلة.
  int get _activeAdvancedFilters {
    var n = 0;
    if (_selectedRating > 0) n++;
    if (_availableNow) n++;
    if (_priceRange.start > _kPriceMin || _priceRange.end < _kPriceMax) n++;
    return n;
  }

  Widget _buildFilterToggle() {
    final active = _activeAdvancedFilters;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () => setState(() => _filtersExpanded = !_filtersExpanded),
        icon: Icon(_filtersExpanded ? Icons.expand_less : Icons.tune, size: 18),
        label: Text(active == 0 ? 'فلاتر متقدمة' : 'فلاتر متقدمة ($active)'),
      ),
    );
  }

  Widget _buildAdvancedFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
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
            activeColor: Theme.of(context).colorScheme.primary,
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
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                style: TextStyle(
                    fontSize: 48,
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              const SizedBox(height: 16),
              Text(
                'لا توجد نتائج تطابق البحث',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 16),
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
          _hasMoreDoctors
              ? 'النتائج (${filteredDoctors.length} من المحمَّل)'
              : 'النتائج (${filteredDoctors.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        ...filteredDoctors.map(_buildDoctorCard),
        // الفلاتر تعمل على المحمَّل فقط، فبقاء صفحات يُقال صراحةً بدل أن
        // يظنّ المريض أن هذا كل ما في المنصّة.
        if (_hasMoreDoctors) ...[
          const SizedBox(height: AppSpacing.sm),
          if (_isLoadingMore)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: () => _fetchRealDoctors(loadMore: true),
              icon: const Icon(Icons.expand_more),
              label: const Text('تحميل المزيد من الأطباء'),
            ),
        ],
      ],
    );
  }

  /// بطاقة الطبيب.
  ///
  /// كانت البطاقة السابقة تُقرأ من أسفلها: الاسم والتخصص أعلى، ثم مربّع
  /// لوني فارغ مكان الصورة، ثم فاصل، ثم النجوم، ثم النبذة، ثم بطاقة
  /// متداخلة للموقع، وأخيراً السعر وأيام العمل وزرّ الحجز — أي أن السعر
  /// والإجراء، وهما ما يقرّر عليهما المريض، يقعان تحت الطيّ.
  ///
  /// الترتيب الآن: الهويّة (حرف الاسم، الاسم، التخصص، التوثيق) → التقييم
  /// والسعر في سطر واحد → الموقع → الحجز. ثلاثة أسطر قابلة للمسح البصري
  /// السريع، وبطاقة واحدة بلا بطاقات متداخلة.
  Widget _buildDoctorCard(Map<String, dynamic> doctor) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = (doctor['name'] ?? 'طبيب').toString();
    final rating = (doctor['rating'] as num?)?.toDouble() ?? 0;
    final reviews = (doctor['reviews'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        onTap: () => _openBooking(doctor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // حرف الاسم بدل مربّع لوني فارغ: لا صور أطباء في النظام،
                // والمربّع الفارغ يقرأ كصورة لم تُحمَّل.
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initial(name),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 6),
                          // كل طبيب معروض هنا موثَّق (الاستعلام يشترطه)،
                          // فالعلامة تأكيد لا تمييز.
                          Icon(Icons.verified, size: 16, color: scheme.primary),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (doctor['specialization'] ?? '').toString(),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Icon(Icons.star_rounded,
                    size: 18, color: AppColors.rating),
                const SizedBox(width: 4),
                Text(
                  rating == 0 ? 'جديد' : rating.toStringAsFixed(1),
                  style: theme.textTheme.titleSmall,
                ),
                if (reviews > 0) ...[
                  const SizedBox(width: 4),
                  Text('($reviews)', style: theme.textTheme.bodySmall),
                ],
                const Spacer(),
                Text(
                  '${(doctor['price'] as num).toInt()} جنيه',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: scheme.primary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (doctor['clinicLocation'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () => _openBooking(doctor),
              child: const Text('احجز موعداً'),
            ),
          ],
        ),
      ),
    );
  }

  void _openBooking(Map<String, dynamic> doctor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PatientBookingScreen(initialDoctorId: doctor['id']),
      ),
    );
  }

  /// أول حرف من اسم الطبيب بعد إسقاط لقب «د.».
  static String _initial(String name) {
    final cleaned = name.replaceFirst(RegExp(r'^د\.?\s*'), '').trim();
    return cleaned.isEmpty ? '؟' : cleaned.characters.first;
  }
}
