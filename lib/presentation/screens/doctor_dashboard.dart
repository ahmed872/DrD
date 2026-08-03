import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firebase_auth_service.dart';
import '../../core/theme/app_theme.dart';

class DoctorDashboard extends StatefulWidget {
  const DoctorDashboard({super.key});

  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  DateTime _selectedDate = DateTime.now();
  int _selectedFilterIndex = 0; // 0: اليوم, 1: الغد, 2: هذا الأسبوع, -1: مخصص

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم الطبيب'),
        centerTitle: true,
        backgroundColor: AppColors.brand,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(context),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Settings Card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'إعدادات العيادة',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.brand),
                        ),
                        const Divider(),
                        ListTile(
                          title: const Text('مدة الجلسة'),
                          subtitle: const Text('30 دقيقة'),
                          trailing:
                              const Icon(Icons.edit, color: AppColors.brand),
                          onTap: () => _showEditDialog('مدة الجلسة'),
                        ),
                        ListTile(
                          title: const Text('وقت التأخير للمستعجلات'),
                          subtitle: const Text('5 دقائق'),
                          trailing:
                              const Icon(Icons.edit, color: AppColors.brand),
                          onTap: () => _showEditDialog('وقت التأخير'),
                        ),
                        ListTile(
                          title: const Text('ساعات العمل'),
                          subtitle: const Text('09:00 - 17:00'),
                          trailing:
                              const Icon(Icons.edit, color: AppColors.brand),
                          onTap: () => _showEditDialog('ساعات العمل'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Date Selection
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedFilterIndex == 0
                          ? 'مواعيد اليوم'
                          : _selectedFilterIndex == 1
                              ? 'مواعيد الغد'
                              : _selectedFilterIndex == 2
                                  ? 'هذا الأسبوع'
                                  : 'مواعيد مخصصة',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    GestureDetector(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 30)),
                        );
                        if (picked != null && picked != _selectedDate) {
                          setState(() {
                            _selectedDate = picked;
                            _selectedFilterIndex = -1; // مخصص
                          });
                        }
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month,
                              color: AppColors.brand, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            _selectedDate.toString().split(' ')[0],
                            style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.brand,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('اليوم'),
                        selected: _selectedFilterIndex == 0,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedFilterIndex = 0;
                              _selectedDate = DateTime.now();
                            });
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('الغد'),
                        selected: _selectedFilterIndex == 1,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedFilterIndex = 1;
                              _selectedDate =
                                  DateTime.now().add(const Duration(days: 1));
                            });
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('هذا الأسبوع'),
                        selected: _selectedFilterIndex == 2,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedFilterIndex = 2;
                              _selectedDate = DateTime
                                  .now(); // هنا يمكن استخدامه كمرجع فقط لفلترة الأسبوع
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Appointments List Placeholder
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        const Text(
                          'لا توجد مواعيد في هذا التاريخ',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditDialog(String field) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل $field'),
        content: TextField(
          decoration: InputDecoration(
            hintText: 'ادخل $field',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تم تحديث $field')),
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Provider.of<FirebaseAuthService>(context, listen: false).logout();
              Navigator.of(context).pushReplacementNamed('/login');
            },
            child: const Text('تسجيل خروج',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}
