import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/rating_provider.dart';
import '../providers/firebase_auth_service.dart';

/// شاشة تقييم المريض للطبيب - تقييم جودة الخدمة
class PatientRateDoctorScreen extends StatefulWidget {
  final String appointmentId;
  final String doctorId;
  final String doctorName;

  const PatientRateDoctorScreen({
    super.key,
    required this.appointmentId,
    required this.doctorId,
    required this.doctorName,
  });

  @override
  State<PatientRateDoctorScreen> createState() =>
      _PatientRateDoctorScreenState();
}

class _PatientRateDoctorScreenState extends State<PatientRateDoctorScreen> {
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
        .fetchRating(widget.appointmentId, 'patient_to_doctor');

    if (rating != null && mounted) {
      setState(() {
        _selectedRating = rating.serviceRating ?? 0;
        _commentController.text = rating.serviceComment ?? '';
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
        const SnackBar(content: Text('يجب إدخال ملاحظتك عن الخدمة')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final auth = context.read<FirebaseAuthService>();
    final success = await context.read<RatingProvider>().rateDoctorService(
          appointmentId: widget.appointmentId,
          patientId: auth.userId!,
          doctorId: widget.doctorId,
          serviceRating: _selectedRating,
          serviceComment: _commentController.text.trim(),
        );

    setState(() => _isSubmitting = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم حفظ تقييمك بنجاح'),
            backgroundColor: Colors.green,
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
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقييم الطبيب'),
        centerTitle: true,
        backgroundColor: Colors.green,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // عنوان
            Text(
              'تقييمك للدكتور ${widget.doctorName}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 24),

            // تقييم النجوم
            Text(
              'جودة الخدمة:',
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
                        color: Colors.amber,
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

            // ملاحظات المريض
            Text(
              'ملاحظاتك عن الخدمة:',
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
                hintText: 'شارك تجربتك - الخدمة، التعامل، الاحترافية، ...',
                hintTextDirection: TextDirection.rtl,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Colors.green,
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
                  backgroundColor: Colors.green,
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
