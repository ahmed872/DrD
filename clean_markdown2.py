import re

file_path = 'lib/presentation/screens/doctor_settings_screen.dart'
with open(file_path, 'r', encoding='utf-16') as f:
    content = f.read()

content = re.sub(r'^`dart\s*', '', content, flags=re.MULTILINE)
content = re.sub(r'^`\s*$', '', content, flags=re.MULTILINE)

# remove everything before import start
if "import '" in content:
    idx = content.find("import '")
    content = content[idx:]

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
