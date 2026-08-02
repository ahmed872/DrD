import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firebase_auth_service.dart';
import 'doctor_settings_screen.dart';
import 'doctor_schedule_screen.dart';
import 'doctor_patients_screen.dart';
import 'doctor_analytics_screen.dart';
import 'patient_booking_screen.dart';
import 'patient_my_appointments_screen.dart';
import 'patient_medical_history_screen.dart';
import 'patient_search_doctor_screen.dart';
import 'notifications_screen.dart';
import 'patient_settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FirebaseAuthService>(
      builder: (context, auth, _) {
        final isDoctor = auth.userRole == 'doctor';

        return Scaffold(
          appBar: AppBar(
            title: const Text('الرئيسية'),
            centerTitle: true,
            elevation: 1,
            backgroundColor: const Color(0xFF0097A7),
            actions: [
              // جرس الإشعارات — هو ما يجعل تذكيرات المواعيد مرئية للمستخدم.
              const NotificationsBell(),
              // رابط الإعدادات للمرضى
              if (auth.userRole == 'patient')
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PatientSettingsScreen(),
                      ),
                    );
                  },
                  tooltip: 'الإعدادات',
                ),
              // تسجيل الخروج
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('تسجيل الخروج'),
                      content:
                          const Text('هل أنت متأكد من رغبتك في تسجيل الخروج؟'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('إلغاء'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('تسجيل الخروج',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );

                  if (shouldLogout == true) {
                    auth.logout();
                  }
                },
                tooltip: 'تسجيل الخروج',
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // الترحيب
                  Text(
                    'مرحباً',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[500],
                          fontSize: 13,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    auth.userName ?? 'المستخدم',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0097A7),
                          fontSize: 24,
                        ),
                  ),
                  const SizedBox(height: 36),

                  // بطاقة المعلومات
                  _buildInfoCard(context, auth),
                  const SizedBox(height: 36),

                  // الخدمات
                  Text(
                    isDoctor ? 'لوحة الطبيب' : 'الخدمات المتاحة',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.grey[800],
                        ),
                  ),
                  const SizedBox(height: 16),

                  if (isDoctor)
                    _buildDoctorServices(context)
                  else
                    _buildPatientServices(context),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(BuildContext context, FirebaseAuthService auth) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[200]!, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _infoRow(
            context,
            icon: Icons.phone,
            label: 'رقم الجوال',
            value: auth.userData?['phone'] ?? '-',
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.grey[300]),
          const SizedBox(height: 14),
          _infoRow(
            context,
            icon: Icons.person,
            label: auth.userRole == 'doctor' ? 'النوع' : 'النوع',
            value: auth.userRole == 'doctor' ? 'طبيب' : 'مريض',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[800],
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, color: const Color(0xFF0097A7), size: 20),
      ],
    );
  }

  Widget _buildDoctorServices(BuildContext context) {
    final services = [
      {
        'icon': Icons.calendar_month,
        'title': 'المواعيد',
        'subtitle': 'جدول اليوم',
        'action': 'schedule',
      },
      {
        'icon': Icons.settings,
        'title': 'الإعدادات',
        'subtitle': 'إعدادات العيادة',
        'action': 'settings',
      },
      {
        'icon': Icons.people,
        'title': 'المرضى',
        'subtitle': 'قائمة المرضى',
        'action': 'patients',
      },
      {
        'icon': Icons.trending_up,
        'title': 'الإحصائيات',
        'subtitle': 'الأداء والتقارير',
        'action': 'analytics',
      },
    ];

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];
        return _buildServiceCard(
          context,
          icon: service['icon'] as IconData,
          title: service['title'] as String,
          subtitle: service['subtitle'] as String,
          action: service['action'] as String,
        );
      },
    );
  }

  Widget _buildPatientServices(BuildContext context) {
    final services = [
      {
        'icon': Icons.date_range,
        'title': 'حجز موعد',
        'subtitle': 'موعد جديد',
        'action': 'book',
      },
      {
        'icon': Icons.calendar_month,
        'title': 'مواعيدي',
        'subtitle': 'مواعيدك',
        'action': 'appointments',
      },
      {
        'icon': Icons.search,
        'title': 'البحث',
        'subtitle': 'البحث عن طبيب',
        'action': 'search',
      },
      {
        'icon': Icons.folder,
        'title': 'السجل الطبي',
        'subtitle': 'سجلاتك الطبية',
        'action': 'history',
      },
    ];

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];
        return _buildServiceCard(
          context,
          icon: service['icon'] as IconData,
          title: service['title'] as String,
          subtitle: service['subtitle'] as String,
          action: service['action'] as String,
        );
      },
    );
  }

  Widget _buildServiceCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String action,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[200]!, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleServiceTap(context, action),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 40, color: const Color(0xFF0097A7)),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.grey[800],
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleServiceTap(BuildContext context, String action) {
    switch (action) {
      case 'settings':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DoctorSettingsScreen()),
        );
        break;
      case 'schedule':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DoctorScheduleScreen()),
        );
        break;
      case 'patients':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DoctorPatientsScreen()),
        );
        break;
      case 'analytics':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DoctorAnalyticsScreen()),
        );
        break;
      case 'book':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PatientBookingScreen()),
        );
        break;
      case 'appointments':
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const PatientMyAppointmentsScreen()),
        );
        break;
      case 'search':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PatientSearchDoctorScreen()),
        );
        break;
      case 'history':
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const PatientMedicalHistoryScreen()),
        );
        break;
    }
  }
}
