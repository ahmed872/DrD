with open('lib/presentation/screens/doctor_settings_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace("savedSpecAr == 'أخرى (اكتب تخصصك)'", "savedSpecAr == '???? (???? ?????)'")
text = text.replace("_selectedSpecialtyAr = 'أخرى (اكتب تخصصك)'", "_selectedSpecialtyAr = '???? (???? ?????)'")

text = text.replace('التخصص / Specialization', '?????? / Specialization')

old_on_changed = '''                onChanged: (val) {
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
              ),'''

new_on_changed = '''                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedSpecialtyAr = val;
                      _isCustomSpecialty = val == '???? (???? ?????)';
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
                  label: '?????? ???????? (????: ???? ?????)',
                  controller: _customSpecialtyArController,
                  icon: Icons.edit,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  label: '?????? ??????????? (e.g., Physiotherapy)',
                  controller: _customSpecialtyEnController,
                  icon: Icons.edit,
                ),
                const SizedBox(height: 12),
              ],'''

text = text.replace(old_on_changed, new_on_changed)

old_on_changed2 = '''                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedSpecialtyAr = val;
                      _isCustomSpecialty = val == '???? (???? ?????)';
                      if (!_isCustomSpecialty) {
                         _selectedSpecialtyEn = _specialties.firstWhere((e) => e['ar'] == val)['en'];
                      }
                    });
                  }
                },
              ),'''
text = text.replace(old_on_changed2, new_on_changed)

with open('lib/presentation/screens/doctor_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)
