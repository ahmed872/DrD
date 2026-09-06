import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/app_logger.dart';

/// حالة طلب حذف الحساب كما يكتبها الخادم.
enum DeletionRequestStatus {
  /// لا طلب قائم.
  none,

  /// وصل الطلب ولم تنفّذه الدالة بعد.
  requested,

  /// اكتمل الحذف بكل خطواته.
  completed,

  /// تعثّرت إحدى الخطوات — الحساب **لم يُحذف** وقد يحتاج تدخّلاً.
  failed;

  static DeletionRequestStatus parse(Object? raw) {
    switch (raw?.toString()) {
      case 'requested':
        return DeletionRequestStatus.requested;
      case 'completed':
        return DeletionRequestStatus.completed;
      case 'failed':
        return DeletionRequestStatus.failed;
      default:
        return DeletionRequestStatus.none;
    }
  }
}

/// طلب حذف الحساب.
///
/// ## لماذا مستند لا استدعاء مباشر
///
/// الحذف يلمس سبع مجموعات وحساب المصادقة نفسه — أي أنه يحتاج صلاحيات لا
/// يملكها أي عميل ولا يجوز أن يملكها. فالعميل هنا **يعلن نيّة** فقط: يكتب
/// مستنداً بمعرّفه هو، فتلتقطه `onDeletionRequested` على الخادم وتنفّذ.
///
/// هذا نفس نمط `doctor_applications`: قرار العميل مفصول عن سلطة التنفيذ،
/// والفجوة بينهما تفشل مغلقة — طلب بلا دالة يبقى طلباً بلا أثر.
///
/// ومعرّف المستند هو معرّف صاحبه، فالقاعدة تمنع بنيوياً طلب حذف حساب غيره.
class AccountDeletionService {
  AccountDeletionService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('deletion_requests');

  /// يرسل طلب الحذف. تُعاد `true` إن قُبل الطلب — لا إن اكتمل الحذف.
  ///
  /// التمييز مقصود: الاكتمال يقرّره الخادم ويُقرأ عبر [watchStatus]. ادّعاء
  /// «تم حذف حسابك» لحظة الكتابة كذب لو تعثّرت خطوة لاحقة.
  Future<bool> requestDeletion(String userId) async {
    try {
      await _requests.doc(userId).set({
        'status': 'requested',
        'requestedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (e) {
      // الطلب القائم لا يُعاد إنشاؤه: القاعدة تسمح بالإنشاء فقط، فالكتابة
      // الثانية تصل كـ`update` وتُرفض. وهو رفض صحيح لا عطل.
      if (e.code == 'permission-denied') {
        AppLogger.warning('طلب حذف قائم بالفعل أو مرفوض: ${e.code}');
      } else {
        AppLogger.error('تعذّر إرسال طلب حذف الحساب', e);
      }
      return false;
    } catch (e, s) {
      AppLogger.error('تعذّر إرسال طلب حذف الحساب', e, s);
      return false;
    }
  }

  /// متابعة ما فعله الخادم بالطلب.
  Stream<DeletionRequestStatus> watchStatus(String userId) {
    return _requests.doc(userId).snapshots().map(
          (doc) => DeletionRequestStatus.parse(doc.data()?['status']),
        );
  }
}
