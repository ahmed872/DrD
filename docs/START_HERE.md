# ابدأ من هنا — خطوات النشر

كل اللي تحتاجه عشان التطبيق يبقى شغال على لينك. **٤ خطوات، ١٥ دقيقة تقريباً.**

> **لو عندك دقيقة واحدة بس**: أهم حاجة هي الخطوة 1 — قاعدة بياناتك مكشوفة
> للإنترنت دلوقتي.

---

## الخطوة 1 — اسحب الكود الجديد

مهم جداً: **القواعد الجديدة والكود الجديد لازم ينزلوا مع بعض.** لو نزّلت
القواعد على الكود القديم، الحجز وتسجيل الدخول هيقفوا.

```powershell
cd E:\work\damro\medical_appointment_app

git fetch origin
git checkout claude/doctor-booking-pwa-80y6cq
flutter pub get
```

> لو رفض بسبب تعديلات محلية عندك: `git stash` الأول.

---

## الخطوة 2 — سجّل تطبيق ويب في Firebase

**من غير الخطوة دي التطبيق مش هيشتغل على الويب خالص** — إعدادات أندرويد
مافيهاش `authDomain`، وهو اللي Firebase Auth بيعتمد عليه في المتصفح.

1. افتح https://console.firebase.google.com/project/heldoc-68abf/settings/general
2. تحت **Your apps** ← اضغط أيقونة الويب **`</>`**
3. اسم التطبيق: `DrD Web` ← **Register app**
4. هيطلعلك كود فيه `apiKey` و `appId` — **احتفظ بيهم**، هتحتاجهم في خطوة 4

كمان: **Authentication ← Settings ← Authorized domains** ← اتأكد إن
`heldoc-68abf.web.app` موجود.

> الـ `apiKey` ده **مش سر** — Firebase بيبعته للمتصفح بالضرورة. اللي بيحمي
> بياناتك هو القواعد بتاعة خطوة 3.

---

## الخطوة 3 — الأمان (الأهم)

### أ) املأ فهرس أرقام الجوال — قبل القواعد

من غير الخطوة دي **كل الحسابات القديمة مش هتعرف تسجّل دخول**.

السبب: الدخول بالرقم بيدوّر على البريد قبل المصادقة. الحسابات الجديدة عندها
`phone_index`، القديمة لأ.

```powershell
# Firebase Console ← Project settings ← Service accounts
# ← Generate new private key ← احفظه في مجلد المشروع باسم serviceAccount.json

npm --prefix functions install
node tool/backfill_phone_index.js serviceAccount.json
```

⚠️ **امسح `serviceAccount.json` بعد ما تخلص** — ده مفتاح كامل الصلاحيات.

### ب) انشر القواعد والفهارس

```powershell
firebase deploy --only firestore:rules,firestore:indexes
```

تأكّد بعدها: Firestore ← Rules — لازم **ماتشوفش** `allow read, write: if true`.

---

## الخطوة 4 — النشر

### الطريقة السريعة (من جهازك)

```powershell
flutter build web --release --no-web-resources-cdn `
  --dart-define=FIREBASE_WEB_API_KEY=<الـ apiKey من خطوة 2> `
  --dart-define=FIREBASE_WEB_APP_ID=<الـ appId من خطوة 2>

firebase deploy --only hosting
```

هيطلعلك اللينك: **`https://heldoc-68abf.web.app`**

### الطريقة الأوتوماتيكية (يُفضَّل)

بعد إعداد لمرة واحدة، كل `git push` ينشر لوحده وماتحتاجش تبني من جهازك تاني.

GitHub ← **Settings** ← **Secrets and variables** ← **Actions** ←
**New repository secret** — ضيف التلاتة دول:

| الاسم | من فين |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | محتوى `serviceAccount.json` **كامل** |
| `FIREBASE_WEB_API_KEY` | خطوة 2 |
| `FIREBASE_WEB_APP_ID` | خطوة 2 |

وبعدها أي دفعة تنشر تلقائياً (`.github/workflows/deploy.yml`).

---

## ✅ اختبر بعد النشر

- [ ] افتح اللينك من الموبايل وسجّل دخول
- [ ] **الأهم**: افتح من موبايلين واحجز نفس الميعاد في نفس الثانية —
      لازم **واحد بس** ينجح
- [ ] ثبّت التطبيق (هيظهر زر «تثبيت»، وعلى الآيفون شرح بالخطوات)
- [ ] اقفل الإنترنت وافتح التطبيق — لازم تظهر صفحة عربية مش خطأ متصفح

---

## حاجة مؤجَّلة: التذكيرات

تذكير الموعد قبلها بساعة محتاج **Cloud Functions**، ودي محتاجة خطة **Blaze**
(الدفع حسب الاستخدام). استخدامك تقريباً هيبقى مجاني، بس Firebase بيطلب تفعيل
بطاقة.

**التطبيق شغال تمام من غيرها** — التذكيرات بس هي اللي مش هتشتغل.

لما تفعّلها:
```powershell
npm --prefix functions install
firebase deploy --only functions
```

---

## لو حاجة وقعت

| المشكلة | الحل |
|---|---|
| `could not locate firebase.json` | لسه ماسحبتش البرانش — خطوة 1 |
| `auth/unauthorized-domain` | ضيف النطاق في Authentication ← Settings ← Authorized domains |
| «إعدادات Firebase للويب غير مضبوطة» | خطوة 2 ناقصة، أو الـ dart-define مش متمرّر في البناء |
| حساب قديم مش بيدخل | شغّل سكربت خطوة 3-أ |
| استعلام بيفشل بخطأ index | Firebase بيطبع رابط جاهز في console المتصفح — دوس عليه |

---

## توثيق أعمق

| الملف | فيه إيه |
|---|---|
| `FIREBASE_SETUP_STEPS.md` | خطوات الكونسول بتفصيل |
| `SECURITY.md` | نموذج الأمان وإيه اللي لسه ناقص |
| `DEPLOYMENT.md` | النشر + التكاليف + المتاجر |
