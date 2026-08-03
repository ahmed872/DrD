import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'presentation/widgets/next_appointment_card.dart';
import 'presentation/widgets/ui_kit.dart';

/// معاينة التصميم — نقطة دخول للتطوير فقط، مش جزء من التطبيق المنشور.
///
/// الغرض منها إن التصميم يتشاف ويتظبط من غير الحاجة لتسجيل دخول ولا
/// اتصال بقاعدة البيانات. تُشغَّل بـ:
///
///     flutter run -d chrome -t lib/design_preview.dart
///
/// أو تُبنى للمراجعة:
///
///     flutter build web -t lib/design_preview.dart
void main() => runApp(const DesignPreviewApp());

class DesignPreviewApp extends StatelessWidget {
  const DesignPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DrD — معاينة التصميم',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'EG')],
      locale: const Locale('ar', 'EG'),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const _Preview(),
    );
  }
}

class _Preview extends StatefulWidget {
  const _Preview();

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _mode == ThemeMode.dark ? AppTheme.dark : AppTheme.light,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('معاينة التصميم'),
            actions: [
              IconButton(
                icon: Icon(_mode == ThemeMode.dark
                    ? Icons.light_mode
                    : Icons.dark_mode),
                onPressed: () => setState(() => _mode =
                    _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              const Eyebrow('بطاقة الموعد القادم'),
              const SizedBox(height: Gap.sm),
              NextAppointmentCard(
                doctorName: 'د. منى عبد الرحمن',
                specialization: 'باطنة',
                startsAt: DateTime.now().add(const Duration(minutes: 42)),
                timeLabel: '16:20',
              ),
              const SizedBox(height: Gap.md),
              NextAppointmentCard(
                doctorName: 'د. كريم السيد',
                specialization: 'أسنان',
                startsAt: DateTime.now().add(const Duration(days: 3, hours: 5)),
                timeLabel: '11:00',
              ),
              const SizedBox(height: Gap.xxl),
              const Eyebrow('بطاقة طبيب'),
              const SizedBox(height: Gap.sm),
              AppCard(
                onTap: () {},
                child: Row(
                  children: [
                    const InitialAvatar('د. هالة فتحي'),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('د. هالة فتحي',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text('جلدية · ٢٠٠ جنيه',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const StatusPill('٤.٩ ★', color: AppColors.accent),
                  ],
                ),
              ),
              const SizedBox(height: Gap.xxl),
              const Eyebrow('شرائح الحالة'),
              const SizedBox(height: Gap.sm),
              const Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
                StatusPill('محجوز',
                    color: AppColors.brand, icon: Icons.check_circle),
                StatusPill('مكتمل',
                    color: AppColors.success, icon: Icons.done_all),
                StatusPill('بانتظار التأكيد',
                    color: AppColors.warning, icon: Icons.schedule),
                StatusPill('ملغي', color: AppColors.danger, icon: Icons.close),
              ]),
              const SizedBox(height: Gap.xxl),
              const Eyebrow('بطاقة موعد'),
              const SizedBox(height: Gap.sm),
              AppCard(
                accent: AppColors.brand,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('د. أحمد شعبان',
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        const StatusPill('محجوز', color: AppColors.brand),
                      ],
                    ),
                    const ThinDivider(),
                    const DataRow2('التاريخ', 'الاثنين ٤ أغسطس'),
                    const DataRow2('الوقت', '١٠:٣٠ ص', bold: true),
                    const DataRow2('السعر', '١٢٠ جنيه'),
                  ],
                ),
              ),
              const SizedBox(height: Gap.xxl),
              const Eyebrow('الأزرار'),
              const SizedBox(height: Gap.sm),
              FilledButton(onPressed: () {}, child: const Text('أكّد الحجز')),
              const SizedBox(height: Gap.md),
              OutlinedButton(
                  onPressed: () {}, child: const Text('إلغاء الموعد')),
              const SizedBox(height: Gap.xxl),
              const Eyebrow('حقل إدخال'),
              const SizedBox(height: Gap.sm),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'رقم الجوال',
                  hintText: '01xxxxxxxxx',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: Gap.xxl),
              const Eyebrow('حالة فارغة'),
              const SizedBox(height: Gap.sm),
              AppCard(
                child: EmptyState(
                  icon: Icons.event_busy,
                  message: 'لا توجد مواعيد قادمة',
                  action: FilledButton(
                      onPressed: () {}, child: const Text('احجز موعد')),
                ),
              ),
              const SizedBox(height: Gap.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
