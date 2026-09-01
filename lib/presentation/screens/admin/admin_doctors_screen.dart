import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../data/services/admin_service.dart';

enum DoctorFilter { pending, active, suspended, rejected }

extension on DoctorFilter {
  String get label => switch (this) {
        DoctorFilter.pending => 'قيد المراجعة',
        DoctorFilter.active => 'نشط',
        DoctorFilter.suspended => 'موقوف',
        DoctorFilter.rejected => 'مرفوض',
      };
}

const _pageSize = 20;

/// إدارة الأطباء: قوائم مقسومة بحالة التوثيق، وإجراءات قبول/رفض/إيقاف/استعادة.
///
/// وظيفية لا نهائية التصميم عمداً — راجع تعليق `AdminHomeScreen`. كل قراءة
/// هنا صفحات محدودة (`limit`) لا مسح كامل للمجموعة، وكل إجراء يمرّ عبر
/// [AdminService] (الدوال السحابية) لا كتابة مباشرة.
class AdminDoctorsScreen extends StatefulWidget {
  const AdminDoctorsScreen(
      {super.key, this.initialFilter = DoctorFilter.pending});

  final DoctorFilter initialFilter;

  @override
  State<AdminDoctorsScreen> createState() => _AdminDoctorsScreenState();
}

class _AdminDoctorsScreenState extends State<AdminDoctorsScreen> {
  final _adminService = AdminService();
  late DoctorFilter _filter;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _loadFirstPage();
  }

  Query<Map<String, dynamic>> _baseQuery(DoctorFilter filter) {
    final db = FirebaseFirestore.instance;
    switch (filter) {
      case DoctorFilter.pending:
      case DoctorFilter.rejected:
        return db
            .collection('doctorApplications')
            .where('status', isEqualTo: filter.name)
            .orderBy('submittedAt', descending: true);
      case DoctorFilter.active:
        return db
            .collection('users')
            .where('role', isEqualTo: 'doctor')
            .where('isVerified', isEqualTo: true)
            .where('disabled', isEqualTo: false);
      case DoctorFilter.suspended:
        return db
            .collection('users')
            .where('role', isEqualTo: 'doctor')
            .where('disabled', isEqualTo: true);
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _docs.clear();
      _lastDoc = null;
      _hasMore = true;
      _isLoading = true;
    });
    await _fetchPage();
  }

  Future<void> _fetchPage() async {
    Query<Map<String, dynamic>> query = _baseQuery(_filter).limit(_pageSize);
    if (_lastDoc != null) query = query.startAfterDocument(_lastDoc!);

    final snapshot = await query.get();
    if (!mounted) return;
    setState(() {
      _docs.addAll(snapshot.docs);
      _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : _lastDoc;
      _hasMore = snapshot.docs.length == _pageSize;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    await _fetchPage();
  }

  void _switchFilter(DoctorFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    _loadFirstPage();
  }

  Future<void> _runAction(Future<AdminActionResult> Function() action) async {
    final result = await action();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.message),
      backgroundColor: result.isSuccess ? Colors.green : Colors.red,
    ));
    if (result.isSuccess) _loadFirstPage();
  }

  Future<String?> _askReason(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          textAlign: TextAlign.right,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'السبب (إلزامي)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  void _openApplicationDetail(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('التخصص: ${data['specialization'] ?? '—'}',
                textAlign: TextAlign.right),
            const SizedBox(height: 8),
            Text('ملاحظات: ${data['note'] ?? '—'}', textAlign: TextAlign.right),
            if (_filter == DoctorFilter.rejected) ...[
              const SizedBox(height: 8),
              Text('سبب الرفض: ${data['rejectionReason'] ?? '—'}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            if (_filter == DoctorFilter.pending) ...[
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _runAction(() => _adminService.approveDoctor(doc.id));
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child:
                    const Text('قبول', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final reason = await _askReason('سبب الرفض');
                  if (reason == null || reason.isEmpty) return;
                  _runAction(() => _adminService.rejectDoctor(doc.id, reason));
                },
                child: const Text('رفض', style: TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openUserDetail(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الاسم: ${data['name'] ?? '—'}', textAlign: TextAlign.right),
            const SizedBox(height: 8),
            Text('التخصص: ${data['specialization'] ?? '—'}',
                textAlign: TextAlign.right),
            if (_filter == DoctorFilter.suspended) ...[
              const SizedBox(height: 8),
              Text('سبب الإيقاف: ${data['suspensionReason'] ?? '—'}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            if (_filter == DoctorFilter.active)
              OutlinedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final reason = await _askReason('سبب الإيقاف');
                  if (reason == null || reason.isEmpty) return;
                  _runAction(() => _adminService.suspendDoctor(doc.id, reason));
                },
                child: const Text('إيقاف', style: TextStyle(color: Colors.red)),
              ),
            if (_filter == DoctorFilter.suspended)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _runAction(() => _adminService.restoreDoctor(doc.id));
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('استعادة',
                    style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الأطباء'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0097A7),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: DoctorFilter.values
                  .map((f) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(f.label),
                          selected: _filter == f,
                          onSelected: (_) => _switchFilter(f),
                        ),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: _docs.isEmpty && !_isLoading
                ? const Center(child: Text('لا يوجد شيء هنا'))
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
                      final isApplication = _filter == DoctorFilter.pending ||
                          _filter == DoctorFilter.rejected;
                      return ListTile(
                        title: Text(
                          isApplication
                              ? (data['specialization'] ?? '—')
                              : (data['name'] ?? '—'),
                          textAlign: TextAlign.right,
                        ),
                        subtitle: Text(doc.id, textAlign: TextAlign.right),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => isApplication
                            ? _openApplicationDetail(doc)
                            : _openUserDetail(doc),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
