#!/usr/bin/env node
/**
 * تعبئة `phone_index` للحسابات القديمة — هجرة تُشغَّل مرة واحدة.
 *
 * ## لماذا هذا السكربت موجود
 *
 * تسجيل الدخول في التطبيق يتم برقم الجوال، بينما Firebase Auth يعمل بالبريد.
 * فلا بد من ترجمة الرقم إلى بريد **قبل** المصادقة، ومجموعة `phone_index`
 * (معرّف مستندها = رقم الجوال، ومحتواها `{uid, email}` فقط) هي ما يسمح بذلك
 * دون فتح مجموعة `users` كاملة للقراءة العامة.
 *
 * كان التطبيق يعالج الحسابات القديمة بمسار احتياطي: يستعلم على `users` قبل
 * المصادقة، ثم يكتب المدخل الناقص. حُذف ذلك المسار في «المرحلة صفر» لأنه
 * يتطلب قراءة عامة لكل بيانات المستخدمين (أسماء، أرقام، تواريخ ميلاد،
 * أدوار) — وهي بيانات مرضى.
 *
 * البديل: هجرة صريحة تعمل بصلاحيات المدير مرة واحدة.
 *
 * ## متى يُشغَّل
 *
 * **قبل** نشر قواعد المرحلة صفر ونسخة التطبيق الجديدة. بدونه لن يستطيع أي
 * حساب قديم ليس له مدخل في الفهرس تسجيل الدخول.
 *
 * ## ضمانات
 *
 * - لا يحذف شيئاً ولا يعدّل مستندات `users` إطلاقاً.
 * - لا يكتب فوق مدخل قائم؛ إن وجد مدخلاً يشير إلى مستخدم آخر أبلغ عنه
 *   كتعارض وتركه للمراجعة اليدوية (قد يكون رقماً مكرراً بين حسابين).
 * - يعمل بوضع المعاينة افتراضياً؛ لا يكتب إلا مع `--apply`.
 * - قابل لإعادة التشغيل بلا أثر جانبي.
 *
 * ## التشغيل
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/service-account.json
 *   node scripts/backfill_phone_index.js                # معاينة
 *   node scripts/backfill_phone_index.js --apply        # تنفيذ
 */

const { initAdmin, normalizePhone, parseArgs, chunk } = require('./_lib');

async function main() {
  const args = parseArgs();
  const apply = args.apply === true;
  const db = initAdmin(args.project);

  console.log(apply ? '▶️  وضع التنفيذ' : '👁️  وضع المعاينة (بلا كتابة)');

  const users = await db.collection('users').get();
  console.log(`عدد المستخدمين: ${users.size}`);

  const toWrite = [];
  const skipped = { noPhone: [], noEmail: [], alreadyIndexed: [] };
  const conflicts = [];
  const duplicatePhones = new Map();

  for (const userDoc of users.docs) {
    const data = userDoc.data();
    const rawPhone = data.phone;
    const email = (data.email || '').trim().toLowerCase();

    if (!rawPhone) {
      skipped.noPhone.push(userDoc.id);
      continue;
    }
    if (!email) {
      // بلا بريد لا يمكن تسجيل الدخول أصلاً — يحتاج مراجعة يدوية.
      skipped.noEmail.push(userDoc.id);
      continue;
    }

    const phone = normalizePhone(String(rawPhone));

    // رقم واحد لحسابين: لا يمكن للفهرس أن يشير إلا لواحد.
    if (duplicatePhones.has(phone)) {
      conflicts.push({
        phone,
        reason: 'رقم مكرر بين حسابين',
        uids: [duplicatePhones.get(phone), userDoc.id],
      });
      continue;
    }
    duplicatePhones.set(phone, userDoc.id);

    const indexSnap = await db.collection('phone_index').doc(phone).get();
    if (indexSnap.exists) {
      const existing = indexSnap.data();
      if (existing.uid === userDoc.id) {
        skipped.alreadyIndexed.push(phone);
      } else {
        conflicts.push({
          phone,
          reason: 'المدخل يشير إلى مستخدم آخر',
          uids: [existing.uid, userDoc.id],
        });
      }
      continue;
    }

    toWrite.push({ phone, uid: userDoc.id, email });
  }

  console.log('');
  console.log(`سيُكتب مدخل جديد لـ: ${toWrite.length}`);
  console.log(`موجود مسبقاً:        ${skipped.alreadyIndexed.length}`);
  console.log(`بلا رقم جوال:        ${skipped.noPhone.length}`);
  console.log(`بلا بريد إلكتروني:   ${skipped.noEmail.length}`);
  console.log(`تعارضات:             ${conflicts.length}`);

  if (conflicts.length) {
    console.log('\n⚠️  تعارضات تحتاج مراجعة يدوية (لم يُكتب لها شيء):');
    for (const c of conflicts) {
      console.log(`   ${c.phone} — ${c.reason} — ${c.uids.join(' | ')}`);
    }
  }

  if (skipped.noEmail.length) {
    console.log('\n⚠️  حسابات بلا بريد لن تستطيع تسجيل الدخول بالرقم:');
    console.log('   ' + skipped.noEmail.join(', '));
  }

  if (!apply) {
    console.log('\n👁️  معاينة فقط. أضف --apply للتنفيذ.');
    return;
  }

  let written = 0;
  for (const group of chunk(toWrite, 400)) {
    const batch = db.batch();
    for (const entry of group) {
      batch.set(db.collection('phone_index').doc(entry.phone), {
        uid: entry.uid,
        email: entry.email,
        backfilledAt: new Date(),
      });
    }
    await batch.commit();
    written += group.length;
    console.log(`   كُتب ${written}/${toWrite.length}`);
  }

  console.log(`\n✅ اكتمل. مداخل جديدة: ${written}`);
}

main().catch((e) => {
  console.error('❌ فشل:', e);
  process.exit(1);
});
