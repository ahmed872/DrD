/**
 * اختبارات أمان طلبات الأطباء ومراجعة المشرف (المرحلة الثانية).
 *
 * السؤال الذي تجيب عنه هذه الملفّات: هل يستطيع مستخدم أن يجعل نفسه طبيباً؟
 * تُشغَّل على المحاكي الحقيقي، فما ينجح هنا ينجح في الإنتاج.
 *
 *   firebase emulators:exec --only firestore "npm --prefix test/firestore_rules test"
 */

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  setDoc, getDoc, updateDoc, doc, deleteDoc,
  collection, query, where, getDocs, serverTimestamp,
} = require('firebase/firestore');

let testEnv;

const ADMIN = 'admin_1';
const ADMIN2 = 'admin_2';
const APPLICANT = 'applicant_1';
const OTHER = 'applicant_2';
const DOCTOR = 'doctor_1';

/** طلب صالح الشكل — نقطة البداية لكل اختبار. */
const validApplication = (uid = APPLICANT) => ({
  applicantId: uid,
  applicantName: 'أحمد يوسف',
  specialty: 'طب الأسرة',
  professionalBio:
    'طبيب أسرة بخبرة في الرعاية الأولية ومتابعة الأمراض المزمنة في القرى.',
  yearsOfExperience: 8,
  applicantNotes: '',
  status: 'pending',
  submittedAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
});

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'drd-rules-test',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: fs.readFileSync(
        path.resolve(__dirname, '../../firestore.rules'),
        'utf8'
      ),
    },
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    // المشرفون يُزوَّدون خارج التطبيق — من وحدة التحكم أو الخادم.
    await setDoc(doc(db, 'admins', ADMIN), {});
    await setDoc(doc(db, 'admins', ADMIN2), {});
    await setDoc(doc(db, 'users', APPLICANT), {
      role: 'patient', name: 'أحمد يوسف', phone: '201000000001',
    });
    await setDoc(doc(db, 'users', OTHER), {
      role: 'patient', name: 'مريض آخر', phone: '201000000002',
    });
    await setDoc(doc(db, 'users', DOCTOR), {
      role: 'doctor', name: 'د. سعيد', phone: '201000000003',
    });
  });
});

const asApplicant = () => testEnv.authenticatedContext(APPLICANT).firestore();
const asOther = () => testEnv.authenticatedContext(OTHER).firestore();
const asAdmin = () => testEnv.authenticatedContext(ADMIN).firestore();
const asAdmin2 = () => testEnv.authenticatedContext(ADMIN2).firestore();
const asDoctor = () => testEnv.authenticatedContext(DOCTOR).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

/** يزرع طلباً بحالة معيّنة بتجاوز القواعد. */
const seedApplication = (uid, extra = {}) =>
  testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'doctor_applications', uid), {
      ...validApplication(uid),
      submittedAt: new Date(),
      updatedAt: new Date(),
      ...extra,
    });
  });

// ===========================================================================
describe('تقديم الطلب', () => {
  test('المستخدم ينشئ طلبه بمعرّفه هو', async () => {
    await assertSucceeds(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             validApplication())
    );
  });

  test('لا ينشئ المستخدم طلباً بمعرّف مستخدم آخر', async () => {
    // لو مرّ هذا لاستطاع أي شخص أن يقدّم طلباً باسم غيره.
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', OTHER),
             validApplication(OTHER))
    );
  });

  test('لا يُقبل طلب حقله applicantId يخالف معرّف المستند', async () => {
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), applicantId: OTHER })
    );
  });

  test('الزائر غير المسجَّل لا ينشئ طلباً', async () => {
    await assertFails(
      setDoc(doc(asAnon(), 'doctor_applications', APPLICANT),
             validApplication())
    );
  });

  test('لا يُنشأ طلب بحالة approved — التزوير المباشر', async () => {
    // هذا هو الهجوم الأول والأوضح: تخطّي المراجعة بالكامل.
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), status: 'approved' })
    );
  });

  test('لا يُنشأ طلب بحالة rejected', async () => {
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), status: 'rejected' })
    );
  });

  test('لا يكتب مقدّم الطلب reviewedBy', async () => {
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), reviewedBy: ADMIN })
    );
  });

  test('لا يكتب مقدّم الطلب reviewedAt', async () => {
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), reviewedAt: new Date() })
    );
  });

  test('لا يكتب مقدّم الطلب rejectionReason', async () => {
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), rejectionReason: 'لا شيء' })
    );
  });

  test('لا يهرّب مقدّم الطلب حقل role داخل الطلب', async () => {
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), role: 'doctor' })
    );
  });

  test('لا يهرّب مقدّم الطلب حقل isVerified داخل الطلب', async () => {
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), isVerified: true })
    );
  });

  test('يُرفض التخصص الفارغ', async () => {
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), specialty: '' })
    );
  });

  test('تُرفض النبذة الأقصر من الحد الأدنى', async () => {
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), professionalBio: 'طبيب' })
    );
  });

  test('تُرفض نبذة أطول من الحد الأعلى — حماية الحصة', async () => {
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), professionalBio: 'ط'.repeat(1001) })
    );
  });

  test('تُرفض سنوات خبرة سالبة أو غير معقولة', async () => {
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), yearsOfExperience: -1 })
    );
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), yearsOfExperience: 200 })
    );
  });

  test('تُرفض سنوات الخبرة إن لم تكن عدداً صحيحاً', async () => {
    await assertFails(
      setDoc(doc(asApplicant(), 'doctor_applications', APPLICANT),
             { ...validApplication(), yearsOfExperience: 'ثمانية' })
    );
  });
});

