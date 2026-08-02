# 📧 إرسال OTP عبر البريد الإلكتروني

## 🚀 خطوات التثبيت والتفعيل

### 1️⃣ تثبيت Firebase CLI (مرة واحدة فقط)

```bash
npm install -g firebase-tools
firebase login
```

### 2️⃣ إعداد Gmail App Password

Firebase Functions تحتاج بريد Gmail مع كلمة مرور خاصة:

1. اذهب إلى: https://myaccount.google.com/security
2. اضغط **"تطبيقات كلمات المرور"** (اذا لم تظهر، فعّل المصادقة الثنائية أولاً)
3. اختر "البريد" و "Windows"
4. ستحصل على كلمة مرور 16 حرف
5. احفظها (ستحتاجها الآن!)

### 3️⃣ تعيين متغيرات البيئة

```bash
cd functions
firebase functions:config:set gmail.user="your-email@gmail.com" gmail.password="your-app-password"
```

مثال:

```bash
cd functions
firebase functions:config:set gmail.user="doctor.heldoc@gmail.com" gmail.password="abcd efgh ijkl mnop"
```

### 4️⃣ نشر الـ Cloud Function

```bash
firebase deploy --only functions
```

ستظهر رسالة:

```
✔ Deploy complete!

Function URL: https://region-project.cloudfunctions.net/sendOTPEmail
```

### ✅ اختبار النظام

1. افتح التطبيق
2. اضغط "إنشاء حساب جديد"
3. أدخل بريدك الإلكتروني
4. اضغط "إرسال الكود"
5. تحقق من صندوق الوارد - الكود سيصل! 📬

---

## 🔐 ملاحظات أمان مهمة

❌ **لا تضع كلمة المرور في الكود مباشرة** - استخدم Firebase Config

⚠️ **كلمة مرور التطبيق آمنة أكثر من كلمة المرور الأصلية** - لا تشاركها

🛡️ **Firebase Functions تتحكم في الوصول** - كود لا يمكن تشغيله إلا من Firestore

---

## 📱 محتوى الإيميل المرسل

- ✉️ بريد احترافي بتصميم استجابي
- 🔐 رمز OTP بحجم كبير وواضح
- ⏱️ مؤشر انتهاء الصلاحية (10 دقائق)
- 🛡️ تحذير الأمان (لا تشارك الرمز)
- 📍 عربي 100%

---

## 🐛 استكشاف الأخطاء

### الإيميل لا يصل

1. تحقق من Gmail Security: https://myaccount.google.com/security
2. فعّل "تطبيقات أقل أماناً" إذا لزم الأمر
3. تحقق من سجل Firebase Functions:
   ```bash
   firebase functions:log
   ```

### خطأ Authentication

```bash
firebase functions:config:unset gmail
firebase functions:config:set gmail.user="YOUR_EMAIL@gmail.com" gmail.password="YOUR_APP_PASSWORD"
firebase deploy --only functions
```

### شغّل الـ Emulator محلياً

```bash
cd functions
npm install
firebase emulators:start --only functions
```

---

## 📊 مراقبة الإيميلات المرسلة

في Firebase Console:

1. اذهب إلى **Firestore Database**
2. شوف collection **"otps"**
3. كل بريد له سجل: `{ emailSent: true, sentAt: timestamp }`

---

## 🎯 الخطوة التالية (Production)

عندما تكون جاهز للـ production:

- استخدم خدمة بريد احترافية (SendGrid, Mailgun)
- أو استخدم Firebase Admin SDK في backend خاص
- أو استخدم AWS SES
