import re

file_path = 'lib/presentation/screens/doctor_settings_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add _parseTime helper if not exists
if '_parseTime' not in content:
    helper = '''

  TimeOfDay _parseTime(String timeStr) {
    String cleanTime = timeStr.trim();
    final isPM = cleanTime.toUpperCase().contains('PM');
    final isAM = cleanTime.toUpperCase().contains('AM');

    String justTime = cleanTime
        .toUpperCase()
        .replaceAll('AM', '')
        .replaceAll('PM', '')
        .trim();
    final hm = justTime.split(':');
    int hour = int.tryParse(hm[0]) ?? 0;
    int minute = hm.length > 1 ? (int.tryParse(hm[1]) ?? 0) : 0;

    if (isPM && hour != 12) {
      hour += 12;
    } else if (isAM && hour == 12) {
      hour = 0;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
'''
    content = content.replace('  @override\n  void dispose() {', helper)

# Add the UI text field for location
ui_field = '''

              _buildTextField(
                label: 'عنوان العيادة / Clinic Location',
                controller: _clinicLocationController, // ADDED
                icon: Icons.location_on,
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              
              _buildDropdownField(
'''
content = content.replace('_buildDropdownField(', ui_field, 1)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
