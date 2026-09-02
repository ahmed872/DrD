import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_appointment_app/core/theme/app_theme.dart';
import 'package:medical_appointment_app/data/services/doctor_application_service.dart';
import 'package:medical_appointment_app/presentation/widgets/app_widgets.dart';

/// طلب الانضمام كطبيب: الحالة، وعرضها، ووصولها.
void main() {
  group('قراءة حالة الطلب', () {
    test('الحالات الأربع تُقرأ من نصّها السلكي', () {
      expect(DoctorApplicationStatus.parse('pending'),
          DoctorApplicationStatus.pending);
      expect(DoctorApplicationStatus.parse('approved'),
          DoctorApplicationStatus.approved);
      expect(DoctorApplicationStatus.parse('rejected'),
          DoctorApplicationStatus.rejected);
    });

    test('غياب المستند أو حالة مجهولة = لا طلب', () {
      // الافتراض الآمن: من لا طلب له يرى دعوة للتقديم، لا حالة مخترَعة.
      expect(DoctorApplicationStatus.parse(null), DoctorApplicationStatus.none);
      expect(DoctorApplicationStatus.parse('whatever'),
          DoctorApplicationStatus.none);
      expect(DoctorApplicationSnapshot.fromMap(null).status,
          DoctorApplicationStatus.none);
    });

    test('الحقول الناقصة تعطي نصوصاً فارغة لا انهياراً', () {
      // مستندات كُتبت بإصدارات سابقة قد لا تحمل كل الحقول.
      final snap = DoctorApplicationSnapshot.fromMap({'status': 'pending'});
      expect(snap.status, DoctorApplicationStatus.pending);
      expect(snap.specialization, isEmpty);
      expect(snap.rejectionReason, isEmpty);
      expect(snap.submittedAt, isNull);
    });

    test('سبب الرفض يُقرأ ليُعرض لصاحبه', () {
      final snap = DoctorApplicationSnapshot.fromMap({
        'status': 'rejected',
        'specialization': ' جلدية ',
        'rejectionReason': 'نحتاج رقم ترخيص ساري',
      });
      expect(snap.status, DoctorApplicationStatus.rejected);
      expect(snap.specialization, 'جلدية'); // مقصوص
      expect(snap.rejectionReason, 'نحتاج رقم ترخيص ساري');
    });

    test('«قُدّم طلب» يميّز من له طلب عمّن لا طلب له', () {
      expect(DoctorApplicationStatus.none.isSubmitted, isFalse);
      for (final s in [
        DoctorApplicationStatus.pending,
        DoctorApplicationStatus.approved,
        DoctorApplicationStatus.rejected,
      ]) {
        expect(s.isSubmitted, isTrue, reason: s.name);
      }
    });
  });

  group('وصول مسار التقديم', () {
    test('بطاقة التقديم مستدعاة فعلاً من الرئيسية', () {
      // ===== حارس العطب الحقيقي =====
      //
      // قبل المرحلة 11 كانت `DoctorApplicationScreen` مكتملة، و
      // `case 'doctor_application'` معرَّفاً في `home_screen` — ولم يكن في
      // التطبيق كلّه **سطر واحد يستدعيه**. شاشة كاملة لا يصل إليها أحد،
      // فبدا تسجيل الأطباء غير متاح. لا اختبار سلوكي يلتقط هذا: الشاشة
      // نفسها تعمل بلا عيب.
      final home =
          File('lib/presentation/screens/home_screen.dart').readAsStringSync();
      expect(home, contains('DoctorApplicationCard'),
          reason: 'مدخل التقديم كطبيب غير موجود على الرئيسية');
      expect(home, contains("'doctor_application'"),
          reason: 'مسار التقديم غير موصول');
    });

    test('لا رسالة نجاح تُكتب في قناة الخطأ', () {
      // العطب الآخر الذي رُصد على الجهاز: نجاح التسجيل كان يُكتب في
      // `_errorMessage` فيظهر بلوح أحمر يطالب بتفعيل بريد لا يُرسَل أصلاً.
      final auth = File('lib/presentation/providers/firebase_auth_service.dart')
          .readAsStringSync();
      final successIntoError = RegExp(r"_errorMessage = '[^']*(نجاح|✅)");
      expect(successIntoError.hasMatch(auth), isFalse,
          reason: 'رسالة نجاح في قناة الخطأ — استعمل _successMessage');
      expect(auth, contains('_successMessage'));
    });
  });

  group('لافتة الرسالة', () {
    testWidgets('النجاح والخطأ نبرتان مختلفتان لا لوحٌ واحد', (tester) async {
      Future<void> pump(BannerTone tone) => tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: MessageBanner(message: 'رسالة', tone: tone),
            ),
          ));

      await pump(BannerTone.success);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      await pump(BannerTone.danger);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      // الأيقونة تختلف مع النبرة: المعنى لا يعتمد على اللون وحده.
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    });
  });
}
