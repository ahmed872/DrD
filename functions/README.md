# Cloud Functions — DrD

## ما يعمل هنا

| الدالة | النوع | ما تفعله |
|---|---|---|
| `bookAppointment` | Callable | حجز موعد — المرحلة 1أ. راجع `booking.js`. |
| `cancelAppointment` | Callable | إلغاء موعد المريض نفسه — المرحلة 1ب. راجع `lifecycle.js`. |
| `rescheduleAppointment` | Callable | نقل موعد إلى خانة جديدة عند نفس الطبيب — المرحلة 1ب. راجع `lifecycle.js`. |
| `getAvailability` | Callable | قراءة الخانات المتاحة عند طبيب ضمن مدى تاريخ — المرحلة 1ب. راجع `availability.js`. |
| `checkAppointments` | مجدولة كل 5 دقائق | تكتب إشعار تذكير قبل الموعد بساعة، وإشعار غياب بعده بـ10 دقائق |

الدوال تعمل بـ Admin SDK، أي أنها **تتجاوز `firestore.rules`**. لهذا تحديداً
مجموعة `notifications` مغلقة أمام العميل (`allow create: if false`): الإشعار
يُنشأ من الخادم وحده، وإلا أرسل أي مستخدم إشعاراً باسم العيادة.

---

## البنية: `availability.js` مصدر الحقيقة الوحيد للجدول

المرحلة 1ب أخرجت منطق الجدول (أيام العمل، فترات العمل، الاستراحات،
الاستثناءات، مدة/سعة الخانة، معرّفات الخانة والموعد) من `booking.js` إلى
`availability.js`. الثلاثة الآن يستدعونها بلا نسخة موازية:

```
availability.js   ← منطق الجدول الخالص + AppError + خطط الكتابة على الأقفال
   ↑        ↑          ↑
booking.js  lifecycle.js  (getAvailabilityCore داخل availability.js نفسها)
(bookAppointment)  (cancelAppointment, rescheduleAppointment)
```

**القاعدة الحرجة**: `bookAppointment` و`getAvailability` و
`rescheduleAppointment` الثلاثة يستدعون `assertSlotWithinSchedule` و
`generateSlotTimes` و`isWorkingDay` نفسها — فلا تعرض `getAvailability` خانة
يرفضها الحجز، ولا العكس. لكن معاملة `bookAppointment` (ونظيرتها في
`rescheduleAppointment`) تبقى الحكم الأخير دائماً: استجابة `getAvailability`
قد تصبح قديمة بجزء من الثانية قبل لحظة الحجز الفعلية.

حقول الجدول الجديدة (`workingPeriods`, `breaks`, `closedDates`, `vacations`,
`dateOverrides`, `workingDaysByWeekday`, `timezone`) **كلها اختيارية** —
طبيب بلا أيٍّ منها يسلك تماماً كما قبل هذه المرحلة، بلا أي هجرة بيانات.
التفاصيل والأمثلة في التوثيق أعلى كل دالة داخل `availability.js`.

---

## ⚠️ ما حُذف في «المرحلة صفر» ولماذا

الدالة `sendOTPEmail` كانت تراقب مجموعة `otps` وترسل بريداً إلى العنوان
المأخوذ من **معرّف المستند**، بينما القاعدة على تلك المجموعة كانت:

```javascript
match /otps/{otpId} {
  allow create: if true;   // بلا مصادقة إطلاقاً
}
```

أي أن أي شخص على الإنترنت يكتب مستنداً معرّفه بريد أي ضحية، فيصله بريد من
عنوان المشروع بمحتوى يتحكم فيه جزئياً. هذا **مرحّل بريد مفتوح**: تصيّد باسم
العيادة، وحرق سمعة نطاق الإرسال، وفاتورة إرسال على حساب المشروع.

المسار لم يكن مستخدماً في التطبيق أصلاً — الدخول ببريد وكلمة مرور عبر
Firebase Auth، وإعادة تعيين كلمة المرور برسائل Firebase نفسها.

حُذفت الدالة، وحُذفت مجموعة `otps` من القواعد فصارت مغلقة بالقاعدة
الافتراضية، وحُذفت تبعية `nodemailer` وأسرار البريد.

---

## التشغيل والنشر

```bash
cd functions
npm install

# محلياً
firebase emulators:start --only functions

# نشر
firebase deploy --only functions
```

لا تحتاج الدوال الحالية أي متغيرات بيئة — راجع `.env.example`.

---

## معروف وغير مُصلَح بعد

`checkAppointments` تقرأ `data.date` و`data.time`، بينما المواعيد تُكتب اليوم
بالحقلين `appointmentDate` و`startTime`، وتستعلم عن `status == "Scheduled"`
بينما الحالة المكتوبة الآن `Booked`. النتيجة: **التذكيرات لا تُرسَل عملياً**.

هذا خلل وظيفي لا ثغرة أمنية، ولم يُلمس في المرحلة صفر عمداً حتى لا تتوسّع
الدفعة. إصلاحه مع بقية مسار الإشعارات في مرحلة لاحقة.
