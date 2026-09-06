import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/encounter.dart';
import '../../data/services/encounter_service.dart';
import 'encounter_detail_screen.dart';

/// السجل الطبي للمريض — قائمة زياراته الموثَّقة.
///
/// ## ما تغيّر في المرحلة الثالثة
///
/// كانت هذه الشاشة تبني «السجل الطبي» من مستندات **المواعيد**: تقرأ
/// `diagnosis` و`prescription` و`notes` من مستند الحجز نفسه، بقيم بديلة
/// حين تغيب. وكانت تغيب دائماً تقريباً: لا سطر في التطبيق كله كان يكتب
/// `diagnosis` أو `prescription`، فكان المريض يقرأ «لا يوجد تشخيص مسجل»
/// تحت كل زيارة.
///
/// السجل الآن مجموعة مستقلة (`encounters`) يكتبها الطبيب وحده. الفصل ليس
/// ترتيباً: مستند الحجز يكتبه المريض، فخلط بياناته السريرية به كان يجعل
/// الفصل بين ما يملكه كلٌّ منهما فصلاً على مستوى الحقل داخل مستند واحد.
///
/// المواعيد القديمة التي تحمل ملاحظات طبية لا تظهر هنا حتى تُهاجَر —
/// راجع `scripts/README.md`.
class PatientMedicalHistoryScreen extends StatefulWidget {
  const PatientMedicalHistoryScreen({
    super.key,
    this.service = const EncounterService(),
  });

  final EncounterService service;

  @override
  State<PatientMedicalHistoryScreen> createState() =>
      _PatientMedicalHistoryScreenState();
}

class _PatientMedicalHistoryScreenState
    extends State<PatientMedicalHistoryScreen> {
  /// تغييره يعيد بناء `StreamBuilder` باشتراك جديد — وهو ما تعنيه «إعادة
  /// المحاولة» على تدفّق فشل.
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('السجل الطبي')),
      body: uid == null
          ? const EmptyView(
              icon: Icons.lock_outline,
              title: 'سجّل الدخول لعرض سجلك الطبي',
            )
          : StreamBuilder<List<Encounter>>(
              key: ValueKey(_attempt),
              stream: widget.service.watchPatientEncounters(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorView(
                    message: 'تعذّر تحميل سجلك الطبي. تحقّق من اتصالك.',
                    onRetry: () => setState(() => _attempt++),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingView();
                }

                final items = snapshot.data ?? const <Encounter>[];
                if (items.isEmpty) {
                  return const EmptyView(
                    icon: Icons.folder_open_outlined,
                    title: 'لا توجد زيارات مسجلة بعد.',
                    message: 'يظهر هنا ما يوثّقه طبيبك بعد كل زيارة: التشخيص '
                        'والعلاج وتعليمات المتابعة.',
                  );
                }

                return ListView.separated(
                  padding: DrdSpacing.screen,
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: DrdSpacing.sm),
                  itemBuilder: (context, i) =>
                      _EncounterTile(encounter: items[i]),
                );
              },
            ),
    );
  }
}

/// سطر واحد في السجل.
///
/// يعرض ما يكفي للتعرّف على الزيارة: متى، وعند مَن، وبأي تشخيص. النص
/// السريري الكامل في شاشة التفاصيل — قائمة مليئة بفقرات طبية لا تُقرأ.
class _EncounterTile extends StatelessWidget {
  const _EncounterTile({required this.encounter});

  final Encounter encounter;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(encounter.encounterDate);

    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EncounterDetailScreen(encounter: encounter),
        ),
      ),
      semanticLabel: 'زيارة ${encounter.encounterDate}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  encounter.doctorName.isEmpty
                      ? 'الطبيب المعالِج'
                      : encounter.doctorName,
                  style: context.text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                date == null
                    ? encounter.encounterDate
                    : DateFormat('d MMM yyyy', 'ar').format(date),
                style:
                    context.text.bodySmall?.copyWith(color: context.drd.muted),
              ),
            ],
          ),
          const SizedBox(height: DrdSpacing.xxs),
          Text(
            encounter.diagnosis,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodyMedium,
          ),
          if (encounter.followUpDate.isNotEmpty) ...[
            const SizedBox(height: DrdSpacing.xs),
            Row(
              children: [
                Icon(Icons.event_repeat_outlined,
                    size: 14, color: context.colors.primary),
                const SizedBox(width: DrdSpacing.xxs),
                Text(
                  'متابعة: ${encounter.followUpDate}',
                  style: context.text.bodySmall
                      ?.copyWith(color: context.colors.primary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
