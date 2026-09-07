/// قراءة آمنة لحقول Firestore.
///
/// ## المشكلة التي يحلّها هذا الملف
///
/// شاشة دليل الأطباء كانت تقرأ السعر هكذا:
///
/// ```dart
/// 'price': (data['price'] ?? 200).toDouble(),
/// ```
///
/// وهذا صحيح ما دامت القيمة رقماً. لكن السطر يقع داخل `map()` على **كل**
/// الأطباء، وداخل `try/catch` واحد يلفّ الجلب كله. فمستند واحد يحمل `price`
/// نصّاً يرمي `NoSuchMethodError`، فيُلتقط الاستثناء وتبقى القائمة فارغة —
/// أي أن مستنداً واحداً معطوباً يُخفي **كل** الأطباء عن **كل** المرضى.
///
/// شُدِّدت القاعدة في `firestore.rules` فلم تعد قيمة كهذه تُكتب. لكن القاعدة
/// تحكم الكتابات الجديدة وحدها: أي مستند كُتب قبلها يبقى كما هو. ولأن العطل
/// يقع على كل المستخدمين لا على صاحب المستند، فالقراءة الدفاعية هنا ليست
/// ترفاً — هي ما يمنع بيانات قديمة من تعطيل الشاشة الأهم في التطبيق.
///
/// المبدأ: قيمة معطوبة تُفقد بطاقةً واحدة، لا القائمة كلها.
library;

/// رقم من حقل قد يحمل أي شيء.
///
/// يقبل `num` مباشرةً، ويحاول تفسير النصّ الرقمي (بيانات قديمة كتبت `'200'`)،
/// ويُرجع [fallback] لأي شيء آخر.
double safeDouble(Object? raw, {double fallback = 0}) {
  if (raw is num) {
    // `NaN` و`Infinity` يمرّان من `is num` ثم يُفسدان كل مقارنة بعدهما.
    final value = raw.toDouble();
    return value.isFinite ? value : fallback;
  }
  if (raw is String) return double.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

/// عدد صحيح من حقل قد يحمل أي شيء، مع حدّ أدنى وأعلى.
///
/// [min] ليس تجميلاً: `sessionDuration == 0` يجعل حلقة توليد الأوقات
/// `current = current.add(Duration(minutes: 0))` لا تتقدّم أبداً — فتتجمّد
/// شاشة الحجز، ولا يلتقط ذلك `try/catch` لأنه ليس استثناءً بل حلقة لا تنتهي.
int safeInt(
  Object? raw, {
  required int fallback,
  int? min,
  int? max,
}) {
  int? value;
  if (raw is int) {
    value = raw;
  } else if (raw is num) {
    final d = raw.toDouble();
    value = d.isFinite ? d.round() : null;
  } else if (raw is String) {
    value = int.tryParse(raw.trim());
  }

  value ??= fallback;
  if (min != null && value < min) return fallback;
  if (max != null && value > max) return fallback;
  return value;
}

/// نصّ من حقل قد يحمل أي شيء، مقصوصاً عند [maxLength].
///
/// القصّ يحمي التخطيط من نصّ ضخم كُتب قبل تشديد القاعدة.
String safeString(
  Object? raw, {
  String fallback = '',
  int maxLength = 500,
}) {
  final value = raw is String ? raw : (raw == null ? fallback : raw.toString());
  final trimmed = value.trim();
  if (trimmed.isEmpty) return fallback;
  return trimmed.length <= maxLength
      ? trimmed
      : '${trimmed.substring(0, maxLength)}…';
}
