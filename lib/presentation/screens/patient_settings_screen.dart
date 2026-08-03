import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/app_widgets.dart';

class PatientSettingsScreen extends StatefulWidget {
  const PatientSettingsScreen({super.key});

  @override
  State<PatientSettingsScreen> createState() => _PatientSettingsScreenState();
}

class _PatientSettingsScreenState extends State<PatientSettingsScreen> {
  late TextEditingController _nameController;
  DateTime? _selectedBirthDate;
  String _selectedGender = 'male';
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<FirebaseAuthService>();
    _nameController = TextEditingController(text: auth.userName);
    _selectedBirthDate = auth.userBirthDate;
    _selectedGender = auth.userGender ?? 'male';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FirebaseAuthService>(
      builder: (context, auth, _) {
        return AppScaffold(
          title: 'إعداداتي',
          maxWidth: AppBreakpoints.form,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          actions: [
            if (!_isEditing)
              IconButton(
                onPressed: () => setState(() => _isEditing = true),
                icon: const Icon(Icons.edit_outlined),
                color: Colors.white,
                tooltip: 'تعديل البيانات',
              ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildIdentityCard(auth),
              const SizedBox(height: AppSpacing.xl),
              const SectionTitle(
                title: 'بياناتي',
                icon: Icons.badge_outlined,
              ),
              _buildFormCard(auth),
              const SizedBox(height: AppSpacing.xl),
              if (_isEditing) _buildEditActions(auth),
              const SizedBox(height: AppSpacing.xl),
              const SectionTitle(
                title: 'الحساب',
                icon: Icons.shield_outlined,
              ),
              _buildLogoutCard(auth),
            ],
          ),
        );
      },
    );
  }

  /// بطاقة الهوية أعلى الشاشة: الاسم والصورة الرمزية ورقم الجوال في مكان
  /// واحد، بدل أن يكون الرقم حقلاً معطّلاً وسط النموذج.
  Widget _buildIdentityCard(FirebaseAuthService auth) {
    final tokens = context.tokens;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          AppAvatar(name: auth.userName, size: 74),
          const SizedBox(height: AppSpacing.lg),
          Text(
            auth.userName ?? 'المستخدم',
            textAlign: TextAlign.center,
            style: context.texts.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            auth.userPhone ?? 'بدون رقم',
            textDirection: TextDirection.ltr,
            style: context.texts.bodyMedium?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          StatusPill(
            label: 'حساب مريض',
            color: tokens.success,
            icon: Icons.verified_user_rounded,
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(FirebaseAuthService auth) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _nameController,
            label: 'الاسم الكامل',
            icon: Icons.person_outline_rounded,
            enabled: _isEditing,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildDateField(),
          const SizedBox(height: AppSpacing.lg),
          _buildGenderSelection(),
        ],
      ),
    );
  }

  Widget _buildDateField() {
    final tokens = context.tokens;
    final hasDate = _selectedBirthDate != null;

    return InkWell(
      onTap: _isEditing ? _pickBirthDate : null,
      borderRadius: AppRadius.rMd,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'تاريخ الميلاد',
          prefixIcon: const Icon(Icons.cake_outlined, size: 20),
          suffixIcon: _isEditing
              ? Icon(Icons.edit_calendar_outlined, color: tokens.textMuted)
              : null,
          enabled: _isEditing,
        ),
        child: Text(
          hasDate
              ? '${_selectedBirthDate!.day}/${_selectedBirthDate!.month}/'
                  '${_selectedBirthDate!.year}'
              : 'غير محدد',
          style: context.texts.bodyLarge?.copyWith(
            color: hasDate ? tokens.textStrong : tokens.textFaint,
          ),
        ),
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthDate ?? DateTime(2000),
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
      helpText: 'اختر تاريخ ميلادك',
    );
    if (picked != null) setState(() => _selectedBirthDate = picked);
  }

  Widget _buildGenderSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الجنس', style: context.texts.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _genderTile('ذكر', 'male', Icons.man_rounded),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _genderTile('أنثى', 'female', Icons.woman_rounded),
            ),
          ],
        ),
      ],
    );
  }

  Widget _genderTile(String label, String value, IconData icon) {
    final tokens = context.tokens;
    final selected = _selectedGender == value;
    final primary = context.colors.primary;

    return Material(
      color: selected ? primary.withValues(alpha: 0.08) : tokens.surfaceSunken,
      borderRadius: AppRadius.rMd,
      child: InkWell(
        onTap:
            _isEditing ? () => setState(() => _selectedGender = value) : null,
        borderRadius: AppRadius.rMd,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rMd,
            border: Border.all(
              color: selected ? primary : tokens.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? primary
                    : (_isEditing ? tokens.textMuted : tokens.textFaint),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: context.texts.labelMedium?.copyWith(
                  color: selected
                      ? primary
                      : (_isEditing ? tokens.textBody : tokens.textFaint),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditActions(FirebaseAuthService auth) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isSaving ? null : _cancelEdit,
            child: const Text('إلغاء'),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: FilledButton.icon(
            onPressed: _isSaving ? null : () => _saveChanges(auth),
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_isSaving ? 'جارٍ الحفظ' : 'حفظ'),
          ),
        ),
      ],
    );
  }

  Widget _buildLogoutCard(FirebaseAuthService auth) {
    final tokens = context.tokens;

    return AppCard(
      onTap: () => _logout(auth),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.dangerSoft,
              borderRadius: AppRadius.rMd,
            ),
            child: Icon(Icons.logout_rounded, color: tokens.danger, size: 21),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تسجيل الخروج',
                  style: context.texts.titleSmall?.copyWith(
                    color: tokens.danger,
                  ),
                ),
                Text(
                  'ستحتاج لإدخال رقمك وكلمة المرور مرة أخرى',
                  style: context.texts.bodySmall
                      ?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _saveChanges(FirebaseAuthService auth) async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      AppSnack.error(context, 'الاسم مطلوب');
      return;
    }

    setState(() => _isSaving = true);

    final success = await auth.updatePatientProfile(
      name: name,
      gender: _selectedGender,
      birthDate: _selectedBirthDate,
    );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (success) _isEditing = false;
    });

    if (success) {
      AppSnack.success(context, 'تم حفظ البيانات بنجاح');
    } else {
      AppSnack.error(context, auth.errorMessage ?? 'حدث خطأ أثناء الحفظ');
    }
  }

  void _cancelEdit() {
    final auth = context.read<FirebaseAuthService>();
    setState(() {
      _isEditing = false;
      _nameController.text = auth.userName ?? '';
      _selectedBirthDate = auth.userBirthDate;
      _selectedGender = auth.userGender ?? 'male';
    });
  }

  Future<void> _logout(FirebaseAuthService auth) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'تسجيل الخروج',
      message: 'هل تريد تسجيل الخروج من حسابك؟',
      confirmLabel: 'تسجيل الخروج',
      destructive: true,
      icon: Icons.logout_rounded,
    );

    if (!confirmed || !mounted) return;

    final navigator = Navigator.of(context);
    await auth.logout();
    if (!mounted) return;
    navigator.pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
