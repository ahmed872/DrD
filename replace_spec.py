import re
with open('lib/presentation/screens/doctor_settings_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

pattern = r'  // Specialization\n.*?  // Working hours and days'
replacement = '''  // Specialization
  String? _selectedSpecialtyAr;
  String? _selectedSpecialtyEn;
  bool _isCustomSpecialty = false;
  final TextEditingController _customSpecialtyArController = TextEditingController();
  final TextEditingController _customSpecialtyEnController = TextEditingController();

  final List<Map<String, String>> _specialties = [
    {'ar': '???', 'en': 'General Practice'},
    {'ar': '?????', 'en': 'Dentistry'},
    {'ar': '????', 'en': 'Obstetrics'},
    {'ar': '?????', 'en': 'Dermatology'},
    {'ar': '?????', 'en': 'Pediatrics'},
    {'ar': '????', 'en': 'Ophthalmology'},
    {'ar': '?????', 'en': 'Internal Medicine'},
    {'ar': '????', 'en': 'Orthopedics'},
    {'ar': '??? ???? ??????', 'en': 'ENT'},
    {'ar': '?? ??????', 'en': 'Neurology'},
    {'ar': '????? ?????', 'en': 'Urology'},
    {'ar': '???', 'en': 'Cardiology'},
    {'ar': '?????', 'en': 'Psychiatry'},
    {'ar': '???? (???? ?????)', 'en': 'Other (Type your specialty)'},
  ];

  // Working hours and days'''

text = re.sub(pattern, replacement, text, flags=re.DOTALL)

with open('lib/presentation/screens/doctor_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)
