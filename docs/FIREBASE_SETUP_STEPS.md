# خطوات Firebase — نفّذها بالترتيب

مشروعك: **`heldoc-68abf`** · الرابط: https://console.firebase.google.com/project/heldoc-68abf

نفّذ من **1 إلى 5** بالترتيب. الخطوة 1 هي الأهم والأعجل.

---

## 1️⃣ انشر قواعد الأمان — دلوقتي حالاً 🚨

**ليه مستعجلة؟** المستودع مكانش فيه `firestore.rules` خالص. معناه إن قاعدة
بياناتك شغالة على اللي متظبط يدوي في الكونسول — وغالباً وضع الاختبار المفتوح
اللي بيسمح لأي حد على الإنترنت يقرا كل بيانات مرضاك.

### تحقّق الأول إنك فعلاً مكشوف

الكونسول ← **Firestore Database** ← تبويب **Rules**

لو شايف السطر ده:
```javascript
allow read, write: if true;
```
يبقى قاعدة بياناتك مفتوحة للعالم كله. كمّل الخطوات تحت فوراً.

### التنفيذ

```bash
# مرة واحدة على جهازك
npm install -g firebase-tools
firebase login

# جوّه مجلد المشروع
cd /path/to/DrD
firebase use heldoc-68abf

# انشر القواعد والفهارس
firebase deploy --only firestore:rules,firestore:indexes
```

### أكّد إنها اتنشرت

ارجع للكونسول ← Firestore ← Rules — المفروض تشوف القواعد العربية الجديدة
وتاريخ نشر النهارده.

> **الفهارس** ممكن تاخد من دقيقة لـ 10 دقايق تتبني. تابعها في
> Firestore ← Indexes. لو فيه استعلام بيفشل قبل ما تخلص، ده طبيعي ومؤقت.

---

## 2️⃣ ضيف تطبيق ويب (عشان الـ PWA تشتغل أصلاً)

**ليه؟** مشروعك فيه تطبيق أندرويد بس. إعدادات أندرويد مافيهاش `authDomain`،
وده اللي Firebase Auth بيعتمد عليه في المتصفح. من غيره **تسجيل الدخول على
الويب مش هيشتغل خالص**.

### الطريقة السهلة (موصى بيها)

```bash
dart pub global activate flutterfire_cli
cd /path/to/DrD
flutterfire configure --project=heldoc-68abf --platforms=web,android
```

هيسألك يعمل تطبيق ويب جديد — وافق. وهيكتب القيم لوحده في
`lib/firebase_options.dart`.

### الطريقة اليدوية

1. الكونسول ← ⚙️ **Project settings**
2. تحت **Your apps** ← اضغط أيقونة الويب **`</>`**
3. App nickname: `DrD Web` ← **Register app**
4. هيطلعلك بلوك كود فيه:
   ```js
   apiKey: "AIza...",
   appId: "1:736610467870:web:...",
   authDomain: "heldoc-68abf.firebaseapp.com",
   ```
5. انسخ `apiKey` و `appId` وحطهم في `lib/firebase_options.dart` جوّه `web`

> **مهمة**: الـ `apiKey` ده **مش سر**. Firebase بيبعته للمتصفح بالضرورة وأي
> حد يقدر يشوفه في أي موقع منشور. اللي بيحمي بياناتك هو `firestore.rules`
> بتاعة خطوة 1 — مش إخفاء المفتاح ده.

---

## 3️⃣ اسمح لنطاقك بتسجيل الدخول

**ليه؟** Firebase بيرفض المصادقة من أي نطاق مش مسجَّل، وبيدي خطأ
`auth/unauthorized-domain`.

الكونسول ← **Authentication** ← تبويب **Settings** ← **Authorized domains**
← **Add domain**

ضيف:
- `heldoc-68abf.web.app` (بتاع Firebase Hosting — بيتضاف لوحده غالباً)
- نطاقك الخاص لو عندك واحد، مثلاً `drd.com`

> `localhost` موجود افتراضياً، فالتطوير المحلي هيشتغل من غير ما تعمل حاجة.

---

## 4️⃣ اتأكد إن طريقة الدخول مفعّلة

الكونسول ← **Authentication** ← **Sign-in method**

لازم **Email/Password** تكون **Enabled**. (التطبيق بيسجّل الدخول بالرقم في
الواجهة، بس تحت السطح بيترجم الرقم لإيميل ويستخدم Email/Password.)

---

## 5️⃣ انشر الموقع

```bash
cd /path/to/DrD
flutter build web --release --no-web-resources-cdn
firebase deploy --only hosting
```

هيطلعلك رابط زي `https://heldoc-68abf.web.app` — افتحه من الموبايل وجرّب.

> **ترتيب مهم**: انشر القواعد (خطوة 1) **قبل** الموقع. العكس معناه إن
> التطبيق يبقى متاح للناس وقاعدة البيانات لسه مفتوحة.

---

## ✅ قائمة تحقّق سريعة

- [ ] Firestore ← Rules مافيهاش `if true`
- [ ] Firestore ← Indexes كلها **Enabled** (مش Building)
- [ ] Project settings ← Your apps فيها تطبيق ويب
- [ ] Authentication ← Settings ← Authorized domains فيها نطاقك
- [ ] Authentication ← Sign-in method ← Email/Password مفعّلة
- [ ] فتحت الرابط وسجّلت دخول بنجاح
- [ ] عملت حجز من موبايلين في نفس الوقت — واحد بس اللي نجح ✅

---

## 🔜 حاجات مؤجَّلة (مش مستعجلة دلوقتي)

| الحاجة | ليه | إمتى |
|---|---|---|
| **App Check** | يمنع أي حد يستخدم قاعدة بياناتك من غير تطبيقك | قبل الإطلاق الواسع |
| **تفعيل الإيميل** | دلوقتي معطّل في الكود — يعني حد يقدر يسجّل بإيميل شخص تاني | قبل الإطلاق العام |
| **حذف الحساب** | **إلزامي** لمتجر آبل | قبل رفع iOS |
| **سياسة خصوصية** | **إلزامية** للمتجرين لأنك بتجمع بيانات صحية | قبل رفع أي متجر |
| **Blaze plan** | Cloud Functions (تذكير المواعيد) محتاجة خطة مدفوعة | لما تفعّل التذكيرات |

> التفاصيل الكاملة في [`SECURITY.md`](SECURITY.md).
