import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/constants/appointment_status.dart';

void main() {
  group('AppointmentStatus.parse', () {
    test('يقبل كل الصيغ القديمة الموجودة في قاعدة البيانات', () {
      // هذه القيم كُتبت فعلياً في مستندات حقيقية على مدار تطوير التطبيق.
      // لو توقّف التحليل عن قبول أي منها تختفي مواعيد مرضى من الشاشة.
      for (final legacy in ['Booked', 'Scheduled', 'upcoming', 'pending']) {
        expect(AppointmentStatus.parse(legacy), AppointmentStatus.booked,
            reason: 'الصيغة القديمة "$legacy" يجب أن تُقرأ كموعد قائم');
      }
    });

    test('لا يفرّق بين حالة الأحرف', () {
      expect(AppointmentStatus.parse('COMPLETED'), AppointmentStatus.completed);
      expect(AppointmentStatus.parse('completed'), AppointmentStatus.completed);
      expect(AppointmentStatus.parse('Completed'), AppointmentStatus.completed);
    });

    test('يقبل الإملاءين الأمريكي والبريطاني للإلغاء', () {
      expect(AppointmentStatus.parse('Cancelled'), AppointmentStatus.cancelled);
      expect(AppointmentStatus.parse('Canceled'), AppointmentStatus.cancelled);
    });

    test('يتعامل مع null والقيم غير المعروفة كموعد قائم', () {
      // إخفاء موعد مكتوب في قاعدة البيانات أسوأ من عرضه بحالة افتراضية:
      // المريض سيحضر بأي حال.
      expect(AppointmentStatus.parse(null), AppointmentStatus.booked);
      expect(AppointmentStatus.parse(''), AppointmentStatus.booked);
      expect(AppointmentStatus.parse('شيء غريب'), AppointmentStatus.booked);
    });

    test('يتجاهل المسافات داخل القيمة وحولها', () {
      expect(AppointmentStatus.parse(' Pending Confirmation '),
          AppointmentStatus.pendingConfirmation);
    });
  });

  group('الخانات المشغولة', () {
    test('الحالات القائمة والمكتملة تشغل الخانة', () {
      expect(AppointmentStatus.occupying, contains(AppointmentStatus.booked));
      expect(
          AppointmentStatus.occupying, contains(AppointmentStatus.completed));
    });

    test('الملغي والمنتهي لا يشغلان الخانة', () {
      // وإلا بقيت خانة ملغاة تبدو محجوزة ولا يستطيع أحد أخذها.
      expect(AppointmentStatus.occupying,
          isNot(contains(AppointmentStatus.cancelled)));
      expect(AppointmentStatus.occupying,
          isNot(contains(AppointmentStatus.expired)));
    });

    test('قائمة قيم whereIn تغطي الصيغ القديمة والجديدة', () {
      final values = AppointmentStatus.occupyingWireValues;
      expect(values, contains('booked'));
      expect(values, contains('scheduled'));
      expect(values, contains('upcoming'));
      expect(values, contains('Booked'));
      // حدّ Firestore لعامل whereIn هو 30 قيمة.
      expect(values.length, lessThanOrEqualTo(30));
    });
  });

  group('الخصائص المشتقّة', () {
    test('الموعد القائم وحده قابل للإلغاء', () {
      expect(AppointmentStatus.booked.isCancellable, isTrue);
      expect(AppointmentStatus.completed.isCancellable, isFalse);
      expect(AppointmentStatus.cancelled.isCancellable, isFalse);
    });

    test('لكل حالة نص عربي غير فارغ', () {
      for (final status in AppointmentStatus.values) {
        expect(status.arabicLabel, isNotEmpty);
        expect(status.wireValue, isNotEmpty);
      }
    });
  });
}
