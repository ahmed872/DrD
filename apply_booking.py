import re

file_path = 'lib/presentation/screens/patient_booking_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add clinicLocation to doctor map
old_map = "          'bioEn': data['bioEn'] ?? '',\n        };"
new_map = '''          'bioEn': data['bioEn'] ?? '',
          'clinicLocation': data['clinicLocation'] ?? '',
          'workingDays': data['workingDays'] ?? {},
        };'''
content = content.replace(old_map, new_map)

# Modify Doctor listing card to show location
old_bio_display = '''                      Text(
                        doctor['bio'],
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      const SizedBox(height: 8),'''

new_bio_display = '''                      Text(
                        doctor['bio'],
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      if (doctor['clinicLocation'] != null && doctor['clinicLocation'].toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 14, color: Colors.orange),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                doctor['clinicLocation'],
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.orange[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),'''
content = content.replace(old_bio_display, new_bio_display)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