// ===========================================================================
describe('قراءة الطلبات', () => {
  beforeEach(() => seedApplication(APPLICANT));

  test('مقدّم الطلب يقرأ طلبه', async () => {
    await assertSucceeds(
      getDoc(doc(asApplicant(), 'doctor_applications', APPLICANT))
    );
  });

  test('مستخدم آخر لا يقرأ طلب غيره', async () => {
    await assertFails(
      getDoc(doc(asOther(), 'doctor_applications', APPLICANT))
    );
  });

  test('طبيب معتمَد لا يقرأ طلبات الآخرين', async () => {
    // الطبيب ليس مشرفاً؛ اعتماده لا يمنحه اطّلاعاً على طلبات غيره.
    await assertFails(
      getDoc(doc(asDoctor(), 'doctor_applications', APPLICANT))
    );
  });

  test('الزائر غير المسجَّل لا يقرأ أي طلب', async () => {
    await assertFails(
      getDoc(doc(asAnon(), 'doctor_applications', APPLICANT))
    );
  });

  test('غير المشرف لا يستطيع تصفّح مجموعة الطلبات', async () => {
    await assertFails(getDocs(collection(asOther(), 'doctor_applications')));
  });

  test('المشرف يقرأ الطلبات المعلّقة ويصفّيها', async () => {
    await assertSucceeds(
      getDocs(query(collection(asAdmin(), 'doctor_applications'),
                    where('status', '==', 'pending')))
    );
  });

  test('المشرف يقرأ طلباً بعينه', async () => {
    await assertSucceeds(
      getDoc(doc(asAdmin(), 'doctor_applications', APPLICANT))
    );
  });
});

