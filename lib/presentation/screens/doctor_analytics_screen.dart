import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

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
    'peakDayEn': '-',
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
      if (user == null) return;

      int sessionDur = 30;
      // التقييم من المُجمَّع الذي يكتبه الخادم (`createReview`) لا من حساب
      // محلي على المراجعات: كان معروضاً هنا كرقم ثابت `5.0` مهما كان تقييم
      // الطبيب الحقيقي.
      double avgRating = 0;
      int reviewCount = 0;
      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (docRef.exists) {
        final data = docRef.data();
        sessionDur = data?['sessionDuration'] ?? 30;
        avgRating = (data?['rating'] as num?)?.toDouble() ?? 0;
        reviewCount = (data?['reviews'] as num?)?.toInt() ?? 0;
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

      Map<int, int> weekdayCounts = {
        1: 0,
        2: 0,
        3: 0,
        4: 0,
        5: 0,
        6: 0,
        7: 0
      }; // 1 = Mon... 7 = Sun

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
      weekdayCounts.forEach((day, count) {
        if (count > maxCount) {
          maxCount = count;
          maxDay = day;
        }
      });
      final dayNamesAr = {
        1: 'الإثنين',
        2: 'الثلاثاء',
        3: 'الأربعاء',
        4: 'الخميس',
        5: 'الجمعة',
        6: 'السبت',
        7: 'الأحد'
      };
      final dayNamesEn = {
        1: 'Mon',
        2: 'Tue',
        3: 'Wed',
        4: 'Thu',
        5: 'Fri',
        6: 'Sat',
        7: 'Sun'
      };

      double noShow = total == 0 ? 0.0 : (cancelled / total) * 100;

      var sortedReasons = reasonCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      List<Color> reasonColors = [
        Colors.blueAccent,
        Colors.teal,
        Colors.deepPurple,
        Colors.pink,
        Colors.orange
      ];
      List<Map<String, dynamic>> topR = [];
      for (int i = 0; i < sortedReasons.length && i < 4; i++) {
        topR.add({
          'reason': sortedReasons[i].key,
          'count': sortedReasons[i].value,
          'color': reasonColors[i % reasonColors.length],
        });
      }

      List<Map<String, dynamic>> weekly = [];
      List<int> order = [6, 7, 1, 2, 3, 4, 5];
      for (int day in order) {
        weekly.add({
          'day': dayNamesAr[day]!,
          'dayEn': dayNamesEn[day]!,
          'appointments': weekdayCounts[day] ?? 0,
        });
      }

      setState(() {
        _analyticsData = {
          'totalAppointments': total,
          'completedAppointments': completed,
          'cancelledAppointments': cancelled,
          'totalPatients': uniquePatients.length,
          'newPatients': uniquePatients.length, // approximation
          'avgRating': avgRating,
          'reviewCount': reviewCount,
          'totalRevenue': revenue.toInt(),
          'avgSessionDuration': sessionDur,
          'noShowRate': noShow,
          'peakDay': total > 0 ? dayNamesAr[maxDay] : '-',
          'peakDayEn': total > 0 ? dayNamesEn[maxDay] : '-',
        };
        _weeklyData = weekly;
        _topReasons = topR;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ في جلب البيانات: ${e}')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('الإحصائيات'),
          centerTitle: true,
          backgroundColor: const Color(0xFF0097A7),
          elevation: 1,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإحصائيات'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0097A7),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTimeFilter(),
              const SizedBox(height: 20),
              _buildMetricsGrid(),
              const SizedBox(height: 24),
              _buildPerformanceCard(),
              const SizedBox(height: 24),
              if (_weeklyData.isNotEmpty) _buildWeeklyChart(),
              if (_weeklyData.isNotEmpty) const SizedBox(height: 24),
              if (_topReasons.isNotEmpty) _buildTopReasonsSection(),
              if (_topReasons.isNotEmpty) const SizedBox(height: 24),
              _buildQuickStatsGrid(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _timeFilterChip('هذا الشهر', 0),
          const SizedBox(width: 8),
          _timeFilterChip('آخر 3 شهور', 1),
          const SizedBox(width: 8),
          _timeFilterChip('هذا العام', 2),
        ],
      ),
    );
  }

  Widget _timeFilterChip(String label, int index) {
    final isSelected = _selectedTimeRange == index;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedTimeRange = index);
        _fetchRealAnalytics();
      },
      backgroundColor: Colors.grey[100],
      selectedColor: Colors.blue.shade700,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _metricCard(
          'المواعيد',
          '${_analyticsData["totalAppointments"]}',
          Colors.blue.shade700,
          '📅',
        ),
        _metricCard(
          'مكتملة',
          '${_analyticsData["completedAppointments"]}',
          Colors.green.shade600,
          '✅',
        ),
        _metricCard(
          'المرضى',
          '${_analyticsData["totalPatients"]}',
          Colors.purple.shade600,
          '👥',
        ),
        _metricCard(
          // «لا تقييمات بعد» أصدق من عرض 0 ⭐ لطبيب لم يقيّمه أحد.
          'التقييم',
          (_analyticsData['reviewCount'] ?? 0) == 0
              ? 'لا تقييمات بعد'
              : '${_analyticsData["avgRating"]} ⭐ '
                  '(${_analyticsData["reviewCount"]})',
          Colors.amber.shade700,
          '⭐',
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value, Color color, String emoji) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.5), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceCard() {
    final total = _analyticsData['totalAppointments'] as int;
    final completed = _analyticsData['completedAppointments'] as int;
    final noShowRate = _analyticsData['noShowRate'] as double;

    double compRateValue = total == 0 ? 0.0 : (completed / total);
    String completionRateStr = (compRateValue * 100).toStringAsFixed(1);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الأداء',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${completionRateStr}%',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const Text('نسبة الإتمام',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: compRateValue,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation(Colors.green),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${noShowRate.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const Text('عدم الحضور', style: TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: noShowRate / 100,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation(Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyChart() {
    double maxAppointments = 0;
    for (var d in _weeklyData) {
      if (d['appointments'] > maxAppointments) {
        maxAppointments = (d['appointments'] as int).toDouble();
      }
    }
    if (maxAppointments == 0) maxAppointments = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'المواعيد الأسبوعية',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 240,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _weeklyData.map((data) {
                  final appointments = data['appointments'] as int;
                  final barHeight = appointments == 0
                      ? 5.0
                      : ((appointments / maxAppointments) * 160);

                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          appointments.toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: barHeight,
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.blue.shade700,
                                Colors.blue.shade400,
                              ],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data['dayEn'],
                          style:
                              const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopReasonsSection() {
    int total = 0;
    for (var r in _topReasons) {
      total += r['count'] as int;
    }
    if (total == 0) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'أسباب الاستشارة الشهيرة',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._topReasons.map((reason) {
          final count = reason['count'] as int;
          final percentage = ((count / total) * 100).toStringAsFixed(0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${count}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(reason['reason'],
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: count / total,
                        minHeight: 6,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          reason['color'] as Color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${percentage}%',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildQuickStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _quickStatCard(
          '🕐',
          'متوسط المدة',
          '${_analyticsData["avgSessionDuration"]} دقيقة',
          Colors.blue.shade700,
        ),
        _quickStatCard(
          '💰',
          'الإيرادات',
          '${_analyticsData["totalRevenue"]} جنيه',
          Colors.green.shade600,
        ),
        _quickStatCard(
          '👤',
          'مرضى جدد',
          '${_analyticsData["newPatients"]}',
          Colors.purple.shade600,
        ),
        _quickStatCard(
          '📅',
          'أفضل يوم',
          '${_analyticsData["peakDay"]}',
          Colors.amber.shade700,
        ),
      ],
    );
  }

  Widget _quickStatCard(String emoji, String label, String value, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: color),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
