import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/simple_auth_service.dart';

class HomeScreenSimple extends StatelessWidget {
  const HomeScreenSimple({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الرئيسية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<SimpleAuthService>().logout();
            },
          ),
        ],
      ),
      body: Consumer<SimpleAuthService>(
        builder: (context, auth, _) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Welcome message
                Text(
                  'أهلاً وسهلاً!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  auth.userName ?? 'مستخدم',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 32),

                // User info card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ListTile(
                          title: const Text('البريد الإلكتروني'),
                          subtitle: Text(auth.userId ?? ''),
                          trailing: const Icon(Icons.email),
                        ),
                        ListTile(
                          title: const Text('نوع الحساب'),
                          subtitle: Text(
                            auth.userRole == 'doctor'
                                ? 'طبيب 👨‍⚕️'
                                : 'مريض 👤',
                          ),
                          trailing: Icon(
                            auth.userRole == 'doctor'
                                ? Icons.medical_services
                                : Icons.person,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Different content based on role
                if (auth.userRole == 'doctor')
                  _DoctorPanel()
                else
                  _PatientPanel(),

                const SizedBox(height: 32),

                // Logout button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('تسجيل الخروج'),
                    onPressed: () {
                      context.read<SimpleAuthService>().logout();
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DoctorPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'لوحة الطبيب',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _FeatureCard(
              icon: Icons.calendar_today,
              label: 'جدول المواعيد',
              onTap: () {},
            ),
            _FeatureCard(
              icon: Icons.settings,
              label: 'إعدادات العيادة',
              onTap: () {},
            ),
            _FeatureCard(
              icon: Icons.people,
              label: 'المرضى',
              onTap: () {},
            ),
            _FeatureCard(
              icon: Icons.show_chart,
              label: 'الإحصائيات',
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }
}

class _PatientPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'لوحة المريض',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _FeatureCard(
              icon: Icons.add_circle,
              label: 'حجز موعد',
              onTap: () {},
            ),
            _FeatureCard(
              icon: Icons.calendar_today,
              label: 'مواعيدي',
              onTap: () {},
            ),
            _FeatureCard(
              icon: Icons.person_search,
              label: 'البحث عن طبيب',
              onTap: () {},
            ),
            _FeatureCard(
              icon: Icons.history,
              label: 'السجل الطبي',
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.blue),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
