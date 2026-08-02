import re

with open('lib/presentation/screens/doctor_schedule_screen.dart', 'r', encoding='utf-8') as f:
    ds = f.read()

action_buttons_loc = ds.find('  Widget _buildActionButtons(')

completed_actions = """
  Widget _buildCompletedActions(Map<String, dynamic> appointment) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showAddNoteDialog(appointment['id'], appointment['doctorNote'] ?? appointment['notes'] ?? ''),
            icon: const Icon(Icons.edit_note),
            label: const Text('إضافة ملاحظة طبيب / Add Note'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.blue),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddNoteDialog(String appointmentId, String currentNote) async {
    final TextEditingController noteController = TextEditingController(text: currentNote);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ملاحظة طبية / Medical Note', textAlign: TextAlign.right),
          content: TextField(
            controller: noteController,
            maxLines: 4,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              hintText: 'اكتب ملاحظاتك الطبية هنا...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await FirebaseFirestore.instance
                      .collection('appointments')
                      .doc(appointmentId)
                      .update({'notes': noteController.text.trim()});
                  await _fetchAppointments();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حفظ الملاحظة بنجاح'), backgroundColor: Colors.green),
                  );
                } catch(e) {}
              },
              child: const Text('حفظ / Save'),
            ),
          ],
        );
      },
    );
  }

"""
if '_buildCompletedActions(' not in ds:
    ds = ds[:action_buttons_loc] + completed_actions + ds[action_buttons_loc:]

    invoke_pattern = r"if\s*\(isPending\)\s*_buildActionButtons\(appointment\),"
    invoke_repl = """if (isPending) _buildActionButtons(appointment) else _buildCompletedActions(appointment),"""

    ds = re.sub(invoke_pattern, invoke_repl, ds)

with open('lib/presentation/screens/doctor_schedule_screen.dart', 'w', encoding='utf-8') as f:
    f.write(ds)

print("Add Note Dialog added!")
