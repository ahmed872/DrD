file_path = 'lib/presentation/screens/doctor_settings_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# find end of class and trim
idx = content.rfind('}\n')
if idx != -1:
    content = content[:idx+1] + '\n'

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
