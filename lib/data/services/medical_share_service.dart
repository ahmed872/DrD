import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/medical_share_status.dart';
import '../models/medical_share.dart';

/// نتيجة عملية على مشاركة.
class ShareResult {
  const ShareResult.success([this.shareId])
      : isSuccess = true,
        message = null;

  const ShareResult.failure(this.message)
      : isSuccess = false,
        shareId = null;

  final bool isSuccess;
  final String? message;
  final String? shareId;
}

/// طبيب في دليل الأطباء المعتمدين.
///
/// مشتقّ من `users` حيث `role == 'doctor'` — وهو الدور الذي لا يكتبه عميل
/// إطلاقاً: يكتبه الخادم بعد موافقة المشرف (المرحلة الثانية). لا آلية اعتماد
/// ثانية.
class DirectoryDoctor {
  const DirectoryDoctor({
    required this.id,
    required this.name,
    this.specialization = '',
  });

  final String id;
  final String name;
  final String specialization;
}

/// مشاركة السجلات الطبية بموافقة المريض.
///
/// **ما لا تفعله هذه الخدمة**: لا تكتب محتوى سريرياً في المشاركة إطلاقاً.
/// المريض يرسل معرّفات سجلاته، والخادم يقرأها ويتحقّق من ملكيتها ويبني
/// اللقطة. لو كتب العميل المحتوى لأمكن اختلاق تشخيص ونسبته لطبيب.
class MedicalShareService {
  const MedicalShareService({FirebaseFirestore? firestore})
      : _injected = firestore;

  final FirebaseFirestore? _injected;

  FirebaseFirestore get _db => _injected ?? FirebaseFirestore.instance;

  static const String collectionName = 'medical_shares';

  /// أقصى عدد سجلات في موافقة واحدة — مطابق لما تفرضه القاعدة.
  static const int maxEncountersPerShare = 20;

  CollectionReference<Map<String, dynamic>> get _shares =>
      _db.collection(collectionName);

  // ===========================================================================
  // الدليل
  // ===========================================================================

  /// الأطباء المعتمدون، لاختيار المستقبِل.
  ///
  /// المصدر `doctor_profiles`: إسقاط عام يكتبه الخادم ولا يحمل أي بيان شخصي.
  /// وجود المستند هو شهادة الاعتماد — الخادم لا ينشئه إلا لمن وافق عليه
  /// مشرف، ويحذفه فور خفض الدور أو حذف الحساب. وهو نفس الشرط الذي تفرضه
  /// قاعدة `medical_shares` على المستقبِل، فلا يظهر في القائمة من ترفضه
  /// القاعدة لاحقاً.
  Future<List<DirectoryDoctor>> fetchApprovedDoctors(
      {String? excludeId}) async {
    final snap = await _db.collection('doctor_profiles').get();
    final doctors = snap.docs
        .where((d) => d.id != excludeId)
        .map((d) => DirectoryDoctor(
              id: d.id,
              name: (d.data()['name'] ?? '').toString(),
              specialization: (d.data()['specialization'] ?? '').toString(),
            ))
        .toList();
    doctors.sort((a, b) => a.name.compareTo(b.name));
    return doctors;
  }

  // ===========================================================================
  // القراءة
  // ===========================================================================

  /// مشاركات المريض، الأحدث أولاً.
  Stream<List<MedicalShare>> watchPatientShares(String patientId) {
    return _shares
        .where('patientId', isEqualTo: patientId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(MedicalShare.fromSnapshot).toList());
  }

