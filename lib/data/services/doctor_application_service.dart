import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/doctor_application_status.dart';
import '../models/doctor_application.dart';

/// نتيجة عملية على طلب — نجاح، أو رسالة عربية تشرح السبب.
///
/// الرسالة تُصاغ هنا لا في الشاشة: خطأ `permission-denied` القادم من
/// Firestore لا يعني شيئاً للطبيب، وترجمته في كل موضع استدعاء تُنتج نصوصاً
/// مختلفة لنفس الحالة.
class ApplicationResult {
  const ApplicationResult.success()
      : isSuccess = true,
        message = null;

  const ApplicationResult.failure(this.message) : isSuccess = false;

  final bool isSuccess;
  final String? message;
}

/// قراءة وكتابة طلبات الأطباء.
///
/// **ما لا تفعله هذه الخدمة**: لا تكتب `status: approved` ولا `reviewedBy`
/// ولا `reviewedAt` من مسار مقدّم الطلب، ولا تكتب `role` إطلاقاً. تلك حقول
/// يملكها المشرف أو الخادم، وقواعد الأمان ترفضها من هنا حتى لو كُتبت خطأً.
class DoctorApplicationService {
  const DoctorApplicationService({FirebaseFirestore? firestore})
      : _injected = firestore;

  final FirebaseFirestore? _injected;

  /// يُحلّ عند أول استعمال لا عند البناء: إنشاء الخدمة في اختبار لا يجب أن
  /// يتطلّب تهيئة Firebase.
  FirebaseFirestore get _db => _injected ?? FirebaseFirestore.instance;

  static const String collectionName = 'doctor_applications';

  CollectionReference<Map<String, dynamic>> get _applications =>
      _db.collection(collectionName);

  /// طلب المستخدم الحالي، متدفّقاً.
  ///
  /// عدم وجود المستند يُقرأ [DoctorApplicationStatus.none] لا خطأً: «لم
  /// يتقدّم بعد» حالة طبيعية، لا فشل تحميل.
  Stream<DoctorApplication> watchMyApplication(String uid) {
    return _applications.doc(uid).snapshots().map(
          (snap) => snap.exists
              ? DoctorApplication.fromSnapshot(snap)
              : DoctorApplication.none(uid),
        );
  }

  Future<DoctorApplication> fetchMyApplication(String uid) async {
    final snap = await _applications.doc(uid).get();
    return snap.exists
        ? DoctorApplication.fromSnapshot(snap)
        : DoctorApplication.none(uid);
  }

  /// يقدّم طلباً جديداً أو يعيد تقديم طلب مرفوض.
  ///
  /// الحالتان كتابة واحدة من جهة الواجهة، لكنهما عمليتان مختلفتان في
  /// القواعد: الأولى `create` والثانية `update` مقيّدة بـ
  /// `rejected → pending`. الفرق يقرّره وجود المستند، لا العميل.
  Future<ApplicationResult> submit({
    required String uid,
    required String applicantName,
    required String specialty,
    required String professionalBio,
    required int yearsOfExperience,
    String applicantNotes = '',
  }) async {
    // حقول مقدّم الطلب وحدها. أي حقل زائد هنا يُسقط الكتابة كلها في
    // القواعد (`hasOnly`) — وهذا مقصود: الخطأ يجب أن يُرى، لا أن يُتجاهل.
    final payload = <String, dynamic>{
      'applicantId': uid,
      'applicantName': applicantName.trim(),
      'specialty': specialty.trim(),
      'professionalBio': professionalBio.trim(),
      'yearsOfExperience': yearsOfExperience,
      'applicantNotes': applicantNotes.trim(),
      'status': DoctorApplicationStatus.pending.wireValue,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final ref = _applications.doc(uid);
      final existing = await ref.get();

      if (existing.exists) {
        final current =
            DoctorApplicationStatus.parse(existing.data()?['status']);
        if (!current.isEditable) {
          return ApplicationResult.failure(
            current.isApproved
                ? 'طلبك مقبول بالفعل.'
                : 'طلبك قيد المراجعة، ولا يمكن تعديله الآن.',
          );
        }
        // `update` لا `set`: الأخيرة تمحو حقول المراجعة السابقة، والقاعدة
        // ترفض ذلك أصلاً — لكن الرفض من الخادم رسالة خطأ، والصواب هنا
        // ألّا نطلب ما لا يجوز.
        await ref.update(payload);
      } else {
        await ref.set({
          ...payload,
          'submittedAt': FieldValue.serverTimestamp(),
        });
      }
      return const ApplicationResult.success();
    } on FirebaseException catch (e) {
      return ApplicationResult.failure(_readableError(e));
    } catch (_) {
      return const ApplicationResult.failure(
        'تعذّر إرسال الطلب. تحقّق من اتصالك وحاول مرة أخرى.',
      );
    }
  }

  // ===========================================================================
  // مسار المشرف
  // ===========================================================================

