import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/doctor_application.dart';
import '../../data/services/doctor_application_service.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/doctor_application_card.dart';
import 'admin_applications_screen.dart';
import 'doctor_shared_records_screen.dart';
import 'patient_shares_screen.dart';
import 'doctor_application_screen.dart';
import 'doctor_settings_screen.dart';
import 'doctor_schedule_screen.dart';
import 'doctor_patients_screen.dart';
import 'doctor_analytics_screen.dart';
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
              // مدخل مراجعة الطلبات — للمشرف وحده.
              //
              // إخفاؤه عن غيره تنظيم لا حماية: القواعد ترفض قراءة الطلبات
              // وكتابتها من أي حساب ليس في مجموعة `admins`.
              if (auth.isAdmin)
                IconButton(
                  icon: const Icon(Icons.fact_check_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminApplicationsScreen(),
                    ),
                  ),
                  tooltip: 'مراجعة طلبات الأطباء',
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
                          child: Text(
                            'تسجيل الخروج',
                            style: TextStyle(color: context.colors.error),
                          ),
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
              padding: const EdgeInsets.all(DrdSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // الترحيب
                  Text(
                    'مرحباً',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.drd.muted,
                    ),
                  ),
                  const SizedBox(height: DrdSpacing.xxs),
                  Text(
                    auth.userName ?? 'المستخدم',
                    style: context.text.headlineSmall,
                  ),
                  const SizedBox(height: DrdSpacing.lg),

                  // بطاقة المعلومات
                  _buildInfoCard(context, auth),

                  SectionHeader(
                    title: isDoctor ? 'لوحة الطبيب' : 'الخدمات المتاحة',
                  ),

                  if (isDoctor)
                    _buildDoctorServices(context)
                  else
                    _buildPatientServices(context),

                  // دعوة الانضمام كطبيب — **بعد** خدمات المريض عمداً.
                  //
                  // من يفتح التطبيق يفتحه ليحجز موعداً. وضع الدعوة فوق
                  // الحجز يجعل المنتج يبدو كأنه يوظّف أطباء لا كأنه يخدم
                  // مرضى.
                  if (!isDoctor) const _DoctorApplicationSection(),

                  const SizedBox(height: DrdSpacing.xl),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(BuildContext context, FirebaseAuthService auth) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _infoRow(
            context,
            icon: Icons.phone,
            label: 'رقم الجوال',
            value: auth.userData?['phone'] ?? '-',
          ),
          const Divider(),
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
                style: context.text.bodySmall?.copyWith(
                  color: context.drd.muted,
                ),
              ),
              const SizedBox(height: DrdSpacing.xxs),
              Text(
                value,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: DrdSpacing.sm),
        Icon(icon, color: context.colors.primary, size: 20),
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
      {
        'icon': Icons.folder_shared_outlined,
        'title': 'سجلات مشتركة',
        'subtitle': 'شاركها المرضى معك',
        'action': 'shared_with_me',
      },
    ];

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: DrdSpacing.sm,
        mainAxisSpacing: DrdSpacing.sm,
        mainAxisExtent: _serviceCardExtent(context),
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
      // مدخل واحد للحجز.
      //
      // كان هنا مدخلان: «حجز موعد» يفتح شاشة تبحث وتحجز، و«البحث» يفتح شاشة
      // بحث تنتهي بالشاشة نفسها. فكان المريض القادم من البحث يرى صندوق بحث
      // ثانياً وقائمة أطباء ثانية بعد أن اختار طبيبه. الرحلة الآن واحدة:
      // ابحث عن طبيب ← اختر ← احجز.
      {
        'icon': Icons.search,
        'title': 'ابحث عن طبيب',
        'subtitle': 'اختر طبيبك واحجز موعدك',
        'action': 'search',
      },
      {
        'icon': Icons.calendar_month,
        'title': 'مواعيدي',
        'subtitle': 'مواعيدك',
        'action': 'appointments',
      },
      {
        'icon': Icons.folder,
        'title': 'السجل الطبي',
        'subtitle': 'سجلاتك الطبية',
        'action': 'history',
      },
      {
        'icon': Icons.share_outlined,
        'title': 'السجلات المشتركة',
        'subtitle': 'مَن يرى سجلاتك',
        'action': 'shares',
      },
    ];

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: DrdSpacing.sm,
        mainAxisSpacing: DrdSpacing.sm,
        mainAxisExtent: _serviceCardExtent(context),
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

  /// ارتفاع بطاقة الخدمة، محسوباً لا مفترضاً.
  ///
  /// كان المُشبِك يترك النسبة الافتراضية 1:1، فيصير ارتفاع البطاقة مساوياً
  /// لعرضها — رقم يقرّره عرض الشاشة ولا علاقة له بما في البطاقة. ومحتواها
  /// شبه ثابت (أيقونة 40 وسطرا نص)، فيكفي جهاز أضيق قليلاً أو تكبير خط
  /// بسيط ليتجاوز المحتوى الحدّ: وهو ما ظهر شريطاً أصفر
  /// «BOTTOM OVERFLOWED BY 2.0 PIXELS» تحت بطاقة «ابحث عن طبيب».
  ///
  /// الحساب هنا يتبع تكبير خط النظام، فتكبر البطاقة مع النص بدل أن تقصّه —
  /// وهذا يخص هذا التطبيق تحديداً: كثير من مستخدميه كبار في السن يرفعون
  /// حجم الخط في إعدادات الهاتف.
  static double _serviceCardExtent(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final titleSize = context.text.titleSmall?.fontSize ?? 14;
    final bodySize = context.text.bodySmall?.fontSize ?? 12;

    // النصّ العربي يحتاج سطراً أعلى من اللاتيني: النازلات والتشكيل.
    const lineHeight = 1.6;

    return DrdSpacing.card.vertical +
        _serviceIconSize +
        DrdSpacing.sm +
        scaler.scale(titleSize) * lineHeight +
        DrdSpacing.xxs +
        // سطران للوصف: «اختر طبيبك واحجز موعدك» ينسدل على الشاشات الضيقة.
        scaler.scale(bodySize) * lineHeight * 2;
  }

  static const double _serviceIconSize = 40;

  Widget _buildServiceCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String action,
  }) {
    return AppCard(
      onTap: () => _handleServiceTap(context, action),
      semanticLabel: '$title — $subtitle',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: _serviceIconSize, color: context.colors.primary),
          const SizedBox(height: DrdSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.text.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: DrdSpacing.xxs),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(color: context.drd.muted),
          ),
        ],
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
      case 'shares':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PatientSharesScreen()),
        );
        break;
      case 'shared_with_me':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DoctorSharedRecordsScreen()),
        );
        break;
    }
  }
}

