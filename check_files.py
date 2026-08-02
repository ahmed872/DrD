import os

files_to_check = [
    'lib/presentation/screens/doctor_settings_screen.dart',
    'lib/presentation/screens/patient_search_doctor_screen.dart',
    'lib/presentation/screens/patient_booking_screen.dart',
    'lib/presentation/screens/patient_my_appointments_screen.dart'
]

for f in files_to_check:
    print(f"--- {f} ---")
    with open(f, 'r', encoding='utf-8', errors='ignore') as file:
        content = file.read()
        
        if 'clinicLocation' in content:
            print("HAS clinicLocation")
        else:
            print("MISSING clinicLocation")
            
        if 'FirebaseFirestore.instance' in content:
            print("HAS FirebaseFirestore")
        else:
            print("MISSING FirebaseFirestore")
            
        if '_showAppointmentDetails' in content:
            print("HAS _showAppointmentDetails")
        else:
            print("MISSING _showAppointmentDetails")
    print()
