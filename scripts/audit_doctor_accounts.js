#!/usr/bin/env node
/**
 * جرد حسابات الأطباء — تشغيل يدوي، **قراءة فقط** افتراضياً.
 *
 * ## المشكلة التي يحلّها
 *
 * أغلقت المرحلة الثانية باب ترقية الذات: `users` لا تقبل `role != 'patient'`
 * عند الإنشاء، ولا تقبل تعديل `role` بعده، والترقية تمرّ عبر
 * `doctor_applications` ومراجعة مشرف ويكتبها الخادم وحده.
 *
 * لكن تلك القاعدة تخصّ **الإنشاء والتعديل** — لا الماضي. وشاشة التسجيل
 * القديمة كانت تعرض زرّي «مريض / طبيب»، وقاعدة الأمان القديمة كانت تقبل
 * `role in ['doctor', 'patient']` من العميل. فكل حساب ضغط «طبيب» قبل الإصلاح
 * ما زال طبيباً: يظهر في الدليل، ويُحجز عنده، ويكتب سجلات سريرية على مرضى
 * حقيقيين — بلا أي مراجعة.
 *
 * لا يستطيع أي كود أن يعرف من هؤلاء دون النظر في بيانات الإنتاج. هذا السكربت
 * ينظر ويصنّف ولا يقرّر.
 *
 * ## لماذا لا يخفض الرتبة تلقائياً
 *
 * لأن «طبيب بلا طلب معتمَد» ليس بالضرورة محتالاً: قد يكون طبيباً حقيقياً
 * زُوِّد يدوياً من وحدة التحكم قبل وجود نظام الطلبات. خفضه تلقائياً يقطع
 * عيادة عاملة عن مرضاها. القرار لصاحب المنتج، حساباً حساباً.
 *
 * ## التشغيل
 *
 *     npm i firebase-admin
 *     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 *
 *     node scripts/audit_doctor_accounts.js                 # تقرير على الشاشة
 *     node scripts/audit_doctor_accounts.js --json out.json # تقرير للملف
 *
 * وللخفض — بعد قرارك، وبمعرّفات صريحة لا بالجملة:
 *
 *     node scripts/audit_doctor_accounts.js \
 *       --demote uid1,uid2 --apply
 *
 * بدون `--apply` يعرض `--demote` ما كان سيفعله ولا يكتب شيئاً.
 *
 * ⚠ لم يُشغَّل هذا السكربت على أي بيئة. خُذ نسخة احتياطية أولاً.
 */

const admin = require("firebase-admin");

const args = process.argv.slice(2);
const APPLY = args.includes("--apply");
const jsonAt = args.indexOf("--json");
const JSON_PATH = jsonAt >= 0 ? args[jsonAt + 1] : null;
const demoteAt = args.indexOf("--demote");
const DEMOTE = demoteAt >= 0
  ? String(args[demoteAt + 1] || "").split(",").map((s) => s.trim()).filter(Boolean)
  : [];

admin.initializeApp();
const db = admin.firestore();

/** تصنيفات الحساب. كل حساب يقع في واحد بالضبط. */
const APPROVED = "approved_doctor";
const LEGACY = "legacy_doctor";
const PATIENT = "patient";
const INCONSISTENT = "inconsistent";

function classify(user, application) {
  const role = user.role;
  const status = application ? application.status : null;

  if (user.deleted === true) {
    // حساب محذوف يجب ألا يحمل دور طبيب فعّالاً.
    return role === "doctor" ? INCONSISTENT : PATIENT;
  }

  if (role === "doctor") {
    return status === "approved" ? APPROVED : LEGACY;
  }

  if (role === "patient") {
    // طلب معتمَد ودور مريض = الخادم فشل في إتمام الترقية، أو خُفض يدوياً
    // بعدها. الحالتان تحتاجان نظرة بشرية.
    return status === "approved" ? INCONSISTENT : PATIENT;
  }

  // دور غائب أو قيمة لا يعرفها التطبيق.
  return INCONSISTENT;
}

