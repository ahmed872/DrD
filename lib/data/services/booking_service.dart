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

/// إشغال خانة زمنية واحدة، كما تعرضه شاشة الحجز.
class SlotAvailability {
  const SlotAvailability({required this.booked, this.capacity});

  /// عدد الحجوزات القائمة في الخانة.
  final int booked;

  /// السعة المسجَّلة وقت إنشاء الخانة.
  ///
  /// `null` يعني أنه لا يوجد مستند خانة بعد — أي أن أحداً لم يحجز هذا الوقت،
  /// فالخانة فارغة. المرجع هنا هو السعة المخزَّنة وليست إعدادات الطبيب
  /// الحالية: لو غيّر الطبيب `maxPatientsPerSlot` بعد بدء الحجز، تبقى
  /// الحجوزات القائمة محكومة بالسعة التي حُجزت عليها — وهو نفس ما تفرضه
  /// المعاملة وقاعدة الأمان.
  final int? capacity;

  /// هل امتلأت الخانة؟
  bool get isFull => capacity != null && booked >= capacity!;
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

    // كان هنا فحص مسبق للمواعيد القديمة (`_findLegacyConflict`) يستعلم على
    // `appointments` بفلتر الطبيب والتاريخ. ذلك الاستعلام ترفضه قاعدة الأمان
    // لحساب المريض — تماماً كما كانت ترفض استعلام الإشغال — فكان يفشل دائماً
    // ويُرجع `null` بصمت. أي أنه لم يكن يفحص شيئاً منذ نُشرت القواعد.
    //
    // أُزيل بدل تركه يوهم بحماية غير موجودة. المعاملة أدناه هي الحماية
    // الفعلية، وهي تعمل: تقرأ مستند الخانة (المسموح بقراءته) داخل معاملة
    // ذرّية، فلا يمكن لاثنين تجاوز السعة.

    // كشف التكرار: هل لهذا المريض حجز قائم في هذه الخانة بالفعل؟
    //
    // كان يُفحص عبر `patientIds` داخل مستند الخانة — وهو حقل مقروء لكل
    // مستخدم مسجَّل، فيكشف مَن حجز عند أي طبيب ومتى.
    //
    // البديل الطبيعي كان قراءة مستند الموعد ذي المعرّف المحسوب داخل المعاملة،
    // لكن قراءة مستند **غير موجود** تُقيَّم على قاعدة `allow read: if isOwner()`
    // و`resource` عندها `null`، فتفشل القاعدة بخطأ null وتُرفض القراءة. أي أن
    // ذلك الحل كان سيكسر **كل حجز أول** — التقطه اختبار التزامن الجديد.
    //
    // ولا يجوز حلّه بالسماح بقراءة المستندات غير الموجودة: معرّف الموعد
    // محسوب ومعروف الشكل، فالسماح يكشف "هل لهذا المريض موعد عند هذا الطبيب
    // في هذا الوقت؟" لمن يعرف المعرّفين.
    //
    // الاستعلام أدناه مقيَّد بصاحب الطلب نفسه، فتسمح به القاعدة، ويعطي إجابة
    // دقيقة. والضمان الصلب يبقى في القواعد: كتابة موعد فوق موعد قائم مرفوضة،
    // فتفشل المعاملة كلها ولا يُرفع العدّاد.
    final duplicate = await _hasActiveBookingInSlot(
      doctorId: doctorId,
      patientId: patientId,
      dateStr: dateStr,
      time: normalizedTime,
    );
    if (duplicate) {
      return const BookingResult.failed(
        BookingFailure.alreadyBookedBySamePatient,
        'أنت حاجز هذا الموعد بالفعل',
      );
    }

