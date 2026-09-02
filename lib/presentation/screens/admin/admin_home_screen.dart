import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/role_guard.dart';
import 'admin_analytics_screen.dart';
import 'admin_doctors_screen.dart';

/// أساس لوحة الإدارة — عدّادات سريعة وروابط. وظيفية لا تصميماً نهائياً؛
/// راجع `docs/SECURITY.md` قسم «المرحلة 2» للنطاق الكامل.
///
/// الوصول هنا محمي بالفعل من مستوى `HomeScreen` (لا يظهر الرابط إلا
/// لمن يحمل `admin: true`)، لكن هذا **عرض فقط**، لا حماية: كل قراءة أو
/// إجراء هنا يمرّ عبر `firestore.rules`/الدوال السحابية التي تتحقق من
/// الصلاحية من جديد بمعزل عن الواجهة تماماً.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // الزرّ المؤدي إلى هنا مخفي لغير الأدمن، والزرّ المخفي ليس حاجزاً:
    // الحارس يجعل الواجهة متّسقة مع صلاحية الخادم بدل شاشة تفشل استعلاماتها.
    return const RoleGuard(requireAdmin: true, child: _AdminHomeBody());
  }
}

class _AdminHomeBody extends StatelessWidget {
  const _AdminHomeBody();

  @override
  Widget build(BuildContext context) {
    final users = FirebaseFirestore.instance.collection('users');
    final applications =
        FirebaseFirestore.instance.collection('doctorApplications');

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الإدارة'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CountCard(
              title: 'طلبات توثيق قيد الانتظار',
              icon: Icons.pending_actions,
              color: Theme.of(context).colorScheme.secondary,
              countFuture:
                  _countOf(applications.where('status', isEqualTo: 'pending')),
              onTap: () =>
                  _openDoctors(context, initialFilter: DoctorFilter.pending),
            ),
            const SizedBox(height: 12),
            _CountCard(
              title: 'أطباء نشطون',
              icon: Icons.verified,
              color: Theme.of(context).colorScheme.tertiary,
              countFuture: _activeDoctorCount(users),
              onTap: () =>
                  _openDoctors(context, initialFilter: DoctorFilter.active),
            ),
            const SizedBox(height: 12),
            _CountCard(
              title: 'أطباء موقوفون',
              icon: Icons.block,
              color: Theme.of(context).colorScheme.error,
              countFuture: _countOf(users
                  .where('role', isEqualTo: 'doctor')
                  .where('disabled', isEqualTo: true)),
              onTap: () =>
                  _openDoctors(context, initialFilter: DoctorFilter.suspended),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminAnalyticsScreen(),
                ),
              ),
              icon: const Icon(Icons.insights_outlined),
              label: const Text('تحليلات المنصّة'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () =>
                  _openDoctors(context, initialFilter: DoctorFilter.pending),
              icon: const Icon(Icons.list),
              label: const Text('إدارة الأطباء'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDoctors(BuildContext context,
      {required DoctorFilter initialFilter}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminDoctorsScreen(initialFilter: initialFilter),
      ),
    );
  }
}

/// عدد الأطباء النشطين = الموثَّقون ناقص الموقوفون منهم.
///
/// ## لماذا طرحٌ لا شرط ثالث
///
/// كان الاستعلام `where('disabled', isEqualTo: false)`. المساواة في
/// Firestore لا تطابق **غياب** الحقل: مستند بلا `disabled` لا يدخل النتيجة
/// أصلاً. و`disabled` أُضيف في المرحلة 2، ولا `grandfather_doctors.js`
/// يكتبه (يقتصر على `isVerified`) — فكل طبيب أقدم منه، وكل طبيب رُقّي
/// بالسكربت، بلا الحقل. النتيجة: «أطباء نشطون: 0» بينما العيادة تعمل.
/// رُصد فعلياً في مراجعة المرحلة 10 على المحاكي: خمسة أطباء موثَّقين،
/// والعدّاد صفر.
///
/// بقية النظام يعامل غياب الحقل بصوابه — القواعد
/// (`d.get('disabled', false) != true`) و`fetchBookableDoctor`
/// (`disabled === true`) — فكان هذا العدّاد وحده يقرأ الغياب «غير نشط».
///
/// الطرح يعيد الاتساق بلا هجرة بيانات ولا فهرس جديد: الموقوف من يحمل
/// `disabled: true` صراحةً، ومن عداه نشط. استعلاما `count()` تجميعيان،
/// وكلاهما مفهرس أصلاً (`users`: role+isVerified، وrole+isVerified+disabled).
Future<int?> _activeDoctorCount(CollectionReference<Object?> users) async {
  final verified = users
      .where('role', isEqualTo: 'doctor')
      .where('isVerified', isEqualTo: true);
  final all = await verified.count().get();
  final suspended =
      await verified.where('disabled', isEqualTo: true).count().get();
  final active = (all.count ?? 0) - (suspended.count ?? 0);
  return active < 0 ? 0 : active;
}

/// عدّ بسيط لاستعلام تجميعي واحد — يوحّد نوع ما تعرضه البطاقة.
Future<int?> _countOf(Query<Object?> query) async =>
    (await query.count().get()).count;

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.countFuture,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Future<int?> countFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.onPrimary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              FutureBuilder<int?>(
                future: countFuture,
                builder: (context, snapshot) {
                  final count = snapshot.data;
                  return Text(
                    count?.toString() ?? '—',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: color),
                  );
                },
              ),
              const SizedBox(width: 16),
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
