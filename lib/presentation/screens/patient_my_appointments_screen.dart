import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/constants/appointment_status.dart';
import '../../data/services/booking_service.dart';
import '../providers/firebase_auth_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';

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
            'status': data['status'] ?? AppointmentStatus.booked.wireValue,
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
          ScaffoldMessenger.of(context).showSnackBar(
            AppSnackBar.error('حدث خطأ أثناء تحميل المواعيد: $e'),
          );
        }
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _cancelAppointment(String appointmentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الموعد', textAlign: TextAlign.right),
        content: const Text('هل أنت متأكد من إلغاء هذا الموعد؟',
            textAlign: TextAlign.right),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'تأكيد الإلغاء',
              style: TextStyle(color: context.colors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // الإلغاء يمرّ عبر BookingService حتى يُحرَّر قفل الخانة في نفس
        // المعاملة. تغيير الحالة وحده — كما كان — يترك عدّاد الخانة مرفوعاً،
        // فتبدو الخانة محجوزة إلى الأبد ولا يستطيع أي مريض آخر أخذها.
        final ok = await _bookingService.cancel(appointmentId: appointmentId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ok
                ? AppSnackBar.success('تم إلغاء الموعد بنجاح')
                : AppSnackBar.error('تعذّر إلغاء الموعد، حاول مرة أخرى'),
          );
          _fetchMyAppointments();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            AppSnackBar.error('حدث خطأ أثناء الإلغاء: $e'),
          );
        }
      }
    }
  }

  void _showAppointmentDetails(Map<String, dynamic> appointment) {
    final currentStatus = AppointmentStatus.parse(appointment['status']);

    final dateStr =
        DateFormat('yyyy-MM-dd', 'ar').format(appointment['date'] as DateTime);
    final timeStr = appointment['time'] as String;
    final endTimeStr = appointment['endTime'] as String;
    final reason = appointment['reason'] as String? ?? 'غير محدد';
    final notes = appointment['notes'] as String? ?? '';
    final clinicLocation = appointment['clinicLocation'] as String? ?? '';
    final clinicPhone = appointment['clinicPhone']?.toString() ?? '';
    final price = appointment['price'] != null
        ? num.tryParse(appointment['price'].toString()) ?? 0
        : 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل الموعد', textAlign: TextAlign.right),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusChip.appointment(currentStatus),
              const SizedBox(height: DrdSpacing.md),

              // Doctor Info
              Text(
                'معلومات الطبيب',
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: context.colors.primary,
                ),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                  'الطبيب:', appointment['doctorName'] ?? 'Unknown'),
              _buildDetailRow(
                  'التخصص:', appointment['specialization'] ?? 'غير محدد'),
              const SizedBox(height: 16),

              // Appointment Date & Time
              Text(
                'موعد الزيارة',
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: context.colors.primary,
                ),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 8),
              _buildDetailRow('التاريخ:', dateStr),
              _buildDetailRow('وقت البداية:', timeStr),
              if (endTimeStr.isNotEmpty)
                _buildDetailRow('وقت النهاية:', endTimeStr),
              _buildDetailRow(
                  'المدة:', '${appointment['duration'] ?? 30} دقيقة'),
              const SizedBox(height: 16),

              // Appointment Details
              Text(
                'تفاصيل الموعد',
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: context.colors.primary,
                ),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 8),
              if (reason.isNotEmpty) _buildDetailRow('السبب:', reason),
              if (notes.isNotEmpty) _buildDetailRow('ملاحظات:', notes),
              if (price > 0) _buildDetailRow('التكلفة:', 'SR $price'),
              const SizedBox(height: 16),

              // Clinic Info
              if (clinicLocation.isNotEmpty || clinicPhone.isNotEmpty) ...[
                Text(
                  'معلومات العيادة',
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: context.colors.primary,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 8),
                if (clinicLocation.isNotEmpty)
                  _buildDetailRow('الموقع:', clinicLocation),
                if (clinicPhone.isNotEmpty)
                  _buildDetailRow('الهاتف:', clinicPhone),
              ],

              if (currentStatus == AppointmentStatus.completed) ...[
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'الحمد لله على السلامة، نتمنى لك دوام الصحة والعافية',
                    style: TextStyle(
                      color: context.drd.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showRatingDialog(appointment);
                    },
                    icon: const Icon(Icons.star_rate),
                    label: const Text('تقييم الطبيب'),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showRatingDialog(Map<String, dynamic> appointment) {
    double rating = 5.0;
    final TextEditingController commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('تقييم الطبيب', textAlign: TextAlign.right),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('كيف كانت تجربتك مع د. ${appointment['doctorName']}؟',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      color: index < rating
                          ? context.drd.rating
                          : context.drd.disabled,
                      size: 32,
                    ),
                    onPressed: () {
                      setState(() => rating = index + 1.0);
                    },
                  );
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'اكتب تعليقك هنا (اختياري)',
                  border: OutlineInputBorder(),
                ),
                textAlign: TextAlign.right,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _submitRating(
                    appointment, rating, commentController.text);
              },
              child: const Text('إرسال التقييم'),
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

      // معرّف المراجعة = معرّف الموعد.
      //
      // هذا يمنح التفرّد مجاناً — مراجعة واحدة لكل زيارة — ويسمح لقاعدة
      // الأمان بالتحقّق من الموعد نفسه: هل هو لهذا المريض؟ هل تمّ فعلاً؟
      // كانت الكتابة السابقة `.add()` بمعرّف عشوائي، فلا تفرّد ولا تحقّق.
      final appointmentId = appointment['id'] as String;
      await FirebaseFirestore.instance
          .collection('reviews')
          .doc(appointmentId)
          .set({
        'doctorId': doctorId,
        'patientId': auth.userId,
        'patientName': auth.userName ?? 'مريض',
        'appointmentId': appointmentId,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // متوسط تقييم الطبيب لم يعد يُحسب هنا.
      //
      // كانت الشاشة تقرأ `users/{doctorId}` وتكتب `rating` و`reviews` في
      // معاملة من العميل — أي أن رقم الثقة الوحيد في التطبيق كان تحت سيطرة
      // أي مستخدم مسجَّل. الحساب انتقل إلى `syncDoctorRating` على الخادم،
      // وقاعدة الأمان لم تعد تسمح للعميل بلمس الحقلين إطلاقاً.

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar.success('تم إرسال تقييمك بنجاح!'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar.error('حدث خطأ أثناء إرسال التقييم: $e'),
        );
      }
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: context.drd.muted,
              ),
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredAppointments {
    // كانت القسمة هنا على قائمتين نصّيتين مكتوبتين يدوياً، ولا تحتويان
    // `NoShow` ولا `PendingConfirmation` — فموعد في أي من الحالتين كان
    // يختفي من التبويبين معاً ولا يراه المريض إطلاقاً. القسمة الآن مانعة
    // جامعة: كل موعد يظهر في تبويب واحد بالضبط.
    final upcoming = _selectedFilterIndex == 0;
    return _allAppointments
        .where((app) =>
            AppointmentStatus.parse(app['status']).isActive == upcoming)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final appointmentsToList = _filteredAppointments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مواعيدي'),
      ),
      body: Column(
        children: [
          // Custom Tab Bar
          Container(
            padding: const EdgeInsets.all(DrdSpacing.md),
            color: context.colors.surface,
            child: Row(
              children: [
                _buildTab('المواعيد السابقة', 1),
                const SizedBox(width: 12),
                _buildTab('المواعيد القادمة', 0),
              ],
            ),
          ),
          const Divider(height: 1),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : appointmentsToList.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: appointmentsToList.length,
                        itemBuilder: (context, index) {
                          return _buildAppointmentCard(
                              appointmentsToList[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String title, int index) {
    final isSelected = _selectedFilterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedFilterIndex = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? context.colors.primary
                : context.colors.surfaceContainerHigh,
            borderRadius: DrdRadius.smAll,
            border: Border.all(
              color: isSelected ? context.colors.primary : context.drd.border,
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected
                  ? context.colors.onPrimary
                  : context.colors.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 80, color: context.drd.disabled),
          const SizedBox(height: DrdSpacing.md),
          Text(
            _selectedFilterIndex == 0
                ? 'لا توجد مواعيد قادمة'
                : 'لا توجد مواعيد سابقة',
            style: context.text.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedFilterIndex == 0
                ? 'قم بحجز موعد جديد من صفحة البحث'
                : 'لم تقم بزيارة أي طبيب من قبل',
            style: context.text.bodyMedium?.copyWith(
              color: context.drd.muted,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ دالة للتحقق من إمكانية إلغاء الموعد
  bool _canCancelAppointment(Map<String, dynamic> appointment) {
    final appointmentDate = appointment['date'] as DateTime;
    final appointmentTime = appointment['time'] as String;
    final status = appointment['status'] as String;

    // التحقق من حالة الموعد
    if (!AppointmentStatus.parse(status).isCancellable) {
      return false; // لا يمكن إلغاء ما تم أو أُلغي بالفعل
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

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    final bool isUpcoming = _selectedFilterIndex == 0;
    final bool canCancel = _canCancelAppointment(appointment);

    final currentStatus = AppointmentStatus.parse(appointment['status']);

    final dateStr =
        DateFormat('yyyy-MM-dd', 'ar').format(appointment['date'] as DateTime);
    final timeStr = appointment['time'] as String;

    return InkWell(
      onTap: () => _showAppointmentDetails(appointment),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 2,
        // الموعد القادم يستحق حدّاً أوضح؛ الماضي يتراجع بصرياً.
        shape: RoundedRectangleBorder(
          borderRadius: DrdRadius.lgAll,
          side: BorderSide(
            color: isUpcoming ? context.colors.primary : context.drd.border,
            width: DrdSizes.hairline,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header: Date, Time & Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  StatusChip.appointment(currentStatus),
                  Row(
                    children: [
                      Text(
                        timeStr,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Icon(Icons.access_time,
                          size: 16, color: context.drd.muted),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Icon(Icons.calendar_today,
                          size: 16, color: context.drd.muted),
                    ],
                  ),
                ],
              ),
              const Divider(height: 24),

              // Doctor Info
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        appointment['doctorName'] ?? 'طبيب غير معروف',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        appointment['specialization'] ?? 'تخصص عام',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.drd.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: context.colors.primaryContainer,
                    child: Icon(Icons.person,
                        color: context.colors.onPrimaryContainer, size: 30),
                  ),
                ],
              ),

              // Cancel and Review Actions
              // ✅ عرض زر الإلغاء فقط إذا كان الموعد لم يمضِ بعد
              if (isUpcoming && canCancel) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _cancelAppointment(appointment['id']),
                    icon: const Icon(Icons.cancel),
                    label: const Text('إلغاء الموعد'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.error,
                      side: BorderSide(color: context.colors.error),
                    ),
                  ),
                ),
              ] else if (isUpcoming && !canCancel) ...[
                // مضى وقت الموعد فلم يعد الإلغاء ممكناً.
                const SizedBox(height: DrdSpacing.md),
                const AppBanner.warning(
                  message: 'لا يمكن إلغاء الموعد (انقضى الوقت)',
                ),
              ],

              if (AppointmentStatus.parse(appointment['status']) ==
                  AppointmentStatus.completed) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('سيتم تفعيل التقييم قريباً!')),
                      );
                    },
                    icon: const Icon(Icons.star_rate),
                    label: const Text('تقييم الطبيب'),
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
