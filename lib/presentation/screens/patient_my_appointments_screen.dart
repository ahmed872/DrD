import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_logger.dart';
import '../../data/services/booking_service.dart';
import '../providers/firebase_auth_service.dart';
import '../widgets/app_widgets.dart';
import 'patient_booking_screen.dart';

/// الأسماء العربية لحالات الموعد. الألوان تأتي من `tokens.statusColor` حتى لا
/// يتكرّر جدول ألوان في كل شاشة كما كان.
const Map<String, String> kStatusLabels = {
  'upcoming': 'قادم',
  'Scheduled': 'مجدول',
  'Booked': 'محجوز',
  'pending': 'قيد الانتظار',
  'Completed': 'مكتمل',
  'Cancelled': 'ملغي',
  'Rejected': 'مرفوض',
};

class PatientMyAppointmentsScreen extends StatefulWidget {
  const PatientMyAppointmentsScreen({super.key});

  @override
  State<PatientMyAppointmentsScreen> createState() =>
      _PatientMyAppointmentsScreenState();
}

class _PatientMyAppointmentsScreenState
    extends State<PatientMyAppointmentsScreen> {
  final BookingService _bookingService = BookingService();

  int _selectedFilterIndex = 0; // 0: Upcoming, 1: Past
  List<Map<String, dynamic>> _allAppointments = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchMyAppointments();
  }

  Future<void> _fetchMyAppointments() async {
    setState(() => _isLoading = true);
    final auth = Provider.of<FirebaseAuthService>(context, listen: false);
    if (auth.userId != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('appointments')
            .where('patientId', isEqualTo: auth.userId)
            .get();

        _allAppointments = snap.docs.map((doc) {
          final data = doc.data();
          final dateStr = data['appointmentDate'] as String?;
          final startTime = data['startTime'] ?? data['time'] ?? '00:00';
          final endTime = data['endTime'] ?? '';

          DateTime parsedDate;
          if (dateStr != null && dateStr.isNotEmpty) {
            parsedDate = DateTime.tryParse(dateStr) ?? DateTime.now();
          } else {
            parsedDate = DateTime.now();
          }

          return {
            'id': doc.id,
            'doctorName': data['doctorName'] ?? 'Unknown',
            'doctorNameEn': data['doctorNameEn'] ?? 'Unknown',
            'specialization': data['doctorSpecialization'] ?? 'مراجعة',
            'date': parsedDate,
            'time': startTime,
            'endTime': endTime,
            'duration': data['duration'] ?? 30,
            'reason': data['reason'] ?? '',
            'status': data['status'] ?? 'Scheduled',
            'price': data['price'] ?? 0,
            'doctorId': data['doctorId'],
            'notes': data['notes'] ?? '',
            'clinicLocation': data['clinicLocation'] ?? '',
            'clinicPhone': data['clinicPhone'] ?? '',
          };
        }).toList();

        // Sort by date and time (newest first)
        _allAppointments.sort((a, b) {
          final dateCmp =
              (b['date'] as DateTime).compareTo(a['date'] as DateTime);
          if (dateCmp != 0) return dateCmp;
          return (b['time'] as String).compareTo(a['time'] as String);
        });
      } catch (e) {
        AppLogger.info('Error fetching appointments: $e');
        if (mounted) {
          AppSnack.error(context, 'حدث خطأ أثناء تحميل المواعيد');
        }
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _cancelAppointment(String appointmentId) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'إلغاء الموعد',
      message: 'هل أنت متأكد من إلغاء هذا الموعد؟ سيصبح الوقت متاحاً لمريض '
          'آخر فوراً.',
      confirmLabel: 'تأكيد الإلغاء',
      cancelLabel: 'تراجع',
      destructive: true,
    );

    if (!confirmed) return;

    try {
      // الإلغاء يمرّ عبر BookingService حتى يُحرَّر قفل الخانة في نفس
      // المعاملة. تغيير الحالة وحده — كما كان — يترك عدّاد الخانة مرفوعاً،
      // فتبدو الخانة محجوزة إلى الأبد ولا يستطيع أي مريض آخر أخذها.
      final ok = await _bookingService.cancel(appointmentId: appointmentId);

      if (!mounted) return;
      if (ok) {
        AppSnack.success(context, 'تم إلغاء الموعد بنجاح');
      } else {
        AppSnack.error(context, 'تعذّر إلغاء الموعد، حاول مرة أخرى');
      }
      _fetchMyAppointments();
    } catch (e) {
      if (mounted) AppSnack.error(context, 'حدث خطأ أثناء الإلغاء');
    }
  }

  List<Map<String, dynamic>> get _filteredAppointments {
    final activeStatuses = ['upcoming', 'Scheduled', 'Booked', 'pending'];
    final pastStatuses = ['Completed', 'Cancelled', 'Rejected'];

    if (_selectedFilterIndex == 0) {
      return _allAppointments
          .where((app) => activeStatuses.contains(app['status']))
          .toList();
    } else {
      return _allAppointments
          .where((app) => pastStatuses.contains(app['status']))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appointments = _filteredAppointments;
    final upcomingCount = _allAppointments
        .where((a) => ['upcoming', 'Scheduled', 'Booked', 'pending']
            .contains(a['status']))
        .length;

    return AppScaffold(
      title: 'مواعيدي',
      subtitle: upcomingCount == 0
          ? 'لا توجد مواعيد قادمة'
          : 'لديك $upcomingCount موعد قادم',
      onRefresh: _fetchMyAppointments,
      headerBottom: AppSegmented(
        labels: const ['القادمة', 'السابقة'],
        selectedIndex: _selectedFilterIndex,
        onChanged: (i) => setState(() => _selectedFilterIndex = i),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      child: _isLoading
          ? const AppLoader(message: 'جارٍ تحميل مواعيدك…')
          : appointments.isEmpty
              ? _buildEmptyState()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final appointment in appointments) ...[
                      _AppointmentCard(
                        appointment: appointment,
                        isUpcomingTab: _selectedFilterIndex == 0,
                        onTap: () => _showDetails(appointment),
                        onCancel: () => _cancelAppointment(appointment['id']),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    final isUpcoming = _selectedFilterIndex == 0;

    return EmptyState(
      icon: isUpcoming ? Icons.event_available_rounded : Icons.history_rounded,
      title: isUpcoming ? 'لا توجد مواعيد قادمة' : 'لا توجد مواعيد سابقة',
      message: isUpcoming
          ? 'احجز موعدك الأول وستجده هنا.'
          : 'المواعيد المكتملة والملغاة تظهر في هذه القائمة.',
      action: isUpcoming
          ? FilledButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PatientBookingScreen(),
                  ),
                );
                if (mounted) _fetchMyAppointments();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('احجز موعد'),
            )
          : null,
    );
  }

  void _showDetails(Map<String, dynamic> appointment) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AppointmentDetailsSheet(
        appointment: appointment,
        onRate: () {
          Navigator.pop(ctx);
          _showRatingDialog(appointment);
        },
      ),
    );
  }

  void _showRatingDialog(Map<String, dynamic> appointment) {
    double rating = 5;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          icon: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: ctx.tokens.gold.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.star_rounded,
              color: ctx.tokens.gold,
              size: 26,
            ),
          ),
          title: const Text('تقييم الطبيب', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'كيف كانت تجربتك مع ${appointment['doctorName']}؟',
                textAlign: TextAlign.center,
                style: ctx.texts.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: ctx.tokens.gold,
                      size: 34,
                    ),
                    onPressed: () => setLocalState(() => rating = index + 1.0),
                  );
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'اكتب تعليقك هنا (اختياري)',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _submitRating(
                        appointment,
                        rating,
                        commentController.text,
                      );
                    },
                    child: const Text('إرسال'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitRating(
      Map<String, dynamic> appointment, double rating, String comment) async {
    try {
      final doctorId = appointment['doctorId'];
      final auth = Provider.of<FirebaseAuthService>(context, listen: false);

      // Add review to 'reviews' collection
      await FirebaseFirestore.instance.collection('reviews').add({
        'doctorId': doctorId,
        'patientId': auth.userId,
        'patientName': auth.userName ?? 'مريض',
        'appointmentId': appointment['id'],
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update doctor's overall rating
      final docRef =
          FirebaseFirestore.instance.collection('users').doc(doctorId);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docData = await transaction.get(docRef);
        if (docData.exists) {
          final data = docData.data()!;

          // Safely parse existing rating/reviews, defaulting to 0 if not exist
          int currentReviews = 0;
          if (data.containsKey('reviews') && data['reviews'] != null) {
            currentReviews = (data['reviews'] as num).toInt();
          }

          double currentRating = 0.0;
          if (data.containsKey('rating') && data['rating'] != null) {
            currentRating = (data['rating'] as num).toDouble();
          }

          double newRating = ((currentRating * currentReviews) + rating) /
              (currentReviews + 1);

          transaction.update(docRef, {
            'rating': newRating,
            'reviews': currentReviews + 1,
          });
        }
      });

      if (mounted) AppSnack.success(context, 'تم إرسال تقييمك بنجاح!');
    } catch (e) {
      if (mounted) AppSnack.error(context, 'حدث خطأ أثناء إرسال التقييم');
    }
  }
}

