/**
 * هجرة الملاحظات الطبية القديمة من مستندات المواعيد إلى `encounters`.
 *
 * ## لماذا
 *
 * قبل المرحلة الثالثة كان الطبيب يكتب ملاحظته على مستند **الموعد** في حقل
 * `notes`، وكانت شاشة السجل الطبي تقرأ منه. صار السجل السريري مجموعة
 * مستقلة، فالمواعيد التي تحمل ملاحظات قديمة لا تظهر للمريض حتى تُهاجَر.
 *
 * لا تُحذف أي بيانات: الحقل الأصلي يبقى على مستند الموعد كما هو. السكربت
 * يُنشئ سجلاً موازياً فقط.
 *
 * ## ما يُهاجَر
 *
 * موعد **مكتمل** يحمل `notes` غير فارغ ولا سجل له بعد. الملاحظة تُكتب في
 * `clinicalNotes`، ويُوضع في `diagnosis` نصّ صريح يقول إن التشخيص لم
 * يُسجَّل — لأن الحقل مطلوب في القاعدة، ولأن اختراع تشخيص من ملاحظة حرة
 * تزوير لسجل طبي.
 *
 * ## التشغيل
 *
 *     node scripts/migrate_appointment_notes_to_encounters.js            # فحص فقط
 *     node scripts/migrate_appointment_notes_to_encounters.js --apply    # تنفيذ
 *
 * الوضع الافتراضي **فحص بلا كتابة**. لم يُشغَّل هذا السكربت على أي بيئة.
 * راجع scripts/README.md قبل تشغيله.
 */

const admin = require('firebase-admin');

const APPLY = process.argv.includes('--apply');

const COMPLETED = new Set([
  'Completed', 'completed', 'Done', 'done',
]);

/** نص التشخيص حين لا يوجد — صريح، لا مخترَع. */
const NO_DIAGNOSIS = 'لم يُسجَّل تشخيص (سجل مُرحَّل من ملاحظة سابقة)';

async function main() {
  if (!admin.apps.length) admin.initializeApp();
  const db = admin.firestore();

  const snapshot = await db.collection('appointments').get();

  const candidates = [];
  for (const doc of snapshot.docs) {
    const a = doc.data();
    const notes = (a.notes || '').toString().trim();
    if (!notes) continue;
    if (!COMPLETED.has((a.status || '').toString())) continue;
    if (!a.doctorId || !a.patientId) continue;
    candidates.push({ id: doc.id, appointment: a, notes });
  }

  // معرّف السجل هو معرّف الموعد، فالفحص قراءة مباشرة لا استعلام.
  const toWrite = [];
  for (const c of candidates) {
    const existing = await db.collection('encounters').doc(c.id).get();
    if (existing.exists) continue;
    toWrite.push(c);
  }

  console.log(`مواعيد تحمل ملاحظات مكتملة: ${candidates.length}`);
  console.log(`منها بلا سجل بعد:          ${toWrite.length}`);

  if (!APPLY) {
    console.log('\n— وضع الفحص. لم تُكتب أي بيانات. —');
    for (const c of toWrite.slice(0, 10)) {
      console.log(`  ${c.id}  ${c.appointment.appointmentDate}  `
        + `"${c.notes.slice(0, 60)}${c.notes.length > 60 ? '…' : ''}"`);
    }
    if (toWrite.length > 10) console.log(`  … و${toWrite.length - 10} غيرها`);
    console.log('\nللتنفيذ: أضف --apply');
    return;
  }

  let written = 0;
  for (const c of toWrite) {
    const a = c.appointment;
    await db.collection('encounters').doc(c.id).set({
      appointmentId: c.id,
      patientId: a.patientId,
      doctorId: a.doctorId,
      doctorName: (a.doctorName || '').toString(),
      doctorSpecialization: (a.doctorSpecialization || '').toString(),
      encounterDate: (a.appointmentDate || '').toString(),
      diagnosis: NO_DIAGNOSIS,
      // الملاحظة الأصلية تُنقل كما هي، مقتطعة عند حد القاعدة.
      clinicalNotes: c.notes.slice(0, 4000),
      treatmentPlan: '',
      followUpNotes: '',
      followUpDate: '',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    written += 1;
  }
  console.log(`تم إنشاء ${written} سجلاً. الحقل الأصلي على المواعيد لم يُمَس.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
