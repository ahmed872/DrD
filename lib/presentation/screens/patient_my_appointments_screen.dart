import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../data/services/booking_service.dart';
import '../../data/services/review_service.dart';
import '../providers/firebase_auth_service.dart';
import '../../core/utils/app_logger.dart';

class PatientMyAppointmentsScreen extends StatefulWidget {
  const PatientMyAppointmentsScreen({super.key});

  @override
  State<PatientMyAppointmentsScreen> createState() =>
      _PatientMyAppointmentsScreenState();
}

class _PatientMyAppointmentsScreenState
    extends State<PatientMyAppointmentsScreen> {
  final BookingService _bookingService = BookingService();
  final ReviewService _reviewService = ReviewService();

  /// معرّفات المواعيد التي قيّمها المريض بالفعل.
  ///
  /// تُقرأ مرة واحدة مع قائمة المواعيد لتحديد شكل الزر (تقييم / تم التقييم)،
  /// بينما الأهلية الحقيقية تُحسم على الخادم عند الضغط — الواجهة لا تقرّر.
  Set<String> _reviewedAppointmentIds = {};

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

        // المراجعات التي كتبها هذا المريض — استعلام واحد لكل القائمة، بدل
        // سؤال الخادم عن أهلية كل موعد على حدة. يحدّد شكل الزر فقط؛ القرار
        // الفعلي يبقى على الخادم عند الضغط.
        _reviewedAppointmentIds = await _fetchReviewedAppointmentIds(
          auth.userId!,
        );
      } catch (e) {
        AppLogger.info('Error fetching appointments: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ أثناء تحميل المواعيد: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// معرّفات المواعيد التي قيّمها هذا المريض.
  ///
  /// معرّف مستند المراجعة هو معرّف الموعد نفسه (`functions/reviews.js`)، لذا
  /// معرّفات المستندات وحدها تكفي بلا قراءة أي حقل.
  Future<Set<String>> _fetchReviewedAppointmentIds(String patientId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('reviews')
          .where('patientId', isEqualTo: patientId)
          .get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (e) {
      // فشل القراءة لا يمنع عرض المواعيد؛ يظهر زر التقييم والخادم يحسم.
      AppLogger.info('تعذّر جلب المراجعات السابقة: $e');
      return _reviewedAppointmentIds;
    }
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
            child: const Text('تأكيد الإلغاء',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // الإلغاء يمرّ عبر BookingService إلى `cancelAppointment` على
        // الخادم، فيتحقق من الحالة والمهلة ويُحرّر قفل الخانة في نفس
        // المعاملة — لا يعدّل التطبيق الموعد أو الخانة مباشرة.
        final result =
            await _bookingService.cancel(appointmentId: appointmentId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: result.isSuccess ? Colors.green : Colors.red,
            ),
          );
          _fetchMyAppointments();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ أثناء الإلغاء: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showAppointmentDetails(Map<String, dynamic> appointment) {
    final statusMap = {
      'upcoming': 'قادم',
      'Scheduled': 'مجدول',
      'Booked': 'محجوز',
      'pending': 'قيد الانتظار',
      'Completed': 'مكتمل',
      'Cancelled': 'ملغي',
      'Rejected': 'مرفوض',
    };

    final statusColorMap = {
      'upcoming': Colors.blue,
      'Scheduled': Colors.blue,
      'Booked': Colors.blue,
      'pending': Colors.orange,
      'Completed': Colors.green,
      'Cancelled': Colors.red,
      'Rejected': Colors.red,
    };

    final currentStatusText = appointment['status'] as String;
    final statusStr = statusMap[currentStatusText] ?? currentStatusText;
    final statusColor = statusColorMap[currentStatusText] ?? Colors.grey;

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
        titleTextStyle: const TextStyle(
          color: Color(0xFF0097A7),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withOpacity(0.5)),
                ),
                child: Text(
                  statusStr,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Doctor Info
              Text(
                'معلومات الطبيب',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0097A7),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0097A7),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0097A7),
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0097A7),
                      ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 8),
                if (clinicLocation.isNotEmpty)
                  _buildDetailRow('الموقع:', clinicLocation),
                if (clinicPhone.isNotEmpty)
                  _buildDetailRow('الهاتف:', clinicPhone),
              ],

              if (currentStatusText == 'Completed') ...[
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'الحمد لله على السلامة، نتمنى لك دوام الصحة والعافية',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: _reviewedAppointmentIds
                          .contains(appointment['id'] as String)
                      ? const _ReviewedBadge()
                      : ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openRatingFlow(appointment);
                          },
                          icon: const Icon(Icons.star_rate),
                          label: const Text('تقييم الطبيب'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.white,
                          ),
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

  /// يسأل الخادم عن الأهلية أولاً، ثم يفتح نافذة التقييم.
  ///
  /// الواجهة لا تقرّر الأهلية من حالة الموعد وحدها: قد تكون الزيارة مُقيَّمة
  /// من جهاز آخر، أو تكون الحالة تغيّرت منذ آخر تحديث للقائمة.
  Future<void> _openRatingFlow(Map<String, dynamic> appointment) async {
    final appointmentId = appointment['id'] as String;
    final messenger = ScaffoldMessenger.of(context);

    final eligibility = await _reviewService.checkEligibility(appointmentId);
    if (!mounted) return;

    if (eligibility.alreadyReviewed) {
      setState(() => _reviewedAppointmentIds = {
            ..._reviewedAppointmentIds,
            appointmentId,
          });
      messenger.showSnackBar(const SnackBar(
        content: Text('سبق أن قيّمت هذه الزيارة، شكراً لك'),
      ));
      return;
    }

    if (!eligibility.eligible) {
      messenger.showSnackBar(SnackBar(
        content: Text(
          eligibility.reason == 'appointment-not-completed'
              ? 'يمكنك التقييم بعد اكتمال الكشف فقط'
              : 'تعذّر فتح التقييم الآن، حاول مرة أخرى',
        ),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    if (!mounted) return;
    _showRatingDialog(appointment);
  }

  void _showRatingDialog(Map<String, dynamic> appointment) {
    int rating = 5;
    var isSubmitting = false;
    final TextEditingController commentController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                    tooltip: '${index + 1} من 5',
                    icon: Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 32,
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () => setDialogState(() => rating = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: commentController,
                maxLines: 3,
                // نفس الحد المفروض على الخادم (`MAX_COMMENT_LENGTH`)، حتى
                // يُمنع التجاوز قبل الإرسال بدل أن يُرفض بعده.
                maxLength: 1000,
                enabled: !isSubmitting,
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
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              // التعطيل أثناء الإرسال يمنع الضغط المزدوج من الأساس؛ ولو وصل
              // طلبان رغم ذلك فالخادم يُرجع نفس المراجعة بلا عدّاد مضاعف.
              onPressed: isSubmitting
                  ? null
                  : () async {
                      setDialogState(() => isSubmitting = true);
                      await _submitRating(
                          appointment, rating, commentController.text);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: isSubmitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('إرسال التقييم'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitRating(
      Map<String, dynamic> appointment, int rating, String comment) async {
    final appointmentId = appointment['id'] as String;
    final messenger = ScaffoldMessenger.of(context);

    // الطلب يحمل الزيارة والنجوم والتعليق فقط.
    //
    // كان هنا مساران: كتابة مستند المراجعة، ثم معاملة منفصلة تحسب متوسط
    // الطبيب على العميل وتكتبه. انقطاع بينهما كان يترك مراجعة بلا أثر في
    // المتوسط، وإعادة الإرسال كانت ترفع العدّاد مرتين على زيارة واحدة.
    // الآن `createReview` تكتب الاثنين في معاملة واحدة على الخادم.
    final result = await _reviewService.submit(
      appointmentId: appointmentId,
      rating: rating,
      comment: comment,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() => _reviewedAppointmentIds = {
            ..._reviewedAppointmentIds,
            appointmentId,
          });
    }

    messenger.showSnackBar(SnackBar(
      content: Text(result.message),
      backgroundColor: result.isSuccess ? Colors.green : Colors.red,
    ));
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
                color: Colors.grey[700],
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
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
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
    final appointmentsToList = _filteredAppointments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مواعيدي'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0097A7),
        elevation: 1,
      ),
      body: Column(
        children: [
          // Custom Tab Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
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
            color: isSelected ? const Color(0xFF0097A7) : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFF0097A7) : Colors.grey[300]!,
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[700],
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
              size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _selectedFilterIndex == 0
                ? 'لا توجد مواعيد قادمة'
                : 'لا توجد مواعيد سابقة',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedFilterIndex == 0
                ? 'قم بحجز موعد جديد من صفحة البحث'
                : 'لم تقم بزيارة أي طبيب من قبل',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
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

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    final bool isUpcoming = _selectedFilterIndex == 0;
    final bool canCancel = _canCancelAppointment(appointment);

    final statusMap = {
      'upcoming': 'قادم',
      'Scheduled': 'مجدول',
      'Booked': 'محجوز',
      'pending': 'قيد الانتظار',
      'Completed': 'مكتمل',
      'Cancelled': 'ملغي',
      'Rejected': 'مرفوض',
    };

    final statusColorMap = {
      'upcoming': Colors.blue,
      'Scheduled': Colors.blue,
      'Booked': Colors.blue,
      'pending': Colors.orange,
      'Completed': Colors.green,
      'Cancelled': Colors.red,
      'Rejected': Colors.red,
    };

    final currentStatusText = appointment['status'] as String;
    final statusStr = statusMap[currentStatusText] ?? currentStatusText;
    final statusColor = statusColorMap[currentStatusText] ?? Colors.grey;

    final dateStr =
        DateFormat('yyyy-MM-dd', 'ar').format(appointment['date'] as DateTime);
    final timeStr = appointment['time'] as String;

    return InkWell(
      onTap: () => _showAppointmentDetails(appointment),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isUpcoming
                ? Colors.blue.withOpacity(0.2)
                : Colors.grey.withOpacity(0.2),
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
                  // Status Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withOpacity(0.5)),
                    ),
                    child: Text(
                      statusStr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),

                  Row(
                    children: [
                      Text(
                        timeStr,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Icon(Icons.access_time,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Icon(Icons.calendar_today,
                          size: 16, color: Colors.grey),
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
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.blue[50],
                    child:
                        const Icon(Icons.person, color: Colors.blue, size: 30),
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
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    label: const Text('إلغاء الموعد',
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ] else if (isUpcoming && !canCancel) ...[
                // ⏰ إذا مضى الموعد، عرض رسالة إعلامية
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'لا يمكن إلغاء الموعد (انقضى الوقت)',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // زر التقييم على البطاقة.
              //
              // كان هذا الزر يعرض «سيتم تفعيل التقييم قريباً!» بينما التقييم
              // يعمل فعلاً من نافذة التفاصيل — زرّان بنفس الاسم، أحدهما ميت.
              if (appointment['status'] == 'Completed') ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: _reviewedAppointmentIds
                          .contains(appointment['id'] as String)
                      ? const _ReviewedBadge()
                      : ElevatedButton.icon(
                          onPressed: () => _openRatingFlow(appointment),
                          icon:
                              const Icon(Icons.star_rate, color: Colors.amber),
                          label: const Text('تقييم الطبيب'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[50],
                            foregroundColor: Colors.blue[800],
                          ),
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

/// شارة «تم التقييم» — تحلّ محل زر التقييم بعد إرسال المراجعة.
///
/// المراجعة غير قابلة للتعديل بعد كتابتها (راجع `functions/reviews.js`)،
/// فعرض زر يفتح نافذة لن تُقبل كتابتها كان سيعِد بما لا يحدث.
class _ReviewedBadge extends StatelessWidget {
  const _ReviewedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, color: Colors.amber, size: 18),
          SizedBox(width: 8),
          Text(
            'تم التقييم',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
