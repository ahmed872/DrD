import 'package:intl/intl.dart';

class TimeSlot {
  final String startTime;
  final String endTime;
  bool isBooked;
  bool isExpired;

  TimeSlot({
    required this.startTime,
    required this.endTime,
    this.isBooked = false,
    this.isExpired = false,
  });
}

class TimeSlotGenerator {
  static final DateFormat _timeFormat = DateFormat("HH:mm:ss");

  static List<TimeSlot> generateSlots({
    required String startTimeStr,
    required String endTimeStr,
    required int durationMinutes,
    required int bufferMinutes,
    required DateTime date,
    List<String> bookedSlots = const [],
  }) {
    final List<TimeSlot> slots = [];

    DateTime? current = _parseTime(startTimeStr, date);
    final DateTime? end = _parseTime(endTimeStr, date);

    if (current == null || end == null) return slots;

    final DateTime now = DateTime.now();
    final bool isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final bool isPastDate =
        date.isBefore(DateTime(now.year, now.month, now.day));

    while (current!.isBefore(end)) {
      final DateTime slotEnd = current.add(Duration(minutes: durationMinutes));
      if (slotEnd.isAfter(end)) break;

      final String slotStartStr = _timeFormat.format(current);
      final String slotEndStr = _timeFormat.format(slotEnd);

      // Check if slot is expired (past dates are fully expired, future dates are never expired)
      bool isExpired = false;
      if (isPastDate) {
        isExpired = true;
      } else if (isToday) {
        isExpired = now.isAfter(current.add(const Duration(minutes: 10)));
      }

      slots.add(TimeSlot(
        startTime: slotStartStr,
        endTime: slotEndStr,
        isBooked: bookedSlots.contains(slotStartStr),
        isExpired: isExpired,
      ));

      current = slotEnd.add(Duration(minutes: bufferMinutes));
    }

    return slots;
  }

  static DateTime? _parseTime(String timeStr, DateTime date) {
    try {
      final parts = timeStr.trim().split(':');
      if (parts.length >= 2) {
        return DateTime(
          date.year,
          date.month,
          date.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
      }
    } catch (e) {
      // Return null on malformed string instead of crashing
    }
    return null;
  }
}
