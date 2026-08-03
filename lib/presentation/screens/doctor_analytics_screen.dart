import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/app_widgets.dart';

class DoctorAnalyticsScreen extends StatefulWidget {
  const DoctorAnalyticsScreen({super.key});

  @override
  State<DoctorAnalyticsScreen> createState() => _DoctorAnalyticsScreenState();
}

class _DoctorAnalyticsScreenState extends State<DoctorAnalyticsScreen> {
  int _selectedTimeRange = 0;
  bool _isLoading = true;

  Map<String, dynamic> _analyticsData = {
    'totalAppointments': 0,
    'completedAppointments': 0,
    'cancelledAppointments': 0,
    'totalPatients': 0,
    'newPatients': 0,
    'avgRating': 0.0,
    'totalRevenue': 0,
    'avgSessionDuration': 0,
    'noShowRate': 0.0,
    'peakDay': '-',
  };

  List<Map<String, dynamic>> _weeklyData = [];
  List<Map<String, dynamic>> _topReasons = [];

  @override
  void initState() {
    super.initState();
    _fetchRealAnalytics();
  }

  Future<void> _fetchRealAnalytics() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      int sessionDur = 30;
      double doctorRating = 0;
      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (docRef.exists) {
        sessionDur = docRef.data()?['sessionDuration'] ?? 30;
        // التقييم يُقرأ من ملف الطبيب. كان مكتوباً 5.0 ثابتاً في الواجهة،
        // فكانت الشاشة تعرض تقييماً كاملاً لطبيب بلا أي تقييم.
        doctorRating = (docRef.data()?['rating'] ?? 0).toDouble();
      }

      DateTime now = DateTime.now();
      DateTime startDate;
      if (_selectedTimeRange == 0) {
        // This month
        startDate = DateTime(now.year, now.month, 1);
      } else if (_selectedTimeRange == 1) {
        // Last 3 months
        startDate = DateTime(now.year, now.month - 3, 1);
      } else {
        // This year
        startDate = DateTime(now.year, 1, 1);
      }

      final apSnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('doctorId', isEqualTo: user.uid)
          .get();

      int total = 0;
      int completed = 0;
      int cancelled = 0;
      double revenue = 0;
      Set<String> uniquePatients = {};
      Map<String, int> reasonCounts = {};

