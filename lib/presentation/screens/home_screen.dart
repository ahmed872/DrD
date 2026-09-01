import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/doctor_account_state.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/role_guard.dart';
import 'admin/admin_home_screen.dart';
import 'notifications_screen.dart';
import '../../core/theme/app_spacing.dart';
import '../widgets/app_surfaces.dart';
import '../widgets/app_widgets.dart';
import '../widgets/patient_home_section.dart';
import '../widgets/doctor_summary_card.dart';
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
            actions: [
              if (auth.userId != null) _NotificationBell(uid: auth.userId!),
              if (auth.userRole == 'patient')
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'الإعدادات',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PatientSettingsScreen(),
                    ),
                  ),
                ),
              // شريط الرئيسية كان يحمل أربعة أزرار: إشعارات، ومزامنة
              // صلاحيات، وإعدادات، وخروج. اثنان منها إجراءان نادران
              // (الخروج، ومزامنة صلاحية الإدارة بعد منحها بـ
              // `create_admin.js`)، فجُمعا في قائمة إضافية.
              //
              // ولا يصحّ إخفاء المزامنة خلف `auth.isAdmin`: هي لازمة تحديداً
              // حين يحمل الرمز الحالي حالةً أقدم من المنح، أي حين تكون
              // `isAdmin` كاذبة. لذلك تبقى متاحة للجميع، خارج الصفّ الأول.
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'المزيد',
                onSelected: (value) async {
                  if (value == 'refresh') {
                    await auth.refreshClaims();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(auth.isAdmin
                            ? 'صلاحية الإدارة مفعّلة'
                            : 'لا تحمل صلاحية إدارة حالياً'),
                      ));
                    }
                  } else if (value == 'logout') {
                    final shouldLogout = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('تسجيل الخروج'),
                        content: const Text(
                            'هل أنت متأكد من رغبتك في تسجيل الخروج؟'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('إلغاء'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text('تسجيل الخروج',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                          ),
                        ],
                      ),
                    );
                    if (shouldLogout == true) auth.logout();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'refresh',
                    child: ListTile(
                      leading: Icon(Icons.sync),
                      title: Text('تحديث الصلاحيات'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      leading: Icon(Icons.logout),
                      title: Text('تسجيل الخروج'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // على شاشة عريضة كان المحتوى يمتدّ بعرض النافذة: بطاقة «موعدك
          // القادم» بعرض 1400 بكسل، وصفّ إجراءات متباعد بلا داعٍ. الحصر
          // يوسّط المحتوى في عرض مقروء ولا يغيّر شيئاً على الهاتف.
          body: SingleChildScrollView(
            child: ContentWidthLimit(
              maxWidth: AppBreakpoints.contentMaxWidth,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // الترحيب
                    Text('مرحباً',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      auth.userName ?? 'المستخدم',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // بطاقة رقم الهاتف ونوع الحساب كانت هنا، في أعلى الشاشة.
                    // معلومتان يعرفهما المستخدم عن نفسه، تحتلّان الموضع الذي
                    // يستحقّه موعده القادم. نُقلتا إلى الإعدادات حيث تُراجَع
                    // البيانات فعلاً، وحلّ محلّهما ما يخصّ اليوم.

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
                                    color:
                                        Theme.of(context).colorScheme.primary),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text('لوحة الإدارة',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                ),
                                const DirectionalForwardIcon(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ===== الطبيب =====
                    if (isDoctor) ...[
                      // الحالة أولاً: الموقوف كان يرى لوحته كاملة بلا إشارة.
                      DoctorStatusBanner(
                        state: doctorAccountStateFrom(auth.userData),
                      ),
                      if (doctorAccountStateFrom(auth.userData)
                              .hasClinicAccess &&
                          auth.userId != null) ...[
                        DoctorSummaryCard(doctorId: auth.userId!),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      const SectionTitle(title: 'أدوات العيادة'),
                      _buildDoctorServices(
                        context,
                        doctorAccountStateFrom(auth.userData),
                      ),
                    ]

                    // ===== المريض =====
                    // الترتيب مقصود: الموعد القادم، ثم البحث، ثم الإجراءات
                    // السريعة، ثم بقيّة المواعيد. الأهمّ أعلى الشاشة بلا تمرير.
                    else ...[
                      if (auth.userId != null)
                        PatientHomeSection(patientId: auth.userId!),
                    ],

                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// أدوات العيادة.
  ///
  /// كانت شبكة بطاقات بارتفاع 165 بكسل لكل منها أيقونة ضخمة وسطران —
  /// نفس الهدر الذي أُزيل من جانب المريض. صارت صفّ إجراءات مضغوطاً بنفس
  /// المكوّن، فتُقرأ الشاشتان بوصفهما نظاماً واحداً.
  ///
  /// مصفوفة الحالات كما هي: شاشات العيادة للنشط وحده، والإعدادات تبقى
  /// للموقوف ليصل إلى بياناته وإلى الدعم.
  Widget _buildDoctorServices(BuildContext context, DoctorAccountState state) {
    final clinic = state.hasClinicAccess;
    return QuickActionsRow(
      actions: [
        if (clinic)
          QuickAction(
            icon: Icons.calendar_month,
            label: 'المواعيد',
            onTap: () => _handleServiceTap(context, 'schedule'),
          ),
        if (clinic)
          QuickAction(
            icon: Icons.people_outline,
            label: 'المرضى',
            onTap: () => _handleServiceTap(context, 'patients'),
          ),
        if (clinic)
          QuickAction(
            icon: Icons.insights_outlined,
            label: 'الإحصائيات',
            onTap: () => _handleServiceTap(context, 'analytics'),
          ),
        QuickAction(
          icon: Icons.settings_outlined,
          label: 'الإعدادات',
          onTap: () => _handleServiceTap(context, 'settings'),
        ),
      ],
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
