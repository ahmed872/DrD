import 'package:cloud_functions/cloud_functions.dart';

import '../../core/utils/app_logger.dart';
import '../../core/utils/error_messages.dart';

/// حالة الخانة كما يحدّدها الخادم.
enum SlotStatus {
  /// فيها مكان ويمكن الحجز.
  available,

  /// امتلأت.
  full,

  /// مضى وقتها.
  past,

  /// أغلقها الطبيب.
  closed;

  static SlotStatus parse(Object? raw) {
    return switch (raw?.toString()) {
      'available' => SlotStatus.available,
      'full' => SlotStatus.full,
      'past' => SlotStatus.past,
      'closed' => SlotStatus.closed,
      // قيمة غير معروفة تُعامَل كغير متاحة: إظهار خانة لا يقبلها الخادم
      // أسوأ من إخفاء خانة متاحة.
      _ => SlotStatus.closed,
    };
  }

  bool get isBookable => this == SlotStatus.available;

  String get arabicLabel => switch (this) {
        SlotStatus.available => 'متاح',
        SlotStatus.full => 'مكتمل',
        SlotStatus.past => 'انتهى',
        SlotStatus.closed => 'مغلق',
      };
}

/// خانة زمنية واحدة كما يصفها الخادم.
class AvailabilitySlot {
  const AvailabilitySlot({
    required this.slotId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.bookedCount,
    required this.remainingCapacity,
    required this.status,
  });

  factory AvailabilitySlot.fromMap(Map<String, dynamic> map) {
    final capacity = (map['capacity'] as num?)?.toInt() ?? 1;
    final booked = (map['bookedCount'] as num?)?.toInt() ?? 0;
    return AvailabilitySlot(
      slotId: (map['slotId'] ?? '').toString(),
      date: (map['date'] ?? '').toString(),
      startTime: (map['startTime'] ?? '').toString(),
      endTime: (map['endTime'] ?? '').toString(),
      capacity: capacity,
      bookedCount: booked,
      remainingCapacity:
          (map['remainingCapacity'] as num?)?.toInt() ?? (capacity - booked),
      status: SlotStatus.parse(map['status']),
    );
  }

  final String slotId;

  /// `yyyy-MM-dd`.
  final String date;

  /// `HH:mm` بنظام 24 ساعة.
  final String startTime;
  final String endTime;
  final int capacity;
  final int bookedCount;
  final int remainingCapacity;
  final SlotStatus status;

  /// هل هذه خانة مجموعة (تتّسع لأكثر من مريض)؟
  bool get isGroupSlot => capacity > 1;

  /// الوقت بصيغة عربية للعرض: `9:00 ص`.
  String get displayTime {
    final parts = startTime.split(':');
    if (parts.length != 2) return startTime;
    var hour = int.tryParse(parts[0]) ?? 0;
    final period = hour >= 12 ? 'م' : 'ص';
    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour -= 12;
    }
    return '$hour:${parts[1]} $period';
  }
}

/// توفّر يوم واحد.
class DayAvailability {
  const DayAvailability({required this.date, required this.slots});

  final String date;
  final List<AvailabilitySlot> slots;

  List<AvailabilitySlot> get bookable =>
      slots.where((s) => s.status.isBookable).toList();

  bool get hasBookableSlots => slots.any((s) => s.status.isBookable);

  /// يوم بلا خانات إطلاقاً = ليس يوم عمل عند هذا الطبيب.
  bool get isWorkingDay => slots.isNotEmpty;
}

/// نتيجة استعلام التوفّر.
class AvailabilityResult {
  const AvailabilityResult.success(this.days)
      : errorMessage = null,
        isNetworkIssue = false;

  const AvailabilityResult.failed(this.errorMessage,
      {this.isNetworkIssue = false})
      : days = const {};

  /// `yyyy-MM-dd` → توفّر ذلك اليوم، مرتّبة تصاعدياً.
  final Map<String, DayAvailability> days;
  final String? errorMessage;
  final bool isNetworkIssue;

  bool get isSuccess => errorMessage == null;

  DayAvailability? forDate(String date) => days[date];

  /// أول يوم فيه خانة قابلة للحجز — لتحديد التاريخ الافتراضي بلا تخمين.
  String? get firstBookableDate {
    for (final entry in days.entries) {
      if (entry.value.hasBookableSlots) return entry.key;
    }
    return null;
  }
}

/// قراءة التوفّر من الخادم.
///
/// ## لماذا لا تُحسب الخانات في التطبيق
///
/// كانت شاشة الحجز تولّد الخانات بنفسها من `workingHours` و`sessionDuration`
/// ثم تسأل Firestore مباشرة عن عدد المحجوزين في كل وقت. نسختان من منطق
/// الجدول — واحدة في Dart وأخرى في `functions/availability.js` — وأي فرق
/// بينهما يعني وقتاً يعرضه التطبيق ثم يرفضه الخادم عند التأكيد. والأسوأ أن
/// التطبيق لم يكن يعرف الاستراحات ولا الإجازات ولا استثناءات التواريخ التي
/// أضافتها المرحلة 1ب، فيعرضها كأوقات متاحة.
///
/// `getAvailability` تستدعي **نفس** دوال الجدول التي يستدعيها الحجز، فما
/// يظهر هو ما يُقبل. مع ذلك يبقى الرد لقطة قد تقدُم: معاملة الحجز هي الحكم
/// الأخير، والواجهة تعالج `slot-unavailable` بإعادة تحميل التوفّر.
class AvailabilityService {
  AvailabilityService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<AvailabilityResult> fetch({
    required String doctorId,
    required String dateFrom,
    String? dateTo,
  }) async {
    try {
      final callable = _functions.httpsCallable('getAvailability');
      final response = await callable.call<Object?>({
        'doctorId': doctorId,
        'dateFrom': dateFrom,
        if (dateTo != null) 'dateTo': dateTo,
      });

      final data = Map<String, dynamic>.from(response.data as Map);
      final rawSlots = (data['slots'] as List?) ?? const [];

      final byDate = <String, List<AvailabilitySlot>>{};
      for (final raw in rawSlots) {
        final slot = AvailabilitySlot.fromMap(
          Map<String, dynamic>.from(raw as Map),
        );
        byDate.putIfAbsent(slot.date, () => []).add(slot);
      }

      final sortedDates = byDate.keys.toList()..sort();
      return AvailabilityResult.success({
        for (final date in sortedDates)
          date: DayAvailability(date: date, slots: byDate[date]!),
      });
    } on FirebaseFunctionsException catch (e) {
      final reason = _reasonOf(e);
      AppLogger.warning('تعذّر جلب التوفّر ($reason)');
      return AvailabilityResult.failed(
        AppErrorMessages.resolve(reason: reason, serverMessage: e.message),
        isNetworkIssue: AppErrorMessages.isNetworkIssue(reason),
      );
    } catch (e, s) {
      AppLogger.error('خطأ غير متوقع أثناء جلب التوفّر', e, s);
      return const AvailabilityResult.failed(unknownMessage,
          isNetworkIssue: true);
    }
  }

  String _reasonOf(FirebaseFunctionsException e) {
    final details = e.details;
    if (details is Map && details['reason'] != null) {
      return details['reason'].toString();
    }
    return e.code;
  }
}
