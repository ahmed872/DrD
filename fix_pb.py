with open('lib/presentation/screens/patient_booking_screen.dart', 'r', encoding='utf-8') as f:
    pb = f.read()

start_idx = pb.find('Widget _buildTimeSlot(String time, int? remaining) {')
end_idx = pb.find('Widget chip({')

if start_idx != -1 and end_idx != -1:
    old_repl = pb[start_idx:end_idx]
    new_repl = """Widget _buildTimeSlot(String time, int? remaining) {
      final isSelected = _selectedTime == time;
      String formattedTime = time;
      final parts = time.split(':');
      if (parts.length == 2) {
        int h = int.tryParse(parts[0]) ?? 0;
        final m = parts[1].split('\\n')[0]; // strip anything extra
        final period = h >= 12 ? 'م' : 'ص';
        if (h == 0) h = 12;
        else if (h > 12) h -= 12;
        formattedTime = '${h.toString()}:$m $period';
      }
      
      final displayLabel = remaining != null ? '$formattedTime\\n(باقي $remaining مكان)' : formattedTime;
      return chip(
        label: displayLabel,
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _selectedTime = time);
        },
      );
    }

    """
    pb = pb.replace(old_repl, new_repl)
    with open('lib/presentation/screens/patient_booking_screen.dart', 'w', encoding='utf-8') as f:
        f.write(pb)
    print('Fixed patient booking AM/PM')
else:
    print('Could not find replace string')
