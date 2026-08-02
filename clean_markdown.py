import re

file_path = 'lib/presentation/screens/doctor_settings_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Strip any markdown blocks if the subagent wrapped the code
content = re.sub(r'^`dart\s*', '', content, flags=re.MULTILINE)
content = re.sub(r'^`\s*$', '', content, flags=re.MULTILINE)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
