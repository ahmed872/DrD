/**
 * تعبئة مجموعة `phone_index` من مستندات `users` القائمة.
 *
 * ## ليه السكربت ده ضروري؟
 *
 * تسجيل الدخول بالرقم يحتاج ترجمة الرقم إلى بريد إلكتروني **قبل** المصادقة،
 * لأن Firebase Auth يعمل بالبريد. القواعد الجديدة تمنع قراءة مجموعة `users`
 * من زائر غير مسجَّل (وهي الثغرة التي كانت تكشف كل بيانات المرضى)، والبديل
 * هو مجموعة `phone_index` التي تحتوي على `{uid, email}` فقط.
 *
 * المشكلة: الحسابات المنشأة قبل التحديث ليس لها مدخل في الفهرس. التطبيق
 * يكتب المدخل الناقص تلقائياً عند أول تسجيل دخول ناجح — لكن تسجيل الدخول
 * نفسه يحتاج الفهرس. حلقة مقفلة تمنع كل المستخدمين القدامى من الدخول.
 *
 * هذا السكربت يكسر الحلقة: يُشغَّل **مرة واحدة** بصلاحيات المشرف (التي
 * تتجاوز قواعد الأمان) فيملأ الفهرس لكل الحسابات القائمة.
 *
 * ## التشغيل
 *
 * 1. Firebase Console ← ⚙️ Project settings ← Service accounts
 *    ← "Generate new private key" ← احفظ الملف باسم `serviceAccount.json`
 *
 * 2. من مجلد المشروع:
 *
 *        npm --prefix functions install
 *        node tool/backfill_phone_index.js path/to/serviceAccount.json
 *
 * 3. احذف `serviceAccount.json` بعد الانتهاء — هو مفتاح كامل الصلاحيات
 *    على مشروعك، ولا يجوز رفعه على Git إطلاقاً.
 *
 * السكربت آمن للتشغيل أكثر من مرة: يتخطّى أي مدخل موجود بالفعل.
 */

const path = require("path");
const admin = require(path.join(__dirname, "..", "functions", "node_modules", "firebase-admin"));

const keyPath = process.argv[2];

// وضع المحاكي: للتجربة على بيانات وهمية قبل المساس بقاعدة البيانات الحقيقية.
//
//     firebase emulators:start --only firestore
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node tool/backfill_phone_index.js
//
// المحاكي لا يتحقّق من الاعتماديات، فلا حاجة لمفتاح خدمة.
const useEmulator = !!process.env.FIRESTORE_EMULATOR_HOST;

if (!keyPath && !useEmulator) {
  console.error(
    "الاستخدام: node tool/backfill_phone_index.js <serviceAccount.json>\n" +
    "أو للتجربة على المحاكي: FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node tool/backfill_phone_index.js"
  );
  process.exit(1);
}

if (useEmulator) {
  console.log(`⚙️  وضع المحاكي: ${process.env.FIRESTORE_EMULATOR_HOST}\n`);
  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "demo-drd" });
} else {
  admin.initializeApp({
    credential: admin.credential.cert(require(path.resolve(keyPath))),
  });
}

const db = admin.firestore();

/**
 * توحيد صيغة رقم الجوال — نسخة مطابقة لـ `normalizePhoneNumber` في
 * `lib/presentation/providers/firebase_auth_service.dart`.
 *
 * لا بد أن تتطابق الدالتان حرفياً: أي اختلاف يعني أن السكربت يكتب المدخل
 * تحت مفتاح مختلف عن الذي يبحث عنه التطبيق، فلا يجد شيئاً.
 */
function normalizePhone(phone) {
  let cleaned = String(phone).replace(/\D/g, "");
  if (cleaned.startsWith("00")) cleaned = cleaned.slice(2);
  if (cleaned.startsWith("0")) cleaned = cleaned.slice(1);
  if (!cleaned.startsWith("20")) cleaned = "20" + cleaned;
  return cleaned;
}

async function main() {
  console.log("جارٍ قراءة المستخدمين...\n");

  const users = await db.collection("users").get();
  console.log(`عدد المستخدمين: ${users.size}\n`);

  let created = 0;
  let skipped = 0;
  let invalid = 0;

  // الدفعات محدودة بـ 500 عملية في Firestore.
  let batch = db.batch();
  let pending = 0;

  for (const doc of users.docs) {
    const data = doc.data();
    const phone = data.phone;
    const email = data.email;

    if (!phone || !email) {
      console.warn(`  ⚠️  تخطّي ${doc.id}: ${!phone ? "بلا رقم" : "بلا بريد"}`);
      invalid++;
      continue;
    }

    const key = normalizePhone(phone);
    const ref = db.collection("phone_index").doc(key);

    // القراءة قبل الكتابة تجعل السكربت آمناً للتكرار، وتمنع الكتابة فوق
    // مدخل صحيح بآخر قديم لو تغيّر بريد المستخدم بعد التعبئة الأولى.
    const existing = await ref.get();
    if (existing.exists) {
      skipped++;
      continue;
    }

    batch.set(ref, {
      uid: doc.id,
      email: String(email).trim().toLowerCase(),
      backfilledAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    created++;
    pending++;

    if (pending >= 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
      console.log(`  ... حُفظت ${created} حتى الآن`);
    }
  }

  if (pending > 0) await batch.commit();

  console.log("\n─────────────────────────────");
  console.log(`✅ مدخلات جديدة : ${created}`);
  console.log(`⏭️  موجودة سلفاً : ${skipped}`);
  console.log(`⚠️  بيانات ناقصة: ${invalid}`);
  console.log("─────────────────────────────");

  if (invalid > 0) {
    console.log(
      "\nالحسابات ذات البيانات الناقصة لن تستطيع الدخول بالرقم.\n" +
      "راجعها يدوياً في الكونسول، أو اطلب من أصحابها إعادة التسجيل."
    );
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("\n❌ فشل السكربت:", e.message);
    process.exit(1);
  });
