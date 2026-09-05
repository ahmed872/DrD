import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/firebase_auth_service.dart';
import '../../core/utils/app_logger.dart';

class DoctorPatientsScreen extends StatefulWidget {
  const DoctorPatientsScreen({super.key});

  @override
  State<DoctorPatientsScreen> createState() => _DoctorPatientsScreenState();
}

class _DoctorPatientsScreenState extends State<DoctorPatientsScreen> {
  late TextEditingController _searchController;
  int _selectedSortIndex = 0; // 0: Recent, 1: Name, 2: Visits

  List<Map<String, dynamic>> _allPatients = [];
  bool _isLoading = true;

  /// يفرّق بين "لا يوجد مرضى" و"تعذّر التحميل".
  ///
  /// الشاشة كانت تعرض الحالتين بنفس الشكل، فبدا خطأ الصلاحيات وكأنه عيادة
  /// بلا مرضى.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _fetchPatients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// بناء قائمة مرضى الطبيب من مستندات المواعيد وحدها.
  ///
  /// ## لماذا لا تُقرأ `users` هنا؟
  ///
  /// كانت هذه الدالة تقرأ `users/{patientId}` لكل مريض. قواعد Firestore تسمح
  /// بقراءة مستند مستخدم لصاحبه فقط، أو لأي مستخدم مسجَّل إن كان **طبيباً**؛
  /// مستند المريض ليس واحداً منهما، فالقراءة تُرفض بـ `permission-denied`.
  ///
  /// وبما أن القراءة كانت داخل الحلقة داخل `try` الخارجي، فإن أول مريض كان
  /// يرمي استثناءً فتُهجر القائمة كلها ويُعرض للطبيب "لا يوجد مرضى" بلا أي
  /// رسالة خطأ. الشاشة كانت فارغة دائماً في الإنتاج.
  ///
  /// الحل ليس توسيع صلاحية القراءة على `users` — ذلك يفتح بيانات كل المرضى
  /// لكل طبيب. الاسم ورقم الهاتف منسوخان أصلاً في مستند الموعد وقت الحجز
  /// (`patientName` و`patientPhone`)، والطبيب يقرأ مواعيده بصلاحية كاملة.
  ///
  /// النتيجة: لا استعلام مرفوض، ولا صلاحية جديدة، ونفس المعلومات.
  ///
  /// ما فُقد بهذا التغيير: البريد الإلكتروني (غير منسوخ في الموعد) و`nameEn`
  /// و`age` — وآخرها لم يكن حقيقياً أصلاً: التطبيق لا يكتب `age` في أي مكان،
  /// فكانت الشاشة تعرض "٣٠ سنة" لكل مريض على وجه الأرض.
  Future<void> _fetchPatients() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final auth = Provider.of<FirebaseAuthService>(context, listen: false);

      final appointmentsSnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('doctorId', isEqualTo: auth.userId)
          .get();

      final patientAppointments = <String, List<Map<String, dynamic>>>{};
      for (final doc in appointmentsSnapshot.docs) {
        final data = doc.data();
        final patientId = data['patientId'] as String?;
        if (patientId != null) {
          patientAppointments.putIfAbsent(patientId, () => []).add(data);
        }
      }

      final loadedPatients = <Map<String, dynamic>>[];
      final now = DateTime.now();

      for (final entry in patientAppointments.entries) {
        final patientId = entry.key;
        final apps = entry.value;

        DateTime? lastVisit;
        DateTime? nextAppointment;
        String? nextTime;

        // الاسم والهاتف يُؤخذان من أحدث موعد، لأن المريض قد يكون غيّر اسمه
        // بين زيارتين والنسخة الأحدث هي الأقرب للصحيح.
        DateTime? newestDate;
        String? patientName;
        String? patientPhone;

        for (final appData in apps) {
          final dateStr = appData['appointmentDate'] as String?;
          final timeStr = (appData['startTime'] ?? appData['time']) as String?;
          if (dateStr == null) continue;

          final appDate = DateTime.tryParse(dateStr);
          if (appDate == null) continue;

          if (newestDate == null || appDate.isAfter(newestDate)) {
            newestDate = appDate;
            patientName = appData['patientName'] as String?;
            patientPhone = appData['patientPhone'] as String?;
          }

          if (appDate.isBefore(now)) {
            if (lastVisit == null || appDate.isAfter(lastVisit)) {
              lastVisit = appDate;
            }
          } else {
            if (nextAppointment == null || appDate.isBefore(nextAppointment)) {
              nextAppointment = appDate;
              nextTime = timeStr;
            }
          }
        }

        lastVisit ??= now;

        loadedPatients.add({
          'id': patientId,
          'name': (patientName == null || patientName.isEmpty)
              ? 'مريض غير معروف'
              : patientName,
          'phone': (patientPhone == null || patientPhone.isEmpty)
              ? 'غير متوفر'
              : patientPhone,
          'lastVisit': lastVisit,
          'totalVisits': apps.length,
          'nextAppointment': nextAppointment,
          'nextTime': nextTime,
          'status': nextAppointment != null ? 'active' : 'inactive',
        });
      }

