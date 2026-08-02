import re

file_path = 'lib/presentation/screens/doctor_settings_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add _clinicLocationController
content = content.replace(
    'final _sessionPriceController = TextEditingController();', 
    '''final _sessionPriceController = TextEditingController();
  final _clinicLocationController = TextEditingController(); // ADDED'''
)

# Load clinicLocation profile
content = content.replace(
    "_clinicNameEn.text = data['clinicNameEn'] ?? '';",
    '''_clinicNameEn.text = data['clinicNameEn'] ?? '';
        _clinicLocationController.text = data['clinicLocation'] ?? ''; // ADDED
'''
)

# Update _saveSetting
content = content.replace(
    "'clinicNameEn': _clinicNameEn.text,",
    ''''clinicNameEn': _clinicNameEn.text,
        'clinicLocation': _clinicLocationController.text, // ADDED
'''
)

# Add to dispose
content = content.replace(
    "_sessionPriceController.dispose();",
    '''_sessionPriceController.dispose();
    _clinicLocationController.dispose(); // ADDED'''
)

# Load working days and hours robustly
old_load_hours = "if (data['workingHours'] != null) {"
new_load_hours = '''if (data['workingHours'] != null) {
          try {
            final parts = data['workingHours'].split(' - ');
            if (parts.length == 2) {
              final startStr = parts[0].trim();
              final endStr = parts[1].trim();
              _startTime = _parseTime(startStr);
              _endTime = _parseTime(endStr);
            }
          } catch (_) {}
        }
        
        if (data['workingDays'] != null && data['workingDays'] is Map) {
          try {
            final workingDaysMap = Map<String, dynamic>.from(data['workingDays']);
            setState(() {
              _workingDays.clear();
              for (var key in workingDaysMap.keys) {
                _workingDays[key] = workingDaysMap[key] == true;
              }
            });
          } catch (_) {}
        }
        if (data['workingHours'] != null) { // this replaces the old if so the parser below works
'''

content = content.replace(old_load_hours, new_load_hours)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
