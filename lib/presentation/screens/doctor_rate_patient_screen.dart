import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/rating_provider.dart';
import '../providers/firebase_auth_service.dart';
import '../../core/theme/app_theme.dart';

/// شاشة تقييم الطبيب للمريض - تقييم الحالة الصحية
class DoctorRatePatientScreen extends StatefulWidget {
  final String appointmentId;
  final String patientId;
  final String patientName;

  const DoctorRatePatientScreen({
    super.key,
    required this.appointmentId,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<DoctorRatePatientScreen> createState() =>
      _DoctorRatePatientScreenState();
}

class _DoctorRatePatientScreenState extends State<DoctorRatePatientScreen> {
  late TextEditingController _commentController;
  int _selectedRating = 0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController();
    _loadExistingRating();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingRating() async {
    final rating = await context
        .read<RatingProvider>()
        .fetchRating(widget.appointmentId, 'doctor_to_patient');

    if (rating != null && mounted) {
      setState(() {
        _selectedRating = rating.healthConditionRating ?? 0;
        _commentController.text = rating.healthConditionComment ?? '';
      });
    }
  }

  Future<void> _submitRating() async {
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب اختيار تقييم من 1 إلى 5')),
      );
      return;
    }

    if (_commentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب إدخال وصف الحالة الصحية')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final auth = context.read<FirebaseAuthService>();
    final success = await context.read<RatingProvider>().ratePatientHealth(
          appointmentId: widget.appointmentId,
          doctorId: auth.userId!,
          patientId: widget.patientId,
          healthRating: _selectedRating,
          healthComment: _commentController.text.trim(),
        );

    setState(() => _isSubmitting = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم حفظ التقييم بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.pop(context, true);
        });
      } else {
        final provider = context.read<RatingProvider>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'حدث خطأ'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقييم المريض'),
        centerTitle: true,
        backgroundColor: AppColors.brand,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // عنوان
            Text(
              'تقييم حالة ${widget.patientName}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 24),

            // تقييم النجوم
            Text(
              'حالتك الصحية:',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  return GestureDetector(
                    onTap: () => setState(() => _selectedRating = index + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        _selectedRating > index
                            ? Icons.star
                            : Icons.star_border,
                        size: 40,
                        color: AppColors.accent,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _selectedRating > 0 ? 'التقييم: $_selectedRating / 5' : '',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // وصف الحالة الصحية
            Text(
              'وصف الحالة الصحية من وجهة نظرك:',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentController,
              maxLines: 5,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'مثال: الحالة مستقرة، الضغط منتظم...',
                hintTextDirection: TextDirection.rtl,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.brand,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // زر الحفظ
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRating,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'حفظ التقييم',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
