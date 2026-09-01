import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/constants/doctor_account_state.dart';

/// حالة الطبيب موزّعة على ثلاثة حقول يكتبها الخادم، وكل شاشة كانت تعيد
/// استنتاجها — أو لا تستنتجها فتعرض للطبيب الموقوف أدوات لا تعمل.
void main() {
  group('استنتاج حالة الحساب', () {
    test('طبيب موثَّق وغير موقوف = نشط', () {
      expect(
        doctorAccountStateFrom({
          'role': 'doctor',
          'isVerified': true,
          'disabled': false,
        }),
        DoctorAccountState.active,
      );
    });

    test('طبيب بلا حقل disabled إطلاقاً = نشط', () {
      // الأطباء السابقون للمرحلة 2 لا يحملون الحقل.
      expect(
        doctorAccountStateFrom({'role': 'doctor', 'isVerified': true}),
        DoctorAccountState.active,
      );
    });

    test('الإيقاف يسبق التوثيق في الأولوية', () {
      // الطبيب الموقوف يبقى `isVerified: true` — تمييز متعمَّد في المرحلة 2.
      // لو غلب التوثيق لظهر «نشط» وانتظر حجوزات لا تأتي.
      expect(
        doctorAccountStateFrom({
          'role': 'doctor',
          'isVerified': true,
          'disabled': true,
        }),
        DoctorAccountState.suspended,
      );
    });

    test('طبيب غير موثَّق = قيد المراجعة', () {
      expect(
        doctorAccountStateFrom({'role': 'doctor', 'isVerified': false}),
        DoctorAccountState.pending,
      );
    });

    test('متقدّم ما زال مريضاً تُقرأ حالته من طلبه', () {
      expect(
        doctorAccountStateFrom({
          'role': 'patient',
          'verificationStatus': 'pending',
        }),
        DoctorAccountState.pending,
      );
      expect(
        doctorAccountStateFrom({
          'role': 'patient',
          'verificationStatus': 'rejected',
        }),
        DoctorAccountState.rejected,
      );
    });

    test('مريض عادي ليس طبيباً', () {
      expect(
        doctorAccountStateFrom({'role': 'patient'}),
        DoctorAccountState.notADoctor,
      );
    });

    test('بيانات ناقصة أو غائبة لا تُسقط الاستنتاج', () {
      expect(doctorAccountStateFrom(null), DoctorAccountState.notADoctor);
      expect(doctorAccountStateFrom({}), DoctorAccountState.notADoctor);
    });

    test('حساب مريض لا يُعامَل كطبيب مهما حمل من حقول', () {
      // حقول توثيق على حساب مريض لا تصنع طبيباً — الدور وحده يقرّر.
      expect(
        doctorAccountStateFrom({
          'role': 'patient',
          'isVerified': true,
          'disabled': false,
        }),
        DoctorAccountState.notADoctor,
      );
    });
  });

  group('ما تسمح به كل حالة', () {
    test('وصول العيادة للنشط والموقوف فقط', () {
      expect(DoctorAccountState.active.hasClinicAccess, isTrue);
      expect(DoctorAccountState.suspended.hasClinicAccess, isTrue);
      expect(DoctorAccountState.pending.hasClinicAccess, isFalse);
      expect(DoctorAccountState.rejected.hasClinicAccess, isFalse);
      expect(DoctorAccountState.notADoctor.hasClinicAccess, isFalse);
    });

    test('الحجوزات الجديدة للنشط وحده', () {
      // الموقوف يرى جدوله ومرضاه، ولا تصله حجوزات جديدة — وهو ما يفرضه
      // الخادم أصلاً في `fetchBookableDoctor`.
      expect(DoctorAccountState.active.acceptsNewBookings, isTrue);
      expect(DoctorAccountState.suspended.acceptsNewBookings, isFalse);
      expect(DoctorAccountState.pending.acceptsNewBookings, isFalse);
    });

    test('لكل حالة نص وشرح عربيان', () {
      for (final state in DoctorAccountState.values) {
        expect(state.arabicLabel, isNotEmpty);
        expect(state.arabicDescription, isNotEmpty);
        // لا رمز لاتيني يتسرّب لواجهة عربية.
        expect(RegExp(r'[A-Za-z]{4,}').hasMatch(state.arabicLabel), isFalse);
      }
    });
  });
}