    try {
      await _db.runTransaction<void>((transaction) async {
        final slotRef = _slots.doc(slotId);
        final appointmentRef = _appointments.doc(appointmentId);

        final slotSnapshot = await transaction.get(slotRef);

        if (!slotSnapshot.exists) {
          // أول حجز في هذه الخانة — نُنشئ القفل ونحجز مكاناً واحداً.
          transaction.set(slotRef, {
            'doctorId': doctorId,
            'appointmentDate': dateStr,
            'startTime': normalizedTime,
            'capacity': capacity,
            'bookedCount': 1,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final data = slotSnapshot.data()!;
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
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        // الموعد يُكتب داخل نفس المعاملة: إمّا ينجح القفل والموعد معاً، أو
        // لا يُكتب أي منهما. لا توجد حالة وسطى تترك عدّاداً مرفوعاً بلا موعد.
        //
        // `cancelledAt` يُحذف صراحةً: إعادة حجز موعد ملغى يجب ألا تُبقي أثر
        // الإلغاء السابق، وقائمة السماح في القواعد تتوقّع اختفاءه.
        transaction.set(appointmentRef, {
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

        // إلغاء موعد ملغى بالفعل يجب ألّا ينقص العدّاد مرة ثانية، وإلّا ظهرت
        // الخانة متاحة لأكثر مما تتسع.
        if (!AppointmentStatus.parse(data['status']).isActive) return;

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

  /// إشغال كل خانة زمنية عند طبيب في يوم محدد.
  ///
  /// ## لماذا `slots` وليس `appointments`؟
  ///
  /// كانت هذه الدالة تستعلم على `appointments` بفلتر `doctorId` والتاريخ فقط.
  /// نتيجة ذلك الاستعلام تحتوي على مواعيد مرضى آخرين، وقاعدة الأمان تسمح
  /// بقراءة الموعد لطرفيه وحدهما — فكان Firestore **يرفض الاستعلام كاملاً**
  /// للمريض. الاستدعاء في شاشة الحجز يلتقط الاستثناء ويسجّله فقط، فتبقى
  /// خريطة الإشغال فارغة و**تظهر كل الخانات متاحة**. المريض كان يكتشف أن
  /// الخانة محجوزة بعد ضغط "تأكيد" فقط.
  ///
  /// مجموعة `slots` موجودة أصلاً لهذا الغرض: هي القفل الذي يمنع الحجز
  /// المزدوج، وتحمل `bookedCount` و`capacity`، وقاعدتها تسمح بالقراءة لأي
  /// مستخدم مسجَّل — لأنها لا تكشف من حجز، بل كم حُجز.
  ///
  /// المعاملة الذرّية في [book] لم تتغير: هي ما زالت الحَكَم الوحيد عند
  /// التزامن. هذه الدالة تخدم العرض فقط.
  ///
  /// ملاحظة عن البيانات القديمة: المواعيد المحجوزة قبل نظام الأقفال ليس لها
  /// مستند خانة، فلا تظهر هنا. لا توجد طريقة آمنة لقراءتها من حساب مريض
  /// (وهذا مقصود)، والحل هو تعبئة مستندات الخانات الناقصة بسكربت إداري —
  /// راجع خطة الهجرة في docs/SECURITY.md.
  Future<Map<String, SlotAvailability>> availabilityFor({
    required String doctorId,
    required DateTime date,
  }) async {
    final snapshot = await _slots
        .where('doctorId', isEqualTo: doctorId)
        .where('appointmentDate', isEqualTo: SlotId.formatDate(date))
        .get();

    final availability = <String, SlotAvailability>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final raw = data['startTime'];
      if (raw == null) continue;
      availability[SlotId.normalizeTime(raw.toString())] = SlotAvailability(
        booked: (data['bookedCount'] as num?)?.toInt() ?? 0,
        capacity: (data['capacity'] as num?)?.toInt(),
      );
    }
    return availability;
  }

  /// هل للمريض حجز قائم في هذه الخانة بالذات؟
  ///
  /// الاستعلام مقيَّد بـ `patientId` الخاص بصاحب الطلب، وهو الشكل الوحيد الذي
  /// تسمح به قاعدة الأمان على `appointments` — الفلترة بالطبيب والتاريخ وحدهما
  /// تُرجع مواعيد مرضى آخرين فيُرفض الاستعلام كاملاً.
  Future<bool> _hasActiveBookingInSlot({
    required String doctorId,
    required String patientId,
    required String dateStr,
    required String time,
  }) async {
    try {
      final snapshot = await _appointments
          .where('doctorId', isEqualTo: doctorId)
          .where('patientId', isEqualTo: patientId)
          .where('appointmentDate', isEqualTo: dateStr)
          .get();

      return snapshot.docs.any((doc) {
        final data = doc.data();
        if (!AppointmentStatus.parse(data['status']).isActive) return false;
        final raw = data['startTime'] ?? data['time'];
        return raw != null && SlotId.normalizeTime(raw.toString()) == time;
      });
    } catch (e) {
      // فشل الفحص المسبق لا يوقف الحجز: القواعد هي الضمان الفعلي، وهذا
      // الاستعلام موجود لتحسين الرسالة لا لتأمين العملية.
      AppLogger.warning('تعذّر فحص الحجز المكرّر: $e');
      return false;
    }
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
