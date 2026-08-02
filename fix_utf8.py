import os

def fix_encoding(filepath):
    try:
        with open(filepath, 'r', encoding='windows-1252') as f:
            content = f.read()
        # if it has mangled chars, try encoding to latin1 then decoding to utf-8
        if 'Ã' in content or 'Ø' in content:
            new_content = content.encode('windows-1252').decode('utf-8')
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print(f"Fixed {filepath}")
        else:
            print(f"File {filepath} looks OK (or couldn't detect mangling).")
    except Exception as e:
        print(f"Failed for {filepath}: {e}")

files = [
    'lib/presentation/screens/doctor_settings_screen.dart',
    'lib/presentation/screens/patient_search_doctor_screen.dart',
    'lib/presentation/screens/patient_booking_screen.dart',
    'lib/presentation/screens/patient_my_appointments_screen.dart'
]

for file in files:
    fix_encoding(file)
