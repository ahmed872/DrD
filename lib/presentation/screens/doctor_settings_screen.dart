import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_logger.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/app_widgets.dart';

class DoctorSettingsScreen extends StatefulWidget {
  const DoctorSettingsScreen({super.key});

  @override
  State<DoctorSettingsScreen> createState() => _DoctorSettingsScreenState();
}

class _DoctorSettingsScreenState extends State<DoctorSettingsScreen> {
  // Controllers for clinic information
  final _clinicNameAr = TextEditingController();
  final _clinicNameEn = TextEditingController();
  final _clinicLocationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioAr = TextEditingController();
  final _bioEn = TextEditingController();
  final _sessionDurationController = TextEditingController(text: '30');
  final _maxPatientsPerSlotController = TextEditingController(text: '4');
  String _bookingSystemType = 'Individual';
  final _sessionPriceController = TextEditingController();

  // Specialization
  String? _selectedSpecialtyAr;
  String? _selectedSpecialtyEn;

  final List<Map<String, String>> _specialties = [
    {'ar': 'عام', 'en': 'General Practice'},
    {'ar': 'أسنان', 'en': 'Dentistry'},
    {'ar': 'نساء', 'en': 'Obstetrics'},
    {'ar': 'جلدية', 'en': 'Dermatology'},
    {'ar': 'أطفال', 'en': 'Pediatrics'},
    {'ar': 'عيون', 'en': 'Ophthalmology'},
    {'ar': 'باطنية', 'en': 'Internal Medicine'},
    {'ar': 'عظام', 'en': 'Orthopedics'},
  ];