  /// ما وُجّه إلى الطبيب وهو **نشط**.
  ///
  /// قيد الحالة ليس ترشيحاً في الواجهة: قاعدة الأمان تشترطه، واستعلام
  /// بدونه يُرفض كاملاً. هذا ما يجعل الإلغاء يقطع الوصول فوراً بدل أن
  /// يُخفي عنصراً من قائمة.
  Stream<List<MedicalShare>> watchDoctorInbox(String doctorId) {
    return _shares
        .where('recipientDoctorId', isEqualTo: doctorId)
        .where('status', isEqualTo: MedicalShareStatus.active.wireValue)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(MedicalShare.fromSnapshot).toList());
  }

  /// متابعة مشاركة بعينها — تستعملها شاشة التفاصيل لترى الإلغاء فوراً.
  Stream<MedicalShare?> watchShare(String shareId) {
    return _shares.doc(shareId).snapshots().map(
          (snap) => snap.exists ? MedicalShare.fromSnapshot(snap) : null,
        );
  }

  // ===========================================================================
  // الكتابة
  // ===========================================================================

  /// ينشئ حدث موافقة جديداً.
  ///
  /// **كل مشاركة مستند جديد** بمعرّف تلقائي، حتى لو تكرّرت نفس السجلات مع
  /// نفس الطبيب. لا يُعاد كتابة موافقة سابقة ولا تُدمج فيها: سجل مَن وافق
  /// على ماذا ومتى يجب أن يبقى كاملاً، والدمج يمحو موافقة حدثت فعلاً.
  Future<ShareResult> createShare({
    required String patientId,
    required String patientName,
    required DirectoryDoctor recipient,
    required List<String> encounterIds,
  }) async {
    final ids = encounterIds.toSet().toList(growable: false);

    if (ids.isEmpty) {
      return const ShareResult.failure('اختر سجلاً واحداً على الأقل.');
    }
    if (ids.length > maxEncountersPerShare) {
      return const ShareResult.failure(
        'لا يمكن مشاركة أكثر من $maxEncountersPerShare سجلاً في المرة الواحدة.',
      );
    }
    if (recipient.id == patientId) {
      return const ShareResult.failure('لا يمكن مشاركة سجلاتك مع نفسك.');
    }

    try {
      // بلا محتوى سريري: معرّفات فقط. الخادم يبني اللقطة.
      final ref = await _shares.add({
        'patientId': patientId,
        'patientName': patientName.trim(),
        'recipientDoctorId': recipient.id,
        'recipientDoctorName': recipient.name,
        'recipientDoctorSpecialization': recipient.specialization,
        'encounterIds': ids,
        'status': MedicalShareStatus.pending.wireValue,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return ShareResult.success(ref.id);
    } on FirebaseException catch (e) {
      return ShareResult.failure(_readableError(e));
    } catch (_) {
      return const ShareResult.failure(
        'تعذّرت المشاركة. تحقّق من اتصالك وحاول مرة أخرى.',
      );
    }
  }

  /// يلغي مشاركة — يقطع وصول الطبيب فوراً.
  Future<ShareResult> revoke(String shareId) async {
    try {
      await _shares.doc(shareId).update({
        'status': MedicalShareStatus.revoked.wireValue,
        'revokedAt': FieldValue.serverTimestamp(),
      });
      return const ShareResult.success();
    } on FirebaseException catch (e) {
      return ShareResult.failure(_readableError(e));
    } catch (_) {
      return const ShareResult.failure(
        'تعذّر إلغاء المشاركة. حاول مرة أخرى.',
      );
    }
  }

  /// يترجم خطأ Firestore إلى جملة يفهمها المريض.
  ///
  /// `permission-denied` هنا غالباً ليست عطلاً: هي محاولة مشاركة سجل غير
  /// مملوك، أو إلغاء مشاركة سبق إلغاؤها. «حدث خطأ ما» تخفي ذلك.
  static String _readableError(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' =>
        'تعذّر إتمام العملية. تأكّد أن السجلات المختارة تخصّك وأن الطبيب '
            'المختار ما زال معتمَداً.',
      'unavailable' ||
      'deadline-exceeded' =>
        'تعذّر الوصول إلى الخادم. تحقّق من اتصالك وحاول مرة أخرى.',
      'not-found' => 'لم تعد هذه المشاركة موجودة.',
      _ => 'تعذّر إتمام العملية. حاول مرة أخرى.',
    };
  }
}
