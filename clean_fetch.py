import re

with open('lib/presentation/screens/patient_search_doctor_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# We have duplicated blocks defining `standardSpecs`, `dynamicSpecs`, etc.
# Check where `_fetchRealDoctors` starts and ends.
pattern = r'Future<void> _fetchRealDoctors\(\) async \{.*?\s*\}\s*catch \(e\) \{'
correct_method = """Future<void> _fetchRealDoctors() async {
    setState(() => _isLoadingDoctors = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'doctor')
          .get();

      final doctors = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'طبيب غير معروف',
          'nameEn': data['nameEn'] ?? 'Unknown Doctor',
          'clinicNameAr': data['clinicNameAr'] ?? data['name'] ?? 'عيادة',
          'clinicNameEn': data['clinicNameEn'] ?? 'Clinic',
          'specialization': data['specialization'] ?? 'عام',
          'specializationEn': data['specializationEn'] ?? 'General',
          'price': (data['price'] ?? 200).toDouble(),
          'clinicLocation': data['clinicLocation'] ?? 'القاهرة',
          'workingDays': data['workingDays'] ?? [],
          'workingHours': data['workingHours'] ?? 'من 9:00 إلى 5:00',
          'sessionDuration': data['sessionDuration'] ?? 30,
          'bio': data['bio'] ?? 'طبيب متخصص',
          'bioEn': data['bioEn'] ?? 'Specialized Doctor',
          'rating': (data['rating'] ?? 0.0).toDouble(),
          'reviews': data['reviews'] ?? 0,
          'available': true,
          'nextSlot': 'متاح الآن',
          'patients': 0,
          'icon': '👨‍⚕️',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _allDoctors = doctors;

          // Extract standard and custom specialties
          final standardSpecs = [
            'الكل', 'عام', 'أسنان', 'نساء', 'جلدية', 'أطفال', 'عيون',
            'باطنة', 'عظام', 'أنف وأذن وحنجرة', 'مخ وأعصاب', 'مسالك بولية',
            'قلب', 'نفسية'
          ];
          
          Set<String> dynamicSpecs = {};
          for (var doctor in doctors) {
            final spec = doctor['specialization'] as String?;
            if (spec != null && spec.trim().isNotEmpty && !spec.contains('أخرى') && spec != 'أخرى') {
              dynamicSpecs.add(spec);
            }
          }
          
          final missingSpecs = dynamicSpecs.where((s) => !standardSpecs.contains(s)).toList();
          _specialties.clear();
          _specialties.addAll(standardSpecs);
          _specialties.addAll(missingSpecs);
          
          _isLoadingDoctors = false;
        });
      }
    } catch (e) {"""

text = re.sub(pattern, correct_method, text, flags=re.DOTALL)

with open('lib/presentation/screens/patient_search_doctor_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)
