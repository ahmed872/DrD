import re

with open('lib/presentation/screens/doctor_settings_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Fix encoding issues first (the mojibake on "التخصص / Specialization")
text = text.replace('Ø§Ù„ØªØ®ØµØµ', 'التخصص')
text = text.replace('Ø£Ø®Ø±Ù‰ (Ø§ÙƒØªØ¨ ØªØ®ØµØµÙƒ)', 'أخرى (اكتب تخصصك)')

# Replacement 1: Variables and specialties list
target1 = r'  // Specialization\n  String\? _selectedSpecialtyAr;\n  String\? _selectedSpecialtyEn;\n\n  final List<Map<String, String>> _specialties = \[\n    [^\]]+\];'

rep1 = """  // Specialization
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
  ];"""

print("Target 1 found:", bool(re.search(target1, text)))
text = re.sub(target1, rep1, text)

# Replacement 2: loading from data
target2 = r"          // Load specialization\n          final savedSpecAr = data\['specialization'\];\n          if \(savedSpecAr != null\) \{\n            final isStandard = _specialties.any\(\(element\) => element\['ar'\] == savedSpecAr\);\n            if \(isStandard\) \{\n              _selectedSpecialtyAr = savedSpecAr;\n              _selectedSpecialtyEn = data\['specializationEn'\] \?\? _specialties.firstWhere\(\(e\) => e\['ar'\] == savedSpecAr\)\['en'\];\n            \}\n          \}"

rep2 = """          // Load specialization
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
          }"""

print("Target 2 found:", bool(re.search(target2, text)))
text = re.sub(target2, rep2, text)

# Replacement 3: Dropdown
target3 = r"              DropdownButtonFormField<String>\((.*?)\},\n              \),"
rep3 = """              DropdownButtonFormField<String>(\\1},
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
              ],"""
if not bool(re.search(target3, text, re.DOTALL)):
    print("Fallback for target 3")
    # manual replacement since my regex was probably bad due to nested braces
    pass
else:
    print("Target 3 found")
    
# Let's try string split and insert for target 3:
idx = text.find("DropdownButtonFormField<String>(")
idx_end = text.find("const SizedBox(height: 12),", idx)
if idx != -1 and idx_end != -1:
    old_dropdown = text[idx:idx_end]
    # fix the onChange
    new_on_change = """onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedSpecialtyAr = val;
                      _isCustomSpecialty = val == 'أخرى (اكتب تخصصك)';
                      if (!_isCustomSpecialty) {
                         _selectedSpecialtyEn = _specialties.firstWhere((e) => e['ar'] == val)['en'];
                      }
                    });
                  }
                },"""
    new_dropdown = re.sub(r'onChanged: \(val\) \{.*?,', new_on_change + '\n              ),', old_dropdown, flags=re.DOTALL)
    
    text = text[:idx] + new_dropdown + """
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
""" + text[idx_end+len("const SizedBox(height: 12),"):]


# Replacement 4: Saving
target4 = r"'specialization': _selectedSpecialtyAr \?\? '',\s*'specializationEn': _selectedSpecialtyEn \?\? '',"
rep4 = """'specialization': _isCustomSpecialty ? _customSpecialtyArController.text.trim() : (_selectedSpecialtyAr ?? ''),\n            'specializationEn': _isCustomSpecialty ? _customSpecialtyEnController.text.trim() : (_selectedSpecialtyEn ?? ''),"""
print("Target 4 found:", bool(re.search(target4, text)))
text = re.sub(target4, rep4, text)


with open('lib/presentation/screens/doctor_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

