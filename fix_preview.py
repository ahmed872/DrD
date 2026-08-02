import re

# 1. Fix doctor_settings_screen.dart
with open('lib/presentation/screens/doctor_settings_screen.dart', 'r', encoding='utf-8') as f:
    ds = f.read()

# Let's just find the preview row
preview_old = "_previewRow(\n                  '⏱️ المدة',\n                  '${_sessionDurationController.text} دقيقة',\n                  '${_sessionDurationController.text} min'),"
preview_new = """_previewRow(
                '⏱️ نظام الحجز',
                _bookingSystemType == 'Grouped' ? '${_maxPatientsPerSlotController.text} مرضى كحد أقصى' : '${_sessionDurationController.text} دقيقة',
                _bookingSystemType == 'Grouped' ? '${_maxPatientsPerSlotController.text}' : '${_sessionDurationController.text} min',
              ),"""
ds = ds.replace(preview_old, preview_new)
# In case it has mojibake encoding
preview_old2 = "_previewRow(\n                  'â±ï¸ Ø§Ù„Ù…Ø¯Ø©',\n                  '${_sessionDurationController.text} Ø¯Ù‚ÙŠÙ‚Ø©',\n                  '${_sessionDurationController.text} min'),"
ds = ds.replace(preview_old2, preview_new)

with open('lib/presentation/screens/doctor_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(ds)

# 2. Fix patient_search_doctor_screen.dart
with open('lib/presentation/screens/patient_search_doctor_screen.dart', 'r', encoding='utf-8') as f:
    pss = f.read()

search_map_pattern = r"'sessionDuration': data\['sessionDuration'\] \?\? 30,"
search_map_repl = """'sessionDuration': data['sessionDuration'] ?? 30,
            'bookingSystemType': data['bookingSystemType'] ?? 'Individual',
            'maxPatientsPerSlot': data['maxPatientsPerSlot'] ?? 4,"""
if 'bookingSystemType' not in pss:
    pss = re.sub(search_map_pattern, search_map_repl, pss)

ui_row_old = """_buildDetailRow(
                      '⏱️',
                      'مدة الجلسة',
                      '${doctor['sessionDuration']} دقيقة',
                    ),"""
ui_row_new = """_buildDetailRow(
                      '⏱️',
                      doctor['bookingSystemType'] == 'Grouped' ? 'نظام الحجز' : 'مدة الجلسة',
                      doctor['bookingSystemType'] == 'Grouped' ? '${doctor['maxPatientsPerSlot']} مرضى كحد أقصى' : '${doctor['sessionDuration']} دقيقة',
                    ),"""
pss = pss.replace(ui_row_old, ui_row_new)

# Handle mojibake encoding
ui_row_old2 = """_buildDetailRow(
                      'â±ï¸',
                      'Ù…Ø¯Ø© Ø§Ù„Ø¬Ù„Ø³Ø©',
                      '${doctor['sessionDuration']} Ø¯Ù‚ÙŠÙ‚Ø©',
                    ),"""
pss = pss.replace(ui_row_old2, ui_row_new)


with open('lib/presentation/screens/patient_search_doctor_screen.dart', 'w', encoding='utf-8') as f:
    f.write(pss)

print("Preview updated!")
