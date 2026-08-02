import re

with open('lib/presentation/screens/doctor_settings_screen.dart', 'r', encoding='utf-8') as f:
    ds = f.read()

# Make _parseTime handle AM/PM/ص/م
old_parse_pattern = r"bool isPM = trimmed\.contains\('PM'\);\s*bool isAM = trimmed\.contains\('AM'\);\s*String rawTime = trimmed\.replaceAll\('AM', ''\)\.replaceAll\('PM', ''\)\.trim\(\);"

new_parse_repl = """bool isPM = trimmed.contains('PM') || trimmed.contains('م');
      bool isAM = trimmed.contains('AM') || trimmed.contains('ص');
      String rawTime = trimmed.replaceAll('AM', '').replaceAll('PM', '').replaceAll('ص', '').replaceAll('م', '').replaceAll(' ', '').trim();"""

ds = re.sub(old_parse_pattern, new_parse_repl, ds)

# Fix saving formatted working hours explicitly
old_format_pattern = r"String formattedWorkingHours =\s*'\$\{\_startTime\.format\(context\)\} - \$\{\_endTime\.format\(context\)\}';"

new_format_repl = """String _formatTimeExplicit(TimeOfDay time) {
      final h = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
      final p = time.hour < 12 ? 'AM' : 'PM';
      return '${h.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $p';
    }

    String formattedWorkingHours = '${_formatTimeExplicit(_startTime)} - ${_formatTimeExplicit(_endTime)}';"""

ds = re.sub(old_format_pattern, new_format_repl, ds)

with open('lib/presentation/screens/doctor_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(ds)

# --- 2. Fix the AM/PM display in patient booking screen ---
with open('lib/presentation/screens/patient_booking_screen.dart', 'r', encoding='utf-8') as f:
    pb = f.read()

# Replace _buildTimeSlot simple $time display with formatted label
build_time_slot_pattern = r"Widget _buildTimeSlot\(String time, int\? remaining\) \{\s*final isSelected = _selectedTime == time;\s*final displayLabel = remaining != null \? '\$time\\n\(\$remaining slots left\)' : time;"

new_build_time_slot_repl = """Widget _buildTimeSlot(String time, int? remaining) {
    final isSelected = _selectedTime == time;
    final parts = time.split(':');
    String formattedTime = time;
    if (parts.length == 2) {
      int h = int.tryParse(parts[0]) ?? 0;
      final m = parts[1];
      final period = h >= 12 ? 'م' : 'ص';
      if (h == 0) h = 12;
      else if (h > 12) h -= 12;
      formattedTime = '${h.toString().padLeft(2, '0')}:$m $period';
    }
    
    final displayLabel = remaining != null ? '$formattedTime\\n(باقي $remaining)' : formattedTime;"""

pb = re.sub(build_time_slot_pattern, new_build_time_slot_repl, pb)

with open('lib/presentation/screens/patient_booking_screen.dart', 'w', encoding='utf-8') as f:
    f.write(pb)
