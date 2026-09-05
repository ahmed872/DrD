import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/data/services/booking_service.dart';

/// شاشة الحجز تقرر إظهار الوقت أو إخفاءه بناءً على هذه القيمة وحدها، فخطأ
/// هنا يعني إمّا إخفاء أوقات متاحة أو عرض أوقات محجوزة على أنها متاحة —
/// وهو بالضبط العطل الذي كانت تعاني منه الشاشة قبل هذه المرحلة.
void main() {
  group('SlotAvailability', () {
    test('خانة بلا مستند تعني لا أحد حجز', () {
      // `availabilityFor` لا تُرجع مدخلاً للأوقات التي لم يحجزها أحد، فتقع
      // الشاشة على القيمة الافتراضية. يجب ألا تُقرأ كخانة ممتلئة.
      const slot = SlotAvailability(booked: 0);
      expect(slot.capacity, isNull);
      expect(slot.isFull, isFalse);
    });

    test('خانة فردية محجوزة تعتبر ممتلئة', () {
      const slot = SlotAvailability(booked: 1, capacity: 1);
      expect(slot.isFull, isTrue);
    });

    test('خانة مجموعات تبقى متاحة حتى تبلغ سعتها', () {
      expect(const SlotAvailability(booked: 0, capacity: 4).isFull, isFalse);
      expect(const SlotAvailability(booked: 3, capacity: 4).isFull, isFalse);
      expect(const SlotAvailability(booked: 4, capacity: 4).isFull, isTrue);
    });

    test('عدّاد تجاوز السعة يبقى ممتلئاً ولا ينقلب', () {
      // لا يُفترض أن يحدث — القاعدة والمعاملة تمنعانه — لكن بيانات قديمة قد
      // تحمل عدّاداً أعلى من السعة، ويجب ألا تُعرض الخانة عندها كمتاحة.
      expect(const SlotAvailability(booked: 5, capacity: 4).isFull, isTrue);
    });

    test('سعة صفرية تعني خانة مغلقة', () {
      expect(const SlotAvailability(booked: 0, capacity: 0).isFull, isTrue);
    });
  });
}
