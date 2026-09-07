import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/doctor_application_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/doctor_application.dart';
import '../../data/services/doctor_application_service.dart';
import '../providers/firebase_auth_service.dart';
import 'admin_application_detail_screen.dart';

/// طابور مراجعة طلبات الأطباء.
///
/// إخفاء هذه الشاشة عن غير المشرف ليس حماية — الحماية في القواعد، وهي ترفض
/// كل قراءة وكتابة من غير مشرف. الفحص هنا للعرض: ألّا يرى المريض شاشة
/// فارغة برسالة رفض صلاحية.
class AdminApplicationsScreen extends StatefulWidget {
  const AdminApplicationsScreen({super.key});

  @override
  State<AdminApplicationsScreen> createState() =>
      _AdminApplicationsScreenState();
}

class _AdminApplicationsScreenState extends State<AdminApplicationsScreen> {
  final _service = DoctorApplicationService();

  /// `null` = الكل.
  DoctorApplicationStatus? _filter = DoctorApplicationStatus.pending;

  static const _filters = <(String, DoctorApplicationStatus?)>[
    ('قيد المراجعة', DoctorApplicationStatus.pending),
    ('مقبولة', DoctorApplicationStatus.approved),
    ('مرفوضة', DoctorApplicationStatus.rejected),
    ('الكل', null),
  ];

  /// نص الحالة الفارغة — مطابق للمرشِّح، لا رسالة عامة واحدة.
  String get _emptyTitle => switch (_filter) {
        DoctorApplicationStatus.pending => 'لا توجد طلبات قيد المراجعة',
        DoctorApplicationStatus.approved => 'لا توجد طلبات مقبولة',
        DoctorApplicationStatus.rejected => 'لا توجد طلبات مرفوضة',
        _ => 'لا توجد طلبات',
      };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<FirebaseAuthService>();

    if (!auth.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('مراجعة الطلبات')),
        body: const EmptyView(
          icon: Icons.lock_outline,
          title: 'هذه الصفحة لإدارة DrD',
          message: 'لا تملك صلاحية مراجعة طلبات الأطباء.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('مراجعة الطلبات')),
      body: Column(
        children: [
          _FilterBar(
            filters: _filters,
            selected: _filter,
            onSelected: (f) => setState(() => _filter = f),
          ),
          Expanded(
            child: StreamBuilder<List<DoctorApplication>>(
              stream: _service.watchApplications(status: _filter),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorView(
                    message: 'تعذّر تحميل الطلبات. تحقّق من اتصالك.',
                    onRetry: () => setState(() {}),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingView();
                }

                final items = snapshot.data ?? const <DoctorApplication>[];
                if (items.isEmpty) {
                  return EmptyView(
                    icon: Icons.inbox_outlined,
                    title: _emptyTitle,
                    message: 'ستظهر الطلبات هنا فور وصولها.',
                  );
                }

                return ListView.separated(
                  padding: DrdSpacing.screen,
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: DrdSpacing.sm),
                  itemBuilder: (context, i) =>
                      _ApplicationTile(application: items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// شريط المرشِّحات — الحالة المختارة واضحة، لا مجرد لون باهت.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.selected,
    required this.onSelected,
  });

  final List<(String, DoctorApplicationStatus?)> filters;
  final DoctorApplicationStatus? selected;
  final ValueChanged<DoctorApplicationStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: DrdSpacing.md,
        vertical: DrdSpacing.xs,
      ),
      child: Row(
        children: [
          for (final (label, status) in filters) ...[
            ChoiceChip(
              label: Text(label),
              selected: selected == status,
              onSelected: (_) => onSelected(status),
            ),
            const SizedBox(width: DrdSpacing.xs),
          ],
        ],
      ),
    );
  }
}

/// سطر واحد في الطابور.
///
/// يعرض ما يكفي للفرز: مَن، وفي أي تخصص، ومتى، وبأي حالة. تفاصيل الطلب
/// تُقرأ في شاشته — لا تُكدَّس هنا.
class _ApplicationTile extends StatelessWidget {
  const _ApplicationTile({required this.application});

  final DoctorApplication application;

  @override
  Widget build(BuildContext context) {
    final date = application.updatedAt ?? application.submittedAt;

    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AdminApplicationDetailScreen(application: application),
        ),
      ),
      semanticLabel: 'طلب ${application.applicantName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  application.applicantName.isEmpty
                      ? 'مقدّم طلب'
                      : application.applicantName,
                  style: context.text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              StatusChip.doctorApplication(application.status),
            ],
          ),
          const SizedBox(height: DrdSpacing.xxs),
          Text(
            application.specialty,
            style: context.text.bodyMedium
                ?.copyWith(color: context.colors.primary),
          ),
          if (date != null) ...[
            const SizedBox(height: DrdSpacing.xxs),
            Text(
              DateFormat('d MMMM yyyy', 'ar').format(date),
              style: context.text.bodySmall?.copyWith(color: context.drd.muted),
            ),
          ],
        ],
      ),
    );
  }
}
