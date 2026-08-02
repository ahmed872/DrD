import re

with open('lib/presentation/screens/doctor_settings_screen.dart', 'r', encoding='utf-8') as f:
    ds = f.read()

# I will just replace the exact text.
load_target = "_sessionPriceController.text = (data['price'] ?? '').toString();"
load_repl = """_sessionPriceController.text = (data['price'] ?? '').toString();
          _maxPatientsPerSlotController.text = (data['maxPatientsPerSlot'] ?? '4').toString();
          _bookingSystemType = data['bookingSystemType'] ?? 'Individual';"""

if '_bookingSystemType = data' not in ds:
    ds = ds.replace(load_target, load_repl)

# Handle UI display label (we use mojibake matching because of terminal encoding)
# The string in terminal was 'Ø§Ù„Ù…Ø±Ø¶Ù‰ ÙƒØØ¯ Ø£Ù‚ØµÙ‰/Ù…ÙˆØ¹Ø¯' which is "المرضى كحد أقصى/موعد" in UTF-8
# Let's replace the label in the UI
ui_pattern = r"Expanded\(\s*child:\s*_buildTextField\(\s*label:\s*'[^']*',\s*controller:\s*_maxPatientsPerSlotController,"
ui_replacement = """Expanded(
                          child: _buildTextField(
                            label: 'أقصى عدد للحجز',
                            controller: _maxPatientsPerSlotController,"""
ds = re.sub(ui_pattern, ui_replacement, ds)

with open('lib/presentation/screens/doctor_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(ds)

print("Load bug and label fixed!")
