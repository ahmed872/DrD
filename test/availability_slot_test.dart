import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/data/services/availability_service.dart';

/// نموذج التوفّر هو ما يقرّر أي وقت يُعرض للمريض وأيّه يُمنع، فأي خطأ فيه
/// يعني وقتاً يظهر متاحاً ثم يرفضه الخادم عند التأكيد.
void main() {
  Map<String, dynamic> slotMap({
    String status = 'available',
    int capacity = 1,
    int booked = 0,
    String time = '09:00',
    String date = '2030-03-03',
  }) =>
      {
        'slotId': 'doc_${date}_${time.replaceAll(':', '-')}',
        'date': date,
        'startTime': time,
        'endTime': '09:30',
        'capacity': capacity,
        'bookedCount': booked,
        'remainingCapacity': capacity - booked,
        'status': status,
      };

  group('حالة الخانة', () {
    test('الحالات المعروفة تُقرأ كما هي', () {
      expect(SlotStatus.parse('available'), SlotStatus.available);
      expect(SlotStatus.parse('full'), SlotStatus.full);
      expect(SlotStatus.parse('past'), SlotStatus.past);
      expect(SlotStatus.parse('closed'), SlotStatus.closed);
    });

    test('الحالة غير المعروفة تُعامَل كغير متاحة', () {
      // الافتراض الآمن: إظهار خانة لا يقبلها الخادم أسوأ من إخفاء خانة متاحة.
      expect(SlotStatus.parse('brand-new-status'), SlotStatus.closed);
      expect(SlotStatus.parse(null), SlotStatus.closed);
      expect(SlotStatus.parse(42), SlotStatus.closed);
      expect(SlotStatus.parse('brand-new-status').isBookable, isFalse);
    });

    test('المتاح وحده قابل للحجز', () {
      expect(SlotStatus.available.isBookable, isTrue);
      expect(SlotStatus.full.isBookable, isFalse);
      expect(SlotStatus.past.isBookable, isFalse);
      expect(SlotStatus.closed.isBookable, isFalse);
    });

    test('لكل حالة نص عربي', () {
      for (final status in SlotStatus.values) {
        expect(status.arabicLabel, isNotEmpty);
      }
    });
  });

  group('قراءة الخانة', () {
    test('الحقول تُقرأ من رد الخادم', () {
      final slot = AvailabilitySlot.fromMap(
        slotMap(capacity: 4, booked: 3, status: 'available'),
      );
      expect(slot.capacity, 4);
      expect(slot.bookedCount, 3);
      expect(slot.remainingCapacity, 1);
      expect(slot.isGroupSlot, isTrue);
      expect(slot.status, SlotStatus.available);
    });

    test('خانة فردية ليست خانة مجموعة', () {
      expect(AvailabilitySlot.fromMap(slotMap()).isGroupSlot, isFalse);
    });

    test('حقول ناقصة لا تُسقط التطبيق', () {
      final slot = AvailabilitySlot.fromMap({});
      expect(slot.slotId, '');
      expect(slot.capacity, 1);
      expect(slot.status, SlotStatus.closed);
    });
  });

  group('عرض الوقت بالعربية', () {
    test('صباحاً ومساءً ومنتصف الليل والظهر', () {
      String display(String time) =>
          AvailabilitySlot.fromMap(slotMap(time: time)).displayTime;

      expect(display('09:00'), '9:00 ص');
      expect(display('11:30'), '11:30 ص');
      expect(display('12:00'), '12:00 م');
      expect(display('13:15'), '1:15 م');
      expect(display('17:45'), '5:45 م');
      expect(display('00:30'), '12:30 ص');
    });

    test('وقت غير صالح يُعرض كما هو بدل الانهيار', () {
      expect(AvailabilitySlot.fromMap(slotMap(time: 'غير معروف')).displayTime,
          'غير معروف');
    });
  });

  group('توفّر اليوم', () {
    test('يميّز الخانات القابلة للحجز', () {
      final day = DayAvailability(
        date: '2030-03-03',
        slots: [
          AvailabilitySlot.fromMap(slotMap(time: '09:00', status: 'past')),
          AvailabilitySlot.fromMap(slotMap(time: '10:00', status: 'available')),
          AvailabilitySlot.fromMap(slotMap(time: '11:00', status: 'full')),
          AvailabilitySlot.fromMap(slotMap(time: '12:00', status: 'closed')),
        ],
      );
      expect(day.slots.length, 4);
      expect(day.bookable.length, 1);
      expect(day.bookable.single.startTime, '10:00');
      expect(day.hasBookableSlots, isTrue);
      expect(day.isWorkingDay, isTrue);
    });

    test('يوم بلا خانات إطلاقاً ليس يوم عمل', () {
      const day = DayAvailability(date: '2030-03-01', slots: []);
      expect(day.isWorkingDay, isFalse);
      expect(day.hasBookableSlots, isFalse);
    });

    test('يوم كل خاناته محجوزة يبقى يوم عمل بلا مواعيد', () {
      final day = DayAvailability(
        date: '2030-03-03',
        slots: [AvailabilitySlot.fromMap(slotMap(status: 'full'))],
      );
      expect(day.isWorkingDay, isTrue);
      expect(day.hasBookableSlots, isFalse);
    });
  });

  group('نتيجة التوفّر', () {
    AvailabilityResult buildResult() => AvailabilityResult.success({
          '2030-03-01': DayAvailability(
            date: '2030-03-01',
            slots: [AvailabilitySlot.fromMap(slotMap(status: 'full'))],
          ),
          '2030-03-02': const DayAvailability(date: '2030-03-02', slots: []),
          '2030-03-03': DayAvailability(
            date: '2030-03-03',
            slots: [AvailabilitySlot.fromMap(slotMap(status: 'available'))],
          ),
        });

    test('أول يوم قابل للحجز يتخطّى الأيام الممتلئة والمغلقة', () {
      expect(buildResult().firstBookableDate, '2030-03-03');
    });

    test('لا يوم قابل للحجز يُرجع null', () {
      final result = AvailabilityResult.success({
        '2030-03-01': DayAvailability(
          date: '2030-03-01',
          slots: [AvailabilitySlot.fromMap(slotMap(status: 'full'))],
        ),
      });
      expect(result.firstBookableDate, isNull);
    });

    test('الفشل يحمل رسالة ولا يحمل أياماً', () {
      const result =
          AvailabilityResult.failed('تعذّر الاتصال', isNetworkIssue: true);
      expect(result.isSuccess, isFalse);
      expect(result.days, isEmpty);
      expect(result.isNetworkIssue, isTrue);
      expect(result.forDate('2030-03-03'), isNull);
    });
  });
}
