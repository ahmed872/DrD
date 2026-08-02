import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('إعداداتي'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0097A7),
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
                          backgroundColor: const Color(0xFF0097A7),
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
                              backgroundColor: Colors.grey[300],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'إلغاء',
                              style: TextStyle(color: Colors.grey),
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
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('حفظ'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0097A7),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[200]!, width: 1),
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
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.grey[600], size: 20),
              const SizedBox(width: 12),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
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
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF0097A7)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFF0097A7),
                width: 2,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[100]!),
            ),
            filled: true,
            fillColor: enabled ? Colors.white : Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[800],
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
            color: Colors.grey[600],
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
              color: _isEditing ? Colors.white : Colors.grey[50],
              border: Border.all(color: Colors.grey[200]!),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      color: const Color(0xFF0097A7),
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
                            ? Colors.grey[800]
                            : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
                if (_isEditing)
                  Icon(
                    Icons.edit,
                    color: Colors.grey[400],
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
            color: Colors.grey[600],
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
          color: isSelected ? const Color(0xFF0097A7) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF0097A7) : Colors.grey[200]!,
            width: 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutSection(FirebaseAuthService auth) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _logout(auth),
          icon: const Icon(Icons.logout),
          label: const Text('تسجيل الخروج'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade600,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
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
              // يُلتقط قبل `await` — بعده قد تكون الشاشة أُزيلت.
              final navigator = Navigator.of(context);
              navigator.pop();
              await auth.logout();
              if (!mounted) return;
              navigator.pushNamedAndRemoveUntil('/', (route) => false);
            },
            child:
                const Text('تسجيل الخروج', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
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
