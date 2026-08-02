import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/appointment_status.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/slot_id.dart';

/// سبب فشل الحجز — يُترجم لرسالة عربية في الواجهة.
enum BookingFailure {
  /// الخانة امتلأت بينما كان المريض يؤكّد.
  slotTaken,

  /// المريض حاجز نفس الخانة بالفعل.
  alreadyBookedBySamePatient,

  /// المريض عنده موعد آخر عند نفس الطبيب في نفس اليوم.
  duplicateSameDay,

  /// الوقت المطلوب مضى بالفعل.
  slotInThePast,

  /// خطأ شبكة أو صلاحيات.
  unknown,
}

/// نتيجة محاولة الحجز.
class BookingResult {
  const BookingResult.success(this.appointmentId)
      : failure = null,
        message = 'تم حجز الموعد بنجاح، ألف سلامة عليك';

  const BookingResult.failed(this.failure, this.message) : appointmentId = null;

  final String? appointmentId;
  final BookingFailure? failure;
  final String message;

  bool get isSuccess => failure == null;
}

/// حجز المواعيد بشكل ذرّي (atomic).
///
/// ## المشكلة التي يحلّها هذا الملف
///
/// الكود السابق كان يحجز هكذا:
///
/// ```dart
/// await FirebaseFirestore.instance.collection('appointments').add({...});
/// ```
///
/// `add()` تُنشئ مستنداً بمعرّف عشوائي وتنجح **دائماً**. فحص "هل الخانة
/// محجوزة؟" كان يحدث في الواجهة قبل ذلك بثوانٍ. النتيجة: لو ضغط مريضان
/// "تأكيد" في نفس اللحظة، ينجح الاثنان ويصل الاثنان للعيادة في نفس التوقيت —
/// وهو بالضبط الانتظار الذي بُني التطبيق لتفاديه.
///
/// ## الحل
///
/// كل خانة زمنية صار لها مستند واحد في `slots/{doctorId}_{date}_{time}` يعمل
/// كقفل. الحجز يمرّ داخل [FirebaseFirestore.runTransaction]، فيقرأ عدّاد
/// الخانة ويزيده في عملية واحدة غير قابلة للتجزئة. لو حاول اثنان في نفس
/// الميلي ثانية، Firestore يُعيد تشغيل إحدى المعاملتين ويراها العدّاد ممتلئاً
/// فتفشل بوضوح. القاعدة نفسها مكتوبة أيضاً في `firestore.rules` حتى لا يستطيع
/// عميل معدَّل تجاوزها.
class BookingService {
  BookingService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _slots =>
      _db.collection('slots');
  CollectionReference<Map<String, dynamic>> get _appointments =>
      _db.collection('appointments');

