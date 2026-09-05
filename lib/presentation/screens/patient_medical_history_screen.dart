import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/appointment_status.dart';

class PatientMedicalHistoryScreen extends StatefulWidget {
  const PatientMedicalHistoryScreen({super.key});

  @override
  State<PatientMedicalHistoryScreen> createState() =>
      _PatientMedicalHistoryScreenState();
}

class _PatientMedicalHistoryScreenState
    extends State<PatientMedicalHistoryScreen> {
  int _selectedFilter = 0; // 0: All
  bool _isLoading = true;
  List<Map<String, dynamic>> _medicalRecords = [];

  @override
  void initState() {
    super.initState();
    _fetchMedicalHistory();
  }

  Future<void> _fetchMedicalHistory() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // السجل الطبي = المواعيد المنتهية.
      //
      // كان الاستعلام يفلتر `status == 'Completed'` نصّياً، فيفوّت كل موعد
      // مخزَّن بصيغة قديمة (`completed`, `done`) ولا يظهر في سجل المريض
      // إطلاقاً. الفلترة الآن تتم في Dart عبر `AppointmentStatus.parse` الذي
      // يعرف كل الصيغ التاريخية — وبلا فهرس مركّب إضافي، لأن عدد مواعيد
      // المريض الواحد صغير بطبيعته.
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('patientId', isEqualTo: user.uid)
          .get();

      List<Map<String, dynamic>> records = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (AppointmentStatus.parse(data['status']) !=
            AppointmentStatus.completed) {
          continue;
        }
        records.add({
          'id': doc.id,
          'date': data['appointmentDate'] ?? '',
          'type': 'Visit',
          'typeAr': 'زيارة',
          'doctor': data['doctorName'] ?? '',
          'doctorEn': data['doctorNameEn'] ?? data['doctorName'] ?? '',
          'reason': data['reason'] ?? '',
          'reasonAr': data['reason'] ?? '',
          'diagnosis': data['diagnosis'] ?? 'No diagnosis recorded',
          'diagnosisAr': data['diagnosisAr'] ?? 'لا يوجد تشخيص مسجل',
          'prescription': data['prescription'] ?? 'No prescription',
          'prescriptionAr': data['prescriptionAr'] ?? 'لا يوجد وصفة طبية',
          'notes': data['notes'] ?? 'No additional notes',
          'notesAr': data['notesAr'] ?? 'لا توجد ملاحظات إضافية',
          'icon': '🩺',
          'color': Colors.blue,
        });
      }

      // Sort by date descending
      records
          .sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

      setState(() {
        _medicalRecords = records;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في جلب السجل الطبي: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('السجل الطبي / Medical History'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0097A7),
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilters(),
                Expanded(
                  child: _medicalRecords.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _medicalRecords.length,
                          itemBuilder: (context, index) {
                            return _buildRecordCard(_medicalRecords[index]);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilters() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip('الكل / All', 0),
          const SizedBox(width: 8),
          _filterChip('زيارات / Visits', 1),
        ],
      ),
    );
  }

  Widget _filterChip(String label, int index) {
    final isSelected = _selectedFilter == index;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedFilter = index);
      },
      backgroundColor: Colors.grey[200],
      selectedColor: const Color(0xFF0097A7),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (record['color'] as Color).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        record['icon'],
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record['typeAr'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          record['date'],
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  record['doctor'],
                  style: const TextStyle(
                    color: Color(0xFF0097A7),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow('السبب', record['reasonAr'], Colors.blue),
            const SizedBox(height: 8),
            _buildInfoRow('التشخيص', record['diagnosisAr'], Colors.orange),
            const SizedBox(height: 8),
            _buildInfoRow('الوصفة', record['prescriptionAr'], Colors.green),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.note_alt_outlined,
                      size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ملاحظات / Notes',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record['notesAr'],
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color iconColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.circle, size: 8, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا يوجد سجل طبي متاح',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
