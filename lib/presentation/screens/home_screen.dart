import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/appointment_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_logger.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/next_appointment_card.dart';
import '../widgets/ui_kit.dart';
import 'doctor_analytics_screen.dart';
import 'doctor_patients_screen.dart';
import 'doctor_schedule_screen.dart';
import 'doctor_settings_screen.dart';
import 'notifications_screen.dart';
import 'patient_booking_screen.dart';
import 'patient_medical_history_screen.dart';
import 'patient_my_appointments_screen.dart';
import 'patient_search_doctor_screen.dart';
import 'patient_settings_screen.dart';

/// الشاشة الرئيسية.
///
/// أُعيد بناؤها حول سؤال واحد: إيه أول حاجة المستخدم محتاج يعرفها لما
/// يفتح التطبيق؟ الإجابة مش «قائمة خدمات» — هي **موعده الجاي وفاضلّه قد
/// إيه**. عشان كده بطاقة العدّاد فوق كل حاجة، والخدمات تحتها.
///
/// الشكل القديم كان بيبدأ بترحيب وبطاقة بيانات ثابتة (رقم الجوال والنوع)
/// وهي معلومات المستخدم عارفها أصلاً وماحدش بيفتح التطبيق عشانها.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _next;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNext());
  }

  /// أقرب موعد قائم للمستخدم — للمريض مواعيده، وللطبيب مواعيد عيادته.
  Future<void> _loadNext() async {
    final auth = Provider.of<FirebaseAuthService>(context, listen: false);
    final uid = auth.userId;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final isDoctor = auth.userRole == 'doctor';
      final snap = await FirebaseFirestore.instance
          .collection('appointments')
          .where(isDoctor ? 'doctorId' : 'patientId', isEqualTo: uid)
          .get();

      final now = DateTime.now();
      Map<String, dynamic>? best;
      DateTime? bestAt;

      for (final doc in snap.docs) {
        final d = doc.data();
        if (!AppointmentStatus.parse(d['status']).isActive) continue;

        final at = _startsAt(d);
        if (at == null || at.isBefore(now)) continue;
        if (bestAt == null || at.isBefore(bestAt)) {
          bestAt = at;
          best = {...d, 'id': doc.id, 'startsAt': at};
        }
      }

      if (mounted) setState(() => _next = best);
    } catch (e) {
      AppLogger.error('تعذّر تحميل الموعد القادم', e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// لحظة بدء الموعد — من `startsAt` أو من التاريخ والوقت للمواعيد القديمة.
  DateTime? _startsAt(Map<String, dynamic> d) {
    final ts = d['startsAt'];
    if (ts is Timestamp) return ts.toDate();

    final date = d['appointmentDate']?.toString();
    final time = (d['startTime'] ?? d['time'])?.toString();
    if (date == null || time == null) return null;

    final day = DateTime.tryParse(date);
    if (day == null) return null;
    final parts = time.split(':');
    return DateTime(day.year, day.month, day.day, int.tryParse(parts[0]) ?? 0,
        parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FirebaseAuthService>(
      builder: (context, auth, _) {
        final isDoctor = auth.userRole == 'doctor';
        final t = Theme.of(context).textTheme;

        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _loadNext,
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
                children: [
                  _Header(auth: auth, isDoctor: isDoctor),
                  const SizedBox(height: Gap.xl),

                  // ── الموعد القادم ──
                  if (_loading)
                    const _NextSkeleton()
                  else if (_next != null)
                    NextAppointmentCard(
                      doctorName: isDoctor
                          ? (_next!['patientName']?.toString() ?? 'مريض')
                          : (_next!['doctorName']?.toString() ?? 'الطبيب'),
                      specialization: isDoctor
                          ? _formatDay(_next!['startsAt'] as DateTime)
                          : _next!['doctorSpecialization']?.toString(),
                      startsAt: _next!['startsAt'] as DateTime,
                      timeLabel:
                          (_next!['startTime'] ?? _next!['time'] ?? '00:00')
                              .toString(),
                      onTap: () => _open(
                        isDoctor
                            ? const DoctorScheduleScreen()
                            : const PatientMyAppointmentsScreen(),
                      ),
                    )
                  else
                    AppCard(
                      child: EmptyState(
                        icon: Icons.event_available_outlined,
                        message: isDoctor
                            ? 'لا توجد مواعيد قادمة في عيادتك'
                            : 'مافيش مواعيد قادمة',
                        action: isDoctor
                            ? null
                            : FilledButton.icon(
                                onPressed: () =>
                                    _open(const PatientBookingScreen()),
                                icon: const Icon(Icons.add, size: 20),
                                label: const Text('احجز موعد'),
                              ),
                      ),
                    ),

                  const SizedBox(height: Gap.xxl),
                  Eyebrow(isDoctor ? 'إدارة العيادة' : 'الخدمات'),
                  const SizedBox(height: Gap.md),
                  _Services(isDoctor: isDoctor, onOpen: _open),

                  const SizedBox(height: Gap.xl),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => Navigator.pushNamed(context, '/support'),
                      icon: const Icon(Icons.headset_mic_outlined, size: 18),
                      label: const Text('تحتاج مساعدة؟'),
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  Center(
                    child: Text('DrD', style: t.labelSmall),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDay(DateTime d) => DateFormat('EEEE d MMMM', 'ar').format(d);

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    // الرجوع من أي شاشة قد يكون بعد حجز أو إلغاء، فنحدّث بطاقة الموعد.
    if (mounted) _loadNext();
  }
}

/// ترويسة: تحية واسم المستخدم على جهة، وأدوات على الجهة الأخرى.
class _Header extends StatelessWidget {
  const _Header({required this.auth, required this.isDoctor});

  final FirebaseAuthService auth;
  final bool isDoctor;

  /// تحية حسب وقت اليوم — لمسة صغيرة بتخلي التطبيق يبان إنه بيتابع معاك.
  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'صباح الخير';
    if (h < 17) return 'مساء الخير';
    return 'مساء الخير';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final name = auth.userName ?? 'المستخدم';

    return Row(
      children: [
        InitialAvatar(name, size: 46),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting, style: t.bodySmall),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.titleLarge,
              ),
            ],
          ),
        ),
        const NotificationsBell(),
        IconButton(
          tooltip: 'الإعدادات',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => isDoctor
                  ? const DoctorSettingsScreen()
                  : const PatientSettingsScreen(),
            ),
          ),
        ),
        IconButton(
          tooltip: 'تسجيل الخروج',
          icon: Icon(Icons.logout, color: scheme.onSurfaceVariant),
          onPressed: () => _confirmLogout(context),
        ),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = Provider.of<FirebaseAuthService>(context, listen: false);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (ok == true) await auth.logout();
  }
}

