#!/usr/bin/env node
/**
 * تعبئة `phone_index` للحسابات القديمة — تشغيل يدوي، مرة واحدة.
 *
 * ## المشكلة التي يحلّها
 *
 * تسجيل الدخول يترجم رقم الجوال إلى بريد عبر `phone_index` حصراً. الحسابات
 * التي أُنشئت قبل وجود هذا الفهرس ليس لها مدخل فيه، وكان في التطبيق مسار
 * احتياطي يستعلم على `users` بالرقم — لكنه يجري *قبل* المصادقة، وقاعدة
 * `users` تشترط مستخدماً مسجَّلاً، فكان مرفوضاً دائماً. النتيجة أن صاحب
 * الحساب القديم يرى «رقم الجوال أو كلمة المرور غير صحيحة» ولا يستطيع الدخول
 * أبداً. أُزيل المسار من التطبيق، وهذا السكربت هو بديله الصحيح.
 *
 * ## قبل التشغيل
 *
 *   1. خُذ نسخة احتياطية من Firestore.
 *   2. جرّبه أولاً بـ --dry-run وراجع الناتج.
 *
 * ## التشغيل
 *
 *   npm i firebase-admin
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 *   node scripts/backfill_phone_index.js --dry-run
 *   node scripts/backfill_phone_index.js
 *
 * السكربت **لا يكتب فوق** أي مدخل قائم: لو كان الرقم مسجَّلاً لحساب آخر
 * يتخطّاه ويُبلغ عنه، فلا يسرق رقم أحد.
 */
"use strict";

const admin = require("firebase-admin");

const DRY_RUN = process.argv.includes("--dry-run");

/** نفس التطبيع المستخدم في التطبيق (firebase_auth_service.dart). */
function normalizePhone(raw) {
  let cleaned = String(raw || "").replace(/[^\d]/g, "");
  if (cleaned.startsWith("00")) cleaned = cleaned.slice(2);
  if (cleaned.startsWith("0")) cleaned = cleaned.slice(1);
  if (!cleaned.startsWith("20")) cleaned = `20${cleaned}`;
  return cleaned;
}

async function main() {
  admin.initializeApp();
  const db = admin.firestore();

  const users = await db.collection("users").get();
  const report = { total: users.size, written: 0, present: 0, conflict: 0, skipped: 0 };
  const conflicts = [];

  for (const doc of users.docs) {
    const data = doc.data();
    const phone = data.phone ? normalizePhone(data.phone) : "";
    const email = data.email;

    if (!phone || !email) {
      report.skipped += 1;
      continue;
    }

    const ref = db.collection("phone_index").doc(phone);
    const existing = await ref.get();

    if (existing.exists) {
      if (existing.data().uid === doc.id) {
        report.present += 1;
      } else {
        report.conflict += 1;
        conflicts.push({ phone, indexUid: existing.data().uid, userUid: doc.id });
      }
      continue;
    }

    if (!DRY_RUN) {
      await ref.set({
        uid: doc.id,
        email,
        backfilledAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    report.written += 1;
  }

  console.log(DRY_RUN ? "\n--- DRY RUN, nothing written ---" : "\n--- backfill complete ---");
  console.table(report);

  if (conflicts.length) {
    console.log("\nرقم مسجَّل لحساب مختلف — لم يُلمَس، يحتاج مراجعة يدوية:");
    console.table(conflicts);
  }

  // الفارق بين `total` ومجموع الباقي هو عدد الحسابات التي كانت محبوسة.
  console.log(
    `\n${report.written} حساباً كان يتعذّر عليه تسجيل الدخول${DRY_RUN ? " (لم يُصلَح بعد)" : " وصار يستطيع"}.`
  );
}

main().catch((err) => {
  console.error("FAILED:", err);
  process.exit(1);
});
