import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../providers/firebase_auth_service.dart';
import '../providers/rating_provider.dart';
import '../widgets/app_widgets.dart';
import '../widgets/rating_widgets.dart';

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
      AppSnack.error(context, 'يجب اختيار تقييم من 1 إلى 5');
      return;
    }

    if (_commentController.text.trim().isEmpty) {
      AppSnack.error(context, 'يجب إدخال ملاحظتك عن الخدمة');
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

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      AppSnack.success(context, 'تم حفظ تقييمك بنجاح');
      Navigator.pop(context, true);
    } else {
      final provider = context.read<RatingProvider>();
      AppSnack.error(context, provider.errorMessage ?? 'حدث خطأ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AppScaffold(
      title: 'تقييم الطبيب',
      maxWidth: AppBreakpoints.form,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: AppAvatar(
              name: widget.doctorName,
              icon: Icons.medical_services_rounded,
              size: 72,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            widget.doctorName,
            textAlign: TextAlign.center,
            style: context.texts.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'كيف كانت تجربتك؟ تقييمك يساعد باقي المرضى.',
            textAlign: TextAlign.center,
            style: context.texts.bodyMedium?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppCard(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.xl,
              horizontal: AppSpacing.lg,
            ),
            child: InteractiveRatingSelector(
              initialRating: _selectedRating,
              onRatingChanged: (value) =>
                  setState(() => _selectedRating = value),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionTitle(
            title: 'ملاحظاتك عن الخدمة',
            icon: Icons.rate_review_outlined,
          ),
          TextField(
            controller: _commentController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'شارك تجربتك: الخدمة، التعامل، الاحترافية…',
              floatingLabelBehavior: FloatingLabelBehavior.never,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: _isSubmitting ? null : _submitRating,
            child: _isSubmitting
                ? const SizedBox(
                    height: 21,
                    width: 21,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Text('حفظ التقييم'),
          ),
        ],
      ),
    );
  }
}
