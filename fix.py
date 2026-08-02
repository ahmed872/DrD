import os

def fix_file(file):
    with open(file, 'r', encoding='utf-8') as f:
        content = f.read()

    # The corrupted strings and their replacements
    content = content.replace("print('Error fetching appointments: \');", "print('Error fetching appointments: \');")
    content = content.replace("Text('خطأ: \'),", "Text('خطأ: \'),")
    content = content.replace("'🕐 \',", "'🕐 \',")
    content = content.replace("Text('حدث خطأ أثناء الإلغاء: \'),", "Text('حدث خطأ أثناء الإلغاء: \'),")
    content = content.replace("'\',", "'\',")

    with open(file, 'w', encoding='utf-8') as f:
        f.write(content)

fix_file('lib/presentation/screens/doctor_schedule_screen.dart')
fix_file('lib/presentation/screens/patient_my_appointments_screen.dart')
