with open('lib/presentation/screens/patient_search_doctor_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Fix encoding
replacements = {
    'Ø§Ù„ÙƒÙ„': 'الكل', 'Ø¹Ø§Ù…': 'عام', 'Ø£Ø³Ù†Ø§Ù†': 'أسنان', 'Ù†Ø³Ø§Ø¡': 'نساء',
    'Ø¬Ù„Ø¯ÙŠØ©': 'جلدية', 'Ø£Ø·ÙØ§Ù„': 'أطفال', 'Ø¹ÙŠÙˆÙ†': 'عيون', 'Ø¨Ø§Ø·Ù†Ø©': 'باطنة',
    'Ø¹Ø¸Ø§Ù…': 'عظام', 'Ø£Ù†Ù ÙˆØ£Ø°Ù† ÙˆØÙ†Ø¬Ø±Ø©': 'أنف وأذن وحنجرة',
    'Ù…Ø® ÙˆØ£Ø¹ØµØ§Ø¨': 'مخ وأعصاب', 'Ù…Ø³Ø§Ù„Ùƒ Ø¨ÙˆÙ„ÙŠØ©': 'مسالك بولية',
    'Ù‚Ù„Ø¨': 'قلب', 'Ù†ÙØ³ÙŠØ©': 'نفسية', 'Ø§Ù„Ø¨ØØ« Ø¹Ù† Ø·Ø¨ÙŠØ¨': 'البحث عن طبيب',
    'Ø·Ø¨ÙŠØ¨ ØºÙŠØ± Ù…Ø¹Ø±ÙˆÙ': 'طبيب غير معروف', 'Ø¹ÙŠØ§Ø¯Ø©': 'عيادة',
    'Ø§Ù„Ù‚Ø§Ù‡Ø±Ø©': 'القاهرة', 'Ù…Ù† 9:00 Ø¥Ù„Ù‰ 5:00': 'من 9:00 إلى 5:00',
    'Ø·Ø¨ÙŠØ¨ Ù…ØªØ®ØµØµ': 'طبيب متخصص', 'Ù…ØªØ§Ø Ø§Ù„Ø¢Ù†': 'متاح الآن',
    'ØØ¯Ø« Ø®Ø·Ø£ ÙÙŠ ØªØÙ…ÙŠÙ„ Ø§Ù„Ø£Ø·Ø¨Ø§Ø¡': 'حدث خطأ في تحميل الأطباء',
    'Ø§Ø¨ØØ« Ø¹Ù† Ø§Ø³Ù… Ø§Ù„Ø·Ø¨ÙŠØ¨ Ø£Ùˆ Ø§Ù„ØªØ®ØµØµ...': 'ابحث عن اسم الطبيب أو التخصص...',
    'Ø§Ù„ØªØ®ØµØµ': 'التخصص', 'Ø§Ù„ÙÙ„Ø§ØªØ± Ø§Ù„Ù…ØªÙ‚Ø¯Ù…Ø©': 'الفلاتر المتقدمة',
    'Ø§Ù„ØØ¯ Ø§Ù„Ø£Ø¯Ù†Ù‰ Ù„Ù„ØªÙ‚ÙŠÙŠÙ…': 'الحد الأدنى للتقييم', 'âÙ‚Ø·': 'فقط',
    'Ø¬Ø§Ø±ÙŠ ØªØÙ…ÙŠÙ„ Ø§Ù„Ø£Ø·Ø¨Ø§Ø¡...': 'جاري تحميل الأطباء...'
}
for k, v in replacements.items():
    text = text.replace(k, v)


old_fetch = """      if (mounted) {
        setState(() {
          _allDoctors = doctors;
          _isLoadingDoctors = false;
        });
      }"""

new_fetch = """      if (mounted) {
        setState(() {
          _allDoctors = doctors;
          
          // dynamic specialties
          final standardSpecs = [
            'الكل',
            'عام',
            'أسنان',
            'نساء',
            'جلدية',
            'أطفال',
            'عيون',
            'باطنة',
            'عظام',
            'أنف وأذن وحنجرة',
            'مخ وأعصاب',
            'مسالك بولية',
            'قلب',
            'نفسية',
          ];
          
          Set<String> dynamicSpecs = {};
          for (var doctor in doctors) {
            final spec = doctor['specialization'] as String?;
            if (spec != null && spec.trim().isNotEmpty && spec != 'أخرى (اكتب تخصصك)' && spec != 'أخرى') {
              dynamicSpecs.add(spec);
            }
          }
          
          final missingSpecs = dynamicSpecs.where((s) => !standardSpecs.contains(s)).toList();
          _specialties.clear();
          _specialties.addAll(standardSpecs);
          _specialties.addAll(missingSpecs);

          _isLoadingDoctors = false;
        });
      }"""

text = text.replace(old_fetch, new_fetch)

# make specialties array not final
text = text.replace("final List<String> _specialties = [", "List<String> _specialties = [")

with open('lib/presentation/screens/patient_search_doctor_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)
