# Replaces garbage with proper Arabic strings in doctor settings screen

with open('lib/presentation/screens/doctor_settings_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

replacements = {
    'Ø§Ù„ØªØ®ØµØµ': 'التخصص',
    'Ø£Ø®Ø±Ù‰ (Ø§ÙƒØªØ¨ ØªØ®ØµØµÙƒ)': 'أخرى (اكتب تخصصك)',
    'Ø£Ø®Ø±Ù‰': 'أخرى',
    'Ø¹Ø§Ù…': 'عام',
    'Ø£Ø³Ù†Ø§Ù†': 'أسنان',
    'Ù†Ø³Ø§Ø¡': 'نساء',
    'Ø¬Ù„Ø¯ÙŠØ©': 'جلدية',
    'Ø£Ø·ÙØ§Ù„': 'أطفال',
    'Ø¹ÙŠÙˆÙ†': 'عيون',
    'Ø¨Ø§Ø·Ù†Ø©': 'باطنة',
    'Ø¹Ø¸Ø§Ù…': 'عظام',
    'Ø£Ù†Ù ÙˆØ£Ø°Ù† ÙˆØÙ†Ø¬Ø±Ø©': 'أنف وأذن وحنجرة',
    'Ù…Ø® ÙˆØ£Ø¹ØµØ§Ø¨': 'مخ وأعصاب',
    'Ù…Ø³Ø§Ù„Ùƒ Ø¨ÙˆÙ„ÙŠØ©': 'مسالك بولية',
    'Ù‚Ù„Ø¨': 'قلب',
    'Ù†ÙØ³ÙŠØ©': 'نفسية',
    'Ø§Ù„Ø³Ø¨Øª': 'السبت',
    'Ø§Ù„Ø£ØØ¯': 'الأحد',
    'Ø§Ù„Ø§Ø«Ù†ÙŠÙ†': 'الاثنين',
    'Ø§Ù„Ø«Ù„Ø§Ø«Ø§Ø¡': 'الثلاثاء',
    'Ø§Ù„Ø£Ø±Ø¨Ø¹Ø§Ø¡': 'الأربعاء',
    'Ø§Ù„Ø®Ù…ÙŠØ³': 'الخميس',
    'Ø§Ù„Ø¬Ù…Ø¹Ø©': 'الجمعة'
}

for k, v in replacements.items():
    text = text.replace(k, v)

with open('lib/presentation/screens/doctor_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)
