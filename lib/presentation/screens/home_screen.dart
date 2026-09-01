import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/doctor_account_state.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/role_guard.dart';
import 'admin/admin_home_screen.dart';
import 'notifications_screen.dart';
import 'doctor_application_screen.dart';
import 'doctor_settings_screen.dart';
import 'doctor_schedule_screen.dart';
import 'doctor_patients_screen.dart';
import 'doctor_analytics_screen.dart';
import 'patient_booking_screen.dart';
import 'patient_my_appointments_screen.dart';
import 'patient_medical_history_screen.dart';
import 'patient_search_doctor_screen.dart';
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
            actions: [
              if (auth.userId != null) _NotificationBell(uid: auth.userId!),
              // تحديث صلاحية الإدارة — لازم بعد منحها بـ create_admin.js لأن
              // الجلسة الحالية تحمل رمزاً صدر قبل المنح. راجع
              // FirebaseAuthService.refreshClaims.
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: 'تحديث الصلاحيات',
                onPressed: () async {
                  await auth.refreshClaims();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(auth.isAdmin
                          ? 'صلاحية الإدارة مفعّلة'
                          : 'لا تحمل صلاحية إدارة حالياً'),
                    ));
                  }
                },
              ),
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
                          child: Text('تسجيل الخروج',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    auth.userName ?? 'المستخدم',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 24,
                        ),
                  ),
                  const SizedBox(height: 36),

                  // بطاقة المعلومات
                  _buildInfoCard(context, auth),
                  const SizedBox(height: 24),

                  // لوحة الإدارة — تظهر فقط لصاحب Custom Claim صحيح. هذا
                  // إخفاء عرض لا حماية: الوصول الفعلي محكوم بـ
                  // firestore.rules والدوال السحابية بمعزل تام عن هذا الشرط.
                  if (auth.isAdmin) ...[
                    Material(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AdminHomeScreen()),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.admin_panel_settings,
                                  color: Theme.of(context).colorScheme.primary),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text('لوحة الإدارة',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                              ),
                              Icon(Icons.chevron_left),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // الخدمات
                  Text(
                    isDoctor ? 'لوحة الطبيب' : 'الخدمات المتاحة',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 16),

                  // حالة حساب الطبيب قبل أدواته: الطبيب الموقوف كان يرى
                  // لوحته كاملة بلا أي إشارة إلى أن المرضى لا يرونه.
                  if (isDoctor)
                    DoctorStatusBanner(
                      state: doctorAccountStateFrom(auth.userData),
                    ),

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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
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
      {
        'icon': Icons.medical_information,
        'title': 'التقدّم كطبيب',
        'subtitle': 'انضم كطبيب في DrD',
        'action': 'doctor_application',
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
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
                Icon(icon,
                    size: 40, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      case 'doctor_application':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DoctorApplicationScreen()),
        );
        break;
    }
  }
}

/// جرس الإشعارات مع عدّاد غير المقروء — استعلام محدود (`limit`) لا قراءة
/// كاملة للمجموعة، ومحصور بمساواتين على `recipientId`/`isRead` فلا يحتاج
/// فهرساً مركّباً جديداً (Firestore يدمج فهارس الحقل المفرد تلقائياً لمثل
/// هذا الاستعلام).
class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.uid});

  final String uid;

  static const _countCap = 50;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientId', isEqualTo: uid)
          .where('isRead', isEqualTo: false)
          .limit(_countCap)
          .snapshots(),
      builder: (context, snapshot) {
        final unread = snapshot.data?.docs.length ?? 0;
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'الإشعارات',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationsScreen()),
                );
              },
            ),
            if (unread > 0)
              Positioned(
                top: 8,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Text(
                    unread >= _countCap ? '$_countCap+' : '$unread',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onError,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
