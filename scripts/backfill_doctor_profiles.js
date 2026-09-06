#!/usr/bin/env node
/**
 * تعبئة `doctor_profiles` للأطباء القائمين — تشغيل يدوي، مرة واحدة.
 *
 * ## لماذا هو إلزامي لا اختياري
 *
 * أُغلقت قراءة `users` على صاحبها، وانتقل دليل الأطباء إلى `doctor_profiles`:
 * إسقاط عام لا يحمل الهاتف ولا البريد ولا تاريخ الميلاد. يملأه المحفّز
 * `syncDoctorPublicProfile` عند **كل كتابة** في `users`.
 *
 * والمحفّز لا يعمل بأثر رجعي. أي أن الأطباء القائمين — الذين لم يُعدَّل
 * مستندهم منذ نشر الدالة — لا ملفات لهم، و**دليل الأطباء يظهر فارغاً**.
 *
 * لذلك ترتيب النشر ليس تفصيلاً:
 *
 *     1. نشر الدوال          (firebase deploy --only functions)
 *     2. تشغيل هذا السكربت   ← لا تتخطَّ هذه الخطوة
 *     3. نشر القواعد         (firebase deploy --only firestore:rules)
 *
 * القواعد آخراً عمداً: حتى تلك اللحظة يظل الدليل القديم يقرأ `users` ويعمل،
 * فلا نافذة يكون فيها الدليل فارغاً أمام المستخدمين.
 *
 * ## التشغيل
 *
 *     npm i firebase-admin
 *     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 *     node scripts/backfill_doctor_profiles.js            # فحص فقط
 *     node scripts/backfill_doctor_profiles.js --apply    # تنفيذ
 *
 * الوضع الافتراضي **فحص بلا كتابة**. لم يُشغَّل هذا السكربت على أي بيئة.
 */

const admin = require("firebase-admin");

const APPLY = process.argv.includes("--apply");

admin.initializeApp();
const db = admin.firestore();

/**
 * نسخة طبق الأصل من `PUBLIC_DOCTOR_FIELDS` في functions/index.js.
 *
 * التكرار مقصود: السكربت يعمل بـ Admin SDK خارج بيئة الدوال، واستيراد
 * `functions/index.js` هنا يُهيّئ `firebase-functions` ويسجّل المحفّزات.
 * أي حقل يُضاف هناك يجب أن يُضاف هنا — وإلا اختلف ما يعبّئه السكربت عما
 * يبقيه المحفّز محدَّثاً.
 */
const PUBLIC_DOCTOR_FIELDS = [
  "name", "nameEn",
  "clinicNameAr", "clinicNameEn", "clinicLocation",
  "specialization", "specializationEn",
  "bio", "bioEn",
  "price", "sessionDuration", "maxPatientsPerSlot", "bookingSystemType",
  "workingHours", "workingDays",
  "rating", "reviews",
];

async function main() {
  const doctors = await db.collection("users")
    .where("role", "==", "doctor")
    .get();

  let created = 0;
  let refreshed = 0;
  let skippedDeleted = 0;

  console.log("");
  console.log(APPLY ? "تعبئة الملفات العامة" : "معاينة (بلا كتابة)");
  console.log("═".repeat(60));
  console.log(`أطباء بدور doctor: ${doctors.size}`);
  console.log("");

  for (const doc of doctors.docs) {
    const user = doc.data();

    if (user.deleted === true) {
      // حساب محذوف لا يُنشر — نفس شرط المحفّز.
      console.log(`  · ${doc.id}: حساب محذوف — يُتخطّى`);
      skippedDeleted += 1;
      continue;
    }

    const existing = await db.collection("doctor_profiles").doc(doc.id).get();
    const profile = {
      doctorId: doc.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    for (const field of PUBLIC_DOCTOR_FIELDS) {
      if (user[field] !== undefined) profile[field] = user[field];
    }

    if (existing.exists) {
      refreshed += 1;
      console.log(`  ⟳ ${doc.id}: ${user.name || "(بلا اسم)"} — تحديث`);
    } else {
      created += 1;
      console.log(`  + ${doc.id}: ${user.name || "(بلا اسم)"} — إنشاء`);
    }

    if (APPLY) {
      await db.collection("doctor_profiles").doc(doc.id).set(profile);
    }
  }

  console.log("");
  console.log("─".repeat(60));
  console.log(`إنشاء: ${created} · تحديث: ${refreshed} · متخطَّى: ${skippedDeleted}`);

  // ملفات عامة بلا مستند طبيب مقابل: بقايا من خفض دور أو حذف حساب لم
  // يلتقطه المحفّز. تُعرض ولا تُحذف تلقائياً — الحذف قرار.
  const profiles = await db.collection("doctor_profiles").get();
  const doctorIds = new Set(doctors.docs.map((d) => d.id));
  const orphans = profiles.docs.filter((p) => !doctorIds.has(p.id));
  if (orphans.length) {
    console.log("");
    console.log(`⚠ ${orphans.length} ملف عام بلا طبيب مقابل:`);
    for (const o of orphans) console.log(`    ${o.id}`);
    console.log("  راجعها يدوياً — قد تكون حسابات خُفضت أو حُذفت.");
  }

  console.log("");
  if (!APPLY) console.log("معاينة فقط. أضف --apply للتنفيذ.");
}

main().then(
  () => process.exit(0),
  (e) => {
    console.error(e);
    process.exit(1);
  }
);