/// قسم طلب الانضمام كطبيب على الصفحة الرئيسية.
///
/// يتدفّق مع مستند الطلب، فينتقل من «قدّم طلباً» إلى «قيد المراجعة» إلى
/// «مقبول» بلا أن يعيد المستخدم فتح التطبيق.
class _DoctorApplicationSection extends StatefulWidget {
  const _DoctorApplicationSection();

  @override
  State<_DoctorApplicationSection> createState() =>
      _DoctorApplicationSectionState();
}

class _DoctorApplicationSectionState extends State<_DoctorApplicationSection> {
  final _service = DoctorApplicationService();

  /// يمنع تكرار طلب تحديث الملف عند كل إعادة بناء.
  bool _refreshRequested = false;

  /// يُزاد ليُعاد الاشتراك في التدفّق عند «إعادة المحاولة».
  int _streamAttempt = 0;

  /// يعيد قراءة مستند المستخدم بعد القبول.
  ///
  /// الترقية تجري على الخادم بعد تسجيل القرار، فحالة الطلب تصل إلى التطبيق
  /// قبل الدور الجديد. بلا هذه القراءة يبقى المستخدم يرى شاشة المريض بعد
  /// قبوله حتى يخرج ويدخل من جديد.
  void _refreshProfileOnce(FirebaseAuthService auth) {
    if (_refreshRequested) return;
    _refreshRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) auth.checkSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<FirebaseAuthService>();
    final uid = auth.userId;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DoctorApplication>(
      key: ValueKey(_streamAttempt),
      stream: _service.watchMyApplication(uid),
      builder: (context, snapshot) {
        // لا شيء يُعرض قبل وصول الحالة: بطاقة «قدّم طلباً» تومض ثم تتحول
        // إلى «قيد المراجعة» تربك أكثر مما تفيد.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        // فشل القراءة يُقال، ولا يُبتلع.
        //
        // كان القسم يختفي صامتاً عند أي خطأ. وهو المدخل **الوحيد** لأن يصبح
        // المستخدم طبيباً، فاختفاؤه لا يعني «لا شيء هنا» بل «لا سبيل إلى
        // التقديم، ولا تفسير». وأشيع أسباب الخطأ — قواعد غير منشورة، أو
        // انقطاع الشبكة — كلها قابلة للإصلاح متى عُرفت.
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: DrdSpacing.lg),
            child: AppBanner.error(
              title: 'تعذّر التحقق من حالة طلب الانضمام',
              message: 'إن كنت طبيباً وتريد التقديم، تحقّق من اتصالك '
                  'ثم أعد المحاولة.',
              action: TextButton(
                onPressed: () => setState(() => _streamAttempt++),
                child: const Text('إعادة المحاولة'),
              ),
            ),
          );
        }
        if (!snapshot.hasData) return const SizedBox.shrink();

        final application = snapshot.data!;
        final approvedButNotYetDoctor =
            application.status.isApproved && auth.userRole != 'doctor';
        if (approvedButNotYetDoctor) _refreshProfileOnce(auth);

        return Padding(
          padding: const EdgeInsets.only(top: DrdSpacing.lg),
          child: DoctorApplicationCard(
            application: application,
            isActivating: approvedButNotYetDoctor,
            onApply: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DoctorApplicationScreen(
                  existing: application.status.isEditable ? application : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
