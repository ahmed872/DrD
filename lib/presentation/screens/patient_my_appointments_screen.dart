import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/constants/appointment_status.dart';
import '../../data/services/booking_service.dart';
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
        // الإلغاء يمرّ عبر BookingService حتى يُحرَّر قفل الخانة في نفس
        // المعاملة. تغيير الحالة وحده — كما كان — يترك عدّاد الخانة مرفوعاً،
        // فتبدو الخانة محجوزة إلى الأبد ولا يستطيع أي مريض آخر أخذها.
        final ok = await _bookingService.cancel(appointmentId: appointmentId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ok
                  ? 'تم إلغاء الموعد بنجاح'
                  : 'تعذّر إلغاء الموعد، حاول مرة أخرى'),
              backgroundColor: ok ? Colors.green : Colors.red,
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
    final currentStatus = AppointmentStatus.parse(appointment['status']);
    final statusStr = currentStatus.arabicLabel;
    final statusColor = _statusColor(currentStatus);

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

              if (currentStatus == AppointmentStatus.completed) ...[
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
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showRatingDialog(appointment);
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
                      color: Colors.amber,
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
          const SnackBar(
              content: Text('تم إرسال تقييمك بنجاح!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('حدث خطأ أثناء إرسال التقييم: $e'),
              backgroundColor: Colors.red),
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
    final statusStr = currentStatus.arabicLabel;
    final statusColor = _statusColor(currentStatus);

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
                    icon: const Icon(Icons.star_rate, color: Colors.amber),
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

/// لون الحالة — مصدر واحد بدل خريطتين مكرَّرتين في هذا الملف.
Color _statusColor(AppointmentStatus status) {
  switch (status) {
    case AppointmentStatus.booked:
      return Colors.blue;
    case AppointmentStatus.completed:
      return Colors.green;
    case AppointmentStatus.cancelled:
      return Colors.red;
    case AppointmentStatus.noShow:
      return Colors.redAccent;
    case AppointmentStatus.pendingConfirmation:
      return Colors.orange;
    case AppointmentStatus.expired:
      return Colors.grey;
  }
}
