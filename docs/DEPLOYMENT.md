# دليل النشر — DrD

كيف تنشر التطبيق على الويب (PWA) وعلى Google Play وApp Store.

---

## ⚠️ اقرأ هذا أولاً: الـ PWA وحده لا يكفي للمتاجر

هذه نقطة مهمة ووفّرت شرحها هنا لأنها تحدّد خطة العمل كلها:

| المنصّة | هل تقبل PWA؟ | الطريقة الصحيحة |
|---|---|---|
| **الويب / المتصفح** | ✅ نعم | نسخة PWA — تُثبَّت من المتصفح مباشرة |
| **Google Play** | ⚠️ بشكل غير مباشر | إمّا تغليف PWA بـ TWA، أو **الأفضل**: بناء APK/AAB أصلي من Flutter |
| **Apple App Store** | ❌ **لا** | Apple ترفض التطبيقات التي هي مجرد موقع مغلَّف (إرشادات المراجعة 4.2). **لا بد** من بناء iOS أصلي من Flutter |

**الخبر الجيد**: مشروعك Flutter، وهذا يعني أن نفس الكود يُنتج الثلاثة معاً.
لست مضطراً للاختيار — التحويل إلى PWA أضاف منصّة الويب، ولم يُلغِ نسختي
أندرويد وiOS. هذا هو المسار الموصى به:

- **الويب**: `flutter build web` → PWA قابلة للتثبيت
- **Google Play**: `flutter build appbundle` → AAB أصلي
- **App Store**: `flutter build ipa` → IPA أصلي

---

## 1. الويب (PWA)

### الخطوة 1 — إعداد Firebase للويب (إجباري، مرة واحدة)

مشروع Firebase الحالي يحتوي على تطبيق أندرويد فقط. بدون تطبيق ويب مسجَّل
لن يعمل تسجيل الدخول في المتصفح إطلاقاً (لغياب `authDomain`).

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=heldoc-68abf --platforms=web,android
```

سيكتب الأمر القيم في `lib/firebase_options.dart`. بدلاً من ذلك يمكنك
تمريرها وقت البناء دون تعديل الملف (أنظف لأنظمة CI):

```bash
flutter build web --release \
  --no-web-resources-cdn \
  --dart-define=FIREBASE_WEB_API_KEY=AIza... \
  --dart-define=FIREBASE_WEB_APP_ID=1:736610467870:web:...
```

> `apiKey` في Firebase ليس سرّاً — فهو يُرسَل للمتصفح بالضرورة. الحماية
> الحقيقية في `firestore.rules`.

### الخطوة 2 — إضافة النطاق للنطاقات المصرَّح بها

Firebase Console ← Authentication ← Settings ← Authorized domains ←
أضف نطاقك. بدون هذه الخطوة يفشل تسجيل الدخول برسالة `auth/unauthorized-domain`.

### الخطوة 3 — البناء

```bash
flutter build web --release --no-web-resources-cdn
```

**`--no-web-resources-cdn`**: يستضيف محرّك العرض (CanvasKit) على نطاقك بدل
تحميله من `gstatic.com`. بدونه لا يستطيع عامل الخدمة تخزينه (لأنه من نطاق
آخر)، فيفشل الإقلاع بلا اتصال ويبطؤ على الشبكات الضعيفة.

**ملاحظة عن عامل الخدمة**: كان هناك خيار `--service-worker-strategy`، لكنه
**حُذف من Flutter 3.44** — تمريره الآن يُنتج خطأ `Could not find an option`.
لم يعد مطلوباً أصلاً: ملف `web/flutter_bootstrap.js` في المستودع يستدعي
`_flutter.loader.load()` بلا وسائط، فلا يسجّل Flutter عامل خدمته المهمل، ويبقى
`web/sw.js` وحده المتحكّم. الفحص في CI يحرس هذا السلوك من الانحدار.

### الخطوة 4 — نشر القواعد ثم الموقع

```bash
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only hosting
```

> انشر القواعد **قبل** الموقع. الترتيب العكسي يترك قاعدة البيانات مفتوحة
> بينما التطبيق متاح للعامة.

### الخطوة 5 — التحقق

```bash
# فحص PWA بمقياس Lighthouse
npx lighthouse https://your-domain.com --view --preset=desktop
```

قائمة مراجعة يدوية:
- [ ] يظهر زر "تثبيت التطبيق" في Chrome
- [ ] بعد التثبيت يفتح بدون شريط عنوان المتصفح
- [ ] إيقاف الشبكة → تظهر صفحة "لا يوجد اتصال" بالعربية
- [ ] نشر إصدار جديد → يظهر شريط "يتوفّر إصدار جديد"
- [ ] تحديث الصفحة بعد تسجيل الدخول → تبقى الجلسة

### عند إصدار نسخة جديدة

ارفع رقم `VERSION` في `web/sw.js` (`v1` → `v2`). بدون ذلك يبقى المستخدمون
على الملفات المخزَّنة القديمة.

---

## 2. Google Play

### الخيار (أ) — تطبيق Flutter أصلي (موصى به)

أفضل أداءً، ويدعم الإشعارات والكاميرا والميزات الأصلية لاحقاً.

**قبل أول رفع — إنشاء مفتاح التوقيع:**

```bash
keytool -genkey -v -keystore ~/drd-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

