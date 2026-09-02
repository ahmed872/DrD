import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/notification_types.dart';
import '../../core/utils/app_logger.dart';
import '../providers/firebase_auth_service.dart';
import 'doctor_schedule_screen.dart';
import 'patient_my_appointments_screen.dart';

const _pageSize = 20;

/// قائمة إشعارات المستخدم — مقسومة صفحات، بلا كتابة عميل لأي حقل غير
/// `isRead`/`readAt` (`firestore.rules` ترفض غير ذلك أصلاً).
///
/// نفس الشاشة تخدم المريض والطبيب: الاستعلام محصور بـ `recipientId` فقط،
/// والفرق الوحيد بينهما هو وجهة الضغط على إشعار — راجع [_openAppointments].
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;

  // معرّفات وُضعت مقروءة محلياً — الاعتماد على `doc.data()['isRead']` وحده
  // يتطلب إعادة قراءة الصفحة من الخادم لتنعكس فوراً في الواجهة؛ هذه
  // المجموعة تعكسها بلا استعلام إضافي.
  final Set<String> _locallyRead = {};

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  String? get _uid =>
      Provider.of<FirebaseAuthService>(context, listen: false).userId;

  Query<Map<String, dynamic>> _baseQuery(String uid) {
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('recipientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true);
  }

  Future<void> _loadFirstPage() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() {
      _docs.clear();
      _lastDoc = null;
      _hasMore = true;
      _isLoading = true;
    });
    await _fetchPage(uid);
  }

  Future<void> _fetchPage(String uid) async {
    try {
      Query<Map<String, dynamic>> query = _baseQuery(uid).limit(_pageSize);
      if (_lastDoc != null) query = query.startAfterDocument(_lastDoc!);

      final snapshot = await query.get();
      if (!mounted) return;
      setState(() {
        _docs.addAll(snapshot.docs);
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : _lastDoc;
        _hasMore = snapshot.docs.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('تعذّر تحميل الإشعارات', e);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    final uid = _uid;
    if (uid == null || _isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    await _fetchPage(uid);
  }

  Future<void> _markRead(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    if (doc.data()['isRead'] == true || _locallyRead.contains(doc.id)) return;
    try {
      // الحقلان المسموح بتعديلهما فقط — راجع `firestore.rules`:
      // notifications.allow update: changedKeys().hasOnly(['read','isRead','readAt']).
      await doc.reference.update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _locallyRead.add(doc.id));
    } catch (e) {
      AppLogger.error('تعذّر وضع علامة مقروء على الإشعار', e);
    }
  }

  /// وجهة الضغط على إشعار مرتبط بموعد — محدَّدة بنوع الإشعار القانوني
  /// (`NotificationType`) لا بدور المستخدم المخزَّن محلياً، فتبقى صحيحة حتى
  /// لو اختلف الدور المعروض في الجلسة عن المتوقَّع.
  void _openAppointments(String type) {
    final isPatientNotification = NotificationType.patientTypes.contains(type);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isPatientNotification
            ? const PatientMyAppointmentsScreen()
            : const DoctorScheduleScreen(),
      ),
    );
  }

  String _formatTime(dynamic createdAt) {
    if (createdAt is Timestamp) {
      return DateFormat('yyyy-MM-dd HH:mm').format(createdAt.toDate());
    }
    return '';
  }

  IconData _iconFor(String type) {
    switch (type) {
      case NotificationType.bookingConfirmed:
      case NotificationType.newAppointment:
        return Icons.event_available;
      case NotificationType.bookingCancelled:
      case NotificationType.appointmentCancelled:
        return Icons.event_busy;
      case NotificationType.bookingRescheduled:
      case NotificationType.appointmentRescheduled:
        return Icons.event_repeat;
      case NotificationType.reminder24h:
      case NotificationType.reminder2h:
      case NotificationType.doctorReminder:
        return Icons.alarm;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: _docs.isEmpty && !_isLoading
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('لا توجد إشعارات حتى الآن')),
                ],
              )
            : ListView.builder(
                itemCount: _docs.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _docs.length) {
                    _loadMore();
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final doc = _docs[index];
                  final data = doc.data();
                  final isRead =
                      data['isRead'] == true || _locallyRead.contains(doc.id);
                  final type = data['type'] as String? ?? '';

                  return Container(
                    // غير المقروء يُبرز بحاوية النسق لا بلون فيروزي ثابت
                    // كان يبقى فاتحاً في الوضع الليلي فيبتلع النص.
                    color: isRead
                        ? null
                        : Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      leading: Icon(_iconFor(type),
                          color: Theme.of(context).colorScheme.primary),
                      title: Text(
                        data['title'] as String? ?? '',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight:
                              isRead ? FontWeight.normal : FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(data['body'] as String? ?? '',
                              textAlign: TextAlign.right),
                          const SizedBox(height: 2),
                          Text(_formatTime(data['createdAt']),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ],
                      ),
                      isThreeLine: true,
                      onTap: () {
                        _markRead(doc);
                        if (data['appointmentId'] != null) {
                          _openAppointments(type);
                        }
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
