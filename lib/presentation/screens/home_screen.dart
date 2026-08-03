import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/app_widgets.dart';
import 'doctor_analytics_screen.dart';
import 'doctor_patients_screen.dart';
import 'doctor_schedule_screen.dart';
import 'doctor_settings_screen.dart';
import 'patient_booking_screen.dart';
import 'patient_medical_history_screen.dart';
import 'patient_my_appointments_screen.dart';
import 'patient_search_doctor_screen.dart';
import 'patient_settings_screen.dart';
import 'support_screen.dart';

/// وصف خدمة واحدة في شبكة الصفحة الرئيسية.
class _Service {
  const _Service({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  /// لون البطاقة. اختلاف اللون بين الخدمات ليس زينة: هو ما يجعل المستخدم
  /// يتعرّف على «مواعيدي» من طرف عينه بدل قراءة أربعة عناوين متطابقة.
  final _Tone tone;
}

enum _Tone { brand, success, warning, info }

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FirebaseAuthService>(
      builder: (context, auth, _) {
        final isDoctor = auth.userRole == 'doctor';
        final services = isDoctor ? _doctorServices : _patientServices;

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Hero(auth: auth, isDoctor: isDoctor)),
              SliverToBoxAdapter(
                child: PageBody(
                  maxWidth: AppBreakpoints.wide,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.xxxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // بطاقة الملف تتداخل مع الرأس المتدرّج عمداً — تربط
                      // الرأس بالمحتوى بدل أن يبدوا طبقتين منفصلتين.
                      Transform.translate(
                        offset: const Offset(0, -28),
                        child: _ProfileCard(auth: auth, isDoctor: isDoctor),
                      ),
                      SectionTitle(
                        title: isDoctor ? 'لوحة الطبيب' : 'الخدمات المتاحة',
                        subtitle: isDoctor
                            ? 'كل ما تحتاجه لإدارة عيادتك'
                            : 'اختر الخدمة التي تريدها',
                        icon: Icons.grid_view_rounded,
                      ),
                      _ServiceGrid(services: services),
                      const SizedBox(height: AppSpacing.xl),
                      _SupportBanner(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static const List<_Service> _doctorServices = [
    _Service(
      icon: Icons.event_note_rounded,
      title: 'المواعيد',
      subtitle: 'جدول اليوم',
      tone: _Tone.brand,
      builder: _buildSchedule,
    ),
    _Service(
      icon: Icons.groups_rounded,
      title: 'المرضى',
      subtitle: 'قائمة المرضى',
      tone: _Tone.info,
      builder: _buildPatients,
    ),
    _Service(
      icon: Icons.insights_rounded,
      title: 'الإحصائيات',
      subtitle: 'الأداء والتقارير',
      tone: _Tone.success,
      builder: _buildAnalytics,
    ),
    _Service(
      icon: Icons.tune_rounded,
      title: 'الإعدادات',
      subtitle: 'إعدادات العيادة',
      tone: _Tone.warning,
      builder: _buildDoctorSettings,
    ),
  ];

  static const List<_Service> _patientServices = [
    _Service(
      icon: Icons.add_circle_outline_rounded,
      title: 'حجز موعد',
      subtitle: 'احجز عند طبيب',
      tone: _Tone.brand,
      builder: _buildBooking,
    ),
    _Service(
      icon: Icons.event_available_rounded,
      title: 'مواعيدي',
      subtitle: 'القادمة والسابقة',
      tone: _Tone.success,
      builder: _buildMyAppointments,
    ),
    _Service(
      icon: Icons.search_rounded,
      title: 'البحث عن طبيب',
      subtitle: 'حسب التخصص',
      tone: _Tone.info,
      builder: _buildSearch,
    ),
    _Service(
      icon: Icons.folder_shared_rounded,
      title: 'السجل الطبي',
      subtitle: 'زياراتك السابقة',
      tone: _Tone.warning,
      builder: _buildHistory,
    ),
  ];

  // دوال بناء منفصلة حتى تبقى قوائم الخدمات `const`.
  static Widget _buildSchedule(BuildContext _) => const DoctorScheduleScreen();
  static Widget _buildPatients(BuildContext _) => const DoctorPatientsScreen();
  static Widget _buildAnalytics(BuildContext _) =>
      const DoctorAnalyticsScreen();
  static Widget _buildDoctorSettings(BuildContext _) =>
      const DoctorSettingsScreen();
  static Widget _buildBooking(BuildContext _) => const PatientBookingScreen();
  static Widget _buildMyAppointments(BuildContext _) =>
      const PatientMyAppointmentsScreen();
  static Widget _buildSearch(BuildContext _) =>
      const PatientSearchDoctorScreen();
  static Widget _buildHistory(BuildContext _) =>
      const PatientMedicalHistoryScreen();
}

// =============================================================================
// الرأس
// =============================================================================

class _Hero extends StatelessWidget {
  const _Hero({required this.auth, required this.isDoctor});

  final FirebaseAuthService auth;
  final bool isDoctor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      decoration: BoxDecoration(
        gradient: tokens.brandGradient,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.xl),
        ),
      ),
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: SafeArea(
        bottom: false,
        child: PageBody(
          maxWidth: AppBreakpoints.wide,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(),
                          style: context.texts.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          auth.userName ?? 'المستخدم',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.headlineSmall
                              ?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  if (!isDoctor)
                    _HeaderAction(
                      icon: Icons.settings_outlined,
                      tooltip: 'الإعدادات',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PatientSettingsScreen(),
                        ),
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  _HeaderAction(
                    icon: Icons.logout_rounded,
                    tooltip: 'تسجيل الخروج',
                    onTap: () => _confirmLogout(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// تحية تتبع وقت اليوم. تفصيلة صغيرة لكنها تجعل الشاشة تبدو حيّة بدل
  /// كلمة «مرحباً» ثابتة لا تتغيّر أبداً.
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'صباح الخير';
    if (hour < 17) return 'مساء الخير';
    return 'مساء الخير';
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<FirebaseAuthService>();
    final ok = await showConfirmDialog(
      context,
      title: 'تسجيل الخروج',
      message: 'هل أنت متأكد من رغبتك في تسجيل الخروج؟',
      confirmLabel: 'تسجيل الخروج',
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (ok) auth.logout();
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.16),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Icon(icon, color: Colors.white, size: 21),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// بطاقة الملف
// =============================================================================

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.auth, required this.isDoctor});

  final FirebaseAuthService auth;
  final bool isDoctor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final phone = auth.userData?['phone']?.toString();

    return AppCard(
      child: Row(
        children: [
          AppAvatar(name: auth.userName, size: 52),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auth.userName ?? 'المستخدم',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleMedium,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.phone_rounded,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        (phone == null || phone.isEmpty) ? 'بدون رقم' : phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodySmall
                            ?.copyWith(color: tokens.textMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          StatusPill(
            label: isDoctor ? 'طبيب' : 'مريض',
            color: isDoctor ? context.colors.primary : tokens.success,
            icon: isDoctor
                ? Icons.medical_services_rounded
                : Icons.favorite_rounded,
            compact: true,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// شبكة الخدمات
// =============================================================================

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({required this.services});

  final List<_Service> services;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // عمودان على الهاتف، أربعة على المتصفح. الشبكة الثابتة بعمودين كانت
        // تترك نصف شاشة سطح المكتب فارغاً.
        final columns = constraints.maxWidth >= 760
            ? 4
            : constraints.maxWidth >= 420
                ? 2
                : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            mainAxisExtent: 138,
          ),
          itemCount: services.length,
          itemBuilder: (context, i) => _ServiceCard(service: services[i]),
        );
      },
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});

  final _Service service;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final color = switch (service.tone) {
      _Tone.brand => context.colors.primary,
      _Tone.success => tokens.success,
      _Tone.warning => tokens.warning,
      _Tone.info => tokens.info,
    };

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: service.builder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.rMd,
            ),
            child: Icon(service.icon, size: 24, color: color),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                service.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                service.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    context.texts.bodySmall?.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// شريط الدعم
// =============================================================================

class _SupportBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SupportScreen()),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.whatsapp.withValues(alpha: 0.14),
              borderRadius: AppRadius.rMd,
            ),
            child: Icon(
              Icons.support_agent_rounded,
              color: tokens.whatsapp,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الدعم الفني', style: context.texts.titleSmall),
                Text(
                  'عندك مشكلة أو استفسار؟ كلّمنا',
                  style: context.texts.bodySmall
                      ?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 15,
            color: tokens.textFaint,
          ),
        ],
      ),
    );
  }
}
