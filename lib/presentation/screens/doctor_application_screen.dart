import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/doctor_application_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/doctor_application.dart';
import '../../data/services/doctor_application_service.dart';
import '../providers/firebase_auth_service.dart';

/// نموذج طلب الانضمام كطبيب.
///
/// النموذج قصير عمداً. كل حقل هنا يجيب عن سؤال يحتاجه المراجع فعلاً ليقرّر،
/// وما لا يُقرَّر به لا يُطلب: لا رفع مستندات ولا أرقام تراخيص ولا صور — تلك
/// تحتاج تخزيناً وسياسة احتفاظ ومسؤولية قانونية لم يُتّخذ فيها قرار بعد.
class DoctorApplicationScreen extends StatefulWidget {
  const DoctorApplicationScreen({super.key, this.existing});

  /// الطلب الحالي إن وُجد — تُملأ منه الحقول عند إعادة التقديم بعد الرفض.
  final DoctorApplication? existing;

  @override
  State<DoctorApplicationScreen> createState() =>
      _DoctorApplicationScreenState();
}

class _DoctorApplicationScreenState extends State<DoctorApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = DoctorApplicationService();

  late final TextEditingController _name;
  late final TextEditingController _specialty;
  late final TextEditingController _bio;
  late final TextEditingController _years;
  late final TextEditingController _notes;

  bool _submitting = false;

  bool get _isResubmission =>
      widget.existing?.status == DoctorApplicationStatus.rejected;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final auth = context.read<FirebaseAuthService>();

    _name = TextEditingController(
      // الاسم يبدأ من الملف الشخصي، ويبقى قابلاً للتعديل: الاسم المهني قد
      // يختلف عن اسم الحساب.
      text: existing?.applicantName.isNotEmpty == true
          ? existing!.applicantName
          : (auth.userName ?? ''),
    );
    _specialty = TextEditingController(text: existing?.specialty ?? '');
    _bio = TextEditingController(text: existing?.professionalBio ?? '');
    _years = TextEditingController(
      text: (existing?.yearsOfExperience ?? 0) > 0
          ? '${existing!.yearsOfExperience}'
          : '',
    );
    _notes = TextEditingController(text: existing?.applicantNotes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _specialty.dispose();
    _bio.dispose();
    _years.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<FirebaseAuthService>();
    final uid = auth.userId;
    if (uid == null) return;

    final confirmed = await _confirm();
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);

    // المُرسِل والمُوجِّه يُلتقطان قبل الانتظار: استعمال `context` بعد فجوة
    // غير متزامنة هو ما يُنتج التحذير، والالتقاط المسبق يحلّه بنيوياً.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final result = await _service.submit(
      uid: uid,
      applicantName: _name.text,
      specialty: _specialty.text,
      professionalBio: _bio.text,
      yearsOfExperience: int.tryParse(_years.text.trim()) ?? 0,
      applicantNotes: _notes.text,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.isSuccess) {
      // النجاح لا يُعرض بالأحمر ولا كتحذير.
      messenger.showSnackBar(AppSnackBar.success(
        'تم إرسال طلبك بنجاح. طلبك الآن قيد المراجعة.',
      ));
      navigator.pop(true);
    } else {
      messenger.showSnackBar(
        AppSnackBar.error(result.message ?? 'تعذّر إرسال الطلب.'),
      );
    }
  }

  /// تأكيد قبل الإرسال.
  ///
  /// الغرض ليس منع الخطأ بل ضبط التوقّع: أن المراجعة بشرية وأن القبول ليس
  /// تلقائياً. طبيب ينتظر تفعيلاً فورياً ثم لا يجده يظن التطبيق معطّلاً.
  Future<bool?> _confirm() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isResubmission ? 'إعادة تقديم الطلب' : 'إرسال الطلب'),
        content: const Text(
          'ستراجع إدارة DrD طلبك قبل تفعيل حساب الطبيب. '
          'لن تتمكّن من تعديل الطلب أثناء المراجعة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isResubmission ? 'تعديل الطلب' : 'طلب الانضمام كطبيب'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: DrdSpacing.screen,
          children: [
            const SizedBox(height: DrdSpacing.md),

            // لماذا نسأل، وماذا يحدث بعد الإرسال — قبل أول حقل، لا بعده.
            const AppBanner.info(
              title: 'لماذا هذه المعلومات؟',
              message:
                  'تراجعها إدارة DrD للتأكد من أن الحساب يخصّ طبيباً فعلاً '
                  'قبل أن يظهر للمرضى ويستقبل الحجوزات. القبول ليس تلقائياً.',
            ),

            if (_isResubmission) ...[
              const SizedBox(height: DrdSpacing.sm),
              AppBanner.warning(
                title: 'سبب الرفض السابق',
                message:
                    widget.existing?.activeRejectionReason ?? 'لم يُسجَّل سبب.',
              ),
            ],

            const SectionHeader(title: 'بياناتك المهنية'),

            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'الاسم كما يظهر للمرضى',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: DoctorApplicationService.validateName,
            ),
            const SizedBox(height: DrdSpacing.sm),

            TextFormField(
              controller: _specialty,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'التخصص',
                hintText: 'مثال: طب الأسرة',
                prefixIcon: Icon(Icons.medical_services_outlined),
              ),
              validator: DoctorApplicationService.validateSpecialty,
            ),
            const SizedBox(height: DrdSpacing.sm),

            TextFormField(
              controller: _years,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'سنوات الخبرة',
                prefixIcon: Icon(Icons.timeline_outlined),
              ),
              validator: DoctorApplicationService.validateYearsOfExperience,
            ),
            const SizedBox(height: DrdSpacing.sm),

            TextFormField(
              controller: _bio,
              maxLines: 5,
              maxLength: DoctorApplicationService.maxBioLength,
              decoration: const InputDecoration(
                labelText: 'نبذة مهنية',
                hintText:
                    'مكان الدراسة، وأين تمارس، وما الحالات التي تتابعها عادةً.',
                alignLabelWithHint: true,
              ),
              validator: DoctorApplicationService.validateBio,
            ),

            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ملاحظات للإدارة (اختياري)',
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: DrdSpacing.lg),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.onPrimary,
                      ),
                    )
                  : Text(_isResubmission ? 'إعادة التقديم' : 'إرسال الطلب'),
            ),
            const SizedBox(height: DrdSpacing.xxl),
          ],
        ),
      ),
    );
  }
}
