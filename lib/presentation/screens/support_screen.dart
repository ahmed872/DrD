import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/app_logger.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const String whatsappPhone = '201093033884'; // رقم الواتس
  static const String whatsappUrl =
      'https://wa.me/$whatsappPhone?text=مرحبا، أريد الحصول على الدعم الفني';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الدعم الفني')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // رسالة ترحيب
              Container(
                padding: const EdgeInsets.all(DrdSpacing.md),
                decoration: BoxDecoration(
                  color: context.colors.primaryContainer,
                  borderRadius: DrdRadius.lgAll,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.help_outline,
                      size: 40,
                      color: context.colors.onPrimaryContainer,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'هل تحتاج إلى مساعدة؟',
                      style: context.text.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: context.colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'نحن هنا لمساعدتك في أي استفسار أو مشكلة تواجهك في التطبيق',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // الخدمات المتاحة
              Text(
                'فيم يمكننا مساعدتك؟',
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              // البطاقات
              Column(
                children: [
                  _buildSupportCard(
                    context,
                    icon: Icons.person_add,
                    title: 'إضافة طبيب جديد',
                    description: 'اطلب إضافة طبيب جديد للنظام',
                  ),
                  const SizedBox(height: 12),
                  _buildSupportCard(
                    context,
                    icon: Icons.bug_report,
                    title: 'إبلاغ عن مشكلة',
                    description: 'أخبرنا عن أي مشكلة تواجهك',
                  ),
                  const SizedBox(height: 12),
                  _buildSupportCard(
                    context,
                    icon: Icons.feedback,
                    title: 'تقديم اقتراح',
                    description: 'شارك اقتراحك لتحسين التطبيق',
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // معلومات التواصل
              Text(
                'تواصل معنا',
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              // زر الواتساب الرئيسي.
              //
              // كان مستطيلاً بتدرّج أخضر وظلّ أخضر — والأخضر في هذا التطبيق
              // يعني «نجح»، فبدا الزرّ رسالةَ نجاح لا إجراءً. وهو الإجراء
              // الأساسي هنا، فيأخذ شكل الإجراء الأساسي.
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _launchWhatsApp(context),
                  icon: const Icon(Icons.message),
                  label: const Text('تواصل عبر واتساب'),
                ),
              ),

              const SizedBox(height: DrdSpacing.xs),
              Center(
                child: Text(
                  '+20 109 303 3884',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.drd.muted,
                  ),
                ),
              ),

              const SizedBox(height: DrdSpacing.md),

              // مدخل ثانٍ لنفس الإجراء — بطاقة قابلة للنقر.
              AppCard(
                onTap: () => _launchWhatsApp(context),
                semanticLabel: 'هل تحتاج مساعدة؟ تواصل عبر واتساب',
                child: Row(
                  children: [
                    Icon(Icons.chat, size: 32, color: context.colors.primary),
                    const SizedBox(width: DrdSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'هل تحتاج مساعدة؟',
                            style: context.text.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: DrdSpacing.xxs),
                          Text(
                            'نحن متاحون الآن',
                            style: context.text.bodySmall?.copyWith(
                              color: context.drd.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: context.drd.muted,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // معلومات إضافية
              Container(
                padding: const EdgeInsets.all(DrdSpacing.md),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHigh,
                  borderRadius: DrdRadius.lgAll,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ملاحظات مهمة:',
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildBulletPoint(context,
                        'وقت الرد: من الأحد للخميس من 8 صباحاً إلى 5 مساءً'),
                    const SizedBox(height: 8),
                    _buildBulletPoint(context,
                        'لإضافة طبيب: أرسل المعلومات الكاملة عبر الواتس'),
                    const SizedBox(height: 8),
                    _buildBulletPoint(context,
                        'للاستفسارات العاجلة: تواصل معنا مباشرة عبر الواتس'),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  /// بطاقة خيار دعم.
  ///
  /// كانت الثلاثة بأخضر وبرتقالي وبنفسجي — ثلاثة خيارات قائمة لا حالات، ولا
  /// شيء يجعل «إبلاغ عن مشكلة» برتقالياً و«تقديم اقتراح» بنفسجياً. الأيقونة
  /// تميّز الخيار.
  Widget _buildSupportCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(DrdSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        borderRadius: DrdRadius.lgAll,
      ),
      child: Row(
        children: [
          Icon(icon, color: context.colors.primary, size: 28),
          const SizedBox(width: DrdSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: context.text.bodySmall?.copyWith(
                    color: context.drd.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(BuildContext context, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.drd.muted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: context.text.bodySmall?.copyWith(
              color: context.drd.muted,
            ),
          ),
        ),
      ],
    );
  }

  void _launchWhatsApp(BuildContext context) async {
    final Uri url = Uri.parse(whatsappUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('الرجاء التأكد من تثبيت تطبيق واتساب على جهازك')),
          );
        }
      }
    } catch (e) {
      AppLogger.info('Error launching WhatsApp: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء محاولة فتح واتساب')),
        );
      }
    }
  }
}
