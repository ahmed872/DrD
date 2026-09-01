/// أنواع الإشعارات القانونية — نسخة طبق الأصل من `NOTIFICATION_TYPES` في
/// `functions/notifications.js`.
///
/// هذه القيم لا تُستخدم لبناء نص الإشعار (العنوان والمحتوى يصلان جاهزين من
/// الخادم — راجع `buildContent` هناك)؛ هي فقط لتمييز نوع الإشعار محلياً
/// لغرضين: اختيار أيقونة مناسبة، وتحديد شاشة الوجهة عند الضغط عليه. أي
/// تعديل على القيم هنا بلا تعديل مطابق في `functions/notifications.js`
/// يكسر كلا الغرضين بصمت.
class NotificationType {
  const NotificationType._();

  static const bookingConfirmed = 'booking_confirmed';
  static const newAppointment = 'new_appointment';
  static const bookingCancelled = 'booking_cancelled';
  static const appointmentCancelled = 'appointment_cancelled';
  static const bookingRescheduled = 'booking_rescheduled';
  static const appointmentRescheduled = 'appointment_rescheduled';
  static const reminder24h = 'reminder_24h';
  static const reminder2h = 'reminder_2h';
  static const doctorReminder = 'doctor_reminder';

  /// الأنواع الموجَّهة للمريض — تحدّد شاشة الوجهة عند الضغط على الإشعار.
  static const patientTypes = {
    bookingConfirmed,
    bookingCancelled,
    bookingRescheduled,
    reminder24h,
    reminder2h,
  };
}