      // 1 = Mon ... 7 = Sun
      Map<int, int> weekdayCounts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0};

      for (var doc in apSnapshot.docs) {
        final data = doc.data();
        final dateStr = data['appointmentDate'] as String?;
        if (dateStr == null) continue;

        DateTime appDate;
        try {
          appDate = DateFormat('yyyy-MM-dd').parse(dateStr);
        } catch (e) {
          continue;
        }

        if (appDate.isBefore(startDate)) continue;

        total++;
        if (data['patientId'] != null) uniquePatients.add(data['patientId']);

        String reason = data['reason']?.toString().trim() ?? '';
        if (reason.isEmpty) reason = 'استشارة';
        reasonCounts[reason] = (reasonCounts[reason] ?? 0) + 1;

        weekdayCounts[appDate.weekday] =
            (weekdayCounts[appDate.weekday] ?? 0) + 1;

        final status = data['status'] ?? '';
        if (status == 'Completed') {
          completed++;
          revenue += (data['price'] ?? 0).toDouble();
        } else if (status == 'Canceled' ||
            status == 'Cancelled' ||
            status == 'Rejected' ||
            status == 'NoShow') {
          cancelled++;
        }
      }

      int maxDay = 1;
      int maxCount = 0;
      weekdayCounts.forEach((day, dayTotal) {
        if (dayTotal > maxCount) {
          maxCount = dayTotal;
          maxDay = day;
        }
      });
      const dayNamesAr = {
        1: 'الإثنين',
        2: 'الثلاثاء',
        3: 'الأربعاء',
        4: 'الخميس',
        5: 'الجمعة',
        6: 'السبت',
        7: 'الأحد',
      };
      // اختصارات عربية للمحور الأفقي — الرسم كان يعرض Mon/Tue داخل واجهة
      // عربية بالكامل.
      const dayShortAr = {
        1: 'إث',
        2: 'ثل',
        3: 'أر',
        4: 'خم',
        5: 'جم',
        6: 'سب',
        7: 'أح',
      };

      double noShow = total == 0 ? 0.0 : (cancelled / total) * 100;

      var sortedReasons = reasonCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      List<Map<String, dynamic>> topR = [];
      for (int i = 0; i < sortedReasons.length && i < 4; i++) {
        topR.add({
          'reason': sortedReasons[i].key,
          'count': sortedReasons[i].value,
        });
      }

      List<Map<String, dynamic>> weekly = [];
      // ترتيب الأسبوع المصري: السبت أولاً.
      List<int> order = [6, 7, 1, 2, 3, 4, 5];
      for (int day in order) {
        weekly.add({
          'day': dayNamesAr[day]!,
          'dayShort': dayShortAr[day]!,
          'appointments': weekdayCounts[day] ?? 0,
        });
      }

      if (!mounted) return;
      setState(() {
        _analyticsData = {
          'totalAppointments': total,
          'completedAppointments': completed,
          'cancelledAppointments': cancelled,
          'totalPatients': uniquePatients.length,
          'newPatients': uniquePatients.length, // approximation
          'avgRating': doctorRating,
          'totalRevenue': revenue.toInt(),
          'avgSessionDuration': sessionDur,
          'noShowRate': noShow,
          'peakDay': total > 0 ? dayNamesAr[maxDay] : '-',
        };
        _weeklyData = weekly;
        _topReasons = topR;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, 'خطأ في جلب البيانات');
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasData = (_analyticsData['totalAppointments'] as int) > 0;

    return AppScaffold(
      title: 'الإحصائيات',
      subtitle: _rangeLabel,
      onRefresh: _fetchRealAnalytics,
      maxWidth: AppBreakpoints.wide,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      headerBottom: AppSegmented(
        labels: const ['هذا الشهر', 'آخر 3 شهور', 'هذا العام'],
        selectedIndex: _selectedTimeRange,
        onChanged: (i) {
          setState(() => _selectedTimeRange = i);
          _fetchRealAnalytics();
        },
      ),
      child: _isLoading
          ? const AppLoader(message: 'جارٍ حساب الإحصائيات…')
          : !hasData
              ? const EmptyState(
                  icon: Icons.insights_rounded,
                  title: 'لا توجد بيانات في هذه الفترة',
                  message: 'اختر فترة أطول، أو انتظر حتى تُسجَّل أول مواعيدك.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMetricsGrid(),
                    const SizedBox(height: AppSpacing.xxl),
                    const SectionTitle(
                      title: 'الأداء',
                      icon: Icons.speed_rounded,
                    ),
                    _buildPerformanceCard(),
                    if (_weeklyData.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      const SectionTitle(
                        title: 'التوزيع الأسبوعي',
                        subtitle: 'عدد المواعيد حسب يوم الأسبوع',
                        icon: Icons.bar_chart_rounded,
                      ),
                      _WeeklyChart(data: _weeklyData),
                    ],
                    if (_topReasons.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      const SectionTitle(
                        title: 'أشهر أسباب الاستشارة',
                        icon: Icons.format_list_bulleted_rounded,
                      ),
                      _TopReasons(reasons: _topReasons),
                    ],
                    const SizedBox(height: AppSpacing.xxl),
                    const SectionTitle(
                      title: 'أرقام سريعة',
                      icon: Icons.dashboard_customize_outlined,
                    ),
                    _buildQuickStats(tokens),
                  ],
                ),
    );
  }

  String get _rangeLabel => switch (_selectedTimeRange) {
        0 => 'هذا الشهر',
        1 => 'آخر ثلاثة شهور',
        _ => 'هذا العام',
      };

  Widget _buildMetricsGrid() {
    final tokens = context.tokens;
    final rating = (_analyticsData['avgRating'] as num).toDouble();

    return _ResponsiveGrid(
      children: [
        StatTile(
          value: '${_analyticsData["totalAppointments"]}',
          label: 'إجمالي المواعيد',
          icon: Icons.event_note_rounded,
          color: context.colors.primary,
        ),
        StatTile(
          value: '${_analyticsData["completedAppointments"]}',
          label: 'مواعيد مكتملة',
          icon: Icons.check_circle_outline_rounded,
          color: tokens.success,
        ),
        StatTile(
          value: '${_analyticsData["totalPatients"]}',
          label: 'عدد المرضى',
          icon: Icons.groups_rounded,
          color: tokens.info,
        ),
        StatTile(
          value: rating == 0 ? '—' : rating.toStringAsFixed(1),
          label: 'متوسط التقييم',
          icon: Icons.star_rounded,
          color: tokens.gold,
        ),
      ],
    );
  }

  Widget _buildPerformanceCard() {
    final tokens = context.tokens;
    final total = _analyticsData['totalAppointments'] as int;
    final completed = _analyticsData['completedAppointments'] as int;
    final noShowRate = _analyticsData['noShowRate'] as double;

    final completionRate = total == 0 ? 0.0 : completed / total;

    return AppCard(
      child: Column(
        children: [
          _MeterRow(
            label: 'نسبة الإتمام',
            value: completionRate,
            display: '${(completionRate * 100).toStringAsFixed(1)}%',
            color: tokens.success,
          ),
          const SizedBox(height: AppSpacing.xl),
          _MeterRow(
            label: 'عدم الحضور والإلغاء',
            value: noShowRate / 100,
            display: '${noShowRate.toStringAsFixed(1)}%',
            color: tokens.danger,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(AppTokens tokens) {
    return _ResponsiveGrid(
      children: [
        StatTile(
          value: '${_analyticsData["avgSessionDuration"]} د',
          label: 'متوسط مدة الجلسة',
          icon: Icons.timer_outlined,
          color: context.colors.primary,
        ),
        StatTile(
          value: '${_analyticsData["totalRevenue"]}',
          label: 'الإيرادات (جنيه)',
          icon: Icons.payments_outlined,
          color: tokens.success,
        ),
        StatTile(
          value: '${_analyticsData["newPatients"]}',
          label: 'مرضى جدد',
          icon: Icons.person_add_alt_rounded,
          color: tokens.info,
        ),
        StatTile(
          value: '${_analyticsData["peakDay"]}',
          label: 'أكثر يوم ازدحاماً',
          icon: Icons.calendar_month_rounded,
          color: tokens.warning,
        ),
      ],
    );
  }
}

// =============================================================================
// عناصر الرسم
// =============================================================================

/// شبكة تتحوّل من عمودين على الهاتف إلى أربعة على المتصفح.
class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.25,
          children: children,
        );
      },
    );
  }
}

