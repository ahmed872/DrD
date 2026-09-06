import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firebase_auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/services/account_deletion_service.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('إعداداتي')),
      body: Consumer<FirebaseAuthService>(
        builder: (context, auth, _) {
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // بيانات المريض
                  _buildProfileCard(auth),
                  const SizedBox(height: 24),

                  // زر تعديل/حفظ
                  if (!_isEditing)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() => _isEditing = true),
                        icon: const Icon(Icons.edit),
                        label: const Text('تعديل البيانات'),
                        style: FilledButton.styleFrom(
                          shape: const RoundedRectangleBorder(
                            borderRadius: DrdRadius.mdAll,
                          ),
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _cancelEdit,
                            style: OutlinedButton.styleFrom(
                              shape: const RoundedRectangleBorder(
                                borderRadius: DrdRadius.mdAll,
                              ),
                            ),
                            child: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _isSaving ? null : () => _saveChanges(auth),
                            icon: const Icon(Icons.save),
                            label: _isSaving
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: context.colors.onPrimary,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('حفظ'),
                            style: FilledButton.styleFrom(
                              shape: const RoundedRectangleBorder(
                                borderRadius: DrdRadius.mdAll,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 24),

                  // قسم تسجيل الخروج
                  _buildLogoutSection(auth),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileCard(FirebaseAuthService auth) {
    return Container(
      padding: const EdgeInsets.all(DrdSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.drd.border, width: DrdSizes.hairline),
        borderRadius: DrdRadius.lgAll,
      ),
      child: Column(
        children: [
          // رقم الجوال (غير قابل للتعديل)
          _buildReadOnlyField(
            label: 'رقم الجوال',
            value: auth.userPhone ?? 'غير محدد',
            icon: Icons.phone,
          ),
          const SizedBox(height: 20),

          // الاسم
          _buildEditableField(
            label: 'الاسم الكامل',
            controller: _nameController,
            icon: Icons.person,
            enabled: _isEditing,
          ),
          const SizedBox(height: 20),

          // تاريخ الميلاد
          _buildDateField(),
          const SizedBox(height: 20),

          // الجنس
          _buildGenderSelection(),
        ],
      ),
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.text.bodySmall?.copyWith(
            color: context.drd.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerHigh,
            borderRadius: DrdRadius.smAll,
          ),
          child: Row(
            children: [
              Icon(icon, color: context.drd.muted, size: 20),
              const SizedBox(width: DrdSpacing.sm),
              Text(
                value,
                style: context.text.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool enabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.text.bodySmall?.copyWith(
            color: context.drd.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          decoration: InputDecoration(
            prefixIcon: Icon(icon),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'تاريخ الميلاد',
          style: context.text.bodySmall?.copyWith(
            color: context.drd.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _isEditing
              ? () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _selectedBirthDate ?? DateTime(2000),
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                  );
                  if (pickedDate != null) {
                    setState(() => _selectedBirthDate = pickedDate);
                  }
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHigh,
              borderRadius: DrdRadius.smAll,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      color: context.drd.muted,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _selectedBirthDate != null
                          ? '${_selectedBirthDate!.day}/${_selectedBirthDate!.month}/${_selectedBirthDate!.year}'
                          : 'غير محدد',
                      style: TextStyle(
                        fontSize: 14,
                        color: _selectedBirthDate != null
                            ? context.colors.onSurface
                            : context.drd.disabled,
                      ),
                    ),
                  ],
                ),
                if (_isEditing)
                  Icon(
                    Icons.edit,
                    color: context.drd.muted,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenderSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الجنس',
          style: context.text.bodySmall?.copyWith(
            color: context.drd.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildGenderButton('ذكر', 'male'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGenderButton('أنثى', 'female'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGenderButton(String label, String value) {
    final isSelected = _selectedGender == value;
    return GestureDetector(
      onTap: _isEditing ? () => setState(() => _selectedGender = value) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? context.colors.primary
              : context.colors.surfaceContainerHigh,
          borderRadius: DrdRadius.smAll,
          border: Border.all(
            color: isSelected ? context.colors.primary : context.drd.border,
            width: DrdSizes.hairline,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? context.colors.onPrimary
                : context.colors.onSurface,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutSection(FirebaseAuthService auth) {
    return Container(
      padding: const EdgeInsets.all(DrdSpacing.md),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _logout(auth),
              icon: const Icon(Icons.logout),
              label: const Text('تسجيل الخروج'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.error,
                side: BorderSide(color: context.colors.error),
                shape: const RoundedRectangleBorder(
                  borderRadius: DrdRadius.smAll,
                ),
              ),
            ),
          ),
          const SizedBox(height: DrdSpacing.sm),
          // حذف الحساب — مطلب متجرَي التطبيقات، ومسار لا رجعة فيه.
          // مفصول بصرياً عن الخروج ومكتوب بنبرة أهدأ: زران أحمران متجاوران
          // يجعلان الضغط الخاطئ سهلاً، والخطأ هنا غير قابل للتراجع.
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => _confirmDeleteAccount(auth),
              icon: const Icon(Icons.person_remove_outlined, size: 18),
              label: const Text('حذف الحساب نهائياً'),
              style: TextButton.styleFrom(
                foregroundColor: context.drd.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// تأكيد حذف الحساب.
  ///
  /// يشرح **ما يُحذف وما يبقى** قبل السؤال، لا بعده: السجل السريري يبقى لأن
  /// الزيارة وثيقة تخصّ الطبيب والعيادة أيضاً، ومريض يتوقّع محو كل أثر له
  /// يستحق أن يعرف ذلك قبل الضغط لا بعده.
  void _confirmDeleteAccount(FirebaseAuthService auth) {
    final userId = auth.userId;
    if (userId == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الحساب نهائياً'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سيُحذف:'),
            Text('• بياناتك الشخصية واسمك ورقمك وبريدك'),
            Text('• إمكانية الدخول بهذا الحساب'),
            SizedBox(height: DrdSpacing.sm),
            Text('سيُلغى:'),
            Text('• مواعيدك القادمة'),
            Text('• كل مشاركة طبية أتحتها لطبيب'),
            SizedBox(height: DrdSpacing.sm),
            Text('سيبقى:'),
            Text('• سجلات زياراتك عند الأطباء الذين كشفوا عليك، '
                'فهي جزء من سجل العيادة ولا تُمحى من طرف واحد.'),
            SizedBox(height: DrdSpacing.sm),
            Text('لا يمكن التراجع عن هذا الإجراء.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              // الملّاح يُلتقط **قبل** أي `await`: بعده يكون هذا العنصر قد
              // أُزيل من الشجرة (تسجيل الخروج يعيد بناء الجذر)، فقراءة
              // `context` عندها تقرأ سياقاً ميتاً.
              final navigator = Navigator.of(context);
              Navigator.pop(dialogContext);
              final ok = await AccountDeletionService().requestDeletion(userId);
              if (!mounted) return;
              if (ok) {
                // الخروج فوري: الخادم يحذف حساب المصادقة بعد لحظات، وترك
                // الجلسة مفتوحة يعني شاشات تفشل استعلاماتها واحدة تلو أخرى.
                _showMessage('تم استلام طلب الحذف. سيُغلق حسابك الآن.');
                await auth.logout();
                navigator.pushNamedAndRemoveUntil('/', (route) => false);
              } else {
                _showMessage(
                  'تعذّر إرسال طلب الحذف. تأكد من اتصالك وحاول مرة أخرى.',
                  isError: true,
                );
              }
            },
            child: Text(
              'حذف نهائياً',
              style: TextStyle(color: context.colors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _saveChanges(FirebaseAuthService auth) async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      _showMessage('الاسم مطلوب', isError: true);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final success = await auth.updatePatientProfile(
      name: name,
      gender: _selectedGender,
      birthDate: _selectedBirthDate,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
        if (success) {
          _isEditing = false;
        }
      });
    }

    if (success) {
      _showMessage('تم حفظ البيانات بنجاح ✅');
    } else {
      _showMessage(auth.errorMessage ?? 'حدث خطأ', isError: true);
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

  void _logout(FirebaseAuthService auth) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج من حسابك؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await auth.logout();
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/',
                  (route) => false,
                );
              }
            },
            child: Text(
              'تسجيل الخروج',
              style: TextStyle(color: context.colors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      isError ? AppSnackBar.error(message) : AppSnackBar.success(message),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
