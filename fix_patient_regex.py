import re

with open('lib/presentation/screens/patient_search_doctor_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Replace the entire specialties list definition
pattern_list = r'final List<String> _specialties = \[[^\]]+\];'
replacement_list = """final List<String> _specialties = [
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
  ];"""

text = re.sub(pattern_list, replacement_list, text)

# Inject dynamic specialties logic
pattern_fetch = r'(\s*)if \(mounted\) \{\n(\s*)setState\(\(\) \{\n(\s*)_allDoctors = doctors;'
replacement_fetch = r"""\1if (mounted) {
\2setState(() {
\3_allDoctors = doctors;

\3// Extract standard and custom specialties
\3final standardSpecs = [
\3  'الكل', 'عام', 'أسنان', 'نساء', 'جلدية', 'أطفال', 'عيون',
\3  'باطنة', 'عظام', 'أنف وأذن وحنجرة', 'مخ وأعصاب', 'مسالك بولية',
\3  'قلب', 'نفسية'
\3];
\3
\3Set<String> dynamicSpecs = {};
\3for (var doctor in doctors) {
\3  final spec = doctor['specialization'] as String?;
\3  if (spec != null && spec.trim().isNotEmpty && !spec.contains('أخرى (اكتب تخصصك)') && spec != 'أخرى') {
\3    dynamicSpecs.add(spec);
\3  }
\3}
\3
\3final missingSpecs = dynamicSpecs.where((s) => !standardSpecs.contains(s)).toList();
\3_specialties.clear();
\3_specialties.addAll(standardSpecs);
\3_specialties.addAll(missingSpecs);"""

text = re.sub(pattern_fetch, replacement_fetch, text)

with open('lib/presentation/screens/patient_search_doctor_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)
