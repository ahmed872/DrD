import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_logger.dart';
import '../providers/firebase_auth_service.dart';

/// شاشة الإشعارات.
///
/// كانت دالة `checkAppointments` في السحابة تكتب تذكيرات المواعيد في مجموعة
/// `notifications`، لكن لا شيء في التطبيق كان يقرأ منها — فالتذكير الذي
/// يُفترض أنه جوهر التطبيق (اعرف موعدك قبلها بساعة) لم يكن يصل للمريض أبداً.
///
/// هذه الشاشة هي الطرف المستقبِل الناقص.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<FirebaseAuthService>(context, listen: false);
    final userId = auth.userId;

    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: userId == null
          ? const _Empty(message: 'سجّل الدخول لعرض إشعاراتك')
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: notificationsQuery(userId).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  AppLogger.error('تعذّر تحميل الإشعارات', snapshot.error);
                  return const _Empty(
                    icon: Icons.wifi_off,
                    message: 'تعذّر تحميل الإشعارات، تأكد من اتصالك بالإنترنت',
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const _Empty(
                    icon: Icons.notifications_none,
                    message: 'لا توجد إشعارات حتى الآن',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _NotificationTile(doc: docs[i]),
                );
              },
            ),
    );
  }

  /// استعلام إشعارات المستخدم — مشترك بين الشاشة وشارة العدّاد.
  static Query<Map<String, dynamic>> notificationsQuery(String userId) {
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50);
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final isRead = data['read'] == true;
    final type = data['type']?.toString() ?? '';

    final isWarning = type == 'appointment_missed';
    final color = isWarning ? AppColors.warning : AppColors.primary;

    return Card(
      // غير المقروء يُميَّز بلون خفيف بدل نقطة صغيرة — أوضح للقراءة السريعة.
      color: isRead ? null : color.withValues(alpha: 0.06),
      child: ListTile(
        onTap: isRead ? null : () => _markAsRead(),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(
            isWarning ? Icons.warning_amber_rounded : Icons.event_available,
            color: color,
          ),
        ),
        title: Text(
          data['title']?.toString() ?? 'إشعار',
          style: TextStyle(
            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
            fontSize: 15,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(data['body']?.toString() ?? '',
                style: const TextStyle(height: 1.5)),
            const SizedBox(height: 6),
            Text(
              _formatDate(data['createdAt']),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  Future<void> _markAsRead() async {
    try {
      // قواعد الأمان تسمح للمستلم بتعديل حقل `read` وحده.
      await doc.reference.update({'read': true});
    } catch (e) {
      AppLogger.warning('تعذّر تعليم الإشعار كمقروء: $e');
    }
  }

  String _formatDate(Object? raw) {
    if (raw is! Timestamp) return '';
    final date = raw.toDate();
    final diff = DateTime.now().difference(date);

    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays == 1) return 'أمس';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} أيام';
    return DateFormat('yyyy/MM/dd', 'ar').format(date);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({this.icon = Icons.notifications_none, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

/// أيقونة جرس مع شارة عدد غير المقروء، تُوضع في شريط التطبيق.
class NotificationsBell extends StatelessWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<FirebaseAuthService>(context);
    final userId = auth.userId;

    if (userId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'الإشعارات',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationsScreen(),
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                top: 8,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 17),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  child: Text(
                    // ما فوق التسعة يُعرض «+٩» حتى لا تتمدّد الشارة.
                    count > 9 ? '+9' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
