import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/app_widgets.dart';

import '../../core/utils/app_logger.dart';
import '../providers/firebase_auth_service.dart';

/// التقدّم لتصبح طبيباً — يكتب طلباً في `doctorApplications/{uid}` مباشرة
/// (تحكمها `firestore.rules`)، ولا يمنح أي صلاحية طبيب بذاته. الإدارة وحدها
/// تقرّر عبر `approveDoctor`/`rejectDoctor` — راجع `functions/admin.js`.
class DoctorApplicationScreen extends StatefulWidget {
  const DoctorApplicationScreen({super.key});

  @override
  State<DoctorApplicationScreen> createState() =>
      _DoctorApplicationScreenState();
}

class _DoctorApplicationScreenState extends State<DoctorApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _specializationController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _specializationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit(String uid, {required bool isResubmit}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final ref =
          FirebaseFirestore.instance.collection('doctorApplications').doc(uid);
      final data = {
        'uid': uid,
        'status': 'pending',
        'specialization': _specializationController.text.trim(),
        'note': _noteController.text.trim(),
        'submittedAt': FieldValue.serverTimestamp(),
      };

      if (isResubmit) {
        await ref.update(data);
      } else {
        await ref.set(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم إرسال طلبك، سيراجعه فريق DrD قريباً'),
          backgroundColor: Theme.of(context).colorScheme.tertiary,
        ));
        setState(() {});
      }
    } catch (e, s) {
      AppLogger.error('فشل إرسال طلب التوثيق', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('تعذّر إرسال الطلب، حاول مرة أخرى'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<FirebaseAuthService>(context, listen: false);
    final uid = auth.userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('التقدّم كطبيب'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: uid == null
          ? const Center(child: Text('يجب تسجيل الدخول'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('doctorApplications')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                // بدون هذا الفرع يسقط خطأ البثّ (صلاحية مرفوضة، انقطاع
                // شبكة) إلى `status == null`، فيُعرض للطبيب نموذج فارغ كأنه
                // لم يتقدّم قط — فيعيد الإرسال فوق طلب قائم.
                if (snapshot.hasError) {
                  return ErrorStateView(
                    message: 'تعذّر عرض حالة طلبك الآن. تحقّق من اتصالك '
                        'وأعد المحاولة.',
                    onRetry: () => setState(() {}),
                  );
                }

                final data = snapshot.data?.data();
                final status = data?['status'] as String?;

                if (status == 'pending') return _buildPendingView(data!);
                if (status == 'approved') return _buildApprovedView();
                if (status == 'rejected') {
                  return _buildForm(uid, isResubmit: true, rejected: data);
                }
                return _buildForm(uid, isResubmit: false, rejected: null);
              },
            ),
    );
  }

  Widget _buildPendingView(Map<String, dynamic> data) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.hourglass_top,
              size: 56, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 16),
          const Text('طلبك قيد المراجعة',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'سيصلك تحديث بمجرد أن يراجع فريق DrD طلبك.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _readOnlyField('التخصص', data['specialization'] ?? ''),
          if ((data['note'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            _readOnlyField('ملاحظات', data['note']),
          ],
        ],
      ),
    );
  }

  Widget _buildApprovedView() {
    return Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle,
              size: 56, color: Theme.of(context).colorScheme.tertiary),
          SizedBox(height: 16),
          Text('تم قبولك كطبيب في DrD',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(
            'أعد تسجيل الدخول إن لم تظهر لوحة الطبيب بعد.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyField(String label, String value) {
    return Align(
      // اتجاهي: «البداية» تصير اليمين في العربية واليسار لو تُرجم التطبيق.
      alignment: AlignmentDirectional.centerStart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildForm(
    String uid, {
    required bool isResubmit,
    required Map<String, dynamic>? rejected,
  }) {
    if (isResubmit && _specializationController.text.isEmpty) {
      _specializationController.text = rejected?['specialization'] ?? '';
      _noteController.text = rejected?['note'] ?? '';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rejected != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Theme.of(context).colorScheme.error),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('طلبك السابق رُفض',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 6),
                    Text(rejected['rejectionReason'] ?? '—',
                        textAlign: TextAlign.right),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text(
              'قدّم طلباً ليراجعه فريق DrD. لا يمنحك هذا صلاحية طبيب فوراً.',
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _specializationController,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'التخصص',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'التخصص مطلوب' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteController,
              textAlign: TextAlign.right,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                hintText: 'رقم الترخيص، سنوات الخبرة، أي معلومة تفيد المراجعة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSubmitting
                  ? null
                  : () => _submit(uid, isResubmit: isResubmit),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isSubmitting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.onPrimary,
                          strokeWidth: 2))
                  : Text(isResubmit ? 'إعادة التقديم' : 'إرسال الطلب',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}
