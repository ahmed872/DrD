import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/medical_share.dart';
import '../../data/services/medical_share_service.dart';
import '../providers/firebase_auth_service.dart';
import 'shared_record_detail_screen.dart';

/// صندوق الطبيب: السجلات التي شاركها معه المرضى.
///
/// **ليست سجلات ألّفها هو.** الفرق مهم منتَجياً وقانونياً: ما هنا نسخة
/// شاركها مريض من كشف طبيب آخر، والواجهة تقول ذلك صراحةً حتى لا تُقرأ
/// كسجلّ من عيادته.
///
/// الاستعلام مقيَّد بـ `status == 'active'` لأن قاعدة الأمان تشترطه —
/// استعلام بدونه يُرفض كاملاً. ولذلك يختفي المشترَك الملغى فوراً، لا لأن
/// الواجهة أخفته.
class DoctorSharedRecordsScreen extends StatefulWidget {
  const DoctorSharedRecordsScreen({
    super.key,
    this.service = const MedicalShareService(),
  });

  final MedicalShareService service;

  @override
  State<DoctorSharedRecordsScreen> createState() =>
      _DoctorSharedRecordsScreenState();
}

class _DoctorSharedRecordsScreenState extends State<DoctorSharedRecordsScreen> {
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<FirebaseAuthService>().userId;

    return Scaffold(
      appBar: AppBar(title: const Text('السجلات المشتركة معك')),
      body: uid == null
          ? const EmptyView(
              icon: Icons.lock_outline,
              title: 'سجّل الدخول لعرض السجلات المشتركة',
            )
          : StreamBuilder<List<MedicalShare>>(
              key: ValueKey(_attempt),
              stream: widget.service.watchDoctorInbox(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorView(
                    message: 'تعذّر تحميل السجلات المشتركة. تحقّق من اتصالك.',
                    onRetry: () => setState(() => _attempt++),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingView();
                }

                final items = snapshot.data ?? const <MedicalShare>[];
                if (items.isEmpty) {
                  return const EmptyView(
                    icon: Icons.inbox_outlined,
                    title: 'لا توجد سجلات مشتركة معك',
                    message:
                        'حين يشارك مريض سجلاً معك، سيظهر هنا. المشاركة تبدأ '
                        'من المريض وحده.',
                  );
                }

                return ListView.separated(
                  padding: DrdSpacing.screen,
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: DrdSpacing.sm),
                  itemBuilder: (context, i) => _InboxTile(share: items[i]),
                );
              },
            ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.share});

  final MedicalShare share;

  @override
  Widget build(BuildContext context) {
    final created = share.createdAt;
    final first = share.snapshots.isNotEmpty ? share.snapshots.first : null;

    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SharedRecordDetailScreen(
            shareId: share.id,
            viewer: ShareViewer.doctor,
          ),
        ),
      ),
      semanticLabel: 'سجل شاركه ${share.patientName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, size: 20, color: context.drd.muted),
              const SizedBox(width: DrdSpacing.xs),
              Expanded(
                child: Text(
                  share.patientName.isEmpty ? 'مريض' : share.patientName,
                  style: context.text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (created != null)
                Text(
                  DateFormat('d MMM yyyy', 'ar').format(created),
                  style: context.text.bodySmall
                      ?.copyWith(color: context.drd.muted),
                ),
            ],
          ),
          const SizedBox(height: DrdSpacing.xxs),
          // تمييز صريح: نسخة شاركها المريض، لا كشف من عيادة القارئ.
          Text(
            'شاركها المريض معك',
            style: context.text.bodySmall?.copyWith(color: context.drd.muted),
          ),
          if (first != null) ...[
            const SizedBox(height: DrdSpacing.xs),
            Text(
              first.diagnosis,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium,
            ),
          ],
          if (share.recordCount > 1) ...[
            const SizedBox(height: DrdSpacing.xxs),
            Text(
              'و${share.recordCount - 1} سجل آخر',
              style: context.text.bodySmall
                  ?.copyWith(color: context.colors.primary),
            ),
          ],
        ],
      ),
    );
  }
}
