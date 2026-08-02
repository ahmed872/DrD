import re

file_path = 'lib/presentation/screens/patient_search_doctor_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace mock data with dynamic fetch
mock_pattern = r"final List<Map<String, dynamic>> _allDoctors = \[(.*?)\];"
replacement = '''List<Map<String, dynamic>> _allDoctors = [];
  bool _isLoadingDoctors = true;

  @override
  void initState() {
    super.initState();
    _fetchRealDoctors();
  }

  Future<void> _fetchRealDoctors() async {
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
          'name': data['clinicNameAr'] ?? data['name'] ?? 'طبيب غير معروف',
          'nameEn': data['clinicNameEn'] ?? data['nameEn'] ?? 'Unknown Doctor',
          'specialty': data['specialization'] ?? 'عام',
          'specialtyEn': data['specializationEn'] ?? 'General',
          'rating': 4.8,
          'reviews': 0,
          'price': data['price'] ?? 200,
          'bio': data['bio'] ?? 'طبيب متخصص',
          'bioEn': data['bioEn'] ?? 'Specialized Doctor',
          'available': true,
          'nextSlot': 'متاح الآن',
          'patients': 0,
          'icon': '👨‍⚕️',
          'clinicLocation': data['clinicLocation'] ?? '',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _allDoctors = doctors;
          _isLoadingDoctors = false;
        });
      }
    } catch (e) {
      print('Error fetching doctors: \');
      if (mounted) {
        setState(() => _isLoadingDoctors = false);
      }
    }
  }
'''
import re
content = re.sub(mock_pattern, replacement, content, flags=re.DOTALL)

# Add imports if missing
if "import 'package:cloud_firestore/cloud_firestore.dart';" not in content:
    content = "import 'package:cloud_firestore/cloud_firestore.dart';\n" + content

# Fix _buildResults to show loading
build_res = "Widget _buildResults() {\n    List<Map<String, dynamic>> filteredDoctors = _allDoctors;"
new_build_res = '''Widget _buildResults() {
    if (_isLoadingDoctors) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'جاري تحميل الأطباء...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }
    List<Map<String, dynamic>> filteredDoctors = _allDoctors;'''
content = content.replace(build_res, new_build_res)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
