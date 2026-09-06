import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/medical_share.dart';
import '../../data/services/medical_share_service.dart';
import 'shared_record_detail_screen.dart';

/// مشاركات المريض — مَن يرى سجلاته، ومتى شارك، وما ألغاه.
///
/// الشاشة هي أداة الرقابة: بلا مكان يرى فيه المريض ما شاركه، تصبح الموافقة
/// قراراً يُتخذ مرة ويُنسى.
class PatientSharesScreen extends StatefulWidget {
  const PatientSharesScreen({
    super.key,
    this.service = const MedicalShareService(),
  });

  final MedicalShareService service;

  @override
  State<PatientSharesScreen> createState() => _PatientSharesScreenState();
}

class _PatientSharesScreenState extends State<PatientSharesScreen> {
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('السجلات المشتركة')),
      body: uid == null
          ? const EmptyView(
              icon: Icons.lock_outline,
              title: 'سجّل الدخول لعرض مشاركاتك',
            )
          : StreamBuilder<List<MedicalShare>>(
              key: ValueKey(_attempt),
              stream: widget.service.watchPatientShares(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorView(
                    message: 'تعذّر تحميل مشاركاتك. تحقّق من اتصالك.',
                    onRetry: () => setState(() => _attempt++),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingView();
                }

                final items = snapshot.data ?? const <MedicalShare>[];
                if (items.isEmpty) {
                  return const EmptyView(
                    icon: Icons.share_outlined,
                    title: 'لم تشارك أي سجل بعد.',
                    message: 'من «السجل الطبي» يمكنك اختيار زيارة ومشاركتها مع '
                        'طبيب تثق به.',
                  );
                }

                return ListView.separated(
                  padding: DrdSpacing.screen,
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: DrdSpacing.sm),
                  itemBuilder: (context, i) => _ShareTile(share: items[i]),
                );
              },
            ),
    );
  }
}

class _ShareTile extends StatelessWidget {
  const _ShareTile({required this.share});

  final MedicalShare share;

  @override
  Widget build(BuildContext context) {
    final created = share.createdAt;

    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SharedRecordDetailScreen(
            shareId: share.id,
            viewer: ShareViewer.patient,
          ),
        ),
      ),
      semanticLabel: 'مشاركة مع ${share.recipientDoctorName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  share.recipientDoctorName.isEmpty
                      ? 'طبيب'
                      : share.recipientDoctorName,
                  style: context.text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              StatusChip.medicalShare(share.status),
            ],
          ),
          if (share.recipientDoctorSpecialization.isNotEmpty) ...[
            const SizedBox(height: DrdSpacing.xxs),
            Text(
              share.recipientDoctorSpecialization,
              style: context.text.bodySmall?.copyWith(color: context.drd.muted),
            ),
          ],
          const SizedBox(height: DrdSpacing.xs),
          Row(
            children: [
              Icon(Icons.description_outlined,
                  size: 14, color: context.drd.muted),
              const SizedBox(width: DrdSpacing.xxs),
              Text(
                '${share.recordCount} سجل',
                style:
                    context.text.bodySmall?.copyWith(color: context.drd.muted),
              ),
              if (created != null) ...[
                const SizedBox(width: DrdSpacing.sm),
                Icon(Icons.event_outlined, size: 14, color: context.drd.muted),
                const SizedBox(width: DrdSpacing.xxs),
                Text(
                  DateFormat('d MMM yyyy', 'ar').format(created),
                  style: context.text.bodySmall
                      ?.copyWith(color: context.drd.muted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