async function main() {
  const [users, applications] = await Promise.all([
    db.collection("users").get(),
    db.collection("doctor_applications").get(),
  ]);

  const appById = new Map();
  applications.forEach((doc) => appById.set(doc.id, doc.data()));

  const buckets = {
    [APPROVED]: [], [LEGACY]: [], [PATIENT]: [], [INCONSISTENT]: [],
  };

  users.forEach((doc) => {
    const user = doc.data();
    const application = appById.get(doc.id) || null;
    const bucket = classify(user, application);
    buckets[bucket].push({
      uid: doc.id,
      name: user.name || "",
      role: user.role || null,
      applicationStatus: application ? application.status : null,
      createdAt: user.createdAt ? String(user.createdAt.toDate()) : null,
      deleted: user.deleted === true,
    });
  });

  console.log("");
  console.log("جرد حسابات الأطباء");
  console.log("═".repeat(60));
  console.log(`إجمالي المستخدمين: ${users.size}`);
  console.log(`طلبات الانضمام:    ${applications.size}`);
  console.log("");
  console.log(`✓ طبيب معتمَد        ${buckets[APPROVED].length}`);
  console.log(`⚠ طبيب قديم         ${buckets[LEGACY].length}  ← يحتاج قرارك`);
  console.log(`· مريض              ${buckets[PATIENT].length}`);
  console.log(`✗ حالة غير متسقة    ${buckets[INCONSISTENT].length}`);
  console.log("");

  if (buckets[LEGACY].length) {
    console.log("أطباء بلا طلب معتمَد — يظهرون في الدليل ويكتبون سجلات سريرية:");
    console.log("─".repeat(60));
    for (const row of buckets[LEGACY]) {
      console.log(
        `  ${row.uid}  ${row.name || "(بلا اسم)"}` +
        `  [طلب: ${row.applicationStatus || "لا يوجد"}]` +
        `  [أُنشئ: ${row.createdAt || "غير معروف"}]`
      );
    }
    console.log("");
    console.log("  لكل حساب، القرار واحد من ثلاثة:");
    console.log("    • طبيب حقيقي زُوِّد يدوياً → أنشئ له طلباً معتمَداً للتوثيق");
    console.log("    • لم يعد نشطاً            → اخفضه بـ --demote");
    console.log("    • مجهول                  → تحقّق قبل أي إجراء");
    console.log("");
  }

  if (buckets[INCONSISTENT].length) {
    console.log("حالات غير متسقة — لا تُخفض بلا فحص:");
    console.log("─".repeat(60));
    for (const row of buckets[INCONSISTENT]) {
      console.log(
        `  ${row.uid}  دور=${row.role}  طلب=${row.applicationStatus}` +
        `  محذوف=${row.deleted}`
      );
    }
    console.log("");
  }

  if (JSON_PATH) {
    require("fs").writeFileSync(
      JSON_PATH,
      JSON.stringify({ generatedAt: new Date().toISOString(), buckets }, null, 2)
    );
    console.log(`التقرير الكامل: ${JSON_PATH}`);
    console.log("");
  }

  if (!DEMOTE.length) {
    console.log("لم يُطلب أي خفض. لم تُكتب أي بيانات.");
    return;
  }

  // ── الخفض: بمعرّفات صريحة فقط ────────────────────────────────────────
  console.log("─".repeat(60));
  console.log(APPLY ? "تنفيذ الخفض:" : "معاينة الخفض (بلا كتابة):");

  for (const uid of DEMOTE) {
    const snap = await db.collection("users").doc(uid).get();
    if (!snap.exists) {
      console.log(`  ✗ ${uid}: لا مستند لهذا المعرّف`);
      continue;
    }
    if (snap.data().role !== "doctor") {
      console.log(`  · ${uid}: ليس طبيباً أصلاً (${snap.data().role}) — تُخطّى`);
      continue;
    }

    if (!APPLY) {
      console.log(`  ⟳ ${uid}: سيصبح role=patient، ويُحذف ملفه العام`);
      continue;
    }

    // الخفض يُسجَّل في `audit_logs` كأي قرار صلاحية آخر، وإلا صار تغيير
    // الأدوار في الإنتاج بلا أثر يمكن مراجعته.
    const batch = db.batch();
    batch.update(snap.ref, {
      role: "patient",
      demotedAt: admin.firestore.FieldValue.serverTimestamp(),
      demotedReason: "legacy_doctor_without_approved_application",
    });
    batch.set(db.collection("audit_logs").doc(), {
      action: "legacy_doctor_demoted",
      subjectId: uid,
      actorId: null,
      details: { via: "scripts/audit_doctor_accounts.js" },
      at: admin.firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();
    // `syncDoctorPublicProfile` يحذف الملف العام تلقائياً عند تغيّر الدور.
    console.log(`  ✓ ${uid}: خُفض إلى مريض`);
  }

  console.log("");
  if (!APPLY) {
    console.log("معاينة فقط. أضف --apply للتنفيذ.");
  }
}

main().then(
  () => process.exit(0),
  (e) => {
    console.error(e);
    process.exit(1);
  }
);
