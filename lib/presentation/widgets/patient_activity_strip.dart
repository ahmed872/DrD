import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../data/services/analytics_service.dart';
import 'app_surfaces.dart';

/// شريط نشاط المريض — أربعة أرقام في بطاقة واحدة.
///
/// عمداً **ليس لوحة تحليلات**: المريض لا يدير عيادة، وما يفيده أن يعرف
/// بسطر واحد كم موعداً له وكم أتمّ. لوحة كاملة هنا كانت ستزاحم القائمة
/// التي جاء من أجلها.
///
/// الأرقام من `getPatientAnalytics` — نطاقها `patientId == uid` على
/// الخادم، فلا صيغة لطلب نشاط مريض آخر.
///
/// يفشل **بصمت**: هذا سياق مساعد لا محتوى الشاشة. رسالة خطأ حمراء فوق
/// قائمة المواعيد تُقلق بلا سبب حين تكون القائمة نفسها معروضة سليمة.
class PatientActivityStrip extends StatefulWidget {
  const PatientActivityStrip({super.key, this.service});

  final AnalyticsService? service;

  @override
  State<PatientActivityStrip> createState() => _PatientActivityStripState();
}

class _PatientActivityStripState extends State<PatientActivityStrip> {
  late final Future<AnalyticsResult> _future;

  @override
  void initState() {
    super.initState();
    _future = (widget.service ?? AnalyticsService())
        .patient(range: AnalyticsRange.month);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AnalyticsResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.hasError ||
            snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final counts = snapshot.data!.counts;
        if (counts.total == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
          child: AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'نشاطك خلال ${snapshot.data!.rangeLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    _Stat(label: 'الكل', value: counts.total),
                    _Stat(label: 'قائمة', value: counts.open),
                    _Stat(label: 'مكتملة', value: counts.completed),
                    _Stat(label: 'ملغاة', value: counts.cancelled),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: theme.textTheme.titleLarge),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
