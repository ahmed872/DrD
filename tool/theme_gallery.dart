// معرض نظام التصميم.
//
// ليس جزءاً من التطبيق ولا يُشحن معه: التطبيق نفسه يحتاج إعدادات Firebase
// وقت البناء، فلا يمكن فتح أي شاشة منه لمراجعة النسق بصرياً بدون بيانات
// اعتماد إنتاجية. هذا المدخل يرسم المكوّنات وحدها في الوضعين والاتجاهين.
//
//   flutter run -d chrome -t tool/theme_gallery.dart
//   flutter build web --release -t tool/theme_gallery.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:medical_appointment_app/core/constants/appointment_status.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/core/widgets/widgets.dart';

void main() => runApp(const GalleryApp());

class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key});

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DrD — نظام التصميم',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _mode,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: _Gallery(
        isDark: _mode == ThemeMode.dark,
        onToggle: (v) =>
            setState(() => _mode = v ? ThemeMode.dark : ThemeMode.light),
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.isDark, required this.onToggle});

  final bool isDark;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نظام التصميم'),
        actions: [
          Switch(
              key: const Key('theme-toggle'),
              value: isDark,
              onChanged: onToggle),
          const SizedBox(width: DrdSpacing.xs),
        ],
      ),
      body: ListView(
        padding: DrdSpacing.screen,
        children: [
          const SectionHeader(
            title: 'اللافتات',
            subtitle: 'أيقونة مميّزة الشكل مع كل نغمة — لا لون وحده',
          ),
          const AppBanner.success(message: 'تم حفظ الموعد بنجاح.'),
          const SizedBox(height: DrdSpacing.xs),
          const AppBanner.warning(
            title: 'تعذّر التحقق من الأوقات المتاحة',
            message: 'تأكد من اتصالك بالإنترنت ثم اختر التاريخ مرة أخرى.',
          ),
          const SizedBox(height: DrdSpacing.xs),
          AppBanner.error(
            message: 'تعذّر إلغاء الموعد.',
            action: TextButton(
              onPressed: () {},
              child: const Text('أعد المحاولة'),
            ),
          ),
          const SizedBox(height: DrdSpacing.xs),
          AppBanner.info(
            message: 'سيصلك تأكيد عبر البريد الإلكتروني.',
            onDismiss: () {},
          ),
          const SectionHeader(
            title: 'حالات الموعد',
            subtitle: 'لكل حالة أيقونتها، فالمتشابهتان لونياً تفترقان شكلاً',
          ),
          Wrap(
            spacing: DrdSpacing.xs,
            runSpacing: DrdSpacing.xs,
            children: [
              for (final s in AppointmentStatus.values)
                StatusChip.appointment(s),
            ],
          ),
          const SectionHeader(title: 'الأزرار', subtitle: 'ثلاثة مستويات'),
          FilledButton(onPressed: () {}, child: const Text('احجز موعداً')),
          const SizedBox(height: DrdSpacing.xs),
          OutlinedButton(onPressed: () {}, child: const Text('تعديل البيانات')),
          const SizedBox(height: DrdSpacing.xs),
          TextButton(onPressed: () {}, child: const Text('نسيت كلمة المرور؟')),
          const SizedBox(height: DrdSpacing.xs),
          const FilledButton(onPressed: null, child: Text('غير متاح')),
          const SectionHeader(title: 'الحقول'),
          const TextField(
            decoration: InputDecoration(
              labelText: 'رقم الجوال',
              hintText: '+20 1xx xxx xxxx',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: DrdSpacing.sm),
          const TextField(
            decoration: InputDecoration(
              labelText: 'كلمة المرور',
              prefixIcon: Icon(Icons.lock_outline),
              suffixIcon: Icon(Icons.visibility_off),
              errorText: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل',
            ),
          ),
          const SectionHeader(title: 'البطاقات'),
          AppCard(
            onTap: () {},
            child: Row(
              children: [
                Icon(Icons.person, color: context.colors.primary),
                const SizedBox(width: DrdSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('د. أحمد يوسف', style: context.text.titleSmall),
                      Text(
                        'طب الأسرة',
                        style: context.text.bodySmall
                            ?.copyWith(color: context.drd.muted),
                      ),
                    ],
                  ),
                ),
                StatusChip.appointment(AppointmentStatus.booked),
              ],
            ),
          ),
          const SectionHeader(
            title: 'حالات الصفحة',
            subtitle: '«لا يوجد» و«تعذّر التحميل» ليستا الشيء نفسه',
          ),
          const SizedBox(
              height: 180, child: LoadingView(message: 'جارٍ الحجز…')),
          const SizedBox(
            height: 240,
            child: EmptyView(
              title: 'لا توجد مواعيد قادمة',
              message: 'ابحث عن طبيب لحجز موعدك الأول.',
              icon: Icons.calendar_today_outlined,
            ),
          ),
          SizedBox(
            height: 260,
            child: ErrorView(message: 'تحقّق من اتصالك.', onRetry: () {}),
          ),
          const SectionHeader(title: 'الطباعة'),
          Text('عنوان كبير', style: context.text.headlineSmall),
          Text('عنوان قسم', style: context.text.titleMedium),
          Text(
            'نصّ متن عربي بارتفاع سطر مناسب للقراءة الطويلة، لأن العربية '
            'تحتاج مساحة رأسية أكبر من اللاتينية.',
            style: context.text.bodyMedium,
          ),
          Text(
            'نصّ ثانوي',
            style: context.text.bodySmall?.copyWith(color: context.drd.muted),
          ),
          const SizedBox(height: DrdSpacing.xxl),
        ],
      ),
    );
  }
}
