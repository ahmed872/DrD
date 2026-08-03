import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../providers/firebase_auth_service.dart';
import '../providers/rating_provider.dart';
import '../widgets/app_widgets.dart';
import '../widgets/rating_widgets.dart';

/// شاشة تقييم الطبيب لحالة المريض الصحية
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
      AppSnack.error(context, 'يجب اختيار تقييم من 1 إلى 5');
      return;
    }

    if (_commentController.text.trim().isEmpty) {
      AppSnack.error(context, 'يجب إدخال وصف الحالة الصحية');
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

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      AppSnack.success(context, 'تم حفظ التقييم بنجاح');
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
      title: 'تقييم الحالة الصحية',
      maxWidth: AppBreakpoints.form,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: AppAvatar(name: widget.patientName, size: 72)),
          const SizedBox(height: AppSpacing.lg),
          Text(
            widget.patientName,
            textAlign: TextAlign.center,
            style: context.texts.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'قيّم الحالة الصحية العامة للمريض بعد الكشف.',
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
            title: 'وصف الحالة الصحية',
            icon: Icons.medical_information_outlined,
          ),
          TextField(
            controller: _commentController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'الأعراض، التشخيص، والتوصيات…',
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
