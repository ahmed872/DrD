import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/encounter.dart';

/// نتيجة عملية على سجل سريري.
class EncounterResult {
  const EncounterResult.success()
      : isSuccess = true,
        message = null;

  const EncounterResult.failure(this.message) : isSuccess = false;

  final bool isSuccess;
  final String? message;
}

/// قراءة وكتابة السجلات السريرية.
///
/// **الاستعلامات هنا مقيَّدة بما تستطيع قاعدة الأمان إثباته.** قاعدة
/// `encounters` تسمح بالقراءة لطرفَي السجل، وشرطها مبني على `resource.data`
/// — أي أن الاستعلام يجب أن يحمل القيد نفسه (`patientId ==` أو
/// `doctorId ==`). استعلام بلا قيد يُرفض كاملاً، لا يُرشَّح. هذا درس
/// المرحلة صفر: القاعدة تقبل الاستعلام أو ترفضه، ولا تصفّي نتائجه.
class EncounterService {
  const EncounterService({FirebaseFirestore? firestore})
      : _injected = firestore;

  final FirebaseFirestore? _injected;

  /// يُحلّ عند أول استعمال لا عند البناء، حتى يمكن بناء الخدمة في اختبار
  /// بلا تهيئة Firebase.
  FirebaseFirestore get _db => _injected ?? FirebaseFirestore.instance;

  static const String collectionName = 'encounters';

  CollectionReference<Map<String, dynamic>> get _encounters =>
      _db.collection(collectionName);

  // --- حدود التحقّق، مطابِقة لما تفرضه القواعد ---
  static const int minDiagnosisLength = 2;
  static const int maxDiagnosisLength = 300;
  static const int maxNotesLength = 4000;
  static const int maxFollowUpNotesLength = 1000;

  // ===========================================================================
  // القراءة
  // ===========================================================================

  /// سجلات المريض، الأحدث أولاً.
  Stream<List<Encounter>> watchPatientEncounters(String patientId) {
    return _encounters
        .where('patientId', isEqualTo: patientId)
        .orderBy('encounterDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Encounter.fromSnapshot).toList());
  }

  /// السجلات التي ألّفها هذا الطبيب، الأحدث أولاً.
  ///
  /// ليست «سجلات مرضاه»: طبيب عالج مريضاً لا يرى ما كتبه طبيب آخر عنه.
  /// الوصول لطرف ثالث يمرّ عبر مشاركة صريحة من المريض (المرحلة الرابعة).
  Stream<List<Encounter>> watchDoctorEncounters(String doctorId) {
    return _encounters
        .where('doctorId', isEqualTo: doctorId)
        .orderBy('encounterDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Encounter.fromSnapshot).toList());
  }

  /// سجل زيارة بعينها — قراءة بمعرّف معروف، بلا استعلام ولا فهرس.
  ///
  /// هذا ما يجعله ممكناً: معرّف السجل هو معرّف الموعد.
  Future<Encounter?> fetchForAppointment(String appointmentId) async {
    try {
      final snap = await _encounters.doc(appointmentId).get();
      return snap.exists ? Encounter.fromSnapshot(snap) : null;
    } on FirebaseException {
      return null;
    }
  }

  /// يتابع وجود سجل لزيارة — تستعمله شاشة الطبيب لتقرّر بين «إضافة سجل
  /// الزيارة» و«عرض السجل».
  Stream<Encounter?> watchForAppointment(String appointmentId) {
    return _encounters.doc(appointmentId).snapshots().map(
          (snap) => snap.exists ? Encounter.fromSnapshot(snap) : null,
        );
  }

  // ===========================================================================
  // الكتابة — للطبيب المعالِج وحده
  // ===========================================================================

  /// ينشئ سجل زيارة أو يصحّحه.
  ///
  /// التفرّد بنيوي: المعرّف هو معرّف الموعد، وFirestore لا يقبل مستندين
  /// بنفس المعرّف. محاولتان متزامنتان تنتهيان إلى مستند واحد بلا أي فحص في
  /// العميل — والقاعدة تمنع طبيباً آخر من الكتابة فوقه.
  Future<EncounterResult> save({
    required String appointmentId,
    required String patientId,
    required String doctorId,
    required String doctorName,
    required String doctorSpecialization,
    required String encounterDate,
    required String diagnosis,
    String clinicalNotes = '',
    String treatmentPlan = '',
    String followUpNotes = '',
    String followUpDate = '',
  }) async {
    final ref = _encounters.doc(appointmentId);

    // حقول قائمة السماح وحدها. أي حقل زائد يُسقط الكتابة كلها في القاعدة.
    final payload = <String, dynamic>{
      'appointmentId': appointmentId,
      'patientId': patientId,
      'doctorId': doctorId,
      'doctorName': doctorName,
      'doctorSpecialization': doctorSpecialization,
      'encounterDate': encounterDate,
      'diagnosis': diagnosis.trim(),
      'clinicalNotes': clinicalNotes.trim(),
      'treatmentPlan': treatmentPlan.trim(),
      'followUpNotes': followUpNotes.trim(),
      'followUpDate': followUpDate.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final existing = await ref.get();
      if (existing.exists) {
        // تصحيح: الهوية وتاريخ الإنشاء لا يُرسلان أصلاً، والقاعدة تثبّتهما.
        await ref.update(payload);
      } else {
        await ref.set({
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return const EncounterResult.success();
    } on FirebaseException catch (e) {
      return EncounterResult.failure(_readableError(e));
    } catch (_) {
      return const EncounterResult.failure(
        'تعذّر حفظ سجل الزيارة. تحقّق من اتصالك وحاول مرة أخرى.',
      );
    }
  }

  // ===========================================================================
  // تحقّق النماذج — صدى لما تفرضه القواعد، في مكان يمكن اختباره
  // ===========================================================================

  static String? validateDiagnosis(String? value) {
    final t = (value ?? '').trim();
    if (t.length < minDiagnosisLength) {
      return 'اكتب التشخيص — هو ما يجعل السجل مفيداً لاحقاً.';
    }
    if (t.length > maxDiagnosisLength) {
      return 'التشخيص أطول من الحد المسموح ($maxDiagnosisLength حرفاً).';
    }
    return null;
  }

  static String? validateNotes(String? value) {
    if ((value ?? '').trim().length > maxNotesLength) {
      return 'النص أطول من الحد المسموح ($maxNotesLength حرفاً).';
    }
    return null;
  }

  static String? validateFollowUpNotes(String? value) {
    if ((value ?? '').trim().length > maxFollowUpNotesLength) {
      return 'النص أطول من الحد المسموح '
          '($maxFollowUpNotesLength حرفاً).';
    }
    return null;
  }

  /// يترجم خطأ Firestore إلى جملة يفهمها الطبيب.
  ///
  /// `permission-denied` هنا ليست عطلاً: هي غالباً محاولة توثيق زيارة لم
  /// تكتمل بعد، أو تعديل سجل ألّفه طبيب آخر. «حدث خطأ ما» تخفي ذلك تماماً.
  static String _readableError(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' =>
        'لا يمكن حفظ هذا السجل. تأكّد أن الزيارة مُعلَّمة كمكتملة، وأنك '
            'الطبيب الذي أجراها.',
      'unavailable' ||
      'deadline-exceeded' =>
        'تعذّر الوصول إلى الخادم. تحقّق من اتصالك وحاول مرة أخرى.',
      'not-found' => 'لم يعد هذا الموعد موجوداً.',
      _ => 'تعذّر حفظ سجل الزيارة. حاول مرة أخرى.',
    };
  }
}
