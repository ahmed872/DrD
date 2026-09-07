#!/usr/bin/env node
/**
 * إزالة `patientIds` من مستندات `slots` القديمة — تشغيل يدوي، مرة واحدة.
 *
 * ## المشكلة التي يحلّها
 *
 * مجموعة `slots` مقروءة لكل مستخدم مسجَّل — وهذا ضروري، لأنها مصدر عرض
 * الأوقات المتاحة. لكنها كانت تحمل أيضاً `patientIds`: مصفوفة بمعرّفات
 * المرضى الحاجزين. أي أن أي مستخدم كان يستطيع معرفة **مَن حجز عند أي طبيب
 * وفي أي وقت**.
 *
 * السبب الجذري أن قواعد Firestore لا تُرشّح الحقول عند القراءة: مستند يخلط
 * عدّاداً عاماً بهويّات خاصة يكشف الخاص لكل من يحتاج العام.
 *
 * التطبيق لم يعد يكتب الحقل، والقاعدة تمنعه في الخانات الجديدة. هذا السكربت
 * ينظّف ما هو مكتوب بالفعل.
 *
 * ## قبل التشغيل
 *
 *   1. خُذ نسخة احتياطية من Firestore.
 *   2. جرّبه أولاً بـ --dry-run.
 *   3. **شغّله بعد نشر التطبيق المحدَّث**، وإلا أعادت النسخة القديمة كتابة
 *      الحقل عند أول حجز.
 *
 * ## التشغيل
 *
 *   npm i firebase-admin
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 *   node scripts/strip_slot_patient_ids.js --dry-run
 *   node scripts/strip_slot_patient_ids.js
 *
 * `bookedCount` لا يُلمس: هو مصدر الحقيقة للإشغال، وتغييره يفسد الحجوزات.
 */
"use strict";

const admin = require("firebase-admin");

const DRY_RUN = process.argv.includes("--dry-run");
const BATCH_SIZE = 400; // حد Firestore هو 500 عملية للدفعة الواحدة.

async function main() {
  admin.initializeApp();
  const db = admin.firestore();

  const slots = await db.collection("slots").get();
  let affected = 0;
  let mismatched = 0;
  let batch = db.batch();
  let pending = 0;

  for (const doc of slots.docs) {
    const data = doc.data();
    if (!Object.prototype.hasOwnProperty.call(data, "patientIds")) continue;

    // تحذير تشخيصي: لو خالف طول المصفوفة العدّاد فالبيانات كانت مختلّة أصلاً.
    const ids = Array.isArray(data.patientIds) ? data.patientIds : [];
    if (typeof data.bookedCount === "number" && ids.length !== data.bookedCount) {
      mismatched += 1;
      console.warn(
        `  ⚠ ${doc.id}: bookedCount=${data.bookedCount} لكن patientIds=${ids.length}`
      );
    }

    affected += 1;
    if (!DRY_RUN) {
      batch.update(doc.ref, {
        patientIds: admin.firestore.FieldValue.delete(),
      });
      pending += 1;
      if (pending >= BATCH_SIZE) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }
  }

  if (!DRY_RUN && pending > 0) await batch.commit();

  console.log(DRY_RUN ? "\n--- DRY RUN, nothing written ---" : "\n--- cleanup complete ---");
  console.table({
    slotsScanned: slots.size,
    carriedPatientIds: affected,
    countMismatches: mismatched,
  });
}

main().catch((err) => {
  console.error("FAILED:", err);
  process.exit(1);
});
