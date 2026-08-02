import glob

files = [
    'lib/presentation/screens/patient_my_appointments_screen.dart',
    'lib/presentation/screens/patient_booking_screen.dart'
]

for file_path in files:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    idx = content.rfind('}\n')
    if idx != -1:
        content = content[:idx+1] + '\n'

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