أنشئ `android/key.properties` (وهو مُستثنى من Git بالفعل):

```properties
storePassword=<كلمة السر>
keyPassword=<كلمة السر>
keyAlias=upload
storeFile=/absolute/path/to/drd-upload-key.jks
```

> ⚠️ احتفظ بنسخة احتياطية من ملف `.jks`. فقدانه يعني عدم القدرة على تحديث
> التطبيق على Play إلى الأبد.

**البناء:**

```bash
flutter build appbundle --release
# الناتج: build/app/outputs/bundle/release/app-release.aab
```

**بيانات التطبيق الحالية:**
- `applicationId`: `heldoc.com` (مطابق لـ `google-services.json` — لا تغيّره،
  فتغييره يفصل التطبيق عن مشروع Firebase وعن أي تثبيتات قائمة)
- `minSdk`: 23 (أندرويد 6.0 فأعلى)

### الخيار (ب) — تغليف الـ PWA بـ TWA

مناسب لو أردت نشر نسخة الويب نفسها بأقل جهد.

```bash
npm i -g @bubblewrap/cli
bubblewrap init --manifest=https://your-domain.com/manifest.json
bubblewrap build
```

يتطلّب إثبات ملكية النطاق عبر `/.well-known/assetlinks.json`، وإلا ظهر
شريط عنوان المتصفح داخل التطبيق ورُفض غالباً.

---

## 3. Apple App Store

يحتاج جهاز macOS مع Xcode.

### الخطوة 1 — تسجيل تطبيق iOS في Firebase

المشروع لا يحتوي على `ios/Runner/GoogleService-Info.plist` بعد:

```bash
flutterfire configure --project=heldoc-68abf --platforms=ios
```

استخدم `com.heldoc.drd` كـ Bundle ID (وهو الافتراضي في
`lib/firebase_options.dart`)، أو غيّره في الملفين معاً.

### الخطوة 2 — الضبط في Xcode

```bash
open ios/Runner.xcworkspace
```

- Bundle Identifier مطابق لما سجّلته
- Signing & Capabilities ← اختر فريق التطوير
- Display Name: `DrD`

### الخطوة 3 — البناء والرفع

```bash
flutter build ipa --release
```

ثم ارفع عبر Xcode ← Organizer، أو:

```bash
xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios \
  -u <apple-id> -p <app-specific-password>
```

### ما تحتاجه المراجعة

- سياسة خصوصية منشورة على رابط عام — **إجبارية** لأن التطبيق يجمع بيانات
  صحية
- في App Privacy: صرّح بجمع الاسم، رقم الهاتف، البريد، وبيانات صحية
- حساب تجريبي (طبيب ومريض) للمراجعين
- لقطات شاشة بمقاسات 6.7" و6.5"

---

## 4. النشر الآلي (CI)

`.github/workflows/ci.yml` يُشغّل التحليل والاختبارات وبناء الويب على كل دفعة.
لتفعيل النشر التلقائي على Firebase Hosting أضف الأسرار التالية في
GitHub ← Settings ← Secrets:

| السر | من أين تحصل عليه |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | Firebase Console ← Project Settings ← Service accounts |
| `FIREBASE_WEB_API_KEY` | إعدادات تطبيق الويب |
| `FIREBASE_WEB_APP_ID` | إعدادات تطبيق الويب |

---

## ملخّص الأوامر

```bash
# الويب
flutter build web --release --no-web-resources-cdn
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only hosting

# أندرويد
flutter build appbundle --release

# iOS
flutter build ipa --release

# الجودة قبل أي نشر
flutter analyze && flutter test
```
