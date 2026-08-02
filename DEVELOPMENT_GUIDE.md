# 🔧 دليل التطوير والمساهمة

## 📋 محتويات الملف

1. [بنية المشروع التفصيلية](#بنية-المشروع)
2. [الخطوات التالية المقترحة](#الخطوات-التالية)
3. [دليل إضافة ميزات جديدة](#دليل-إضافة-ميزات-جديدة)
4. [استكشاف بيانات قاعدة البيانات](#استكشاف-البيانات)
5. [معالجة الأخطاء والمشاكل الشائعة](#معالجة-الأخطاء)

---

## 🏗️ بنية المشروع

### Domain Layer (logic + entities)

```
lib/domain/
├── entities/
│   ├── appointment.dart      # نموذج الموعد
│   ├── doctor.dart           # نموذج الطبيب
│   └── profile.dart          # نموذج المستخدم
├── repositories/
│   ├── appointment_repository.dart
│   ├── auth_repository.dart
│   └── doctor_repository.dart
└── usecases/
    ├── appointment/
    │   ├── book_appointment_usecase.dart
    │   ├── get_patient_appointments_usecase.dart
    │   └── get_available_slots_usecase.dart
    ├── auth/
    │   ├── sign_in_usecase.dart
    │   ├── sign_out_usecase.dart
    │   └── sign_up_usecase.dart
    └── doctor/
        ├── get_all_doctors_usecase.dart
        ├── get_doctor_by_id_usecase.dart
        └── update_doctor_usecase.dart
```

### Data Layer (models + datasources + implementations)

```
lib/data/
├── datasources/
│   ├── auth_datasource.dart
│   ├── appointment_datasource.dart
│   └── doctor_datasource.dart
├── models/
│   ├── appointment_model.dart
│   ├── doctor_model.dart
│   └── profile_model.dart
└── repositories/
    ├── appointment_repository_impl.dart
    ├── doctor_repository_impl.dart
    └── supabase_auth_repository.dart
```

### Presentation Layer (UI + state management)

```
lib/presentation/
├── screens/
│   ├── login_screen.dart       # تسجيل دخول/تسجيل
│   ├── doctor_dashboard.dart   # لوحة الطبيب
│   ├── patient_booking_screen.dart  # حجز المريض
│   └── home_screen.dart        # التوجيه الأساسي
├── providers/
│   └── auth_service.dart       # State management
└── widgets/
    └── live_countdown.dart
```

### Core Layer (utilities + configurations)

```
lib/core/
├── utils/
│   └── time_slot_generator.dart  # توليد المواعيد
└── providers/
    └── app_providers.dart       # Dependency Injection
```

---

## ⏭️ الخطوات التالية

### المرحلة 1: تكامل قاعدة البيانات (حرج ⭐⭐⭐)

**الموضوع**: تفعيل Supabase بالفعل

**الملفات المتأثرة**: `lib/main.dart`

**الخطوات**:

```dart
// 1. احصل على بيانات المشروع من dashboard.supabase.com
// 2. انسخ الرابط والمفتاح
// 3. حدّث lib/main.dart:

await Supabase.initialize(
  url: 'https://YOUR_PROJECT.supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
);

// 4. شغّل التطبيق وجرّب التسجيل
```

### المرحلة 2: ربط Dashboard الطبيب (عالي ⭐⭐⭐)

**الموضوع**: جلب البيانات الفعلية من قاعدة البيانات

**الملفات المتأثرة**: `lib/presentation/screens/doctor_dashboard.dart`

**الكود**:

```dart
// استخدام GetDoctorByIdUseCase لجلب البيانات
final doctorData = await getDoctorByIdUseCase.call(userId);
setState(() {
  _sessionDuration = doctorData.sessionDuration;
  _bufferTime = doctorData.bufferTime;
});

// استخدام GetDoctorAppointmentsUseCase للمواعيد
final appointments = await getDoctorAppointmentsUseCase.call(
  doctorId: userId,
  date: _selectedDate,
);
```

### المرحلة 3: ربط واجهة حجز المريض (عالي ⭐⭐⭐)

**الموضوع**: توليد وعرض الفجوات الزمنية المتاحة

**الملفات المتأثرة**: `lib/presentation/screens/patient_booking_screen.dart`

**الخطوات**:

1. عند اختيار الطبيب والتاريخ، استدعِ `GetAvailableSlotsUseCase`
2. عرض النتائج في الشبكة
3. عند التأكيد، استدعِ `BookAppointmentUseCase`

**الكود**:

```dart
// الحصول على الفجوات المتاحة
final slots = await getAvailableSlotsUseCase.call(
  doctorId: _selectedDoctorId,
  date: _selectedDate,
);

// حجز الموعد
final booking = await bookAppointmentUseCase.call(
  appointment: Appointment(
    doctorId: _selectedDoctorId,
    patientId: currentUserId,
    appointmentDatetime: _selectedSlot,
    patientName: _fullName,
    patientPhone: _phone,
    patientAge: int.parse(_age),
    patientGender: _gender,
    symptoms: _symptoms,
  ),
);
```

### المرحلة 4: شاشة "مواعيدي" للمريض (متوسط ⭐⭐)

**الموضوع**: عرض المواعيد السابقة واللاحقة

**الملفات الجديدة**: `lib/presentation/screens/my_appointments_screen.dart`

**الميزات**:

- عرض قائمة المواعيد حسب التاريخ
- خيار إلغاء الموعد
- عرض حالة الموعد (مقادم/منتهي/ملغي)

### المرحلة 5: نظام الإشعارات (منخفض ⭐)

**الموضوع**: تذكيرات المواعيد

**المكتبات المقترحة**:

- `flutter_local_notifications`
- `awesome_notifications`

---

## 📖 دليل إضافة ميزات جديدة

### إضافة عملية جديدة (Business Logic)

**مثال: إضافة تقييم الطبيب**

#### 1. إنشء Entity

```dart
// lib/domain/entities/doctor_review.dart
class DoctorReview {
  final String doctorId;
  final String patientId;
  final double rating;
  final String comment;
  final DateTime createdAt;
}
```

#### 2. إنشء Repository Interface

```dart
// lib/domain/repositories/review_repository.dart
abstract class ReviewRepository {
  Future<void> addReview(DoctorReview review);
  Future<List<DoctorReview>> getDoctorReviews(String doctorId);
}
```

#### 3. إنشء UseCase

```dart
// lib/domain/usecases/review/add_review_usecase.dart
class AddReviewUseCase {
  final ReviewRepository repository;
  AddReviewUseCase(this.repository);

  Future<void> call(DoctorReview review) {
    return repository.addReview(review);
  }
}
```

#### 4. إنشء DataSource

```dart
// lib/data/datasources/review_datasource.dart
class ReviewDataSource {
  final Supabase supabase;

  Future<void> addReview(review) async {
    await supabase.from('reviews').insert(review.toMap());
  }
}
```

#### 5. إنشء Repository Implementation

```dart
// lib/data/repositories/review_repository_impl.dart
class ReviewRepositoryImpl implements ReviewRepository {
  final ReviewDataSource datasource;
  ReviewRepositoryImpl(this.datasource);

  @override
  Future<void> addReview(DoctorReview review) {
    return datasource.addReview(review);
  }
}
```

#### 6. استخدام في الـ UI

```dart
// في screen يومًا ما
final addReviewUseCase = context.read<AddReviewUseCase>();
await addReviewUseCase.call(review);
```

### إضافة شاشة جديدة

**الخطوات**:

1. إنشاء الملف في `lib/presentation/screens/`
2. تصميم الواجهة مع RTL support
3. ربط مع providers للبيانات
4. إضافة التوجيه في `home_screen.dart` أو `main.dart`

---

## 🔍 استكشاف البيانات

### عرض قاعدة البيانات

```sql
-- عرض جميع المستخدمين
SELECT * FROM profiles;

-- عرض الأطباء
SELECT p.full_name, d.* FROM doctors d
JOIN profiles p ON d.id = p.id;

-- عرض المواعيد
SELECT
  a.id,
  doc.full_name as doctor_name,
  pat.full_name as patient_name,
  a.appointment_datetime,
  a.status
FROM appointments a
JOIN profiles doc ON a.doctor_id = doc.id
JOIN profiles pat ON a.patient_id = pat.id;
```

### اختبار APIs يدويًا

```bash
# استخدم REST client مثل Postman أو Insomnia
# الـ Base URL: https://YOUR_PROJECT.supabase.co/rest/v1

# مثال: جلب الأطباء
curl -X GET 'https://YOUR_PROJECT.supabase.co/rest/v1/doctors' \
  -H 'Authorization: Bearer YOUR_ANON_KEY'
```

---

## 🐛 معالجة الأخطاء

### الأخطاء الشائعة

#### 1. خطأ: "Supabase URL not configured"

```
❌ الحل: تأكد من تحديث lib/main.dart بـ URL و anon key
```

#### 2. خطأ: "User not found in profiles"

```dart
// حالة: تسجيل دخول ناجح لكن لا توجد record في profiles table
// السبب: لم تُنشَأ profile record عند التسجيل

// الحل: تحقق من auth_datasource.dart - signUp method
```

#### 3. خطأ: "Permission denied" في RLS

```sql
-- تحقق من سياسات RLS
SELECT * FROM pg_policies
WHERE schemaname = 'public';

-- مثال: السماح للمستخدم برؤية مواعيده فقط
ALTER POLICY "appointments_select_policy" ON appointments
USING (auth.uid() = patient_id OR auth.uid() = doctor_id);
```

#### 4. خطأ: "Hot reload not working"

```bash
# محاولات الحل:
1. اضغط 'R' في terminal
2. إذا لم ينجح: استخدم Ctrl+C ثم flutter run مجددًا
3. إذا ظل المشكلة: flutter clean && flutter pub get
```

### Debugging Tips

```dart
// 1. استخدم print() للتتبع
print('DEBUG: User ID = $userId');

// 2. استخدم debugger
import 'package:flutter/foundation.dart';
debugger();

// 3. عرض الأخطاء
try {
  // ...
} catch (e, stack) {
  print('ERROR: $e');
  print('STACK: $stack');
}
```

---

## 📱 اختبار على أجهزة مختلفة

```bash
# قائمة الأجهزة المتصلة
flutter devices

# تشغيل على جهاز معين
flutter run -d DEVICE_ID

# بناء APK للنشر
flutter build apk --release

# بناء App Bundle (Google Play)
flutter build appbundle --release
```

---

## 🚀 نشر التطبيق

### نشر على Google Play

1. إنشاء حساب Developer
2. إعداد التطبيق على Play Console
3. بناء إصدار Release: `flutter build appbundle --release`
4. تحميل الـ Bundle على Play Console

### نشر على App Store (iOS)

1. إنشاء حساب Developer
2. إعداد App على App Store Connect
3. بناء الإصدار: `flutter build ios --release`
4. استخدام Xcode للتحميل

---

## 📝 قائمة التحقق (Checklist)

قبل النشر:

- [ ] اختبار جميع الشاشات
- [ ] اختبار تسجيل الدخول والخروج
- [ ] اختبار حجز الموعد كاملاً
- [ ] اختبار على جهاز فعلي
- [ ] التحقق من الأخطاء
- [ ] تحديث الـ Credentials
- [ ] إنشاء نسخة Signed APK

---

**آخر تحديث**: النسخة التطويرية الأولى ✅
