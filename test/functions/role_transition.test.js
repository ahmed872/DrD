/**
 * اختبار انتقال الدور — قلب المرحلة الثانية.
 *
 * القواعد تُثبت أن العميل **لا يستطيع** كتابة `role`. هذا الملف يُثبت الشق
 * الآخر: أن الخادم **يكتبه فعلاً** عند القبول. بلا الاثنين معاً يبقى
 * أحدهما ادّعاءً: نظام يمنع الترقية ولا ينفّذها ليس آمناً بل معطّلاً.
 *
 *   firebase emulators:exec --only firestore,functions \
 *     "npm --prefix test/functions test"
 */

const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

admin.initializeApp({ projectId: 'demo-drd' });
const db = admin.firestore();

const APPLICANT = 'fn_applicant_1';
const ADMIN_ID = 'fn_admin_1';

/** ينتظر حتى يحقّق استعلام شرطاً، أو تنتهي المهلة. */
async function waitForQuery(query, predicate, { timeoutMs = 20000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    last = await query.get();
    if (predicate(last)) return last;
    await new Promise((r) => setTimeout(r, 300));
  }
  return last;
}

/** ينتظر حتى يحقّق مستند شرطاً، أو تنتهي المهلة. */
async function waitFor(ref, predicate, { timeoutMs = 20000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    const snap = await ref.get();
    last = snap.exists ? snap.data() : null;
    if (predicate(last)) return last;
    await new Promise((r) => setTimeout(r, 300));
  }
  return last;
}

const validApplication = (status = 'pending') => ({
  applicantId: APPLICANT,
  applicantName: 'أحمد يوسف',
  specialty: 'طب الأسرة',
  professionalBio: 'طبيب أسرة بخبرة في الرعاية الأولية ومتابعة المزمن.',
  yearsOfExperience: 8,
  applicantNotes: '',
  status,
  submittedAt: admin.firestore.FieldValue.serverTimestamp(),
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
});

beforeEach(async () => {
  await db.collection('users').doc(APPLICANT).set({
    role: 'patient',
    name: 'أحمد يوسف',
    phone: '201000000009',
  });
  await db.collection('doctor_applications').doc(APPLICANT).delete();
  const logs = await db.collection('audit_logs').get();
  await Promise.all(logs.docs.map((d) => d.ref.delete()));
});

afterAll(async () => {
  await Promise.all(admin.apps.map((a) => a && a.delete()));
});

describe('ترقية الطبيب بعد القبول', () => {
  test('المستخدم يبقى مريضاً ما دام الطلب معلّقاً', async () => {
    await db
      .collection('doctor_applications')
      .doc(APPLICANT)
      .set(validApplication('pending'));

    // ننتظر أثر التقديم في سجل التدقيق، فنعرف أن الدالة عملت فعلاً — ثم
    // نتأكد أنها لم ترقِّ أحداً. الانتظار على الأثر لا على مهلة، وإلا كان
    // الاختبار يمرّ لأن الدالة لم تعمل بعد لا لأنها امتنعت.
    await waitForQuery(
      db.collection('audit_logs')
        .where('action', '==', 'doctor_application_submitted'),
      (snap) => !snap.empty
    );
    const user = (await db.collection('users').doc(APPLICANT).get()).data();
    expect(user.role).toBe('patient');
    expect(user.isVerified).toBeUndefined();
  }, 30000);

  test('القبول يرقّي المستخدم إلى طبيب موثّق', async () => {
    await db
      .collection('doctor_applications')
      .doc(APPLICANT)
      .set(validApplication('pending'));

    await db.collection('doctor_applications').doc(APPLICANT).update({
      status: 'approved',
      reviewedBy: ADMIN_ID,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const user = await waitFor(
      db.collection('users').doc(APPLICANT),
      (d) => d && d.role === 'doctor'
    );

    expect(user.role).toBe('doctor');
    expect(user.isVerified).toBe(true);
    expect(user.verificationStatus).toBe('approved');
    // التخصص يُنسخ من الطلب حتى لا يظهر الطبيب للمرضى بتخصص فارغ.
    expect(user.specialization).toBe('طب الأسرة');
    // ولا تُمحى بيانات المستخدم القائمة.
    expect(user.name).toBe('أحمد يوسف');
    expect(user.phone).toBe('201000000009');
  }, 40000);

  test('الرفض لا يمنح أي صلاحية', async () => {
    await db
      .collection('doctor_applications')
      .doc(APPLICANT)
      .set(validApplication('pending'));

    await db.collection('doctor_applications').doc(APPLICANT).update({
      status: 'rejected',
      reviewedBy: ADMIN_ID,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      rejectionReason: 'النبذة المهنية غير كافية لتقييم الطلب.',
    });

    // الانتظار على الشرط نفسه لا على مهلة عمياء.
    const logs = await waitForQuery(
      db.collection('audit_logs')
        .where('action', '==', 'doctor_application_rejected'),
      (snap) => !snap.empty
    );
    expect(logs.empty).toBe(false);

    const user = (await db.collection('users').doc(APPLICANT).get()).data();
    expect(user.role).toBe('patient');
  }, 40000);

  test('كل قرار يترك أثراً في سجل التدقيق', async () => {
    await db
      .collection('doctor_applications')
      .doc(APPLICANT)
      .set(validApplication('pending'));
    await db.collection('doctor_applications').doc(APPLICANT).update({
      status: 'approved',
      reviewedBy: ADMIN_ID,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await waitFor(
      db.collection('users').doc(APPLICANT),
      (d) => d && d.role === 'doctor'
    );

    const approved = await db
      .collection('audit_logs')
      .where('action', '==', 'doctor_application_approved')
      .get();
    expect(approved.empty).toBe(false);

    const entry = approved.docs[0].data();
    expect(entry.subjectId).toBe(APPLICANT);
    expect(entry.actorId).toBe(ADMIN_ID);
    expect(entry.at).toBeTruthy();
  }, 40000);

  test('إعادة تشغيل نفس القرار لا تُفسد الحالة', async () => {
    // الدالة تشتقّ الحالة المطلوبة من حالة الطلب بدل التعديل التزايدي،
    // فإعادة المحاولة بعد فشل جزئي تصل إلى النتيجة نفسها.
    await db
      .collection('doctor_applications')
      .doc(APPLICANT)
      .set({ ...validApplication('approved'), reviewedBy: ADMIN_ID });

    const user = await waitFor(
      db.collection('users').doc(APPLICANT),
      (d) => d && d.role === 'doctor'
    );
    expect(user.role).toBe('doctor');

    // كتابة لا تغيّر الحالة يجب ألّا تفعل شيئاً.
    await db
      .collection('doctor_applications')
      .doc(APPLICANT)
      .update({ applicantNotes: 'ملاحظة إضافية' });

    await new Promise((r) => setTimeout(r, 2000));
    const again = (await db.collection('users').doc(APPLICANT).get()).data();
    expect(again.role).toBe('doctor');
    expect(again.isVerified).toBe(true);
  }, 40000);
});
