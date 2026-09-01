import '../widgets/role_guard.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/firebase_auth_service.dart';

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

  final Map<String, bool> _workingDays = {
    'السبت (Saturday)': true,
    'الأحد (Sunday)': true,
    'الاثنين (Monday)': true,
    'الثلاثاء (Tuesday)': true,
    'الأربعاء (Wednesday)': true,
    'الخميس (Thursday)': true,
    'الجمعة (Friday)': false,
  };

  bool _isLoading = false;

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
      debugPrint('Error parsing time: $e');
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
              debugPrint('Error parsing working hours: $e');
            }
          }

          // Load working days Map
          if (data['workingDays'] != null && data['workingDays'] is Map) {
            try {
              final workingDaysMap =
                  Map<String, dynamic>.from(data['workingDays']);
              setState(() {
                for (var key in workingDaysMap.keys) {
                  if (_workingDays.containsKey(key)) {
                    _workingDays[key] = workingDaysMap.keys.contains(key)
                        ? (workingDaysMap[key] == true)
                        : false;
                  }
                }
              });
            } catch (e) {
              debugPrint('Error loading working days: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading doctor profile: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تحميل بيانات العيادة')),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // الحارس يجعل الشاشة متّسقة مع صلاحية الخادم: من ليس طبيباً له عيادة
    // (نشط أو موقوف) يرى رسالة مفهومة بدل استعلامات تُرفض بلا تفسير.
    return RoleGuard(
      requireDoctorClinicAccess: true,
      child: Builder(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات العيادة'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle),
            onPressed: _saveSetting,
            tooltip: 'Save / احفظ',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // === معلومات العيادة ===
              _buildSectionTitle('📋 معلومات العيادة / Clinic Info'),
              const SizedBox(height: 16),

              _buildTextField(
                label: 'اسم العيادة (بالعربية)',
                controller: _clinicNameAr,
                icon: Icons.business,
              ),
              const SizedBox(height: 12),

              _buildTextField(
                label: 'Clinic Name (English)',
                controller: _clinicNameEn,
                icon: Icons.business,
              ),
              const SizedBox(height: 12),

              _buildTextField(
                label: 'موقع العيادة / Clinic Location',
                controller: _clinicLocationController,
                icon: Icons.location_on,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _selectedSpecialtyAr,
                decoration: InputDecoration(
                  labelText: 'التخصص / Specialization',
                  prefixIcon: Icon(Icons.medical_services,
                      color: Theme.of(context).colorScheme.primary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary, width: 2),
                  ),
                ),
                items: _specialties.map((spec) {
                  return DropdownMenuItem<String>(
                    value: spec['ar'],
                    child: Text('${spec['ar']} / ${spec['en']}'),
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
              const SizedBox(height: 12),

              _buildTextField(
                label: 'رقم الهاتف / Phone',
                controller: _phoneController,
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),

              _buildTextField(
                label: 'نبذة عنك (Arabic)',
                controller: _bioAr,
                icon: Icons.info,
                maxLines: 3,
              ),
              const SizedBox(height: 12),

              _buildTextField(
                label: 'About You (English)',
                controller: _bioEn,
                icon: Icons.info,
                maxLines: 3,
              ),

              const SizedBox(height: 24),

              // === أسعار وأوقات المواعيد ===
              _buildSectionTitle('⏱️ مدة الموعد والسعر / Duration & Price'),
              const SizedBox(height: 16),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('نظام مجمع (Grouped)',
                          style: TextStyle(fontSize: 12)),
                      Radio<String>(
                        value: 'Grouped',
                        groupValue: _bookingSystemType,
                        onChanged: (value) =>
                            setState(() => _bookingSystemType = value!),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('نظام فردي (Individual)',
                          style: TextStyle(fontSize: 12)),
                      Radio<String>(
                        value: 'Individual',
                        groupValue: _bookingSystemType,
                        onChanged: (value) =>
                            setState(() => _bookingSystemType = value!),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_bookingSystemType == 'Individual')
                        Expanded(
                          child: _buildTextField(
                            label: 'المدة (دقيقة)',
                            controller: _sessionDurationController,
                            icon: Icons.schedule,
                            keyboardType: TextInputType.number,
                          ),
                        )
                      else
                        Expanded(
                          child: _buildTextField(
                            label: 'أقصى عدد للحجز',
                            controller: _maxPatientsPerSlotController,
                            icon: Icons.people,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          label: 'السعر (جنيه)',
                          controller: _sessionPriceController,
                          icon: Icons.attach_money,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // === ساعات العمل ===
              _buildSectionTitle('🕐 ساعات العمل / Working Hours'),
              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Theme.of(context).colorScheme.primary),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildTimePickerButton(
                          'وقت النهاية / End',
                          _endTime,
                          (time) => setState(() => _endTime = time),
                        ),
                        _buildTimePickerButton(
                          'وقت البداية / Start',
                          _startTime,
                          (time) => setState(() => _startTime = time),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onPrimary,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        child: Text(
                          '${_startTime.format(context)} - ${_endTime.format(context)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // === أيام العمل ===
              _buildSectionTitle('📅 أيام العمل / Working Days'),
              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Theme.of(context).colorScheme.tertiary),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: _workingDays.entries.map((entry) {
                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Switch(
                              value: entry.value,
                              onChanged: (value) {
                                setState(() {
                                  _workingDays[entry.key] = value;
                                });
                              },
                              activeColor:
                                  Theme.of(context).colorScheme.tertiary,
                            ),
                          ],
                        ),
                        const Divider(),
                      ],
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 24),

              // === زر الحفظ ===
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _saveSetting,
                  icon: const Icon(Icons.save),
                  label: const Text(
                    'حفظ الإعدادات / Save Settings',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.tertiary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // === زر عرض المعاينة ===
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _showPreview,
                  icon: const Icon(Icons.visibility),
                  label: const Text(
                    'معاينة / Preview',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          right: BorderSide(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              width: 4),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildTimePickerButton(
    String label,
    TimeOfDay time,
    Function(TimeOfDay) onTimeSelected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        OutlinedButton(
          onPressed: () async {
            final pickedTime = await showTimePicker(
              context: context,
              initialTime: time,
            );
            if (pickedTime != null) {
              onTimeSelected(pickedTime);
            }
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            time.format(context),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  void _saveSetting() async {
    setState(() => _isLoading = true);
    final auth = Provider.of<FirebaseAuthService>(context, listen: false);

    // Format working hours properly from TimeOfDay objects
    String _formatTimeExplicit(TimeOfDay time) {
      final h =
          time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
      final p = time.hour < 12 ? 'AM' : 'PM';
      return '${h.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $p';
    }

    String formattedWorkingHours =
        '${_formatTimeExplicit(_startTime)} - ${_formatTimeExplicit(_endTime)}';

    int duration = int.tryParse(_sessionDurationController.text) ?? 30;
    int maxPatientsPerSlot =
        int.tryParse(_maxPatientsPerSlotController.text) ?? 4;
    double price = double.tryParse(_sessionPriceController.text) ?? 0;

    if ((_bookingSystemType == 'Individual' && duration <= 0) ||
        (_bookingSystemType == 'Grouped' && maxPatientsPerSlot <= 0) ||
        price <= 0) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('يرجى التأكد من أن السعر ومدة الجلسة أكبر من صفر'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
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

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle,
                      color: Theme.of(context).colorScheme.onPrimary),
                  SizedBox(width: 12),
                  Text(
                    '✅ تم الحفظ بنجاح / Saved Successfully',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              backgroundColor: Theme.of(context).colorScheme.tertiary,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تعذّر حفظ الإعدادات، حاول مرة أخرى'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _showPreview() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Text('👁️ معاينة / Preview'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              _previewRow('🏥 العيادة', _clinicNameAr.text, _clinicNameEn.text),
              _previewRow('📍 الموقع', _clinicLocationController.text,
                  _clinicLocationController.text),
              _previewRow('🔬 التخصص', _selectedSpecialtyAr ?? '',
                  _selectedSpecialtyEn ?? ''),
              _previewRow(
                  '📞 الهاتف', _phoneController.text, _phoneController.text),
              _previewRow(
                  _bookingSystemType == 'Grouped' ? '⏳ نظام الحجز' : '⏱️ المدة',
                  _bookingSystemType == 'Grouped'
                      ? '${_maxPatientsPerSlotController.text} مرضى كحد أقصى'
                      : '${_sessionDurationController.text} دقيقة',
                  _bookingSystemType == 'Grouped'
                      ? '${_maxPatientsPerSlotController.text} patients/slot'
                      : '${_sessionDurationController.text} min'),
              _previewRow('السعر', '${_sessionPriceController.text} جنيه',
                  '\$${_sessionPriceController.text}'),
              _previewRow(
                '🕐 الساعات',
                '${_startTime.format(context)} - ${_endTime.format(context)}',
                '${_startTime.format(context)} - ${_endTime.format(context)}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق / Close'),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(String icon, String arText, String enText) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              enText,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.left,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              arText,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          Text(icon),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _clinicNameAr.dispose();
    _clinicNameEn.dispose();
    _phoneController.dispose();
    _bioAr.dispose();
    _bioEn.dispose();
    _sessionDurationController.dispose();
    _sessionPriceController.dispose();
    _clinicLocationController.dispose();
    super.dispose();
  }
}
