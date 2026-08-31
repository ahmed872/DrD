#!/usr/bin/env node
/**
 * ترقية حساب قائم إلى طبيب موثَّق — المسار الوحيد لإنشاء الأطباء.
 *
 * ## لماذا
 *
 * صار إنشاء مستند بدور `doctor` مستحيلاً من العميل: `firestore.rules` تقبل
 * `role == 'patient'` وحده عند الإنشاء، وتمنع أي مستخدم من تعديل `role` أو
 * `isVerified` لنفسه. هذا يغلق أخطر ثغرة كانت في التطبيق (أي شخص يسجّل نفسه
 * طبيباً من شاشة التسجيل، فيظهر في القائمة ويقرأ بيانات مرضى حقيقيين).
 *
 * فلا بد من طريق إداري بديل — وهو هذا السكربت، يعمل بـ Admin SDK.
 *
 * ## سير العمل
 *
 *   1. يسجّل الطبيب حساباً عادياً من التطبيق (كمريض).
 *   2. تتحقق أنت من هويته ومزاولته خارج التطبيق.
 *   3. تشغّل هذا السكربت بمعرّفه أو رقم جواله.
 *
 * ## التشغيل
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/service-account.json
 *
 *   node scripts/promote_to_doctor.js --uid=abc123              # معاينة
 *   node scripts/promote_to_doctor.js --uid=abc123 --apply
 *   node scripts/promote_to_doctor.js --phone=01001234567 --apply
 *
 *   # ترقية بلا توثيق (يظهر لاحقاً بعد التوثيق فقط):
 *   node scripts/promote_to_doctor.js --uid=abc123 --unverified --apply
 *
 *   # سحب التوثيق من طبيب (لا يُحذف حسابه ولا مواعيده):
 *   node scripts/promote_to_doctor.js --uid=abc123 --revoke --apply
 */

const { initAdmin, normalizePhone, parseArgs } = require('./_lib');

async function resolveUid(db, args) {
  if (args.uid) return String(args.uid);

  if (args.phone) {
    const phone = normalizePhone(String(args.phone));
    const indexSnap = await db.collection('phone_index').doc(phone).get();
    if (indexSnap.exists) return indexSnap.data().uid;

    const q = await db.collection('users')
      .where('phone', '==', phone).limit(2).get();
    if (q.empty) return null;
    if (q.size > 1) {
      console.error(`❌ أكثر من حساب بالرقم ${phone} — استخدم --uid`);
      process.exit(1);
    }
    return q.docs[0].id;
  }

  return null;
}

async function main() {
  const args = parseArgs();
  const apply = args.apply === true;
  const revoke = args.revoke === true;
  const verified = args.unverified === true ? false : true;
  const db = initAdmin(args.project);

  if (!args.uid && !args.phone) {
    console.error('الاستخدام: node scripts/promote_to_doctor.js ' +
      '--uid=<uid> | --phone=<رقم> [--apply] [--unverified] [--revoke]');
    process.exit(1);
  }

  const uid = await resolveUid(db, args);
  if (!uid) {
    console.error('❌ لم يُعثر على حساب مطابق. تأكد أن الطبيب سجّل أولاً.');
    process.exit(1);
  }

  const ref = db.collection('users').doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    console.error(`❌ لا يوجد مستند مستخدم بالمعرّف ${uid}`);
    process.exit(1);
  }

  const data = snap.data();
  console.log('الحساب الحالي:');
  console.log(`   المعرّف:  ${uid}`);
  console.log(`   الاسم:    ${data.name || '—'}`);
  console.log(`   الجوال:   ${data.phone || '—'}`);
  console.log(`   البريد:   ${data.email || '—'}`);
  console.log(`   الدور:    ${data.role || '—'}`);
  console.log(`   موثَّق:    ${data.isVerified === true ? 'نعم' : 'لا'}`);

  if (revoke) {
    console.log('\nالإجراء: سحب التوثيق (يبقى الدور والحساب والمواعيد كما هي)');
    if (!apply) {
      console.log('👁️  معاينة فقط. أضف --apply للتنفيذ.');
      return;
    }
    await ref.set(
      { isVerified: false, verifiedAt: new Date(), verifiedBy: 'admin-script' },
      { merge: true }
    );
    console.log('✅ سُحب التوثيق. لن يظهر في البحث ولن تُقبل حجوزات جديدة عنده.');
    console.log('   المواعيد القائمة لم تُمس — راجعها يدوياً إن لزم.');
    return;
  }

  console.log(`\nالإجراء: role → doctor، isVerified → ${verified}`);
  if (!apply) {
    console.log('👁️  معاينة فقط. أضف --apply للتنفيذ.');
    return;
  }

  await ref.set(
    {
      role: 'doctor',
      isVerified: verified,
      verifiedAt: new Date(),
      verifiedBy: 'admin-script',
    },
    { merge: true }
  );

  console.log('✅ تمت الترقية.');
  console.log('   يكمل الطبيب إعداداته من «إعدادات العيادة» داخل التطبيق:');
  console.log('   التخصص، ساعات وأيام العمل، مدة الكشف/السعة، والسعر.');
  if (!verified) {
    console.log('   ⚠️  غير موثَّق بعد — لن يظهر للمرضى حتى تُشغّل السكربت بلا --unverified.');
  }
}

main().catch((e) => {
  console.error('❌ فشل:', e);
  process.exit(1);
});
