import os
import re

files_map = {
    'lib/presentation/screens/patient_my_appointments_screen.dart': r"c:\Users\MR.H\AppData\Roaming\Code\User\workspaceStorage\9b3a55bc274af25266d10e9445e229a5\GitHub.copilot-chat\chat-session-resources\395f67ee-7008-4ede-bf0a-1e6bb71bb073\call_MHxORGpQbHFmRk5pcnR6cUY0Uzc__vscode-1775734138151\content.txt",
    'lib/presentation/screens/patient_search_doctor_screen.dart': r"c:\Users\MR.H\AppData\Roaming\Code\User\workspaceStorage\9b3a55bc274af25266d10e9445e229a5\GitHub.copilot-chat\chat-session-resources\395f67ee-7008-4ede-bf0a-1e6bb71bb073\call_MHxDbUZINDJBSTNlRGVXelpETW0__vscode-1775734138164\content.txt",
    'lib/presentation/screens/patient_booking_screen.dart': r"c:\Users\MR.H\AppData\Roaming\Code\User\workspaceStorage\9b3a55bc274af25266d10e9445e229a5\GitHub.copilot-chat\chat-session-resources\395f67ee-7008-4ede-bf0a-1e6bb71bb073\call_MHxmd1JSOHNsaWlTdnpVNXRJcXg__vscode-1775734138170\content.txt",
    'lib/presentation/screens/doctor_settings_screen.dart': r"c:\Users\MR.H\AppData\Roaming\Code\User\workspaceStorage\9b3a55bc274af25266d10e9445e229a5\GitHub.copilot-chat\chat-session-resources\395f67ee-7008-4ede-bf0a-1e6bb71bb073\call_MHxObFRPWXNhOTdQcG1TWFVEekg__vscode-1775734138182\content.txt"
}

for dest, src in files_map.items():
    if os.path.exists(src):
        with open(src, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Clean markdown wrappers if any
        content = re.sub(r'^`dart\s*', '', content, flags=re.MULTILINE)
        content = re.sub(r'^`\s*$', '', content, flags=re.MULTILINE)

        if "import '" in content:
            idx = content.find("import '")
            content = content[idx:]

        with open(dest, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Copied {src} to {dest}")
    else:
        print(f"File {src} not found")

