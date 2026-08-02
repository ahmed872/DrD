import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/utils/time_slot_generator.dart';

void main() {
  // تاريخ بعيد في المستقبل حتى لا تتأثر النتائج بمنطق انتهاء الصلاحية.
  final futureDate = DateTime.now().add(const Duration(days: 30));

  group('توليد الخانات', () {
    test('يحترم مدة الكشف ووقت الفاصل بين المرضى', () {
      final slots = TimeSlotGenerator.generateSlots(
        startTimeStr: '09:00',
        endTimeStr: '10:00',
        durationMinutes: 20,
        bufferMinutes: 10,
        date: futureDate,
      );

      // 09:00–09:20، فاصل حتى 09:30، ثم 09:30–09:50. الخانة التالية تبدأ
      // 10:00 وتنتهي 10:20 أي بعد نهاية الدوام، فتُستبعد.
      expect(slots.length, 2);
      expect(slots[0].startTime, '09:00:00');
      expect(slots[0].endTime, '09:20:00');
      expect(slots[1].startTime, '09:30:00');
    });

    test('لا ينتج خانة تتجاوز نهاية الدوام', () {
      final slots = TimeSlotGenerator.generateSlots(
        startTimeStr: '09:00',
        endTimeStr: '09:45',
        durationMinutes: 30,
        bufferMinutes: 0,
        date: futureDate,
      );

      expect(slots.length, 1);
      expect(slots.single.endTime, '09:30:00');
    });

    test('يعلّم الخانات المحجوزة', () {
      final slots = TimeSlotGenerator.generateSlots(
        startTimeStr: '09:00',
        endTimeStr: '11:00',
        durationMinutes: 60,
        bufferMinutes: 0,
        date: futureDate,
        bookedSlots: const ['09:00:00'],
      );

      expect(slots.first.isBooked, isTrue);
      expect(slots.last.isBooked, isFalse);
    });

    test('يُرجع قائمة فارغة عند وقت بداية غير صالح بدل أن ينهار', () {
      final slots = TimeSlotGenerator.generateSlots(
        startTimeStr: 'مفتوح',
        endTimeStr: '17:00',
        durationMinutes: 30,
        bufferMinutes: 0,
        date: futureDate,
      );

      expect(slots, isEmpty);
    });

    test('يُرجع قائمة فارغة عندما تسبق النهاية البداية', () {
      final slots = TimeSlotGenerator.generateSlots(
        startTimeStr: '17:00',
        endTimeStr: '09:00',
        durationMinutes: 30,
        bufferMinutes: 0,
        date: futureDate,
      );

      expect(slots, isEmpty);
    });
  });

  group('انتهاء الصلاحية', () {
    test('كل خانات الأيام الماضية منتهية', () {
      final slots = TimeSlotGenerator.generateSlots(
        startTimeStr: '09:00',
        endTimeStr: '17:00',
        durationMinutes: 60,
        bufferMinutes: 0,
        date: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(slots, isNotEmpty);
      expect(slots.every((s) => s.isExpired), isTrue);
    });

    test('خانات الأيام القادمة غير منتهية', () {
      final slots = TimeSlotGenerator.generateSlots(
        startTimeStr: '09:00',
        endTimeStr: '17:00',
        durationMinutes: 60,
        bufferMinutes: 0,
        date: futureDate,
      );

      expect(slots, isNotEmpty);
      expect(slots.any((s) => s.isExpired), isFalse);
    });

    test('خانة اليوم تنتهي بعد مرور 10 دقائق على بدايتها', () {
      // سياسة التطبيق: من يتأخّر أكثر من 10 دقائق يفقد دوره.
      final now = DateTime.now();
      final startedTwentyMinutesAgo = now.subtract(const Duration(minutes: 20));

      final slots = TimeSlotGenerator.generateSlots(
        startTimeStr: '${startedTwentyMinutesAgo.hour.toString().padLeft(2, '0')}'
            ':${startedTwentyMinutesAgo.minute.toString().padLeft(2, '0')}',
        endTimeStr: '23:59',
        durationMinutes: 5,
        bufferMinutes: 0,
        date: DateTime(now.year, now.month, now.day),
      );

      expect(slots, isNotEmpty);
      expect(slots.first.isExpired, isTrue,
          reason: 'خانة بدأت قبل 20 دقيقة يجب أن تكون منتهية');
    });
  });
}
