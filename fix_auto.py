import re
import glob

def fix_mojibake(match):
    text = match.group(0)
    try:
        b = text.encode('windows-1252')
        # If it decodes to UTF-8 successfully, return it.
        # Otherwise, return original.
        decoded = b.decode('utf-8')
        # Only return decoded if it actually changed something and has arabic chars
        # Arabic range: \u0600 - \u06FF
        if re.search(r'[\u0600-\u06FF]', decoded):
            return decoded
        return text
    except:
        return text

# A character is part of mojibake if it's encodeable to windows-1252
# But we only care about segments that contain at least one non-ascii char that's in cp1252
# So let's match runs of characters that can be encoded in cp1252.
def encode_allowed(c):
    try:
        c.encode('windows-1252')
        return True
    except:
        return False

files = ['lib/presentation/screens/patient_search_doctor_screen.dart', 'lib/presentation/screens/doctor_settings_screen.dart']

for filepath in files:
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    new_content = ""
    current_chunk = ""
    for char in content:
        if encode_allowed(char):
            current_chunk += char
        else:
            if current_chunk:
                new_content += fix_mojibake(re.match(r'.*', current_chunk))
                current_chunk = ""
            new_content += char
    
    if current_chunk:
        new_content += fix_mojibake(re.match(r'.*', current_chunk))

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"Fixed {filepath}")
