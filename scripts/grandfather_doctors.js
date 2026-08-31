#!/usr/bin/env node
/**
 * توثيق الأطباء الموجودين قبل «المرحلة صفر» — هجرة تُشغَّل مرة واحدة.
 *
 * ## لماذا
 *
 * صارت القواعد تشترط `isVerified == true` على مستند الطبيب قبل قبول أي حجز
 * عنده. الأطباء المسجَّلون قبل هذا التغيير لا يحملون الحقل، فبدون هذه الهجرة
 * يتوقف الحجز عند **كل** طبيب قائم لحظة نشر القواعد.
 *
 * السكربت يمنحهم الحقل كما هم عليه اليوم (grandfathering) — لا يُنشئ أطباء
 * ولا يغيّر أدواراً.
 *
 * ## متى
 *
 * **قبل** `firebase deploy --only firestore:rules` وقبل نشر نسخة التطبيق.
 *
 * ## ضمانات
 *
 * - يلمس مستندات `role == 'doctor'` فقط.
 * - يكتب حقلاً واحداً (`isVerified`) ولا يمسّ أي حقل آخر.
 * - لا يتخطّى قراراً سابقاً: من كان `isVerified: false` صراحةً يبقى كذلك،
 *   إلا مع `--include-rejected`.
 * - معاينة افتراضياً؛ لا يكتب إلا مع `--apply`.
 *
 * ## التشغيل
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/service-account.json
 *   node scripts/grandfather_doctors.js            # معاينة
 *   node scripts/grandfather_doctors.js --apply    # تنفيذ
 */

const { initAdmin, parseArgs, chunk } = require('./_lib');

async function main() {
  const args = parseArgs();
  const apply = args.apply === true;
  const includeRejected = args['include-rejected'] === true;
  const db = initAdmin(args.project);

  console.log(apply ? '▶️  وضع التنفيذ' : '👁️  وضع المعاينة (بلا كتابة)');

  const doctors = await db.collection('users')
    .where('role', '==', 'doctor')
    .get();

  console.log(`عدد الأطباء: ${doctors.size}`);

  const toVerify = [];
  const already = [];
  const explicitlyRejected = [];

  for (const d of doctors.docs) {
    const value = d.data().isVerified;
    if (value === true) {
      already.push(d.id);
    } else if (value === false && !includeRejected) {
      // قرار سابق بعدم التوثيق — لا نتخطّاه بصمت.
      explicitlyRejected.push(d.id);
    } else {
      toVerify.push({ id: d.id, name: d.data().name || '—' });
    }
  }

  console.log('');
  console.log(`سيُوثَّق:            ${toVerify.length}`);
  console.log(`موثَّق مسبقاً:       ${already.length}`);
  console.log(`مرفوض صراحةً (يُترك): ${explicitlyRejected.length}`);

  for (const d of toVerify) console.log(`   + ${d.id} — ${d.name}`);
  if (explicitlyRejected.length) {
    console.log('\n⚠️  أطباء عليهم isVerified: false — لن يُحجز عندهم:');
    console.log('   ' + explicitlyRejected.join(', '));
    console.log('   لتوثيقهم رغم ذلك: --include-rejected');
  }

  if (!apply) {
    console.log('\n👁️  معاينة فقط. أضف --apply للتنفيذ.');
    return;
  }

  let written = 0;
  for (const group of chunk(toVerify, 400)) {
    const batch = db.batch();
    for (const d of group) {
      batch.set(
        db.collection('users').doc(d.id),
        { isVerified: true, verifiedAt: new Date(), verifiedBy: 'migration' },
        { merge: true }
      );
    }
    await batch.commit();
    written += group.length;
    console.log(`   وُثِّق ${written}/${toVerify.length}`);
  }

  console.log(`\n✅ اكتمل. أطباء وُثِّقوا: ${written}`);
}

main().catch((e) => {
  console.error('❌ فشل:', e);
  process.exit(1);
});
