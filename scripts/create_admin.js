#!/usr/bin/env node
/**
 * منح أو سحب صلاحية الإدارة (Custom Claim) — الطريق الوحيد لإنشاء أول admin.
 *
 * ## لماذا Custom Claim لا حقل Firestore
 *
 * لا يوجد مسار عميل يستطيع أن يمنح نفسه صلاحية admin أبداً — ببساطة لأن
 * الصلاحية غير موجودة في Firestore إطلاقاً. تعيش داخل رمز Firebase Auth
 * الموقَّع (JWT)، ولا يكتبها إلا Admin SDK. `firestore.rules`
 * (`isAdmin()`) و Cloud Functions (`context.auth.token.admin`) كلاهما
 * يتحقق من نفس الحقل الموقَّع، لا من أي قراءة قاعدة بيانات.
 *
 * ## سير العمل
 *
 *   1. الشخص المراد ترقيته يسجّل حساباً عادياً من التطبيق (كمريض).
 *   2. تتحقق أنت من هويته خارج التطبيق.
 *   3. تشغّل هذا السكربت بمعرّفه أو بريده أو رقم جواله.
 *
 * ## أثر مهم: تحديث الرمز
 *
 * منح الصلاحية لا يظهر فوراً في جلسة مسجَّلة بالفعل — رمز Firebase Auth
 * الحالي في يد المستخدم صدر قبل الترقية ولا يحمل `admin: true`. يحتاج
 * تحديثاً (`getIdTokenResult(true)` من التطبيق، أو تسجيل خروج ودخول). راجع
 * `FirebaseAuthService.refreshClaims` في التطبيق.
 *
 * ## التشغيل
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/service-account.json
 *
 *   node scripts/create_admin.js --uid=abc123              # معاينة
 *   node scripts/create_admin.js --uid=abc123 --apply
 *   node scripts/create_admin.js --phone=01001234567 --apply
 *
 *   # سحب الصلاحية:
 *   node scripts/create_admin.js --uid=abc123 --revoke --apply
 */

const admin = require('firebase-admin');
const { initAdmin, normalizePhone, parseArgs } = require('./_lib');

async function resolveUid(db, args) {
  if (args.uid) return String(args.uid);

  if (args.phone) {
    const phone = normalizePhone(String(args.phone));
    const indexSnap = await db.collection('phone_index').doc(phone).get();
    if (indexSnap.exists) return indexSnap.data().uid;

    const q = await db.collection('users').where('phone', '==', phone).limit(2).get();
    if (q.empty) return null;
    if (q.size > 1) {
      console.error(`❌ أكثر من حساب بالرقم ${phone} — استخدم --uid`);
      process.exit(1);
    }
    return q.docs[0].id;
  }

  if (args.email) {
    try {
      const user = await admin.auth().getUserByEmail(String(args.email));
      return user.uid;
    } catch (e) {
      return null;
    }
  }

  return null;
}

async function main() {
  const args = parseArgs();
  const apply = args.apply === true;
  const revoke = args.revoke === true;
  const db = initAdmin(args.project); // يهيّئ admin.initializeApp أيضاً.

  if (!args.uid && !args.phone && !args.email) {
    console.error('الاستخدام: node scripts/create_admin.js ' +
      '--uid=<uid> | --phone=<رقم> | --email=<بريد> [--apply] [--revoke]');
    process.exit(1);
  }

  const uid = await resolveUid(db, args);
  if (!uid) {
    console.error('❌ لم يُعثر على حساب مطابق. تأكد أن الشخص سجّل أولاً.');
    process.exit(1);
  }

  let authUser;
  try {
    authUser = await admin.auth().getUser(uid);
  } catch (e) {
    console.error(`❌ لا يوجد حساب Firebase Auth بالمعرّف ${uid}`);
    process.exit(1);
  }

  const userSnap = await db.collection('users').doc(uid).get();
  const profile = userSnap.exists ? userSnap.data() : null;

  console.log('الحساب الحالي:');
  console.log(`   المعرّف:  ${uid}`);
  console.log(`   البريد:   ${authUser.email || '—'}`);
  console.log(`   الاسم:    ${profile ? profile.name || '—' : '(لا يوجد ملف Firestore)'}`);
  console.log(`   admin حالياً: ${authUser.customClaims && authUser.customClaims.admin === true ? 'نعم' : 'لا'}`);

  // دمج لا استبدال — لو أُضيفت Custom Claims أخرى مستقبلاً لا يمحوها هذا
  // السكربت. `setCustomUserClaims` يستبدل الكائن كاملاً، فلا بد من قراءة
  // الموجود أولاً.
  const existingClaims = authUser.customClaims || {};

  if (revoke) {
    console.log('\nالإجراء: سحب صلاحية الإدارة');
    if (existingClaims.admin !== true) {
      console.log('ℹ️  الحساب ليس admin أصلاً — لا شيء لفعله.');
      return;
    }
    if (!apply) {
      console.log('👁️  معاينة فقط. أضف --apply للتنفيذ.');
      return;
    }
    const { admin: _drop, ...rest } = existingClaims;
    await admin.auth().setCustomUserClaims(uid, rest);
    console.log('✅ سُحبت صلاحية الإدارة.');
    console.log('   الجلسات المسجَّلة حالياً تحتفظ بالصلاحية القديمة حتى');
    console.log('   يُحدَّث رمزها — لا تعتمد على السحب كإجراء فوري إن كان');
    console.log('   الحساب مسجَّل الدخول في هذه اللحظة على جهاز آخر.');
    return;
  }

  console.log('\nالإجراء: منح صلاحية الإدارة (admin: true)');
  if (existingClaims.admin === true) {
    console.log('ℹ️  الحساب admin بالفعل — لا شيء لفعله (عملية آمنة للتكرار).');
    return;
  }
  if (!apply) {
    console.log('👁️  معاينة فقط. أضف --apply للتنفيذ.');
    return;
  }

  await admin.auth().setCustomUserClaims(uid, { ...existingClaims, admin: true });

  console.log('✅ منحت الصلاحية.');
  console.log('   يحتاج الحساب تحديث رمز الجلسة ليرى الصلاحية:');
  console.log('   تسجيل خروج ثم دخول، أو استدعاء getIdTokenResult(true) من التطبيق.');
}

main().catch((e) => {
  console.error('❌ فشل:', e);
  process.exit(1);
});
