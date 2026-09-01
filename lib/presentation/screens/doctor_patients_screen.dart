import '../widgets/role_guard.dart';
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

  Future<void> _fetchPatients() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final auth = Provider.of<FirebaseAuthService>(context, listen: false);

      final appointmentsSnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('doctorId', isEqualTo: auth.userId)
          .get();

      Map<String, List<QueryDocumentSnapshot>> patientAppointments = {};
      for (var doc in appointmentsSnapshot.docs) {
        final data = doc.data();
        final patientId = data['patientId'] as String?;
        if (patientId != null) {
          patientAppointments.putIfAbsent(patientId, () => []).add(doc);
        }
      }

      List<Map<String, dynamic>> loadedPatients = [];
      final now = DateTime.now();

      for (var entry in patientAppointments.entries) {
        String patientId = entry.key;
        List<QueryDocumentSnapshot> apps = entry.value;

        int totalVisits = apps.length;

        DateTime? lastVisit;
        DateTime? nextAppointment;
        String? nextTime;

        for (var appDoc in apps) {
          final appData = appDoc.data() as Map<String, dynamic>;
          final dateStr = appData['appointmentDate'] as String?;
          final timeStr =
              appData['startTime'] as String? ?? appData['time'] as String?;
          if (dateStr == null) continue;

          try {
            DateTime appDate = DateTime.parse(dateStr);
            if (appDate.isBefore(now)) {
              if (lastVisit == null || appDate.isAfter(lastVisit)) {
                lastVisit = appDate;
              }
            } else if (appDate.isAfter(now) || appDate.isAtSameMomentAs(now)) {
              if (nextAppointment == null ||
                  appDate.isBefore(nextAppointment)) {
                nextAppointment = appDate;
                nextTime = timeStr;
              }
            }
          } catch (e) {}
        }

        lastVisit ??= DateTime.now();

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(patientId)
            .get();
        final userData = userDoc.data() ?? {};

        String fallbackName = 'مريض غير معروف';
        try {
          fallbackName =
              (apps.first.data() as Map<String, dynamic>)['patientName'] ??
                  fallbackName;
        } catch (e) {}

        final patientName =
            userData['name'] ?? userData['userName'] ?? fallbackName;

        loadedPatients.add({
          'id': patientId,
          'name': patientName,
          'nameEn': userData['nameEn'] ?? 'Unknown Patient',
          'phone': userData['phone'] ?? 'غير متوفر / N/A',
          'email': userData['email'] ?? 'غير متوفر / N/A',
          'age': userData['age'] ?? 30, // Default if missing
          'lastVisit': lastVisit,
          'totalVisits': totalVisits,
          'nextAppointment': nextAppointment,
          'nextTime': nextTime,
          'notes': 'لا توجد ملاحظات / No notes',
          'status': nextAppointment != null ? 'active' : 'inactive',
        });
      }

      if (mounted) {
        setState(() {
          _allPatients = loadedPatients;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.info('Error fetching patients: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredAndSortedPatients() {
    var filtered = _allPatients.where((patient) {
      final matchesSearch = patient['name']
              .toLowerCase()
              .contains(_searchController.text.toLowerCase()) ||
          patient['phone'].contains(_searchController.text) ||
          patient['email']
              .toLowerCase()
              .contains(_searchController.text.toLowerCase());
      return matchesSearch;
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
    // الحارس يجعل الشاشة متّسقة مع صلاحية الخادم: من ليس طبيباً له عيادة
    // (نشط أو موقوف) يرى رسالة مفهومة بدل استعلامات تُرفض بلا تفسير.
    return RoleGuard(
      requireDoctorClinicAccess: true,
      child: Builder(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('المرضى / Patients'),
          centerTitle: true,
          backgroundColor: Theme.of(context).colorScheme.primary,
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
        backgroundColor: Theme.of(context).colorScheme.primary,
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
              if (filteredPatients.isEmpty)
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
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'إجمالي',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  Text(
                    'Total',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
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
                          color: Theme.of(context).colorScheme.tertiary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'نشطين',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  Text(
                    'Active',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
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
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilterChip(
                label: Text(sorts[index].$1),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() => _selectedSortIndex = index);
                },
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                selectedColor: Theme.of(context).colorScheme.primary,
                labelStyle: TextStyle(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          },
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
            Icon(Icons.person_off,
                size: 80, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 24),
            Text(
              'لا يوجد مرضى',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'No patients found',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
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
              ? Theme.of(context).colorScheme.tertiary
              : Theme.of(context).colorScheme.onSurfaceVariant,
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
                        ? Theme.of(context).colorScheme.tertiary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    border: Border.all(
                      color: isActive
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isActive ? '✨ نشط' : '⏳ غير نشط',
                    style: TextStyle(
                      color: isActive
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                // Name and Age
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            ' سنة',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                          Text(
                            patient['age'].toString(),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontWeight: FontWeight.bold,
                                    ),
                          ),
                          Text(
                            ' • ',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                          Text(
                            patient['name'],
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Text(
                        patient['nameEn'],
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
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

            _patientDetailRow(
              context,
              icon: Icons.email,
              label: 'البريد الإلكتروني / Email',
              value: patient['email'],
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      Text(
                        patient['totalVisits'].toString(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      Text(
                        DateFormat('d MMMM', 'ar').format(patient['lastVisit']),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.secondary,
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
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.onTertiaryContainer),
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onTertiaryContainer,
                                    ),
                          ),
                          Text(
                            '${DateFormat('d MMMM', 'ar').format(patient['nextAppointment'])} • ${patient['nextTime']}',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onTertiaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.event_available,
                        color:
                            Theme.of(context).colorScheme.onTertiaryContainer,
                        size: 24),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'لا يوجد موعد قادم / No upcoming appointment',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  backgroundColor: Theme.of(context).colorScheme.primary,
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 18),
      ],
    );
  }

  void _viewPatientDetails(Map<String, dynamic> patient) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '👤 ${patient['name']} - عرض التفاصيل / Viewing details',
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