  /// طلبات المراجعة، مصفّاة بالحالة.
  ///
  /// `null` تعني الكل. الترتيب بتاريخ التحديث تنازلياً حتى يظهر أحدث ما
  /// يحتاج قراراً في الأعلى.
  Stream<List<DoctorApplication>> watchApplications({
    DoctorApplicationStatus? status,
  }) {
    Query<Map<String, dynamic>> q = _applications;
    if (status != null && status != DoctorApplicationStatus.none) {
      q = q.where('status', isEqualTo: status.wireValue);
    }
    return q
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(DoctorApplication.fromSnapshot).toList());
  }

  /// قبول طلب.
  ///
  /// هذه الكتابة تسجّل **القرار** فقط. ترقية المستخدم إلى طبيب تجري في
  /// دالة `onDoctorApplicationDecision` على الخادم: لا يملك أي عميل — ولا
  /// المشرف — كتابة `role`.
  Future<ApplicationResult> approve({
    required String applicationId,
    required String reviewerId,
  }) async {
    try {
      await _applications.doc(applicationId).update({
        'status': DoctorApplicationStatus.approved.wireValue,
        'reviewedBy': reviewerId,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      return const ApplicationResult.success();
    } on FirebaseException catch (e) {
      return ApplicationResult.failure(_readableError(e));
    }
  }

  /// رفض طلب بسبب مكتوب.
  ///
  /// السبب مفروض في القاعدة أيضاً، لا هنا وحده: رفض بلا سبب يترك الطبيب
  /// أمام باب مغلق بلا معرفة ما يصحّحه.
  Future<ApplicationResult> reject({
    required String applicationId,
    required String reviewerId,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.length < minRejectionReasonLength) {
      return const ApplicationResult.failure(
        'اكتب سبباً واضحاً يساعد الطبيب على تصحيح طلبه.',
      );
    }
    try {
      await _applications.doc(applicationId).update({
        'status': DoctorApplicationStatus.rejected.wireValue,
        'reviewedBy': reviewerId,
        'reviewedAt': FieldValue.serverTimestamp(),
        'rejectionReason': trimmed,
      });
      return const ApplicationResult.success();
    } on FirebaseException catch (e) {
      return ApplicationResult.failure(_readableError(e));
    }
  }

  // --- حدود التحقق، مطابِقة لما تفرضه القواعد ---
  static const int minSpecialtyLength = 2;
  static const int maxSpecialtyLength = 80;
  static const int minBioLength = 20;
  static const int maxBioLength = 1000;
  static const int maxYearsOfExperience = 70;
  static const int minRejectionReasonLength = 10;
  static const int maxRejectionReasonLength = 500;

  // ===========================================================================
  // تحقّق النماذج
  //
  // مستقلّ عن الشاشة عمداً: هذه القيود صدى لما تفرضه `firestore.rules`،
  // ونسخة منها داخل دالة بناء لا يمكن اختبارها ولا مقارنتها بالقاعدة.
  // ===========================================================================

  static String? validateName(String? value) {
    final t = (value ?? '').trim();
    if (t.length < 2) return 'اكتب اسمك الكامل.';
    if (t.length > 100) return 'الاسم طويل أكثر من اللازم.';
    return null;
  }

  static String? validateSpecialty(String? value) {
    final t = (value ?? '').trim();
    if (t.length < minSpecialtyLength) return 'اكتب تخصصك.';
    if (t.length > maxSpecialtyLength) {
      return 'التخصص طويل أكثر من اللازم.';
    }
    return null;
  }

  static String? validateYearsOfExperience(String? value) {
    final n = int.tryParse((value ?? '').trim());
    if (n == null) return 'اكتب عدد السنوات بالأرقام.';
    if (n < 0 || n > maxYearsOfExperience) {
      return 'اكتب عدداً بين 0 و\$maxYearsOfExperience.';
    }
    return null;
  }

  static String? validateBio(String? value) {
    final t = (value ?? '').trim();
    if (t.length < minBioLength) {
      return 'اكتب نبذة لا تقل عن \$minBioLength حرفاً حتى يمكن تقييم الطلب.';
    }
    if (t.length > maxBioLength) {
      return 'النبذة أطول من الحد المسموح.';
    }
    return null;
  }

  static String? validateRejectionReason(String? value) {
    final t = (value ?? '').trim();
    if (t.length < minRejectionReasonLength) {
      return 'اكتب سبباً لا يقل عن \$minRejectionReasonLength أحرف.';
    }
    if (t.length > maxRejectionReasonLength) {
      return 'السبب أطول من الحد المسموح.';
    }
    return null;
  }

  /// يترجم خطأ Firestore إلى جملة يفهمها المستخدم.
  ///
  /// `permission-denied` هنا ليست عطلاً: هي غالباً محاولة فعل لا يسمح به
  /// دور المستخدم، و«حدث خطأ ما» تخفي ذلك تماماً.
  static String _readableError(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' =>
        'لا تملك صلاحية تنفيذ هذا الإجراء. إن كنت ترى هذا بالخطأ فتواصل مع '
            'إدارة DrD.',
      'unavailable' ||
      'deadline-exceeded' =>
        'تعذّر الوصول إلى الخادم. تحقّق من اتصالك وحاول مرة أخرى.',
      'not-found' => 'لم يعد هذا الطلب موجوداً.',
      _ => 'تعذّر إتمام العملية. حاول مرة أخرى.',
    };
  }
}
