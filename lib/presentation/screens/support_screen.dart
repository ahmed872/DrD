import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_logger.dart';
import '../widgets/app_widgets.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const String whatsappPhone = '201093033884'; // رقم الواتس
  static const String whatsappDisplay = '+20 109 303 3884';
  static const String whatsappUrl =
      'https://wa.me/$whatsappPhone?text=مرحبا، أريد الحصول على الدعم الفني';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AppScaffold(
      title: 'الدعم الفني',
      subtitle: 'إحنا معاك في أي وقت',
      maxWidth: AppBreakpoints.content,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WhatsAppCta(onTap: () => _launchWhatsApp(context)),
          const SizedBox(height: AppSpacing.xxl),
          const SectionTitle(
            title: 'فيمَ يمكننا مساعدتك؟',
            subtitle: 'اضغط على أي بند لتبدأ محادثة جاهزة',
            icon: Icons.help_outline_rounded,
          ),
          _TopicTile(
            icon: Icons.person_add_alt_1_rounded,
            title: 'إضافة طبيب جديد',
            description: 'اطلب إضافة طبيب جديد للنظام',
            color: tokens.success,
            onTap: () => _launchWhatsApp(
              context,
              message: 'مرحبا، أريد إضافة طبيب جديد للنظام',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _TopicTile(
            icon: Icons.bug_report_outlined,
            title: 'إبلاغ عن مشكلة',
            description: 'أخبرنا عن أي مشكلة تواجهك',
            color: tokens.warning,
            onTap: () => _launchWhatsApp(
              context,
              message: 'مرحبا، عندي مشكلة في التطبيق:',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _TopicTile(
            icon: Icons.lightbulb_outline_rounded,
            title: 'تقديم اقتراح',
            description: 'شارك اقتراحك لتحسين التطبيق',
            color: tokens.info,
            onTap: () => _launchWhatsApp(
              context,
              message: 'مرحبا، عندي اقتراح لتحسين التطبيق:',
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          const SectionTitle(
            title: 'ملاحظات مهمة',
            icon: Icons.info_outline_rounded,
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _Bullet('وقت الرد: من الأحد للخميس، 8 صباحاً حتى 5 مساءً'),
                SizedBox(height: AppSpacing.md),
                _Bullet('لإضافة طبيب: أرسل المعلومات الكاملة عبر الواتساب'),
                SizedBox(height: AppSpacing.md),
                _Bullet('للاستفسارات العاجلة: تواصل معنا مباشرة عبر الواتساب'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchWhatsApp(BuildContext context, {String? message}) async {
    final text = Uri.encodeComponent(
      message ?? 'مرحبا، أريد الحصول على الدعم الفني',
    );
    final Uri url = Uri.parse('https://wa.me/$whatsappPhone?text=$text');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          AppSnack.error(
            context,
            'الرجاء التأكد من تثبيت تطبيق واتساب على جهازك',
          );
        }
      }
    } catch (e) {
      AppLogger.info('Error launching WhatsApp: $e');
      if (context.mounted) {
        AppSnack.error(context, 'حدث خطأ أثناء محاولة فتح واتساب');
      }
    }
  }
}

/// الزر الرئيسي للتواصل.
///
/// كان في الشاشة السابقة زرّان يفتحان نفس الرابط، فوق بطاقة ترحيب ثالثة تقول
/// نفس الكلام. واحد واضح أفضل من ثلاثة متكرّرة.
class _WhatsAppCta extends StatelessWidget {
  const _WhatsAppCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rLg,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF25D366), Color(0xFF128C7E)],
            ),
            borderRadius: AppRadius.rLg,
            boxShadow: tokens.shadowMd,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تواصل عبر واتساب',
                      style: context.texts.titleMedium
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      SupportScreen.whatsappDisplay,
                      textDirection: TextDirection.ltr,
                      style: context.texts.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white.withValues(alpha: 0.8),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.rMd,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.titleSmall),
                Text(
                  description,
                  style: context.texts.bodySmall
                      ?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 14,
            color: tokens.textFaint,
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.primary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            text,
            style: context.texts.bodyMedium?.copyWith(color: tokens.textBody),
          ),
        ),
      ],
    );
  }
}
