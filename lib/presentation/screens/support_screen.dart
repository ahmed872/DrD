import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/app_logger.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const String whatsappPhone = '201093033884'; // رقم الواتس
  static const String whatsappUrl =
      'https://wa.me/$whatsappPhone?text=مرحبا، أريد الحصول على الدعم الفني';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('الدعم الفني'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0097A7),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // رسالة ترحيب
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0097A7).withOpacity(0.1),
                  border: Border.all(
                      color: const Color(0xFF0097A7).withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.help_outline,
                      size: 40,
                      color: Color(0xFF0097A7),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'هل تحتاج إلى مساعدة؟',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0097A7),
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'نحن هنا لمساعدتك في أي استفسار أو مشكلة تواجهك في التطبيق',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFF0097A7).withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // الخدمات المتاحة
              Text(
                'فيم يمكننا مساعدتك؟',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
              ),

              const SizedBox(height: 16),

              // البطاقات
              Column(
                children: [
                  _buildSupportCard(
                    icon: Icons.person_add,
                    title: 'إضافة طبيب جديد',
                    description: 'اطلب إضافة طبيب جديد للنظام',
                    color: Colors.green[50]!,
                    borderColor: Colors.green[200]!,
                  ),
                  const SizedBox(height: 12),
                  _buildSupportCard(
                    icon: Icons.bug_report,
                    title: 'إبلاغ عن مشكلة',
                    description: 'أخبرنا عن أي مشكلة تواجهك',
                    color: Colors.orange[50]!,
                    borderColor: Colors.orange[200]!,
                  ),
                  const SizedBox(height: 12),
                  _buildSupportCard(
                    icon: Icons.feedback,
                    title: 'تقديم اقتراح',
                    description: 'شارك اقتراحك لتحسين التطبيق',
                    color: Colors.purple[50]!,
                    borderColor: Colors.purple[200]!,
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // معلومات التواصل
              Text(
                'تواصل معنا',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
              ),

              const SizedBox(height: 20),

              // زر الواتس الرئيسي - الأكثر وضوحاً
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _launchWhatsApp(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.green.shade400,
                          Colors.green.shade600,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.message,
                          size: 40,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'اضغط للتواصل عبر WhatsApp',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '+20 109 303 3884',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // بطاقة إضافية قابلة للنقر
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _launchWhatsApp(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0097A7).withOpacity(0.1),
                      border: Border.all(
                        color: const Color(0xFF0097A7),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.chat,
                          size: 32,
                          color: Color(0xFF0097A7),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'هل تحتاج مساعدة؟',
                                style: TextStyle(
                                  color: Color(0xFF0097A7),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'نحن متاحون الآن',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Color(0xFF0097A7),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // معلومات إضافية
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ملاحظات مهمة:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildBulletPoint(
                        'وقت الرد: من الأحد للخميس من 8 صباحاً إلى 5 مساءً'),
                    const SizedBox(height: 8),
                    _buildBulletPoint(
                        'لإضافة طبيب: أرسل المعلومات الكاملة عبر الواتس'),
                    const SizedBox(height: 8),
                    _buildBulletPoint(
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

  Widget _buildSupportCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: borderColor,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
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
              color: Colors.grey[600],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
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
