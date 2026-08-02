import 'package:intl/intl.dart';

/// توليد معرّفات ثابتة للخانات الزمنية والمواعيد.
///
/// هذه هي حجر الأساس لمنع الحجز المزدوج: بدلاً من ترك Firestore يولّد معرّفاً
/// عشوائياً لكل حجز (وهو ما كان يسمح لشخصين بحجز نفس الدقيقة)، صار لكل خانة
/// زمنية معرّف واحد محسوب من (الطبيب + التاريخ + الوقت). مستندان لا يمكن أن
/// يحملا نفس المعرّف، فالتصادم يصبح مستحيلاً على مستوى قاعدة البيانات وليس
/// على مستوى الواجهة.
class SlotId {
  const SlotId._();

  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  /// الفاصل بين أجزاء المعرّف. الشرطة السفلية آمنة في معرّفات Firestore،
  /// بعكس `/` التي تُفسَّر كفاصل مسار.
  static const String _separator = '_';

  /// معرّف الخانة الزمنية: `{doctorId}_{yyyy-MM-dd}_{HH-mm}`.
  ///
  /// [time] يُتوقَّع أن يكون بصيغة 24 ساعة `HH:mm`. النقطتان تُستبدلان بشرطة
  /// لأن بعض أدوات Firebase (تصدير/استيراد المسارات) تتعامل مع `:` بشكل خاص.
  static String forSlot({
    required String doctorId,
    required DateTime date,
    required String time,
  }) {
    return [
      doctorId,
      _dateFormat.format(date),
      normalizeTime(time).replaceAll(':', '-'),
    ].join(_separator);
  }

  /// معرّف الموعد: `{slotId}__{patientId}`.
  ///
  /// الشرطتان تفصلان معرّف المريض عن معرّف الخانة. الفائدة: مريض واحد لا يمكن
  /// أن يحجز نفس الخانة مرتين مهما ضغط على زر التأكيد، لأن المحاولة الثانية
  /// ستكتب على نفس المستند بدل إنشاء مستند جديد.
  static String forAppointment({
    required String doctorId,
    required DateTime date,
    required String time,
    required String patientId,
  }) {
    final slot = forSlot(doctorId: doctorId, date: date, time: time);
    return '$slot${_separator}${_separator}$patientId';
  }

  /// توحيد صيغة الوقت إلى `HH:mm` بنظام 24 ساعة.
  ///
  /// التطبيق كان يخزّن الوقت بأربع صيغ مختلفة (`9:00`, `09:00`, `09:00:00`,
  /// `09:00 AM`). هذه الدالة تقبلها كلها وتُخرج صيغة واحدة، وإلا فإن نفس
  /// الخانة تُنتج معرّفين مختلفين ويعود الحجز المزدوج من الباب الخلفي.
  static String normalizeTime(String raw) {
    var value = raw.trim().toUpperCase();

    final isPm = value.contains('PM') || value.contains('م');
    final isAm = value.contains('AM') || value.contains('ص');

    // إزالة أي شيء غير الأرقام والنقطتين.
    value = value.replaceAll(RegExp(r'[^0-9:]'), '');

    final parts = value.split(':');
    if (parts.isEmpty || parts[0].isEmpty) return raw.trim();

    var hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    if (isPm && hour != 12) hour += 12;
    if (isAm && hour == 12) hour = 0;

    hour = hour.clamp(0, 23);
    final safeMinute = minute.clamp(0, 59);

    return '${hour.toString().padLeft(2, '0')}:'
        '${safeMinute.toString().padLeft(2, '0')}';
  }

  /// صيغة التاريخ المستخدمة في حقل `appointmentDate` داخل Firestore.
  static String formatDate(DateTime date) => _dateFormat.format(date);
}
