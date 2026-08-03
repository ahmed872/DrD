# حالة إعادة التصميم — سجل التقدّم

> يُحدَّث بعد كل خطوة. لو الشغل اتقطع، ابدأ من قسم «الخطوة الجاية».

آخر تحديث: 3 أغسطس 2026 · البرانش: `claude/doctor-booking-pwa-80y6cq`

---

## ✅ خلص واتأكّدت منه

### الأساس
- [x] **نظام تصميم كامل** — `lib/core/theme/app_theme.dart`
      ألوان (`AppColors`)، مسافات (`Gap`)، حواف (`Radii`)، سلّم خطوط،
      وضع ليلي مبني على tokens مش عكس ألوان.
- [x] **خط IBM Plex Sans Arabic** — أربع أوزان في `assets/fonts/`،
      مسجّل في `pubspec.yaml`. رخصة SIL OFL (حرة تجارياً).
- [x] **مكوّنات مشتركة** — `lib/presentation/widgets/ui_kit.dart`:
      `AppCard` · `StatusPill` · `InitialAvatar` · `EmptyState` ·
      `DataRow2` · `TimeText` · `Eyebrow` · `ThinDivider`
- [x] **بطاقة الموعد + العدّاد** — `widgets/next_appointment_card.dart`
- [x] **شاشة معاينة** — `lib/design_preview.dart`
      `flutter run -d chrome -t lib/design_preview.dart`

### إصلاح حرج
- [x] **عامل الخدمة كان بيعرض النسخة القديمة بعد كل نشر**
      `main.dart.js` اسمه ثابت، وكان بيتجاب من الذاكرة أولاً. اتحوّل
      لـ network-first في `web/sw.js` + رفع `VERSION` لـ `v3`.
      **ده كان السبب إن المستخدم شاف التصميم القديم بعد النشر.**

### الشاشات
- [x] **الرئيسية** — أُعيد بناؤها: بتبدأ بالموعد الجاي والعدّاد
- [x] **تسجيل الدخول** — أُعيد بناؤها: شريحتين للتبديل، حقول متدرّجة
- [x] **الحجز** — شبكة المواعيد اتعادت (خانات بمقاس ثابت بدل FilterChip)،
      الشريط والزر بقوا من النسق
- [x] **١٧ شاشة** — كل الألوان المكتوبة بالإيد اتحوّلت للنسق
      (`0xFF0097A7` · `Colors.blue/green/red/...` → `AppColors.*`)
- [x] **٦ شاشات** — النصوص المخلوطة عربي/إنجليزي اتنضّفت

### الجودة
- [x] `flutter analyze` — **صفر أخطاء**
- [x] `flutter test` — **30/30**
- [x] البناء نجح

---

## 🔜 الخطوة الجاية (ابدأ من هنا)

### 1. النشر — مستنّي مفتاح خدمة
البناء جاهز في `build/web`. المفتاح بيتمسح بعد كل استخدام.
```bash
GOOGLE_APPLICATION_CREDENTIALS=<key.json> \
  firebase deploy --only hosting --project heldoc-68abf --non-interactive
```
اللينك: **https://drd-clinic.web.app**

### 2. شاشات لسه على التصميم القديم (بترتيب الأهمية)
| الشاشة | الملف | المشكلة |
|---|---|---|
| مواعيدي | `patient_my_appointments_screen.dart` | تبويبات وبطاقات قديمة، تكرار منطق الحالة |
| جدول الطبيب | `doctor_schedule_screen.dart` | 1100 سطر، فلاتر تواريخ قديمة الشكل |
| البحث عن طبيب | `patient_search_doctor_screen.dart` | بطاقات مش موحّدة |
| الإحصائيات | `doctor_analytics_screen.dart` | رسوم بألوان قديمة |
| قائمة المرضى | `doctor_patients_screen.dart` | — |
| الإعدادات (طبيب/مريض) | `*_settings_screen.dart` | فورمات طويلة بلا تجميع |

**الطريقة المتّبعة**: تعديلات جراحية على الأجزاء البصرية
(`AppBar`، البطاقات، الأزرار، الحالات الفارغة) بدل إعادة كتابة الملف كله —
أوفر وأقل خطراً على المنطق الشغال.

### 3. حاجات مؤجَّلة
- شاشة البداية (`splash_screen.dart`) لسه بالشكل القديم
- `doctor_dashboard.dart` — يبدو غير مستخدم، يتأكد ويتشال
- التذكيرات محتاجة خطة Blaze

---

## 📌 معلومات ثابتة

| | |
|---|---|
| مشروع Firebase | `heldoc-68abf` |
| موقع الاستضافة | `drd-clinic` → https://drd-clinic.web.app |
| القواعد | منشورة ومتحقَّق منها (32 اختبار) |
| الفهارس | الاتنين المطلوبين `READY` |
| أمر البناء | `flutter build web --release --no-web-resources-cdn` |

**بعد أي تعديل على `web/sw.js` أو الأصول**: ارفع `VERSION` في `sw.js`.
