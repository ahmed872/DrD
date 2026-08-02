import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/utils/slot_id.dart';

void main() {
  group('SlotId.normalizeTime', () {
    test('يوحّد كل الصيغ المستخدمة في قاعدة البيانات إلى HH:mm', () {
      // هذه الصيغ الأربع موجودة فعلياً في بيانات التطبيق، وكل واحدة منها
      // كانت تُنتج معرّف خانة مختلفاً — أي أن نفس الموعد يمكن حجزه أربع مرات.
      expect(SlotId.normalizeTime('9:00'), '09:00');
      expect(SlotId.normalizeTime('09:00'), '09:00');
      expect(SlotId.normalizeTime('09:00:00'), '09:00');
      expect(SlotId.normalizeTime('09:00 AM'), '09:00');
    });

    test('يحوّل صيغة 12 ساعة إلى 24 ساعة', () {
      expect(SlotId.normalizeTime('01:30 PM'), '13:30');
      expect(SlotId.normalizeTime('12:00 PM'), '12:00');
      expect(SlotId.normalizeTime('12:00 AM'), '00:00');
      expect(SlotId.normalizeTime('11:45 PM'), '23:45');
    });

    test('يدعم الصباح والمساء بالعربية', () {
      expect(
          SlotId.normalizeTime(
              '٣:٠٠ م'.replaceAll('٣', '3').replaceAll('٠', '0')),
          '15:00');
      expect(SlotId.normalizeTime('9:00 ص'), '09:00');
    });

    test('يتجاهل المسافات الزائدة', () {
      expect(SlotId.normalizeTime('  10:15  '), '10:15');
    });

    test('يحدّ القيم خارج النطاق بدل أن ينهار', () {
      expect(SlotId.normalizeTime('99:99'), '23:59');
    });

    test('يُعيد النص كما هو عند تعذّر التحليل', () {
      expect(SlotId.normalizeTime('غير محدد'), 'غير محدد');
    });
  });

  group('SlotId.forSlot', () {
    final date = DateTime(2026, 3, 7);

    test('ينتج نفس المعرّف لنفس الخانة مهما اختلفت صيغة الوقت', () {
      // جوهر الحماية من الحجز المزدوج: مريضان يرسلان الوقت بصيغتين مختلفتين
      // يجب أن يتنافسا على نفس المستند، لا أن يحصل كل منهما على مستند خاص.
      final a = SlotId.forSlot(doctorId: 'doc1', date: date, time: '09:00');
      final b = SlotId.forSlot(doctorId: 'doc1', date: date, time: '9:00 AM');
      expect(a, b);
    });

    test('يفصل بين الأطباء والتواريخ والأوقات المختلفة', () {
      final base = SlotId.forSlot(doctorId: 'doc1', date: date, time: '09:00');

      expect(base,
          isNot(SlotId.forSlot(doctorId: 'doc2', date: date, time: '09:00')));
      expect(
          base,
          isNot(SlotId.forSlot(
              doctorId: 'doc1', date: DateTime(2026, 3, 8), time: '09:00')));
      expect(base,
          isNot(SlotId.forSlot(doctorId: 'doc1', date: date, time: '09:30')));
    });

    test('لا يحتوي على محارف تكسر مسارات Firestore', () {
      final id = SlotId.forSlot(doctorId: 'doc1', date: date, time: '09:00');
      // الشرطة المائلة تُفسَّر كفاصل مسار، والنقطتان تربكان أدوات التصدير.
      expect(id.contains('/'), isFalse);
      expect(id.contains(':'), isFalse);
      expect(id, 'doc1_2026-03-07_09-00');
    });
  });

  group('SlotId.forAppointment', () {
    final date = DateTime(2026, 3, 7);

    test('نفس المريض ونفس الخانة ينتجان نفس المعرّف', () {
      // يمنع الضغط المزدوج على زر التأكيد من إنشاء حجزين.
      final a = SlotId.forAppointment(
          doctorId: 'doc1', date: date, time: '09:00', patientId: 'p1');
      final b = SlotId.forAppointment(
          doctorId: 'doc1', date: date, time: '09:00 AM', patientId: 'p1');
      expect(a, b);
    });

    test('مريضان مختلفان في نفس الخانة ينتجان معرّفين مختلفين', () {
      // مطلوب لنظام المجموعات الذي يسمح بعدة مرضى في نفس الساعة.
      final a = SlotId.forAppointment(
          doctorId: 'doc1', date: date, time: '09:00', patientId: 'p1');
      final b = SlotId.forAppointment(
          doctorId: 'doc1', date: date, time: '09:00', patientId: 'p2');
      expect(a, isNot(b));
    });
  });

  group('SlotId.formatDate', () {
    test('يستخدم صيغة yyyy-MM-dd المتوافقة مع حقل appointmentDate', () {
      expect(SlotId.formatDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(SlotId.formatDate(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });
}
