import re

with open('lib/presentation/screens/doctor_settings_screen.dart', 'r', encoding='utf-8') as f:
    ds = f.read()

ds = ds.replace("final _patientsPerHourController = TextEditingController(text: '4');\n  String _bookingMode = 'duration';", 
                "final _maxPatientsPerSlotController = TextEditingController(text: '4');\n  String _bookingSystemType = 'Individual';")

ds = ds.replace("_patientsPerHourController.text = (data['patientsPerHour'] ?? '4').toString();\n          _bookingMode = data['bookingMode'] ?? 'duration';",
                "_maxPatientsPerSlotController.text = (data['maxPatientsPerSlot'] ?? '4').toString();\n          _bookingSystemType = data['bookingSystemType'] ?? 'Individual';")

ds = ds.replace("const Text('عدد المرضى في الساعة / Patients per Hour'),", "const Text('نظام مجمع (Grouped)', style: TextStyle(fontSize: 12)),")
ds = ds.replace("value: 'patients_per_hour',\n                        groupValue: _bookingMode,\n                        onChanged: (value) => setState(() => _bookingMode = value!),",
                "value: 'Grouped',\n                        groupValue: _bookingSystemType,\n                        onChanged: (value) => setState(() => _bookingSystemType = value!),")
ds = ds.replace("const Text('مدة الجلسة / Session Duration'),", "const Text('نظام فردي (Individual)', style: TextStyle(fontSize: 12)),")
ds = ds.replace("value: 'duration',\n                        groupValue: _bookingMode,\n                        onChanged: (value) => setState(() => _bookingMode = value!),",
                "value: 'Individual',\n                        groupValue: _bookingSystemType,\n                        onChanged: (value) => setState(() => _bookingSystemType = value!),")

ds = ds.replace("if (_bookingMode == 'duration')", "if (_bookingSystemType == 'Individual')")
ds = ds.replace("controller: _patientsPerHourController,", "controller: _maxPatientsPerSlotController,")
ds = ds.replace("label: 'المرضى/ساعة',", "label: 'المرضى كحد أقصى/موعد',")

ds = ds.replace("int patientsPerHour = int.tryParse(_patientsPerHourController.text) ?? 4;", "int maxPatientsPerSlot = int.tryParse(_maxPatientsPerSlotController.text) ?? 4;")
ds = ds.replace("'patientsPerHour': patientsPerHour,\n          'bookingMode': _bookingMode,", "'maxPatientsPerSlot': maxPatientsPerSlot,\n          'bookingSystemType': _bookingSystemType,")
ds = ds.replace("if ((_bookingMode == 'duration' && duration <= 0) || (_bookingMode == 'patients_per_hour' && patientsPerHour <= 0) || price <= 0)", "if ((_bookingSystemType == 'Individual' && duration <= 0) || (_bookingSystemType == 'Grouped' && maxPatientsPerSlot <= 0) || price <= 0)")


with open('lib/presentation/screens/doctor_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(ds)


with open('lib/presentation/screens/patient_booking_screen.dart', 'r', encoding='utf-8') as f:
    pb = f.read()

pb = pb.replace("'patientsPerHour': data['patientsPerHour'] ?? 4,\n          'bookingMode': data['bookingMode'] ?? 'duration',",
                "'maxPatientsPerSlot': data['maxPatientsPerSlot'] ?? 4,\n          'bookingSystemType': data['bookingSystemType'] ?? 'Individual',")

old_pattern = """String bookingMode = doctor['bookingMode'] ?? 'duration';
    int duration = doctor['sessionDuration'] ?? 30;
    if (bookingMode == 'patients_per_hour') {
      int patientsPerHour = doctor['patientsPerHour'] ?? 4;
      duration = patientsPerHour > 0 ? 60 ~/ patientsPerHour : 15;
    }"""
new_pattern = """String bookingSystemType = doctor['bookingSystemType'] ?? 'Individual';
    int duration = doctor['sessionDuration'] ?? 30;
    if (bookingSystemType == 'Grouped') {
      duration = 60; // 1 hour groups
    }"""
pb = pb.replace(old_pattern, new_pattern)

wrap_pattern = r"Wrap\(\s*alignment: WrapAlignment\.end,\s*spacing: 8,\s*runSpacing: 8,\s*children: _getAvailableTimeSlots\(doctor\)\s*\.where\(\(time\) => !_bookedSlots\.contains\(time\)\)\s*\.map\(\(time\) => _buildTimeSlot\(time\)\)\s*\.toList\(\),\s*\)"
wrap_repl = """Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: _getAvailableTimeSlots(doctor)
                .map((time) {
                  final String sysType = doctor['bookingSystemType'] ?? 'Individual';
                  final int maxPerSlot = (sysType == 'Grouped') ? (doctor['maxPatientsPerSlot'] ?? 4) : 1;
                  int bookedCount = _bookedSlots.where((t) => t == time).length;
                  
                  if (sysType == 'Individual' && _bookedSlots.contains(time)) {
                    return const SizedBox.shrink();
                  } else if (sysType == 'Grouped' && bookedCount >= maxPerSlot) {
                    return const SizedBox.shrink();
                  }

                  return _buildTimeSlot(time, sysType == 'Grouped' ? (maxPerSlot - bookedCount) : null);
                })
                .where((widget) => widget is! SizedBox)
                .toList(),
          )"""
pb = re.sub(wrap_pattern, wrap_repl, pb)

build_time_slot_pattern = r"Widget _buildTimeSlot\(String time\) \{\s*final isSelected = _selectedTime == time;\s*return chip\(\s*label: time,"
build_time_slot_repl = """Widget _buildTimeSlot(String time, int? remaining) {
    final isSelected = _selectedTime == time;
    final displayLabel = remaining != null ? '$time\\n($remaining slots left)' : time;
    return chip(
      label: displayLabel,"""
pb = re.sub(build_time_slot_pattern, build_time_slot_repl, pb)

with open('lib/presentation/screens/patient_booking_screen.dart', 'w', encoding='utf-8') as f:
    f.write(pb)

print("Done grouping apply")