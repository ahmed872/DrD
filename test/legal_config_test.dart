import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/config/legal_config.dart';

/// وصلة المستندات القانونية.
///
/// الاختبار هنا يحرس شيئين: ألا يظهر مدخل بلا وجهة (رابط مكسور يوحي
/// بامتثال لم يحدث)، وألا يُقبل رابط غير آمن لمستند قانوني.
void main() {
  group('صلاحية الرابط', () {
    test('الفارغ والمسافات ليست وجهة', () {
      expect(LegalConfig.isPublishable(''), isFalse);
      expect(LegalConfig.isPublishable('   '), isFalse);
    });

    test('غير https مرفوض', () {
      expect(LegalConfig.isPublishable('http://example.com/privacy'), isFalse);
      expect(LegalConfig.isPublishable('javascript:alert(1)'), isFalse);
      expect(LegalConfig.isPublishable('/privacy'), isFalse);
      expect(LegalConfig.isPublishable('https://'), isFalse);
    });

    test('https بمضيف حقيقي مقبول', () {
      expect(
          LegalConfig.isPublishable('https://drd.example.com/privacy'), isTrue);
      expect(LegalConfig.isPublishable('  https://drd.example.com/privacy  '),
          isTrue);
    });
  });

  group('الحالة الحالية', () {
    test('سياسة الخصوصية لم تُنشر بعد — حاجز إطلاق معلن لا مخفي', () {
      // حين تُنشر السياسة ويُملأ الثابت، يسقط هذا الاختبار عمداً ليُحدَّث
      // إلى `isTrue` — فلا يمرّ التغيير بلا انتباه.
      expect(LegalConfig.hasPrivacyPolicy, isFalse);
    });
  });
}