class _MeterRow extends StatelessWidget {
  const _MeterRow({
    required this.label,
    required this.value,
    required this.display,
    required this.color,
  });

  final String label;
  final double value;
  final String display;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: context.texts.bodyMedium?.copyWith(color: tokens.textBody),
            ),
            Text(
              display,
              style: context.texts.titleMedium?.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: AppRadius.rPill,
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: tokens.surfaceSunken,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.data});

  final List<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    var maxAppointments = 0;
    for (final d in data) {
      final v = d['appointments'] as int;
      if (v > maxAppointments) maxAppointments = v;
    }
    if (maxAppointments == 0) maxAppointments = 1;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: SizedBox(
        height: 190,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: data.map((d) {
            final appointments = d['appointments'] as int;
            final ratio = appointments / maxAppointments;
            final isPeak = appointments == maxAppointments && appointments > 0;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '$appointments',
                      style: context.texts.labelSmall?.copyWith(
                        color:
                            isPeak ? context.colors.primary : tokens.textMuted,
                        fontWeight: isPeak ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // عمود بارتفاع أدنى 6 بكسل حتى تبقى الأيام الفارغة
                    // مرئية بدل أن تختفي تماماً من الرسم.
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: ratio),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, _) => Container(
                        height: 6 + (t * 108),
                        decoration: BoxDecoration(
                          gradient: isPeak
                              ? tokens.brandGradient
                              : LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    context.colors.primary
                                        .withValues(alpha: 0.35),
                                    context.colors.primary
                                        .withValues(alpha: 0.18),
                                  ],
                                ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      d['dayShort'].toString(),
                      style: context.texts.labelSmall
                          ?.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _TopReasons extends StatelessWidget {
  const _TopReasons({required this.reasons});

  final List<Map<String, dynamic>> reasons;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    var total = 0;
    for (final r in reasons) {
      total += r['count'] as int;
    }
    if (total == 0) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < reasons.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.lg),
            _MeterRow(
              label: reasons[i]['reason'].toString(),
              value: (reasons[i]['count'] as int) / total,
              display: '${reasons[i]['count']}',
              // درجات متدرّجة من لون واحد بدل أربعة ألوان عشوائية: القائمة
              // مرتّبة، فالتدرّج يعبّر عن الترتيب بينما الألوان المختلفة تعني
              // فئات مختلفة — وهو معنى خاطئ هنا.
              color: Color.lerp(
                context.colors.primary,
                tokens.textFaint,
                i / (reasons.length + 1),
              )!,
            ),
          ],
        ],
      ),
    );
  }
}