      if (mounted) {
        setState(() {
          _allPatients = loadedPatients;
          _isLoading = false;
        });
      }
    } catch (e, s) {
      // الفشل هنا لم يعد صامتاً: الشاشة الفارغة كانت تخفي خطأ صلاحيات لشهور.
      AppLogger.error('تعذّر تحميل قائمة المرضى', e, s);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredAndSortedPatients() {
    final term = _searchController.text.trim().toLowerCase();
    var filtered = _allPatients.where((patient) {
      if (term.isEmpty) return true;
      // البريد الإلكتروني لم يعد ضمن البيانات المتاحة للطبيب — البحث بالاسم
      // أو الهاتف، وهما المنسوخان في مستند الموعد.
      return (patient['name'] as String).toLowerCase().contains(term) ||
          (patient['phone'] as String).contains(term);
    }).toList();

    // Sort
    switch (_selectedSortIndex) {
      case 0: // Recent
        filtered.sort((a, b) => b['lastVisit'].compareTo(a['lastVisit']));
        break;
      case 1: // Name
        filtered.sort((a, b) => a['name'].compareTo(b['name']));
        break;
      case 2: // Visits
        filtered.sort((a, b) => b['totalVisits'].compareTo(a['totalVisits']));
        break;
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('المرضى / Patients'),
          centerTitle: true,
          backgroundColor: const Color(0xFF0097A7),
          elevation: 1,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final filteredPatients = _getFilteredAndSortedPatients();
    final activePatients =
        _allPatients.where((p) => p['status'] == 'active').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المرضى / Patients'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0097A7),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Statistics
              _buildStatsSection(activePatients),
              const SizedBox(height: 24),

              // Search Bar
              _buildSearchBar(),
              const SizedBox(height: 12),

              // Sort Options
              _buildSortOptions(),
              const SizedBox(height: 24),

              // Patients List
              if (_loadFailed)
                _buildErrorState()
              else if (filteredPatients.isEmpty)
                _buildEmptyState()
              else
                _buildPatientsList(filteredPatients),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsSection(int activeCount) {
    return Row(
      children: [
        Expanded(
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('👥', style: TextStyle(fontSize: 28)),
                  const SizedBox(height: 8),
                  Text(
                    _allPatients.length.toString(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'إجمالي',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  Text(
                    'Total',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[400],
                          fontSize: 10,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('✨', style: TextStyle(fontSize: 28)),
                  const SizedBox(height: 8),
                  Text(
                    activeCount.toString(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'نشطين',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  Text(
                    'Active',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[400],
                          fontSize: 10,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'اسم المريض أو الهاتف / Patient name or phone',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildSortOptions() {
    final sorts = [
      ('الأخيرة / Recent', 0),
      ('الاسم / Name', 1),
      ('الزيارات / Visits', 2),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: List.generate(
          sorts.length,
          (index) {
            final isSelected = _selectedSortIndex == index;
            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: FilterChip(
                label: Text(sorts[index].$1),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() => _selectedSortIndex = index);
                },
                backgroundColor: Colors.grey[100],
                selectedColor: Colors.blue,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// حالة الفشل، منفصلة عن حالة "لا يوجد مرضى".
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(Icons.cloud_off, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              'تعذّر تحميل قائمة المرضى',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'تأكد من اتصالك بالإنترنت ثم أعد المحاولة',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _loadFailed = false);
                _fetchPatients();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          children: [
            Icon(Icons.person_off, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            Text(
              'لا يوجد مرضى',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'No patients found',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[400],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientsList(List<Map<String, dynamic>> patients) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: patients.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final patient = patients[index];
        return _buildPatientCard(patient);
      },
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> patient) {
    final isActive = patient['status'] == 'active';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive
              ? Colors.green.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Header: Name and Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Status Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.green.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    border: Border.all(
                      color: isActive ? Colors.green : Colors.grey,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isActive ? '✨ نشط' : '⏳ غير نشط',
                    style: TextStyle(
                      color: isActive ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                // اسم المريض.
                //
                // كان هنا أيضاً "٣٠ سنة" لكل مريض — التطبيق لا يكتب حقل `age`
                // إطلاقاً، فكانت القيمة الافتراضية تُعرض كعمر حقيقي. عرض سنّ
                // مختلَق في شاشة طبية أسوأ من عدم عرض السنّ.
                Expanded(
                  child: Text(
                    patient['name'] as String,
                    textAlign: TextAlign.end,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),

            // Contact Info
            _patientDetailRow(
              context,
              icon: Icons.phone,
              label: 'الهاتف / Phone',
              value: patient['phone'],
            ),
            const SizedBox(height: 10),

            // Statistics
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'عدد الزيارات / Total Visits',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      Text(
                        patient['totalVisits'].toString(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'آخر زيارة / Last Visit',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      Text(
                        DateFormat('d MMMM', 'ar').format(patient['lastVisit']),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Next Appointment
            if (patient['nextAppointment'] != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.05),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'الموعد التالي / Next Appointment',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.green.shade700,
                                    ),
                          ),
                          Text(
                            '${DateFormat('d MMMM', 'ar').format(patient['nextAppointment'])} • ${patient['nextTime']}',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.event_available,
                        color: Colors.green, size: 24),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.05),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'لا يوجد موعد قادم / No upcoming appointment',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[500],
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                onPressed: () => _viewPatientDetails(patient),
                icon: const Icon(Icons.visibility),
                label: const Text('عرض التفاصيل / View Details'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _patientDetailRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, color: Colors.blue, size: 18),
      ],
    );
  }

  void _viewPatientDetails(Map<String, dynamic> patient) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '👤 ${patient['name']} - عرض التفاصيل / Viewing details',
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
