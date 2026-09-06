import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/encounter.dart';
import '../../data/services/encounter_service.dart';
import 'encounter_detail_screen.dart';
import 'share_records_screen.dart';

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

  /// وضع الاختيار للمشاركة.
  ///
  /// منفصل عن التصفّح عمداً: مشاركة سجل طبي قرار، ولا يجب أن يقع بنقرة
  /// واحدة على بطاقة يظنّها المريض فتحاً للتفاصيل.
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _share(List<Encounter> all) async {
    final chosen =
        all.where((e) => _selected.contains(e.id)).toList(growable: false);
    if (chosen.isEmpty) return;

    final auth = FirebaseAuth.instance.currentUser;
    if (auth == null) return;

    final shared = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ShareRecordsScreen(
          patientId: auth.uid,
          patientName: auth.displayName ?? '',
          encounters: chosen,
        ),
      ),
    );
    if (shared == true) _exitSelection();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? 'اختر سجلات للمشاركة' : 'السجل الطبي'),
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'إلغاء الاختيار',
                onPressed: _exitSelection,
              )
            : null,
      ),
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

                return Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: DrdSpacing.screen,
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: DrdSpacing.sm),
                        itemBuilder: (context, i) => _EncounterTile(
                          encounter: items[i],
                          selecting: _selecting,
                          selected: _selected.contains(items[i].id),
                          onToggle: () => setState(() {
                            final id = items[i].id;
                            if (!_selected.add(id)) _selected.remove(id);
                          }),
                          onStartSelection: () => setState(() {
                            _selecting = true;
                            _selected.add(items[i].id);
                          }),
                        ),
                      ),
                    ),
                    _ShareBar(
                      selecting: _selecting,
                      count: _selected.length,
                      onShare: () => _share(items),
                      onStart: () => setState(() => _selecting = true),
                    ),
                  ],
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
  const _EncounterTile({
    required this.encounter,
    this.selecting = false,
    this.selected = false,
    this.onToggle,
    this.onStartSelection,
  });

  final Encounter encounter;
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggle;
  final VoidCallback? onStartSelection;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(encounter.encounterDate);

    return AppCard(
      onTap: selecting
          ? onToggle
          : () => Navigator.push(
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
              if (selecting) ...[
                Icon(
                  selected
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  color: selected ? context.colors.primary : context.drd.muted,
                  size: 20,
                ),
                const SizedBox(width: DrdSpacing.xs),
              ],
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

/// شريط المشاركة أسفل القائمة.
///
/// يظهر مدخل المشاركة بلا أن يزاحم القراءة: من يفتح سجله الطبي يفتحه ليقرأ
/// غالباً، لا ليشارك.
class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.selecting,
    required this.count,
    required this.onShare,
    required this.onStart,
  });

  final bool selecting;
  final int count;
  final VoidCallback onShare;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DrdSpacing.md,
          DrdSpacing.xs,
          DrdSpacing.md,
          DrdSpacing.md,
        ),
        child: selecting
            ? FilledButton.icon(
                onPressed: count == 0 ? null : onShare,
                icon: const Icon(Icons.share_outlined),
                label: Text(
                  count == 0
                      ? 'اختر سجلاً واحداً على الأقل'
                      : 'مشاركة $count من السجلات',
                ),
              )
            : OutlinedButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.share_outlined),
                label: const Text('مشاركة سجلات مع طبيب'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(DrdSizes.touchTarget),
                ),
              ),
      ),
    );
  }
}
