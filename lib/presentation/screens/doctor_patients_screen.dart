import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_logger.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/app_widgets.dart';

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
          } catch (e) {
            continue;
          }
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
        } catch (e) {
          // الاسم غير موجود في الموعد أيضاً — يبقى الافتراضي.
        }

        final patientName =
            userData['name'] ?? userData['userName'] ?? fallbackName;

        loadedPatients.add({
          'id': patientId,
          'name': patientName,
          'phone': userData['phone'] ?? '',
          'email': userData['email'] ?? '',
          'age': userData['age'],
          'lastVisit': lastVisit,
          'totalVisits': totalVisits,
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
    } catch (e) {
      AppLogger.info('Error fetching patients: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnack.error(context, 'تعذّر تحميل قائمة المرضى');
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredAndSortedPatients() {
    final query = _searchController.text.toLowerCase();

    var filtered = _allPatients.where((patient) {
      return patient['name'].toString().toLowerCase().contains(query) ||
          patient['phone'].toString().contains(_searchController.text) ||
          patient['email'].toString().toLowerCase().contains(query);
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
    final patients = _getFilteredAndSortedPatients();
    final activeCount =
        _allPatients.where((p) => p['status'] == 'active').length;

    return AppScaffold(
      title: 'المرضى',
      subtitle: _isLoading
          ? null
          : '${_allPatients.length} مريض • $activeCount لديهم موعد قادم',
      onRefresh: _fetchPatients,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      headerBottom: AppSearchField(
        controller: _searchController,
        hint: 'اسم المريض أو رقم الهاتف',
        onChanged: (_) => setState(() {}),
      ),
      child: _isLoading
          ? const AppLoader(message: 'جارٍ تحميل المرضى…')
          : _allPatients.isEmpty
              ? const EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'لا يوجد مرضى بعد',
                  message:
                      'بمجرد حجز أول مريض عندك، سيظهر هنا مع سجلّ زياراته.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppSegmented(
                      labels: const ['الأحدث', 'الاسم', 'الزيارات'],
                      selectedIndex: _selectedSortIndex,
                      onChanged: (i) => setState(() => _selectedSortIndex = i),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (patients.isEmpty)
                      const EmptyState(
                        icon: Icons.person_search_rounded,
                        title: 'لا نتائج مطابقة',
                        message: 'جرّب اسماً أو رقماً آخر.',
                      )
                    else
                      for (final patient in patients) ...[
                        _PatientCard(
                          patient: patient,
                          onCall: () => _call(patient['phone'].toString()),
                          onDetails: () => _showPatientSheet(patient),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                  ],
                ),
    );
  }

  Future<void> _call(String phone) async {
    if (phone.trim().isEmpty) {
      AppSnack.info(context, 'لا يوجد رقم هاتف مسجّل لهذا المريض');
      return;
    }
    final uri = Uri.parse('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) AppSnack.error(context, 'تعذّر فتح تطبيق الاتصال');
    }
  }

  /// تفاصيل المريض في لوح سفلي.
  ///
  /// كان زر «عرض التفاصيل» يعرض رسالة مؤقتة فقط ولا يفتح شيئاً — أي زر يعد
  /// بشيء ولا يفعله أسوأ من غيابه.
  void _showPatientSheet(Map<String, dynamic> patient) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PatientDetailsSheet(
        patient: patient,
        onCall: () => _call(patient['phone'].toString()),
      ),
    );
  }
}

// =============================================================================
// بطاقة المريض
// =============================================================================

class _PatientCard extends StatelessWidget {
  const _PatientCard({
    required this.patient,
    required this.onCall,
    required this.onDetails,
  });

  final Map<String, dynamic> patient;
  final VoidCallback onCall;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isActive = patient['status'] == 'active';
    final next = patient['nextAppointment'] as DateTime?;
    final age = patient['age'];

    return AppCard(
      onTap: onDetails,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                name: patient['name']?.toString(),
                color: isActive ? tokens.success : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient['name'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall,
                    ),
                    Text(
                      [
                        if (age != null) '$age سنة',
                        '${patient['totalVisits']} زيارة',
                      ].join(' • '),
                      style: context.texts.bodySmall
                          ?.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: isActive ? 'موعد قادم' : 'غير نشط',
                color: isActive ? tokens.success : tokens.textMuted,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: next != null ? tokens.successSoft : tokens.surfaceSunken,
              borderRadius: AppRadius.rMd,
            ),
            child: Row(
              children: [
                Icon(
                  next != null
                      ? Icons.event_available_rounded
                      : Icons.history_rounded,
                  size: 18,
                  color: next != null ? tokens.success : tokens.textMuted,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    next != null
                        ? 'الموعد التالي: '
                            '${DateFormat('d MMMM', 'ar').format(next)}'
                            '${patient['nextTime'] == null ? '' : ' — ${patient['nextTime']}'}'
                        : 'آخر زيارة: '
                            '${DateFormat('d MMMM yyyy', 'ar').format(patient['lastVisit'] as DateTime)}',
                    style: context.texts.bodySmall?.copyWith(
                      color:
                          next != null ? tokens.onSuccessSoft : tokens.textBody,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCall,
                  icon: const Icon(Icons.phone_rounded, size: 18),
                  label: const Text('اتصال'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onDetails,
                  icon: const Icon(Icons.article_outlined, size: 18),
                  label: const Text('التفاصيل'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PatientDetailsSheet extends StatelessWidget {
  const _PatientDetailsSheet({required this.patient, required this.onCall});

  final Map<String, dynamic> patient;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final next = patient['nextAppointment'] as DateTime?;
    final phone = patient['phone'].toString();
    final email = patient['email'].toString();
    final age = patient['age'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: AppAvatar(name: patient['name']?.toString(), size: 68)),
          const SizedBox(height: AppSpacing.lg),
          Text(
            patient['name'].toString(),
            textAlign: TextAlign.center,
            style: context.texts.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: Column(
              children: [
                InfoRow(
                  label: 'رقم الهاتف',
                  value: phone.isEmpty ? 'غير متوفر' : phone,
                  icon: Icons.phone_rounded,
                  valueColor: phone.isEmpty ? tokens.textFaint : null,
                ),
                InfoRow(
                  label: 'البريد الإلكتروني',
                  value: email.isEmpty ? 'غير متوفر' : email,
                  icon: Icons.mail_outline_rounded,
                  valueColor: email.isEmpty ? tokens.textFaint : null,
                ),
                InfoRow(
                  label: 'السن',
                  value: age == null ? 'غير مسجّل' : '$age سنة',
                  icon: Icons.cake_outlined,
                  valueColor: age == null ? tokens.textFaint : null,
                ),
                InfoRow(
                  label: 'عدد الزيارات',
                  value: '${patient['totalVisits']}',
                  icon: Icons.repeat_rounded,
                ),
                InfoRow(
                  label: 'آخر زيارة',
                  value: DateFormat('d MMMM yyyy', 'ar')
                      .format(patient['lastVisit'] as DateTime),
                  icon: Icons.history_rounded,
                ),
                InfoRow(
                  label: 'الموعد التالي',
                  value: next == null
                      ? 'لا يوجد'
                      : DateFormat('EEEE، d MMMM', 'ar').format(next),
                  icon: Icons.event_available_rounded,
                  valueColor: next == null ? tokens.textFaint : tokens.success,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onCall();
            },
            icon: const Icon(Icons.phone_rounded),
            label: const Text('اتصال بالمريض'),
          ),
        ],
      ),
    );
  }
}