// ===========================================================================
describe('مراجعة المشرف', () => {
  beforeEach(() => seedApplication(APPLICANT));

  test('المشرف يقبل طلباً معلّقاً', async () => {
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'doctor_applications', APPLICANT), {
        status: 'approved',
        reviewedBy: ADMIN,
        reviewedAt: serverTimestamp(),
      })
    );
  });

  test('المشرف يرفض طلباً مع سبب', async () => {
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'doctor_applications', APPLICANT), {
        status: 'rejected',
        reviewedBy: ADMIN,
        reviewedAt: serverTimestamp(),
        rejectionReason: 'التخصص المذكور غير مطابق للبيانات المرفقة.',
      })
    );
  });

  test('الرفض بلا سبب مرفوض', async () => {
    // بلا هذا الشرط يبقى الطبيب أمام باب مغلق لا يعرف كيف يفتحه.
    await assertFails(
      updateDoc(doc(asAdmin(), 'doctor_applications', APPLICANT), {
        status: 'rejected',
        reviewedBy: ADMIN,
        reviewedAt: serverTimestamp(),
      })
    );
  });

  test('الرفض بسبب أقصر من حدّ المعنى مرفوض', async () => {
    await assertFails(
      updateDoc(doc(asAdmin(), 'doctor_applications', APPLICANT), {
        status: 'rejected',
        reviewedBy: ADMIN,
        reviewedAt: serverTimestamp(),
        rejectionReason: 'لا',
      })
    );
  });

  test('لا يوقّع المشرف باسم مشرف آخر', async () => {
    await assertFails(
      updateDoc(doc(asAdmin(), 'doctor_applications', APPLICANT), {
        status: 'approved',
        reviewedBy: ADMIN2,
        reviewedAt: serverTimestamp(),
      })
    );
  });

  test('غير المشرف لا يقبل طلباً', async () => {
    await assertFails(
      updateDoc(doc(asOther(), 'doctor_applications', APPLICANT), {
        status: 'approved',
        reviewedBy: OTHER,
        reviewedAt: serverTimestamp(),
      })
    );
  });

  test('مقدّم الطلب لا يقبل طلبه بنفسه', async () => {
    // الاختبار المركزي لهذه المرحلة كلها.
    await assertFails(
      updateDoc(doc(asApplicant(), 'doctor_applications', APPLICANT), {
        status: 'approved',
        reviewedBy: APPLICANT,
        reviewedAt: serverTimestamp(),
      })
    );
  });

  test('مقدّم الطلب لا يقبل طلبه ولو انتحل توقيع مشرف', async () => {
    await assertFails(
      updateDoc(doc(asApplicant(), 'doctor_applications', APPLICANT), {
        status: 'approved',
        reviewedBy: ADMIN,
        reviewedAt: serverTimestamp(),
      })
    );
  });

  test('طبيب معتمَد لا يقبل طلبات غيره', async () => {
    await assertFails(
      updateDoc(doc(asDoctor(), 'doctor_applications', APPLICANT), {
        status: 'approved',
        reviewedBy: DOCTOR,
        reviewedAt: serverTimestamp(),
      })
    );
  });

  test('لا يُراجَع طلب سبق البتّ فيه بالقبول', async () => {
    await seedApplication(APPLICANT, {
      status: 'approved', reviewedBy: ADMIN, reviewedAt: new Date(),
    });
    await assertFails(
      updateDoc(doc(asAdmin(), 'doctor_applications', APPLICANT), {
        status: 'rejected',
        reviewedBy: ADMIN,
        reviewedAt: serverTimestamp(),
        rejectionReason: 'عدول عن القبول بعد اعتماده.',
      })
    );
  });

  test('لا يمرّر المشرف حقولاً أخرى مع قرار المراجعة', async () => {
    // القرار قرار — لا فرصة لتعديل نبذة الطبيب أو تخصصه من نفس الطلب.
    await assertFails(
      updateDoc(doc(asAdmin(), 'doctor_applications', APPLICANT), {
        status: 'approved',
        reviewedBy: ADMIN,
        reviewedAt: serverTimestamp(),
        specialty: 'جراحة',
      })
    );
  });
});

// ===========================================================================
describe('إعادة التقديم بعد الرفض', () => {
  beforeEach(() =>
    seedApplication(APPLICANT, {
      status: 'rejected',
      reviewedBy: ADMIN,
      reviewedAt: new Date(),
      rejectionReason: 'النبذة المهنية غير كافية لتقييم الطلب.',
    })
  );

  test('صاحب الطلب المرفوض يصحّح ويعيد التقديم', async () => {
    await assertSucceeds(
      updateDoc(doc(asApplicant(), 'doctor_applications', APPLICANT), {
        status: 'pending',
        professionalBio:
          'طبيب أسرة، خريج كلية الطب جامعة القاهرة، خبرة ثماني سنوات في '
          + 'الرعاية الأولية ومتابعة الضغط والسكري.',
        updatedAt: serverTimestamp(),
      })
    );
  });

  test('لا يمحو مقدّم الطلب سبب الرفض عند إعادة التقديم', async () => {
    // سجل المراجعة السابق يبقى — وإلا ضاع أثر القرار الإداري.
    await assertFails(
      updateDoc(doc(asApplicant(), 'doctor_applications', APPLICANT), {
        status: 'pending',
        rejectionReason: '',
        updatedAt: serverTimestamp(),
      })
    );
  });

  test('لا يعدّل مقدّم الطلب حقل المراجع', async () => {
    await assertFails(
      updateDoc(doc(asApplicant(), 'doctor_applications', APPLICANT), {
        status: 'pending',
        reviewedBy: APPLICANT,
        updatedAt: serverTimestamp(),
      })
    );
  });

  test('لا يعدّل مقدّم الطلب تاريخ المراجعة', async () => {
    await assertFails(
      updateDoc(doc(asApplicant(), 'doctor_applications', APPLICANT), {
        status: 'pending',
        reviewedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      })
    );
  });

  test('لا يقفز مقدّم الطلب من مرفوض إلى مقبول', async () => {
    await assertFails(
      updateDoc(doc(asApplicant(), 'doctor_applications', APPLICANT), {
        status: 'approved',
        updatedAt: serverTimestamp(),
      })
    );
  });

  test('إعادة التقديم تخضع لفحص الشكل نفسه', async () => {
    await assertFails(
      updateDoc(doc(asApplicant(), 'doctor_applications', APPLICANT), {
        status: 'pending',
        professionalBio: 'قصيرة',
        updatedAt: serverTimestamp(),
      })
    );
  });

  test('لا يعدّل مستخدم آخر طلباً ليس له', async () => {
    await assertFails(
      updateDoc(doc(asOther(), 'doctor_applications', APPLICANT), {
        status: 'pending',
        updatedAt: serverTimestamp(),
      })
    );
  });
});

