import re

with open('lib/presentation/screens/doctor_settings_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Add new variables
if '_patientsPerHourController' not in content:
    content = re.sub(
        r"final _sessionDurationController = TextEditingController\(text: '30'\);",
        "final _sessionDurationController = TextEditingController(text: '30');\n  final _patientsPerHourController = TextEditingController(text: '4');\n  String _bookingMode = 'duration';",
        content
    )

# Update loading logic
if 'bookingMode' not in content:
    content = re.sub(
        r"_sessionDurationController\.text =\s*\(data\['sessionDuration'\] \?\? ''\)\.toString\(\);",
        "_sessionDurationController.text = (data['sessionDuration'] ?? '').toString();\n          _patientsPerHourController.text = (data['patientsPerHour'] ?? '4').toString();\n          _bookingMode = data['bookingMode'] ?? 'duration';",
        content
    )

# Update UI to toggle between duration and patients per hour
ui_pattern = r"Row\(\s*children: \[\s*Expanded\(\s*child: _buildTextField\(\s*label: 'المدة \(دقيقة\)',[\s\S]*?\]\,[\s\S]*?\)\,"
replacement = '''Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('عدد المرضى في الساعة / Patients per Hour'),
                      Radio<String>(
                        value: 'patients_per_hour',
                        groupValue: _bookingMode,
                        onChanged: (value) => setState(() => _bookingMode = value!),
                      ),
                      const SizedBox(width: 16),
                      const Text('مدة الجلسة / Session Duration'),
                      Radio<String>(
                        value: 'duration',
                        groupValue: _bookingMode,
                        onChanged: (value) => setState(() => _bookingMode = value!),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_bookingMode == 'duration')
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
                            label: 'المرضى/ساعة',
                            controller: _patientsPerHourController,
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
              ),'''

if 'Patients per Hour' not in content:
    content = re.sub(ui_pattern, replacement, content)

# Modify saving logic
save_pattern = r"int duration = int\.tryParse\(_sessionDurationController\.text\) \?\? 0;"
save_repl = "int duration = int.tryParse(_sessionDurationController.text) ?? 30;\n    int patientsPerHour = int.tryParse(_patientsPerHourController.text) ?? 4;"
if 'patientsPerHour' not in content[content.find('void _saveSetting()'):]:
    content = re.sub(save_pattern, save_repl, content)

save_pattern2 = r"'sessionDuration': duration,"
save_repl2 = "'sessionDuration': duration,\n          'patientsPerHour': patientsPerHour,\n          'bookingMode': _bookingMode,"
if "'bookingMode': _bookingMode" not in content:
    content = re.sub(save_pattern2, save_repl2, content)

# Check for duration constraint in validation
val_pattern = r"if \(duration <= 0 \|\| price <= 0\) \{"
val_repl = "if ((_bookingMode == 'duration' && duration <= 0) || (_bookingMode == 'patients_per_hour' && patientsPerHour <= 0) || price <= 0) {"
content = re.sub(val_pattern, val_repl, content)

with open('lib/presentation/screens/doctor_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print('Updated doctor_settings_screen.dart')

with open('lib/presentation/screens/patient_booking_screen.dart', 'r', encoding='utf-8') as f:
    content_b = f.read()

# Add bookingMode and patientsPerHour to fetched doctor map
doc_map_pattern = r"'sessionDuration': data\['sessionDuration'\] \?\? 30,"
doc_map_repl = "'sessionDuration': data['sessionDuration'] ?? 30,\n          'patientsPerHour': data['patientsPerHour'] ?? 4,\n          'bookingMode': data['bookingMode'] ?? 'duration',"
if 'patientsPerHour' not in content_b:
    content_b = re.sub(doc_map_pattern, doc_map_repl, content_b)

# modify _getAvailableTimeSlots
time_slots_pattern = r"int duration = doctor\['sessionDuration'\] \?\? 30;\s*String workingHours = doctor\['workingHours'\] \?\? '09:00 AM - 05:00 PM';"
time_slots_repl = """String bookingMode = doctor['bookingMode'] ?? 'duration';
    int duration = doctor['sessionDuration'] ?? 30;
    if (bookingMode == 'patients_per_hour') {
      int patientsPerHour = doctor['patientsPerHour'] ?? 4;
      duration = patientsPerHour > 0 ? 60 ~/ patientsPerHour : 15;
    }
    String workingHours = doctor['workingHours'] ?? '09:00 AM - 05:00 PM';"""

content_b = re.sub(time_slots_pattern, time_slots_repl, content_b)

with open('lib/presentation/screens/patient_booking_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content_b)
print('Updated patient_booking_screen.dart')