// =============================================================================
// بطاقة الموعد
// =============================================================================

/// هل ما زال بالإمكان إلغاء هذا الموعد؟
bool canCancelAppointment(Map<String, dynamic> appointment) {
  final appointmentDate = appointment['date'] as DateTime;
  final appointmentTime = appointment['time'] as String;
  final status = appointment['status'] as String;

  // التحقق من حالة الموعد
  final cancellableStatuses = ['upcoming', 'Scheduled', 'Booked', 'pending'];
  if (!cancellableStatuses.contains(status)) {
    return false; // لا يمكن إلغاء إذا كان مكتملاً أو ملغياً
  }

  // التحقق من التاريخ الفعلي
  final now = DateTime.now();
  final appointmentDateTime = DateTime(
    appointmentDate.year,
    appointmentDate.month,
    appointmentDate.day,
  );

  // لا يمكن إلغاء موعد انقضى (في الماضي)
  if (appointmentDateTime.isBefore(DateTime(now.year, now.month, now.day))) {
    return false;
  }

  // إذا كان اليوم نفسه، تحقق من الوقت
  if (appointmentDateTime
      .isAtSameMomentAs(DateTime(now.year, now.month, now.day))) {
    try {
      final timeParts = appointmentTime.split(':');
      if (timeParts.length >= 2) {
        final apptHour = int.parse(timeParts[0]);
        final apptMinute = int.parse(timeParts[1]);
        final apptTimeOfDay =
            DateTime(now.year, now.month, now.day, apptHour, apptMinute);

        // لا يمكن إلغاء موعد بدأ بالفعل
        if (now.isAfter(apptTimeOfDay)) {
          return false;
        }
      }
    } catch (e) {
      // في حالة الخطأ في تحليل الوقت، اسمح بالإلغاء للأمان
      return true;
    }
  }

  return true; // يمكن الإلغاء
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.isUpcomingTab,
    required this.onTap,
    required this.onCancel,
  });

  final Map<String, dynamic> appointment;
  final bool isUpcomingTab;
  final VoidCallback onTap;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final status = appointment['status'] as String;
    final statusColor = tokens.statusColor(status);
    final date = appointment['date'] as DateTime;
    final canCancel = canCancelAppointment(appointment);

    return AppCard(
      onTap: onTap,
      accent: statusColor,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // كتلة التاريخ: اليوم والشهر بشكل تقويم مصغّر. أسرع في القراءة
              // بكثير من سطر «2026-08-14» الذي كان مستخدماً.
              _DateBlock(date: date, color: statusColor),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment['doctorName']?.toString() ?? 'طبيب غير معروف',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall,
                    ),
                    Text(
                      appointment['specialization']?.toString() ?? 'تخصص عام',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall
                          ?.copyWith(color: tokens.textMuted),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: tokens.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          appointment['time'].toString(),
                          style: context.texts.labelSmall
                              ?.copyWith(color: tokens.textBody),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        StatusPill(
                          label: kStatusLabels[status] ?? status,
                          color: statusColor,
                          compact: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isUpcomingTab) ...[
            const SizedBox(height: AppSpacing.lg),
            if (canCancel)
              OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('إلغاء الموعد'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.danger,
                  side: BorderSide(color: tokens.danger.withValues(alpha: 0.4)),
                  minimumSize: const Size.fromHeight(44),
                ),
              )
            else
              const NoticeBox.info(
                message: 'لا يمكن إلغاء هذا الموعد — انقضى وقته.',
              ),
          ],
        ],
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.date, required this.color});

  final DateTime date;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.rMd,
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Text(
            DateFormat('d', 'ar').format(date),
            style: context.texts.titleLarge?.copyWith(color: color),
          ),
          Text(
            DateFormat('MMM', 'ar').format(date),
            style: context.texts.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// تفاصيل الموعد
// =============================================================================

/// التفاصيل في لوح سفلي بدل نافذة منبثقة: النافذة كانت تفيض على الشاشات
/// الصغيرة لأنها تعرض أربعة أقسام كاملة.
class _AppointmentDetailsSheet extends StatelessWidget {
  const _AppointmentDetailsSheet({
    required this.appointment,
    required this.onRate,
  });

  final Map<String, dynamic> appointment;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final status = appointment['status'] as String;
    final statusColor = tokens.statusColor(status);

    final reason = appointment['reason'] as String? ?? '';
    final notes = appointment['notes'] as String? ?? '';
    final clinicLocation = appointment['clinicLocation'] as String? ?? '';
    final clinicPhone = appointment['clinicPhone']?.toString() ?? '';
    final endTime = appointment['endTime'] as String? ?? '';
    final price = num.tryParse(appointment['price'].toString()) ?? 0;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.94,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: StatusPill(
                label: kStatusLabels[status] ?? status,
                color: statusColor,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: Text(
                appointment['doctorName']?.toString() ?? 'طبيب غير معروف',
                textAlign: TextAlign.center,
                style: context.texts.headlineSmall,
              ),
            ),
            Center(
              child: Text(
                appointment['specialization']?.toString() ?? 'تخصص عام',
                style:
                    context.texts.bodyMedium?.copyWith(color: tokens.textMuted),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionTitle(
              title: 'موعد الزيارة',
              icon: Icons.event_rounded,
            ),
            AppCard(
              child: Column(
                children: [
                  InfoRow(
                    label: 'التاريخ',
                    value: DateFormat('EEEE، d MMMM yyyy', 'ar')
                        .format(appointment['date'] as DateTime),
                  ),
                  InfoRow(
                    label: 'وقت البداية',
                    value: appointment['time'].toString(),
                  ),
                  if (endTime.isNotEmpty)
                    InfoRow(label: 'وقت النهاية', value: endTime),
                  InfoRow(
                    label: 'المدة',
                    value: '${appointment['duration'] ?? 30} دقيقة',
                  ),
                  if (price > 0)
                    InfoRow(
                      label: 'التكلفة',
                      value: '$price جنيه',
                      valueColor: tokens.success,
                    ),
                ],
              ),
            ),
            if (reason.isNotEmpty || notes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              const SectionTitle(
                title: 'تفاصيل',
                icon: Icons.description_outlined,
              ),
              AppCard(
                child: Column(
                  children: [
                    if (reason.isNotEmpty)
                      InfoRow(label: 'سبب الزيارة', value: reason),
                    if (notes.isNotEmpty)
                      InfoRow(label: 'ملاحظات الطبيب', value: notes),
                  ],
                ),
              ),
            ],
            if (clinicLocation.isNotEmpty || clinicPhone.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              const SectionTitle(
                title: 'العيادة',
                icon: Icons.local_hospital_outlined,
              ),
              AppCard(
                child: Column(
                  children: [
                    if (clinicLocation.isNotEmpty)
                      InfoRow(label: 'الموقع', value: clinicLocation),
                    if (clinicPhone.isNotEmpty)
                      InfoRow(label: 'الهاتف', value: clinicPhone),
                  ],
                ),
              ),
            ],
            if (status == 'Completed') ...[
              const SizedBox(height: AppSpacing.xl),
              const NoticeBox.success(
                message: 'الحمد لله على السلامة، نتمنى لك دوام الصحة والعافية.',
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onRate,
                style: FilledButton.styleFrom(backgroundColor: tokens.gold),
                icon: const Icon(Icons.star_rounded),
                label: const Text('قيّم الطبيب'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
