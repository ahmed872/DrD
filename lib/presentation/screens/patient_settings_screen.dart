import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/legal_config.dart';
import '../../core/theme/app_spacing.dart';
import '../widgets/app_surfaces.dart';
import '../../data/services/account_service.dart';
import '../providers/firebase_auth_service.dart';

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
  bool _isDeleting = false;

  final AccountService _accountService = AccountService();

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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      appBar: AppBar(
        title: const Text('إعداداتي'),
        elevation: 1,
      ),
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _cancelEdit(),
                            style: ElevatedButton.styleFrom(
                              // زرّ ثانوي: سطح محايد ونصّ عليه. بلا
                              // `foregroundColor` يجعل Material 3 النصّ
                              // بلون primary فوق رمادي باهت.
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onSurface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'إلغاء',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('حفظ'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 24),

                  // المستندات القانونية — تظهر حين تُنشر (راجع LegalConfig).
                  _buildLegalSection(),

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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onPrimary,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant, width: 1),
        borderRadius: BorderRadius.circular(12),
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
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20),
              const SizedBox(width: 12),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          decoration: InputDecoration(
            prefixIcon:
                Icon(icon, color: Theme.of(context).colorScheme.primary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            filled: true,
            fillColor: enabled
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
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
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              color: _isEditing
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      color: Theme.of(context).colorScheme.primary,
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
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (_isEditing)
                  Icon(
                    Icons.edit,
                    color: Theme.of(context).colorScheme.outline,
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
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onPrimary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  /// مدخل سياسة الخصوصية — يظهر حين تُنشر وحدها.
  ///
  /// راجع `LegalConfig`: رابط فارغ يعني أن السياسة لم تُنشر بعد، فلا
  /// يُعرض مدخل يوحي بوجودها.
  Widget _buildLegalSection() {
    if (!LegalConfig.hasPrivacyPolicy && !LegalConfig.hasTermsOfService) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        if (LegalConfig.hasPrivacyPolicy)
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('سياسة الخصوصية'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openLegalLink(LegalConfig.privacyPolicyUrl),
          ),
        if (LegalConfig.hasTermsOfService)
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('شروط الاستخدام'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openLegalLink(LegalConfig.termsOfServiceUrl),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _openLegalLink(String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      _showMessage('تعذّر فتح الرابط', isError: true);
    }
  }

  /// إجراءات الحساب.
  ///
  /// ## المرحلة 11: الأحمر يدلّ على الخطر، لا يملأ الشاشة
  ///
  /// كان القسم لوحاً أحمر كامل الإشباع بحدّ أحمر، وداخله زرّ خروج **أحمر
  /// ممتلئ**. عملياً: الخروج — وهو إجراء يومي غير مؤذٍ — كان يبدو أخطر ما
  /// في التطبيق، وحذف الحساب يضيع داخل نفس الكتلة الحمراء. رُصد على جهاز
  /// حقيقي بوصفه «كتلة حمراء ضخمة في الإعدادات».
  ///
  /// الآن: الخروج زرّ محايد بحدّ، والحذف سطر مكبوح تحت فاصل، بلونٍ يدلّ
  /// على الخطر في النصّ والأيقونة وحدهما. الخطورة تبقى مقروءة — والتأكيد
  /// المزدوج هو الحاجز الحقيقي لا اللون.
  Widget _buildLogoutSection(FirebaseAuthService auth) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _isDeleting ? null : () => _logout(auth),
            icon: const Icon(Icons.logout, size: 20),
            label: const Text('تسجيل الخروج'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Divider(color: scheme.outlineVariant, height: 1),
          const SizedBox(height: AppSpacing.md),
          Text(
            'حذف الحساب إجراء نهائي لا يمكن التراجع عنه.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _isDeleting ? null : _confirmDeleteAccount,
              icon: _isDeleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_forever_outlined, size: 20),
              label: Text(_isDeleting ? 'جارٍ الحذف…' : 'حذف حسابي نهائياً'),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
            ),
          ),
        ],
      ),
    );
  }

  /// تأكيد الحذف — خطوتان لا واحدة.
  ///
  /// النص يقول ما سيحدث بالضبط لا «هل أنت متأكد؟»: ما يُحذف، وما يبقى
  /// (سجل الزيارات عند الطبيب بلا اسمك)، وأن المواعيد القائمة ستُلغى.
  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الحساب نهائياً'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سيُحذف حسابك وبياناتك الشخصية ولا يمكن التراجع.'),
            SizedBox(height: 12),
            Text('• ستُلغى مواعيدك القائمة ويُبلَّغ أطباؤها.'),
            Text('• سيُحذف ملفك الشخصي ورقم جوالك من التطبيق.'),
            Text('• تبقى الزيارات السابقة في سجل العيادة بلا اسمك.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('تراجع'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('نعم، احذف حسابي'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    setState(() => _isDeleting = true);
    final auth = context.read<FirebaseAuthService>();
    final result = await _accountService.deleteAccount();
    if (!mounted) return;
    setState(() => _isDeleting = false);

    if (!result.isSuccess) {
      // جلسة قديمة: الخادم يشترط دخولاً حديثاً قبل إجراء لا رجعة فيه،
      // فالمخرج الصحيح هو الخروج ثم الدخول من جديد — لا مجرّد رسالة.
      _showMessage(result.message, isError: true);
      if (result.needsRecentLogin) {
        await auth.logout();
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
      return;
    }

    await auth.logout();
    if (!mounted) return;
    _showMessage(result.message);
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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
            child: Text('تسجيل الخروج',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.tertiary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
