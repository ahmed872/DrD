/**
 * أدوات مشتركة لسكربتات الإدارة.
 *
 * هذه السكربتات تعمل بـ Firebase Admin SDK، أي أنها **تتجاوز
 * `firestore.rules` بالكامل**. لا تشغّلها إلا من جهاز موثوق وبمفتاح حساب
 * خدمة محفوظ خارج المستودع.
 */

const admin = require('firebase-admin');

/** تهيئة Admin SDK باستخدام GOOGLE_APPLICATION_CREDENTIALS. */
function initAdmin(projectId) {
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && !projectId) {
    console.error(
      '❌ لم يُضبط GOOGLE_APPLICATION_CREDENTIALS.\n' +
      '   Firebase Console ← Project Settings ← Service accounts ←\n' +
      '   Generate new private key، ثم:\n' +
      '   export GOOGLE_APPLICATION_CREDENTIALS=/path/service-account.json'
    );
    process.exit(1);
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    ...(projectId ? { projectId } : {}),
  });

  return admin.firestore();
}

/**
 * توحيد رقم الجوال — **نسخة مطابقة** لـ `normalizePhoneNumber` في
 * `lib/presentation/providers/firebase_auth_service.dart`.
 *
 * أي اختلاف بين الاثنين يعني مدخل فهرس لا يجده التطبيق عند تسجيل الدخول،
 * أي حساباً معطَّلاً. لا تعدّل أحدهما دون الآخر.
 */
function normalizePhone(phone) {
  let cleaned = String(phone).replace(/[^\d]/g, '');
  if (cleaned.startsWith('00')) cleaned = cleaned.substring(2);
  if (cleaned.startsWith('0')) cleaned = cleaned.substring(1);
  if (!cleaned.startsWith('20')) cleaned = '20' + cleaned;
  return cleaned;
}

/** قراءة وسائط سطر الأوامر بصيغة --key=value و--flag. */
function parseArgs() {
  const out = {};
  for (const arg of process.argv.slice(2)) {
    if (!arg.startsWith('--')) continue;
    const [key, ...rest] = arg.slice(2).split('=');
    out[key] = rest.length ? rest.join('=') : true;
  }
  return out;
}

/** تقسيم قائمة إلى دفعات — حد Firestore هو 500 عملية لكل دفعة. */
function chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}

module.exports = { initAdmin, normalizePhone, parseArgs, chunk };