// ===========================================================================
describe('الطلب المعلّق مقفل على صاحبه', () => {
  beforeEach(() => seedApplication(APPLICANT));

  test('لا يعدّل مقدّم الطلب طلبه أثناء المراجعة', async () => {
    // تعديل الطلب تحت يد المراجع يجعل القرار يقع على نصّ غير الذي قُرئ.
    await assertFails(
      updateDoc(doc(asApplicant(), 'doctor_applications', APPLICANT), {
        specialty: 'جراحة القلب',
        updatedAt: serverTimestamp(),
      })
    );
  });

  test('لا يسحب مقدّم الطلب طلبه بالحذف', async () => {
    await assertFails(
      deleteDoc(doc(asApplicant(), 'doctor_applications', APPLICANT))
    );
  });

  test('لا يحذف المشرف طلباً — السجل يبقى', async () => {
    await assertFails(
      deleteDoc(doc(asAdmin(), 'doctor_applications', APPLICANT))
    );
  });
});

// ===========================================================================
describe('صلاحية الطبيب لا تُمنح من العميل', () => {
  test('لا يرقّي المستخدم نفسه إلى طبيب في مستنده', async () => {
    await assertFails(
      updateDoc(doc(asApplicant(), 'users', APPLICANT), { role: 'doctor' })
    );
  });

  test('لا يكتب المستخدم isVerified في مستنده', async () => {
    await assertFails(
      updateDoc(doc(asApplicant(), 'users', APPLICANT), { isVerified: true })
    );
  });

  test('لا يكتب المستخدم verificationStatus في مستنده', async () => {
    await assertFails(
      updateDoc(doc(asApplicant(), 'users', APPLICANT),
                { verificationStatus: 'approved' })
    );
  });

  test('قبول الطلب وحده لا يجعل مستند المستخدم طبيباً', async () => {
    // الفصل المقصود: القرار يُسجَّل في الطلب، والصلاحية يكتبها الخادم.
    // لو أخفقت الترقية بقي المستخدم مريضاً — يفشل النظام مغلقاً.
    await seedApplication(APPLICANT);
    await updateDoc(doc(asAdmin(), 'doctor_applications', APPLICANT), {
      status: 'approved',
      reviewedBy: ADMIN,
      reviewedAt: serverTimestamp(),
    });

    let role;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDoc(doc(ctx.firestore(), 'users', APPLICANT));
      role = snap.data().role;
    });
    expect(role).toBe('patient');
  });

  test('حتى المشرف لا يكتب دور المستخدم مباشرةً', async () => {
    // الترقية من الخادم وحده. لا مسار عميل يكتب `role` — لأي أحد.
    await assertFails(
      updateDoc(doc(asAdmin(), 'users', APPLICANT), { role: 'doctor' })
    );
  });
});

// ===========================================================================
describe('مجموعة المشرفين وسجل التدقيق', () => {
  test('المشرف يقرأ مستنده ليعرف أنه مشرف', async () => {
    await assertSucceeds(getDoc(doc(asAdmin(), 'admins', ADMIN)));
  });

  test('غير المشرف لا يقرأ مستند مشرف', async () => {
    await assertFails(getDoc(doc(asOther(), 'admins', ADMIN)));
  });

  test('لا يُتصفَّح قائمة المشرفين', async () => {
    await assertFails(getDocs(collection(asAdmin(), 'admins')));
  });

  test('لا يعيّن المستخدم نفسه مشرفاً', async () => {
    // لو نجح هذا لانهار نموذج الصلاحيات كله.
    await assertFails(setDoc(doc(asOther(), 'admins', OTHER), {}));
  });

  test('لا يعيّن المشرف مشرفاً آخر', async () => {
    await assertFails(setDoc(doc(asAdmin(), 'admins', OTHER), {}));
  });

  test('لا يقرأ أحد سجل التدقيق — ولا المشرف', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'audit_logs', 'log_1'),
                   { action: 'approve' });
    });
    await assertFails(getDoc(doc(asAdmin(), 'audit_logs', 'log_1')));
    await assertFails(getDoc(doc(asOther(), 'audit_logs', 'log_1')));
  });

  test('لا يكتب أحد في سجل التدقيق من العميل', async () => {
    await assertFails(
      setDoc(doc(asAdmin(), 'audit_logs', 'forged'), { action: 'approve' })
    );
  });
});
