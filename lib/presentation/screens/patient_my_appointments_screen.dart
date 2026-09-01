import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../data/services/booking_service.dart';
import '../../data/services/review_service.dart';
import '../widgets/app_widgets.dart';
import 'reschedule_appointment_screen.dart';
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
  /// سقف المواعيد المقروءة. المريض لا يتصفّح تاريخاً بلا نهاية في هذه
  /// الشاشة؛ الأحدث هو المقصود، والسقف يجعل التكلفة ثابتة مع عمر الحساب.
  static const int _appointmentCap = 200;

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
            // ===== المرحلة 7: قراءة محدودة ومرتّبة =====
            //
            // كانت الشاشة تقرأ كل مواعيد المريض منذ إنشاء حسابه ثم تفرزها
            // في Dart. الترتيب على الخادم مع سقف يجعل التكلفة ثابتة ويُبقي
            // الأحدث — وهو ما تعرضه الشاشة أصلاً في أعلى القائمة.
            //
            // `orderBy` لا نطاق `where`: الترتيب لا يُقصي أي مستند مهما كان
            // نوع حقله. الفهرس `patientId + appointmentDate DESC` موجود.
            .orderBy('appointmentDate', descending: true)
            .limit(_appointmentCap)
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
            'slotId': data['slotId'],
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
              content: const Text('تعذّر تحميل مواعيدك، تحقق من الإنترنت'),
              backgroundColor: Theme.of(context).colorScheme.error,
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
          // محدود بنفس سقف المواعيد: لا فائدة من معرفة مراجعة لموعد لم
          // يُقرأ أصلاً في هذه الشاشة.
          .limit(_appointmentCap)
          .get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (e) {
      // فشل القراءة لا يمنع عرض المواعيد؛ يظهر زر التقييم والخادم يحسم.
      AppLogger.info('تعذّر جلب المراجعات السابقة: $e');
      return _reviewedAppointmentIds;
    }
  }

  /// يفتح شاشة تغيير الموعد ويعيد تحميل القائمة عند النجاح.
  Future<void> _openReschedule(Map<String, dynamic> appointment) async {
    final doctorId = appointment['doctorId']?.toString();
    if (doctorId == null || doctorId.isEmpty) return;

    final date = appointment['date'] as DateTime;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RescheduleAppointmentScreen(
          appointmentId: appointment['id'] as String,
          doctorId: doctorId,
          doctorName: appointment['doctorName']?.toString() ?? 'الطبيب',
          currentDate: DateFormat('yyyy-MM-dd').format(date),
          currentTime: appointment['time']?.toString() ?? '',
          currentSlotId: appointment['slotId']?.toString(),
        ),
      ),
    );

    if (changed == true && mounted) _fetchMyAppointments();
  }

  Future<void> _cancelAppointment(String appointmentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الموعد', textAlign: TextAlign.right),
        content: const Text(
          'هل أنت متأكد من إلغاء هذا الموعد؟\n\n'
          'لا يمكن الإلغاء قبل الموعد بأقل من ساعة.',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('تأكيد الإلغاء',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
              backgroundColor: result.isSuccess
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.error,
            ),
          );
          _fetchMyAppointments();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تعذّر إلغاء الموعد، حاول مرة أخرى'),
              backgroundColor: Theme.of(context).colorScheme.error,
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

    final currentStatusText = appointment['status'] as String;
    final statusStr = statusMap[currentStatusText] ?? currentStatusText;

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
        titleTextStyle: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status Badge
              StatusChip(
                label: statusStr,
                tone: _toneForStatus(currentStatusText),
              ),
              const SizedBox(height: 16),

              // Doctor Info
              Text(
                'معلومات الطبيب',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
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
                      color: Theme.of(context).colorScheme.primary,
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
                      color: Theme.of(context).colorScheme.primary,
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
                        color: Theme.of(context).colorScheme.primary,
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
                Center(
                  child: Text(
                    'الحمد لله على السلامة، نتمنى لك دوام الصحة والعافية',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary,
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
                            backgroundColor:
                                Theme.of(context).colorScheme.tertiary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onTertiary,
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
        backgroundColor: Theme.of(context).colorScheme.secondary,
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

    // ===== المرحلة 7: تخلّص من متحكّم الحوار =====
    // كان يُنشأ متحكّم في كل فتح لحوار التقييم ولا يُتخلَّص منه، فيتراكم
    // مع كل مراجعة يكتبها المريض. `whenComplete` يضمن التخلّص سواء أُرسل
    // التقييم أم أُغلق الحوار.
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
                      color: Theme.of(context).colorScheme.tertiary,
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
    ).whenComplete(commentController.dispose);
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
      backgroundColor: result.isSuccess
          ? Theme.of(context).colorScheme.tertiary
          : Theme.of(context).colorScheme.error,
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
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
        elevation: 1,
      ),
      body: Column(
        children: [
          // Custom Tab Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.onPrimary,
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
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
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
              size: 80, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            _selectedFilterIndex == 0
                ? 'لا توجد مواعيد قادمة'
                : 'لا توجد مواعيد سابقة',
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ دالة للتحقق من إمكانية إلغاء الموعد
  /// هل تُعرض أدوات الإلغاء وتغيير الموعد لهذا الموعد؟
  ///
  /// **الحالة وحدها**، لا حساب وقت. كانت هنا حسابات تاريخ وساعة تقرّر
  /// بنفسها، وكانت تخالف الخادم: الخادم يرفض الإلغاء قبل الموعد بأقل من
  /// ساعة (`CANCEL_DEADLINE_MINUTES` في `functions/lifecycle.js`)، بينما
  /// الواجهة كانت تسمح حتى لحظة بدء الموعد — فيضغط المريض ويُفاجأ برفض.
  ///
  /// المهلة قرار خادم لا تكراره الواجهة: نعرض المحاولة، ونثق بالنتيجة،
  /// ونترجم `cancellation-deadline-passed` إلى رسالة مفهومة.
  bool _canCancelAppointment(Map<String, dynamic> appointment) {
    const cancellableStatuses = [
      'upcoming',
      'Scheduled',
      'Booked',
      'pending',
      'confirmed',
    ];
    return cancellableStatuses.contains(appointment['status'] as String);
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

    final currentStatusText = appointment['status'] as String;
    final statusStr = statusMap[currentStatusText] ?? currentStatusText;

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
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
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
                  StatusChip(
                    label: statusStr,
                    tone: _toneForStatus(currentStatusText),
                  ),

                  Row(
                    children: [
                      Text(
                        timeStr,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Icon(Icons.access_time,
                          size: 16,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Icon(Icons.calendar_today,
                          size: 16,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  CircleAvatar(
                    radius: 25,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.person,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 30),
                  ),
                ],
              ),

              // Cancel and Review Actions
              // ✅ عرض زر الإلغاء فقط إذا كان الموعد لم يمضِ بعد
              if (isUpcoming && canCancel) ...[
                const SizedBox(height: 16),
                // تغيير الموعد قبل إلغائه: `rescheduleAppointment` موجودة على
                // الخادم منذ المرحلة 1ب بلا أي واجهة، فكان على المريض أن يُلغي
                // ثم يحجز من جديد — ويخاطر بألا يجد مكاناً بعد أن ترك مكانه.
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openReschedule(appointment),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('تغيير الموعد'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _cancelAppointment(appointment['id']),
                    icon: Icon(Icons.cancel_outlined,
                        color: Theme.of(context).colorScheme.error),
                    label: Text('إلغاء الموعد',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.error),
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
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.secondary),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline,
                          color: Theme.of(context).colorScheme.secondary,
                          size: 18),
                      SizedBox(width: 8),
                      Text(
                        'لا يمكن إلغاء الموعد (انقضى الوقت)',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
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
                          icon: Icon(Icons.star_rate,
                              color: Theme.of(context).colorScheme.tertiary),
                          label: const Text('تقييم الطبيب'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
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
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.tertiary),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star,
              color: Theme.of(context).colorScheme.onTertiaryContainer,
              size: 18),
          SizedBox(width: 8),
          Text(
            'تم التقييم',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onTertiaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// نغمة الحالة — تُشتق من `ColorScheme` فتتبدّل مع الوضع الليلي، بدل خريطة
/// ألوان ثابتة كانت مكرّرة حرفياً في موضعين داخل هذه الشاشة.
StatusTone _toneForStatus(String status) {
  switch (status) {
    case 'Completed':
      return StatusTone.success;
    case 'Cancelled':
    case 'Rejected':
      return StatusTone.danger;
    case 'pending':
      return StatusTone.warning;
    case 'upcoming':
    case 'Scheduled':
    case 'Booked':
      return StatusTone.info;
    default:
      return StatusTone.neutral;
  }
}
