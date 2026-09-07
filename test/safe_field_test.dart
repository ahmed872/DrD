import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/utils/safe_field.dart';

/// القراءة الدفاعية لحقول Firestore.
///
/// ## ما الذي يحرسه
///
/// شُدِّدت قاعدة `users` فلم تعد تقبل سعراً نصّياً ولا مدة جلسة صفراً. لكن
/// القاعدة تحكم الكتابات الجديدة وحدها — وأي مستند كُتب قبلها يبقى كما هو.
///
/// والفرق يهمّ لأن أثر القيمة المعطوبة لا يقع على صاحب المستند: قراءة السعر
/// تجري داخل `map()` على كل الأطباء وداخل `try/catch` واحد، فمستند واحد
/// معطوب كان يُفرغ الدليل **لكل المرضى**. ومدة جلسة صفر تجعل حلقة توليد
/// الأوقات لا تتقدّم أبداً، فتتجمّد شاشة الحجز بلا استثناء يُلتقط.
void main() {
  group('safeDouble', () {
    test('يمرّر الأرقام كما هي', () {
      expect(safeDouble(250), 250.0);
      expect(safeDouble(99.5), 99.5);
      expect(safeDouble(0), 0.0);
    });

    test('يفسّر النصّ الرقمي — بيانات قديمة كتبت السعر نصّاً', () {
      expect(safeDouble('200'), 200.0);
      expect(safeDouble(' 150.5 '), 150.5);
    });

    test('يردّ البديل لما لا يمكن تفسيره بدل أن يرمي', () {
      // هذا هو السطر الذي كان يُفرغ الدليل كله.
      expect(safeDouble('مجاناً', fallback: 0), 0.0);
      expect(safeDouble(true, fallback: 7), 7.0);
      expect(safeDouble(null, fallback: 3), 3.0);
      expect(safeDouble({'a': 1}, fallback: 1), 1.0);
      expect(safeDouble([1, 2], fallback: 1), 1.0);
    });

    test('يرفض NaN واللانهاية', () {
      // كلاهما يمرّ من `is num` ثم يُفسد كل مقارنة بعده: نطاق السعر،
      // والترتيب، وعرض النجوم.
      expect(safeDouble(double.nan, fallback: 5), 5.0);
      expect(safeDouble(double.infinity, fallback: 5), 5.0);
      expect(safeDouble(double.negativeInfinity, fallback: 5), 5.0);
    });
  });

  group('safeInt', () {
    test('يمرّر الصحيح ضمن النطاق', () {
      expect(safeInt(30, fallback: 30, min: 5, max: 240), 30);
      expect(safeInt(240, fallback: 30, min: 5, max: 240), 240);
    });

    test('يقرّب العشري — قيم قديمة كُتبت 30.0', () {
      expect(safeInt(30.0, fallback: 15, min: 5, max: 240), 30);
      expect(safeInt(29.6, fallback: 15, min: 5, max: 240), 30);
    });

    test('صفر مدة الجلسة لا يمرّ أبداً', () {
      // القيمة التي كانت تجمّد شاشة الحجز.
      expect(safeInt(0, fallback: 30, min: 5), 30);
      expect(safeInt(-15, fallback: 30, min: 5), 30);
      expect(safeInt('0', fallback: 30, min: 5), 30);
    });

    test('يردّ البديل خارج النطاق أو عند تعذّر التفسير', () {
      expect(safeInt(100000, fallback: 30, min: 5, max: 240), 30);
      expect(safeInt('ثلاثون', fallback: 30), 30);
      expect(safeInt(null, fallback: 4), 4);
      expect(safeInt(double.nan, fallback: 4), 4);
    });
  });

  group('safeString', () {
    test('يقصّ النصّ الضخم بدل تمريره إلى التخطيط', () {
      final huge = 'ا' * 5000;
      final result = safeString(huge, maxLength: 100);
      expect(result.length, 101); // مئة حرف + علامة القصّ
      expect(result.endsWith('…'), isTrue);
    });

    test('يردّ البديل للفارغ والمسافات وحدها', () {
      expect(safeString('', fallback: 'غير محدّد'), 'غير محدّد');
      expect(safeString('   ', fallback: 'غير محدّد'), 'غير محدّد');
      expect(safeString(null, fallback: 'غير محدّد'), 'غير محدّد');
    });

    test('يمرّر النصّ الطبيعي مشذّباً', () {
      expect(safeString('  د. أحمد  '), 'د. أحمد');
    });
  });

  test('قيمة معطوبة واحدة لا تُسقط بقية السجل', () {
    // محاكاة ما كان يحدث: مستند طبيب واحد بسعر نصّي داخل قائمة سليمة.
    final docs = [
      {'name': 'د. أ', 'price': 200, 'sessionDuration': 30},
      {'name': 'د. ب', 'price': 'مجاناً', 'sessionDuration': 0},
      {'name': 'د. ج', 'price': 150, 'sessionDuration': 20},
    ];

    final mapped = docs
        .map((d) => {
              'name': safeString(d['name'], fallback: 'طبيب'),
              'price': safeDouble(d['price']),
              'sessionDuration':
                  safeInt(d['sessionDuration'], fallback: 30, min: 5, max: 240),
            })
        .toList();

    expect(mapped.length, 3, reason: 'المستند المعطوب أسقط القائمة كلها');
    expect(mapped[1]['price'], 0.0);
    expect(mapped[1]['sessionDuration'], 30);
    expect(mapped[2]['price'], 150.0);
  });
}
