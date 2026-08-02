# Firebase Integration Guide 🔥

## الشروط الأساسية:

✅ **Firebase Project ID:** `heldoc-68abf`
✅ **Google API Key:** `AIzaSyCP8ArkxYPnwhMu1n-td0LDo-bMs7pd5kQ`
✅ **App ID:** `1:736610467870:android:4d0e388c5e463639b02e0f`
✅ **google-services.json:** موجود في `android/app/`

---

## 🚀 البدء بـ Firebase

### 1️⃣ الخطوات الأولى:

```bash
# التأكد من الحزم المثبتة
flutter pub get

# بناء التطبيق
flutter run -d DEVICE_ID
```

### 2️⃣ التحقق من Firebase Connection:

عند فتح التطبيق ستشوف في Console:

```
✅ Firebase تم تهيئونه بنجاح
```

---

## 📊 Firestore Database Structure

كل مستخدم في Collection `users`:

```json
{
  "id": "document_id",
  "phone": "201001234567",
  "name": "محمد علي",
  "role": "patient", // أو "doctor"
  "password": "123456", // يجب تشفيره بـ bcrypt
  "birthDate": "1990-01-15T00:00:00.000Z",
  "gender": "male", // أو "female"
  "createdAt": "2024-04-06T10:30:00.000Z",
  "updatedAt": "2024-04-06T10:30:00.000Z"
}
```

---

## 🔐 أمان Firebase Rules

يجب إضافة هذه القواعد في Firestore Console:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // المستخدمون يرون فقط بياناتهم
    match /users/{userId} {
      allow read: if request.auth.uid == userId;
      allow write: if request.auth.uid == userId;
    }

    // المواعيد محمية
    match /appointments/{appointmentId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
  }
}
```

---

## 🔄 العمليات الحالية:

### ✅ التسجيل الجديد (Sign Up)

- اسم + رقم جوال + كلمة سر + تاريخ ميلاد + جنس
- يُحفظ في Firestore تحت Collection `users`

### ✅ تسجيل الدخول (Login)

- رقم جوال + كلمة سر
- يبحث في Firestore ويتحقق

### ✅ OTP للتحقق

- حالياً محاكاة محلية
- **الإنتاج:** Firebase Authentication مع SMS

---

## ⚙️ التكوين التالي (قريباً):

1. **إضافة معلومات الأطباء**

   ```
   Collection: doctors
   Fields: phone, name, specialization, rating, etc.
   ```

2. **إضافة حجوزات المواعيد**

   ```
   Collection: appointments
   Fields: patientId, doctorId, date, time, status
   ```

3. **إرسال SMS عبر Firebase**
   ```
   - استخدام Cloud Functions
   - التكامل مع Twilio أو Firebase SMS
   ```

---

## 🛠️ أوامر مفيدة:

```bash
# تشغيل التطبيق
flutter run -d AQKSLVH043N71400944

# بناء Release
flutter build apk --release

# التحقق من الأخطاء
flutter analyze

# تشغيل الاختبارات
flutter test
```

---

## 📱 الأجهزة المدعومة الآن:

- ✅ Android (النسخة الحالية)
- ⏳ iOS (بنفس الكود، بحاجة Mac)
- ⏳ Web (اختياري)

---

**آخر تحديث:** 6 April 2026
**Firebase Status:** 🟢 Ready
**Local Auth Fallback:** 🟢 Active