  /// حجز خانة زمنية.
  ///
  /// [capacity] عدد المرضى المسموح بهم في الخانة: 1 لنظام الحجز الفردي،
  /// و`maxPatientsPerSlot` لنظام المجموعات.
  Future<BookingResult> book({
    required String doctorId,
    required String patientId,
    required DateTime date,
    required String time,
    required int capacity,
    required Map<String, dynamic> appointmentData,
  }) async {
    final normalizedTime = SlotId.normalizeTime(time);
    final dateStr = SlotId.formatDate(date);
    final slotId = SlotId.forSlot(
      doctorId: doctorId,
      date: date,
      time: normalizedTime,
    );
    final appointmentId = SlotId.forAppointment(
      doctorId: doctorId,
      date: date,
      time: normalizedTime,
      patientId: patientId,
    );

    // حارس زمني: لا يُسمح بحجز وقت مضى. يُفحص هنا وفي firestore.rules معاً.
    if (_isInThePast(date, normalizedTime)) {
      return const BookingResult.failed(
        BookingFailure.slotInThePast,
        'لا يمكن الحجز في وقت مضى، اختر موعداً لاحقاً',
      );
    }

    // فحص مسبق للمواعيد القديمة التي أُنشئت قبل نظام الأقفال، فهي لا تملك
    // مستند خانة يحميها. هذا الفحص غير ذرّي بطبيعته — المعاملة أدناه هي التي
    // تتكفّل بحالة التزامن الحقيقية — لكنه يمنع التصادم مع البيانات القديمة.
    final legacyConflict = await _findLegacyConflict(
      doctorId: doctorId,
      dateStr: dateStr,
      time: normalizedTime,
      patientId: patientId,
      capacity: capacity,
    );
    if (legacyConflict != null) return legacyConflict;

    try {
      await _db.runTransaction<void>((transaction) async {
        final slotRef = _slots.doc(slotId);
        final slotSnapshot = await transaction.get(slotRef);

        if (!slotSnapshot.exists) {
          // أول حجز في هذه الخانة — نُنشئ القفل ونحجز مكاناً واحداً.
          transaction.set(slotRef, {
            'doctorId': doctorId,
            'appointmentDate': dateStr,
            'startTime': normalizedTime,
            'capacity': capacity,
            'bookedCount': 1,
            'patientIds': [patientId],
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final data = slotSnapshot.data()!;
          final patientIds = List<String>.from(
            (data['patientIds'] as List<dynamic>? ?? const <dynamic>[])
                .map((e) => e.toString()),
          );

          if (patientIds.contains(patientId)) {
            throw const _BookingException(
              BookingFailure.alreadyBookedBySamePatient,
              'أنت حاجز هذا الموعد بالفعل',
            );
          }

          final bookedCount = (data['bookedCount'] as num?)?.toInt() ?? 0;
          // سعة الخانة المسجّلة وقت إنشائها هي المرجع، حتى لا يغيّر الطبيب
          // إعداداته فيُفسد حجوزات قائمة.
          final slotCapacity = (data['capacity'] as num?)?.toInt() ?? capacity;

          if (bookedCount >= slotCapacity) {
            throw const _BookingException(
              BookingFailure.slotTaken,
              'للأسف تم حجز هذا الموعد للتو، اختر وقتاً آخر',
            );
          }

          transaction.update(slotRef, {
            'bookedCount': bookedCount + 1,
            'patientIds': FieldValue.arrayUnion([patientId]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        // الموعد يُكتب داخل نفس المعاملة: إمّا ينجح القفل والموعد معاً، أو
        // لا يُكتب أي منهما. لا توجد حالة وسطى تترك عدّاداً مرفوعاً بلا موعد.
        transaction.set(_appointments.doc(appointmentId), {
          ...appointmentData,
          'doctorId': doctorId,
          'patientId': patientId,
          'appointmentDate': dateStr,
          'startTime': normalizedTime,
          'slotId': slotId,
          'status': AppointmentStatus.booked.wireValue,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      AppLogger.success('تم الحجز: $appointmentId');
      return BookingResult.success(appointmentId);
    } on _BookingException catch (e) {
      AppLogger.warning('فشل الحجز (${e.failure.name}): ${e.message}');
      return BookingResult.failed(e.failure, e.message);
    } on FirebaseException catch (e) {
      AppLogger.error('خطأ Firestore أثناء الحجز', e);
      // `permission-denied` هنا غالباً يعني أن قاعدة الأمان رفضت تجاوز السعة،
      // أي أن الخانة امتلأت فعلاً.
      if (e.code == 'permission-denied') {
        return const BookingResult.failed(
          BookingFailure.slotTaken,
          'للأسف تم حجز هذا الموعد للتو، اختر وقتاً آخر',
        );
      }
      return const BookingResult.failed(
        BookingFailure.unknown,
        'تعذّر إتمام الحجز، تأكد من اتصالك بالإنترنت وحاول مرة أخرى',
      );
    } catch (e, s) {
      AppLogger.error('خطأ غير متوقع أثناء الحجز', e, s);
      return const BookingResult.failed(
        BookingFailure.unknown,
        'حدث خطأ غير متوقع، حاول مرة أخرى',
      );
    }
  }

  /// إلغاء موعد وتحرير مكانه في الخانة، في معاملة واحدة.
  ///
  /// بدون هذا، الإلغاء كان يترك العدّاد مرفوعاً فتبقى الخانة تبدو ممتلئة
  /// للأبد رغم أن أحداً لا يستخدمها.
  Future<bool> cancel({required String appointmentId}) async {
    try {
      await _db.runTransaction<void>((transaction) async {
        final appointmentRef = _appointments.doc(appointmentId);
        final appointmentSnapshot = await transaction.get(appointmentRef);

        if (!appointmentSnapshot.exists) return;

        final data = appointmentSnapshot.data()!;
        final slotId = data['slotId'] as String?;
        // يُقرأ من المستند نفسه بدل تمريره من الواجهة: الطبيب يُلغي مواعيد
        // مرضاه، ولا يملك معرّف المريض في يده عند الضغط على زر الإلغاء.
        final patientId = (data['patientId'] ?? '').toString();

        // المواعيد القديمة لا تحمل `slotId`؛ نلغيها بدون لمس أي قفل.
        if (slotId != null && slotId.isNotEmpty) {
          final slotRef = _slots.doc(slotId);
          final slotSnapshot = await transaction.get(slotRef);
          if (slotSnapshot.exists) {
            final bookedCount =
                (slotSnapshot.data()!['bookedCount'] as num?)?.toInt() ?? 0;
            transaction.update(slotRef, {
              // `clamp` يحمي من عدّاد سالب لو تكرّر الإلغاء لأي سبب.
              'bookedCount': (bookedCount - 1).clamp(0, 1 << 30),
              'patientIds': FieldValue.arrayRemove([patientId]),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }

        transaction.update(appointmentRef, {
          'status': AppointmentStatus.cancelled.wireValue,
          'cancelledAt': FieldValue.serverTimestamp(),
        });
      });
      return true;
    } catch (e, s) {
      AppLogger.error('فشل إلغاء الموعد', e, s);
      return false;
    }
  }

  /// عدد الحجوزات القائمة لكل خانة زمنية عند طبيب في يوم محدد.
  ///
  /// يُرجع عدداً وليس مجرد "محجوز/متاح" لأن نظام المجموعات يسمح بعدة مرضى في
  /// نفس الخانة، والواجهة تحتاج أن تعرض "٣ من ٤".
  ///
  /// يقرأ من `appointments` وليس من `slots` عمداً: مجموعة `slots` حديثة، بينما
  /// `appointments` تحتوي على كل المواعيد بما فيها ما حُجز قبل هذا التحديث.
  Future<Map<String, int>> bookedCountsFor({
    required String doctorId,
    required DateTime date,
  }) async {
    final snapshot = await _appointments
        .where('doctorId', isEqualTo: doctorId)
        .where('appointmentDate', isEqualTo: SlotId.formatDate(date))
        .get();

    final counts = <String, int>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (!AppointmentStatus.occupying.contains(
        AppointmentStatus.parse(data['status']),
      )) {
        continue;
      }
      final raw = data['startTime'] ?? data['time'];
      if (raw == null) continue;
      final time = SlotId.normalizeTime(raw.toString());
      counts[time] = (counts[time] ?? 0) + 1;
    }
    return counts;
  }

  /// هل للمريض موعد قائم عند هذا الطبيب في هذا اليوم؟
  Future<bool> hasAppointmentOnDate({
    required String doctorId,
    required String patientId,
    required DateTime date,
  }) async {
    final snapshot = await _appointments
        .where('doctorId', isEqualTo: doctorId)
        .where('patientId', isEqualTo: patientId)
        .where('appointmentDate', isEqualTo: SlotId.formatDate(date))
        .get();

    return snapshot.docs.any(
      (doc) => AppointmentStatus.parse(doc.data()['status']).isActive,
    );
  }

  Future<BookingResult?> _findLegacyConflict({
    required String doctorId,
    required String dateStr,
    required String time,
    required String patientId,
    required int capacity,
  }) async {
    try {
      final snapshot = await _appointments
          .where('doctorId', isEqualTo: doctorId)
          .where('appointmentDate', isEqualTo: dateStr)
          .get();

      var sameSlotCount = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = AppointmentStatus.parse(data['status']);
        if (!AppointmentStatus.occupying.contains(status)) continue;

        final raw = data['startTime'] ?? data['time'];
        if (raw == null) continue;
        if (SlotId.normalizeTime(raw.toString()) != time) continue;

        if (data['patientId'] == patientId) {
          return const BookingResult.failed(
            BookingFailure.alreadyBookedBySamePatient,
            'أنت حاجز هذا الموعد بالفعل',
          );
        }
        sameSlotCount++;
      }

      if (sameSlotCount >= capacity) {
        return const BookingResult.failed(
          BookingFailure.slotTaken,
          'للأسف تم حجز هذا الموعد للتو، اختر وقتاً آخر',
        );
      }
      return null;
    } catch (e) {
      // فشل الفحص المسبق ليس سبباً لإيقاف الحجز — المعاملة أدناه هي خط
      // الدفاع الحقيقي، وهي التي تحسم النتيجة.
      AppLogger.warning('تعذّر الفحص المسبق للمواعيد القديمة: $e');
      return null;
    }
  }

  bool _isInThePast(DateTime date, String time) {
    final parts = time.split(':');
    if (parts.length < 2) return false;
    final slotStart = DateTime(
      date.year,
      date.month,
      date.day,
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 0,
    );
    return slotStart.isBefore(DateTime.now());
  }
}

/// استثناء داخلي لإخراج سبب الفشل من داخل المعاملة.
class _BookingException implements Exception {
  const _BookingException(this.failure, this.message);

  final BookingFailure failure;
  final String message;
}
