import re

with open('lib/presentation/screens/doctor_settings_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

patch1 = """
  // Specialization
  String? _selectedSpecialtyAr;
  String? _selectedSpecialtyEn;
  bool _isCustomSpecialty = false;
  final TextEditingController _customSpecialtyArController = TextEditingController();
  final TextEditingController _customSpecialtyEnController = TextEditingController();

  final List<Map<String, String>> _specialties = [
    {'ar': 'عام', 'en': 'General Practice'},
    {'ar': 'أسنان', 'en': 'Dentistry'},
    {'ar': 'نساء', 'en': 'Obstetrics'},
    {'ar': 'جلدية', 'en': 'Dermatology'},
    {'ar': 'أطفال', 'en': 'Pediatrics'},
    {'ar': 'عيون', 'en': 'Ophthalmology'},
    {'ar': 'باطنة', 'en': 'Internal Medicine'},
    {'ar': 'عظام', 'en': 'Orthopedics'},
    {'ar': 'أنف وأذن وحنجرة', 'en': 'ENT'},
    {'ar': 'مخ وأعصاب', 'en': 'Neurology'},
    {'ar': 'مسالك بولية', 'en': 'Urology'},
    {'ar': 'قلب', 'en': 'Cardiology'},
    {'ar': 'نفسية', 'en': 'Psychiatry'},
    {'ar': 'أخرى (اكتب تخصصك)', 'en': 'Other (Type your specialty)'},
  ];
"""

text = re.sub(r'  // Specialization\s*String\? _selectedSpecialtyAr;\s*String\? _selectedSpecialtyEn;\s*final List<Map<String, String>> _specialties = \[.*?\];', patch1, text, flags=re.DOTALL)

patch2 = """
          // Load specialization
          final savedSpecAr = data['specialization'];
          if (savedSpecAr != null && savedSpecAr.isNotEmpty) {
            final isStandard = _specialties.any((element) => element['ar'] == savedSpecAr);
            if (isStandard) {
              _selectedSpecialtyAr = savedSpecAr;
              _selectedSpecialtyEn = data['specializationEn'] ?? _specialties.firstWhere((e) => e['ar'] == savedSpecAr)['en'];
              _isCustomSpecialty = savedSpecAr == 'أخرى (اكتب تخصصك)';
            } else {
              _selectedSpecialtyAr = 'أخرى (اكتب تخصصك)';
              _isCustomSpecialty = true;
              _customSpecialtyArController.text = savedSpecAr;
              _customSpecialtyEnController.text = data['specializationEn'] ?? '';
            }
          }
"""

text = re.sub(r'          // Load specialization\s*.*?            }', patch2, text, flags=re.DOTALL)

patch3 = """
              DropdownButtonFormField<String>(
                value: _selectedSpecialtyAr,
                decoration: InputDecoration(
                  labelText: 'التخصص / Specialization',
                  prefixIcon:
                      const Icon(Icons.medical_services, color: Colors.blue),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
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
                      _isCustomSpecialty = val == 'أخرى (اكتب تخصصك)';
                      if (!_isCustomSpecialty) {
                         _selectedSpecialtyEn = _specialties.firstWhere((e) => e['ar'] == val)['en'];
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              
              if (_isCustomSpecialty) ...[
                _buildTextField(
                  label: 'التخصص بالعربية (مثال: علاج طبيعي)',
                  controller: _customSpecialtyArController,
                  icon: Icons.edit,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  label: 'التخصص بالإنجليزية (e.g., Physiotherapy)',
                  controller: _customSpecialtyEnController,
                  icon: Icons.edit,
                ),
                const SizedBox(height: 12),
              ],
"""
text = re.sub(r'              DropdownButtonFormField<String>\(.*?              const SizedBox\(height: 12\),', patch3, text, flags=re.DOTALL)

patch4 = """
          final finalSpecAr = _isCustomSpecialty ? _customSpecialtyArController.text.trim() : (_selectedSpecialtyAr ?? '');
          final finalSpecEn = _isCustomSpecialty ? _customSpecialtyEnController.text.trim() : (_selectedSpecialtyEn ?? '');

          await FirebaseFirestore.instance
              .collection('users')
              .doc(auth.userId)
              .set({
            'clinicNameAr': _clinicNameAr.text,
            'clinicNameEn': _clinicNameEn.text,
            'clinicLocation': _clinicLocationController.text,
            'specialization': finalSpecAr,
            'specializationEn': finalSpecEn,
"""
text = re.sub(r'          await FirebaseFirestore\.instance\s*\.collection\(\'users\'\)\s*\.doc\(auth\.userId\)\s*\.set\(\{\s*\'clinicNameAr\': _clinicNameAr\.text,\s*\'clinicNameEn\': _clinicNameEn\.text,\s*\'clinicLocation\': _clinicLocationController\.text,\s*\'specialization\': _selectedSpecialtyAr \?\? \'\',\s*\'specializationEn\': _selectedSpecialtyEn \?\? \'\',', patch4, text, flags=re.DOTALL)

with open('lib/presentation/screens/doctor_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)
