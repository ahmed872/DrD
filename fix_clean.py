import re

file_path = r"c:\Users\MR.H\AppData\Roaming\Code\User\workspaceStorage\9b3a55bc274af25266d10e9445e229a5\GitHub.copilot-chat\chat-session-resources\395f67ee-7008-4ede-bf0a-1e6bb71bb073\call_MHxVOWZ0MWJRQ3AzZEVDSmRhSWo__vscode-1775734138125\content.txt"
out_path = 'lib/presentation/screens/doctor_settings_screen.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = re.sub(r'^`dart\s*', '', content, flags=re.MULTILINE)
content = re.sub(r'^`\s*$', '', content, flags=re.MULTILINE)

if "import '" in content:
    idx = content.find("import '")
    content = content[idx:]

with open(out_path, 'w', encoding='utf-8') as f:
    f.write(content)