  // Working hours and days
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);

  // المفاتيح تُحفظ في Firestore كما هي، فلا تُغيَّر. النص المعروض للمستخدم
  // يأتي من `_dayLabels` أدناه.
  final Map<String, bool> _workingDays = {
    'السبت (Saturday)': true,
    'الأحد (Sunday)': true,
    'الاثنين (Monday)': true,
    'الثلاثاء (Tuesday)': true,
    'الأربعاء (Wednesday)': true,
    'الخميس (Thursday)': true,
    'الجمعة (Friday)': false,
  };

  static const Map<String, String> _dayLabels = {
    'السبت (Saturday)': 'السبت',
    'الأحد (Sunday)': 'الأحد',
    'الاثنين (Monday)': 'الاثنين',
    'الثلاثاء (Tuesday)': 'الثلاثاء',
    'الأربعاء (Wednesday)': 'الأربعاء',
    'الخميس (Thursday)': 'الخميس',
    'الجمعة (Friday)': 'الجمعة',
  };

  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadDoctorProfile();
  }

  /// Parse time string in format "hh:mm AM/PM" or "hh:mm" to TimeOfDay
  TimeOfDay _parseTime(String timeString) {
    try {
      final trimmed = timeString.trim().toUpperCase();
      bool isPM = trimmed.contains('PM') || trimmed.contains('م');
      bool isAM = trimmed.contains('AM') || trimmed.contains('ص');
      String rawTime = trimmed
          .replaceAll('AM', '')
          .replaceAll('PM', '')
          .replaceAll('ص', '')
          .replaceAll('م', '')
          .replaceAll(' ', '')
          .trim();
      List<String> parts = rawTime.split(':');

      if (parts.length >= 2) {
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts.length > 1 ? parts[1].split(' ')[0] : '0');

        if (isPM && hour < 12) hour += 12;
        if (isAM && hour == 12) hour = 0;

        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (e) {
      AppLogger.info('Error parsing time: $e');
    }

    // Return default time if parsing fails
    return const TimeOfDay(hour: 9, minute: 0);
  }

  Future<void> _loadDoctorProfile() async {
    setState(() => _isLoading = true);

    final auth = Provider.of<FirebaseAuthService>(context, listen: false);
    if (auth.userId != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(auth.userId)
            .get();

        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;

          // Load basic clinic information
          _clinicNameAr.text = data['clinicNameAr'] ?? '';
          _clinicNameEn.text = data['clinicNameEn'] ?? '';
          _clinicLocationController.text = data['clinicLocation'] ?? '';

          // Load specialization
          final savedSpecAr = data['specialization'];
          if (savedSpecAr != null &&
              _specialties.any((element) => element['ar'] == savedSpecAr)) {
            _selectedSpecialtyAr = savedSpecAr;
            _selectedSpecialtyEn = data['specializationEn'] ??
                _specialties.firstWhere((e) => e['ar'] == savedSpecAr)['en'];
          }

          // Load contact and bio
          _phoneController.text = data['phone'] ?? '';
          _bioAr.text = data['bio'] ?? '';
          _bioEn.text = data['bioEn'] ?? '';

          // Load session details
          _sessionDurationController.text =
              (data['sessionDuration'] ?? '').toString();
          _sessionPriceController.text = (data['price'] ?? '').toString();
          _maxPatientsPerSlotController.text =
              (data['maxPatientsPerSlot'] ?? '4').toString();
          _bookingSystemType = data['bookingSystemType'] ?? 'Individual';

          // Load working hours - Parse '09:00 AM - 05:00 PM' format
          if (data['workingHours'] != null) {
            try {
              final parts = data['workingHours'].split(' - ');
              if (parts.length == 2) {
                _startTime = _parseTime(parts[0].trim());
                _endTime = _parseTime(parts[1].trim());
              }
            } catch (e) {
              AppLogger.info('Error parsing working hours: $e');
            }
          }

          // Load working days Map
          if (data['workingDays'] != null && data['workingDays'] is Map) {
            try {
              final workingDaysMap =
                  Map<String, dynamic>.from(data['workingDays']);
              for (var key in workingDaysMap.keys) {
                if (_workingDays.containsKey(key)) {
                  _workingDays[key] = workingDaysMap[key] == true;
                }
              }
            } catch (e) {
              AppLogger.info('Error loading working days: $e');
            }
          }
        }
      } catch (e) {
        AppLogger.info('Error loading doctor profile: $e');
        if (mounted) AppSnack.error(context, 'تعذّر تحميل بيانات العيادة');
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إعدادات العيادة',
      subtitle: 'هذه البيانات هي ما يراه المرضى عنك',
      maxWidth: AppBreakpoints.content,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      actions: [
        IconButton(
          onPressed: _isSaving ? null : _saveSetting,
          icon: const Icon(Icons.check_rounded),
          color: Colors.white,
          tooltip: 'حفظ',
        ),
      ],
      child: _isLoading
          ? const AppLoader(message: 'جارٍ تحميل الإعدادات…')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle(
                  title: 'معلومات العيادة',
                  icon: Icons.local_hospital_outlined,
                ),
                _buildClinicCard(),
                const SizedBox(height: AppSpacing.xxl),
                const SectionTitle(
                  title: 'نظام الحجز والسعر',
                  subtitle: 'يحدّد كيف تُقسَّم مواعيدك على المرضى',
                  icon: Icons.event_seat_outlined,
                ),
                _buildBookingCard(),
                const SizedBox(height: AppSpacing.xxl),
                const SectionTitle(
                  title: 'ساعات العمل',
                  icon: Icons.schedule_rounded,
                ),
                _buildHoursCard(),
                const SizedBox(height: AppSpacing.xxl),
                const SectionTitle(
                  title: 'أيام العمل',
                  icon: Icons.calendar_month_outlined,
                ),
                _buildDaysCard(),
                const SizedBox(height: AppSpacing.xxl),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _saveSetting,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_isSaving ? 'جارٍ الحفظ…' : 'حفظ الإعدادات'),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _showPreview,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('معاينة كما يراها المريض'),
                ),
              ],
            ),
    );
  }

  Widget _buildClinicCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _clinicNameAr,
            label: 'اسم العيادة (بالعربية)',
            icon: Icons.business_outlined,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _clinicNameEn,
            label: 'اسم العيادة (بالإنجليزية)',
            icon: Icons.business_outlined,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _clinicLocationController,
            label: 'موقع العيادة',
            hint: 'المدينة، الشارع، رقم العمارة',
            icon: Icons.location_on_outlined,
          ),
          const SizedBox(height: AppSpacing.lg),
          DropdownButtonFormField<String>(
            initialValue: _selectedSpecialtyAr,
            decoration: const InputDecoration(
              labelText: 'التخصص',
              prefixIcon: Icon(Icons.medical_services_outlined, size: 20),
            ),
            items: _specialties.map((spec) {
              return DropdownMenuItem<String>(
                value: spec['ar'],
                child: Text(spec['ar']!),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedSpecialtyAr = val;
                  _selectedSpecialtyEn =
                      _specialties.firstWhere((e) => e['ar'] == val)['en'];
                });
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _phoneController,
            label: 'رقم هاتف العيادة',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _bioAr,
            label: 'نبذة عنك (بالعربية)',
            hint: 'خبرتك، شهاداتك، وما يميّز عيادتك',
            icon: Icons.info_outline_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _bioEn,
            label: 'نبذة عنك (بالإنجليزية)',
            icon: Icons.info_outline_rounded,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCard() {
    final individual = _bookingSystemType == 'Individual';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // خياران موصوفان بدل زرّي راديو بلا شرح: الفرق بين النظامين يغيّر
          // شكل يوم الطبيب بالكامل، ولم يكن مشروحاً في أي مكان.
          _SystemOption(
            title: 'نظام فردي',
            description: 'كل مريض له وقت خاص به، بمدة ثابتة تحدّدها أنت.',
            icon: Icons.person_rounded,
            selected: individual,
            onTap: () => setState(() => _bookingSystemType = 'Individual'),
          ),
          const SizedBox(height: AppSpacing.md),
          _SystemOption(
            title: 'نظام مجمّع',
            description: 'عدة مرضى في نفس الساعة، والكشف بأسبقية الحضور.',
            icon: Icons.groups_rounded,
            selected: !individual,
            onTap: () => setState(() => _bookingSystemType = 'Grouped'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: individual
                    ? AppTextField(
                        controller: _sessionDurationController,
                        label: 'مدة الجلسة (دقيقة)',
                        icon: Icons.timer_outlined,
                        keyboardType: TextInputType.number,
                      )
                    : AppTextField(
                        controller: _maxPatientsPerSlotController,
                        label: 'أقصى عدد في الساعة',
                        icon: Icons.people_outline_rounded,
                        keyboardType: TextInputType.number,
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppTextField(
                  controller: _sessionPriceController,
                  label: 'سعر الكشف (جنيه)',
                  icon: Icons.payments_outlined,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHoursCard() {
    final tokens = context.tokens;

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _TimeButton(
                  label: 'من',
                  time: _startTime,
                  onPicked: (t) => setState(() => _startTime = t),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: tokens.textFaint,
                  size: 18,
                ),
              ),
              Expanded(
                child: _TimeButton(
                  label: 'إلى',
                  time: _endTime,
                  onPicked: (t) => setState(() => _endTime = t),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.08),
              borderRadius: AppRadius.rMd,
            ),
            child: Text(
              '${_startTime.format(context)}  —  ${_endTime.format(context)}',
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: context.texts.titleMedium
                  ?.copyWith(color: context.colors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaysCard() {
    final tokens = context.tokens;
    final entries = _workingDays.entries.toList();

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                color: tokens.border,
                height: 1,
                indent: AppSpacing.lg,
                endIndent: AppSpacing.lg,
              ),
            SwitchListTile(
              value: entries[i].value,
              onChanged: (value) =>
                  setState(() => _workingDays[entries[i].key] = value),
              title: Text(
                _dayLabels[entries[i].key] ?? entries[i].key,
                style: context.texts.bodyLarge?.copyWith(
                  color:
                      entries[i].value ? tokens.textStrong : tokens.textMuted,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _saveSetting() async {
    setState(() => _isSaving = true);
    final auth = Provider.of<FirebaseAuthService>(context, listen: false);

    // Format working hours properly from TimeOfDay objects
    String formatTimeExplicit(TimeOfDay time) {
      final h =
          time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
      final p = time.hour < 12 ? 'AM' : 'PM';
      final hh = h.toString().padLeft(2, '0');
      final mm = time.minute.toString().padLeft(2, '0');
      return '$hh:$mm $p';
    }

    String formattedWorkingHours =
        '${formatTimeExplicit(_startTime)} - ${formatTimeExplicit(_endTime)}';

    int duration = int.tryParse(_sessionDurationController.text) ?? 30;
    int maxPatientsPerSlot =
        int.tryParse(_maxPatientsPerSlotController.text) ?? 4;
    double price = double.tryParse(_sessionPriceController.text) ?? 0;

    if ((_bookingSystemType == 'Individual' && duration <= 0) ||
        (_bookingSystemType == 'Grouped' && maxPatientsPerSlot <= 0) ||
        price <= 0) {
      setState(() => _isSaving = false);
      AppSnack.error(
        context,
        'يرجى التأكد من أن السعر ومدة الجلسة أكبر من صفر',
      );
      return;
    }

    if (auth.userId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(auth.userId)
            .set({
          'clinicNameAr': _clinicNameAr.text,
          'clinicNameEn': _clinicNameEn.text,
          'clinicLocation': _clinicLocationController.text,
          'specialization': _selectedSpecialtyAr ?? '',
          'specializationEn': _selectedSpecialtyEn ?? '',
          'phone': auth.normalizePhoneNumber(_phoneController.text),
          'bio': _bioAr.text,
          'bioEn': _bioEn.text,
          'sessionDuration': duration,
          'maxPatientsPerSlot': maxPatientsPerSlot,
          'bookingSystemType': _bookingSystemType,
          'price': price,
          'workingHours': formattedWorkingHours,
          'workingDays': _workingDays,
        }, SetOptions(merge: true));

        if (mounted) AppSnack.success(context, 'تم حفظ الإعدادات بنجاح');
      } catch (e) {
        if (mounted) AppSnack.error(context, 'تعذّر حفظ الإعدادات');
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  /// معاينة تعرض بيانات العيادة كما ستظهر للمريض في نتائج البحث.
  void _showPreview() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final tokens = ctx.tokens;
        final grouped = _bookingSystemType == 'Grouped';

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'هكذا يراك المريض',
                  textAlign: TextAlign.center,
                  style: ctx.texts.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xl),
                AppCard(
                  child: Column(
                    children: [
                      InfoRow(
                        label: 'العيادة',
                        value: _orDash(_clinicNameAr.text),
                        icon: Icons.local_hospital_outlined,
                      ),
                      InfoRow(
                        label: 'التخصص',
                        value: _orDash(_selectedSpecialtyAr),
                        icon: Icons.medical_services_outlined,
                      ),
                      InfoRow(
                        label: 'الموقع',
                        value: _orDash(_clinicLocationController.text),
                        icon: Icons.location_on_outlined,
                      ),
                      InfoRow(
                        label: 'الهاتف',
                        value: _orDash(_phoneController.text),
                        icon: Icons.phone_outlined,
                      ),
                      InfoRow(
                        label: grouped ? 'نظام الحجز' : 'مدة الجلسة',
                        value: grouped
                            ? 'مجمّع — حتى '
                                '${_maxPatientsPerSlotController.text} مرضى'
                            : '${_sessionDurationController.text} دقيقة',
                        icon: grouped
                            ? Icons.groups_rounded
                            : Icons.timer_outlined,
                      ),
                      InfoRow(
                        label: 'سعر الكشف',
                        value: '${_orDash(_sessionPriceController.text)} جنيه',
                        icon: Icons.payments_outlined,
                        valueColor: tokens.success,
                      ),
                      InfoRow(
                        label: 'ساعات العمل',
                        value: '${_startTime.format(ctx)} - '
                            '${_endTime.format(ctx)}',
                        icon: Icons.schedule_rounded,
                      ),
                      InfoRow(
                        label: 'أيام العمل',
                        value: _activeDaysText(),
                        icon: Icons.calendar_month_outlined,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _orDash(String? value) =>
      (value == null || value.trim().isEmpty) ? 'لم يُحدَّد' : value.trim();

  String _activeDaysText() {
    final active = _workingDays.entries
        .where((e) => e.value)
        .map((e) => _dayLabels[e.key] ?? e.key)
        .toList();
    return active.isEmpty ? 'لم تُحدَّد أيام عمل' : active.join('، ');
  }

  @override
  void dispose() {
    _clinicNameAr.dispose();
    _clinicNameEn.dispose();
    _phoneController.dispose();
    _bioAr.dispose();
    _bioEn.dispose();
    _sessionDurationController.dispose();
    _maxPatientsPerSlotController.dispose();
    _sessionPriceController.dispose();
    _clinicLocationController.dispose();
    super.dispose();
  }
}

// =============================================================================
// عناصر مساعدة
// =============================================================================

class _SystemOption extends StatelessWidget {
  const _SystemOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final primary = context.colors.primary;

    return Material(
      color: selected ? primary.withValues(alpha: 0.07) : tokens.surfaceSunken,
      borderRadius: AppRadius.rMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rMd,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rMd,
            border: Border.all(
              color: selected ? primary : tokens.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? primary : tokens.textMuted,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.texts.titleSmall?.copyWith(
                        color: selected ? primary : tokens.textStrong,
                      ),
                    ),
                    Text(
                      description,
                      style: context.texts.bodySmall
                          ?.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? primary : tokens.borderStrong,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.time,
    required this.onPicked,
  });

  final String label;
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onPicked;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: context.texts.labelSmall?.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton(
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: time,
              helpText: 'اختر $label',
            );
            if (picked != null) onPicked(picked);
          },
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          child: Text(
            time.format(context),
            textDirection: TextDirection.ltr,
          ),
        ),
      ],
    );
  }
}
