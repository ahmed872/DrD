import re

with open('lib/presentation/screens/doctor_settings_screen.dart', 'r', encoding='utf-8') as f:
    ds = f.read()

pattern = r"_workingDays\.clear\(\);\s*for \(var key in workingDaysMap\.keys\) \{\s*_workingDays\[key\] = workingDaysMap\[key\] == true;\s*\}"
replacement = """for (var key in workingDaysMap.keys) {
                    if (_workingDays.containsKey(key)) {
                      _workingDays[key] = workingDaysMap.keys.contains(key) ? (workingDaysMap[key] == true) : false;
                    }
                  }"""
ds = re.sub(pattern, replacement, ds)

with open('lib/presentation/screens/doctor_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(ds)
print("Working days bug fixed in doctor settings")
