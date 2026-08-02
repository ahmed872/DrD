import re

with open('lib/presentation/screens/doctor_settings_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

pattern = r'(if \(_isCustomSpecialty\) \.\.\.\[[\s\S]*?const SizedBox\(height: 12\),\s*\]\,\s*)+'
new_block = '''              if (_isCustomSpecialty) ...[
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
              ],
'''
text = re.sub(pattern, new_block, text)

with open('lib/presentation/screens/doctor_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