/// شبكة الخدمات.
class _Services extends StatelessWidget {
  const _Services({required this.isDoctor, required this.onOpen});

  final bool isDoctor;
  final void Function(Widget) onOpen;

  @override
  Widget build(BuildContext context) {
    final items = isDoctor
        ? const [
            (Icons.calendar_month_outlined, 'جدول اليوم', 'مواعيد عيادتك'),
            (Icons.groups_outlined, 'المرضى', 'قائمة مرضاك'),
            (Icons.insights_outlined, 'الإحصائيات', 'أداء العيادة'),
            (Icons.tune, 'إعدادات العيادة', 'المواعيد والأسعار'),
          ]
        : const [
            (Icons.add_circle_outline, 'احجز موعد', 'اختر طبيب ووقت'),
            (Icons.search, 'ابحث عن طبيب', 'حسب التخصص'),
            (Icons.event_note_outlined, 'مواعيدي', 'القادمة والسابقة'),
            (Icons.folder_shared_outlined, 'سجلي الطبي', 'تاريخ زياراتك'),
          ];

    final screens = isDoctor
        ? [
            const DoctorScheduleScreen(),
            const DoctorPatientsScreen(),
            const DoctorAnalyticsScreen(),
            const DoctorSettingsScreen(),
          ]
        : [
            const PatientBookingScreen(),
            const PatientSearchDoctorScreen(),
            const PatientMyAppointmentsScreen(),
            const PatientMedicalHistoryScreen(),
          ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Gap.md,
      crossAxisSpacing: Gap.md,
      childAspectRatio: 1.18,
      children: [
        for (var i = 0; i < items.length; i++)
          _ServiceTile(
            icon: items[i].$1,
            title: items[i].$2,
            subtitle: items[i].$3,
            onTap: () => onOpen(screens[i]),
          ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(icon, color: scheme.primary, size: 22),
          ),
          const Spacer(),
          Text(title, style: t.titleMedium),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// هيكل عظمي أثناء تحميل الموعد القادم — أهدأ من مؤشر دوّار.
class _NextSkeleton extends StatelessWidget {
  const _NextSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 168,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
    );
  }
}
