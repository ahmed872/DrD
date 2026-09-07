/**
 * صحّة قيم مستند المستخدم — الحقول التي يقرأها كل مريض.
 *
 * ## لماذا هذا ليس تدقيقاً تجميلياً
 *
 * قائمة السماح في `users` تقول أي الحقول يجوز كتابتها، ولا تقول شيئاً عن
 * **ما يجوز أن تحمله**. وهذه الحقول بعينها لا تبقى في مستند صاحبها: ينسخها
 * `syncDoctorPublicProfile` إلى `doctor_profiles` الذي يقرأه كل مريض عند فتح
 * الدليل، وينسخها `onMedicalShareWritten` إلى لقطات المشاركات الطبية.
 *
 * فثلاثة أعطال كانت ممكنة من حساب طبيب واحد، وأثرها يقع على **كل** المرضى:
 *
 *   1. `price` نصّاً: الدليل يستدعي `.toDouble()` عليه داخل `map()` على كل
 *      الأطباء. الاستثناء يُرمى مرة واحدة فتفرغ القائمة كلها — مستند واحد
 *      معطوب يُخفي كل الأطباء عن كل المرضى.
 *   2. `sessionDuration == 0`: حلقة توليد الأوقات تضيف صفر دقيقة في كل دورة،
 *      فلا تتقدّم أبداً. شاشة الحجز تتجمّد، و`try/catch` لا يلتقطها لأنها
 *      ليست استثناءً بل حلقة لا تنتهي.
 *   3. نصّ ضخم في `bio`: يُقرأ كاملاً في كل فتح للدليل، وتُنسخ نسخة منه في
 *      كل لقطة مشاركة.
 *
 * شاشة إعدادات الطبيب تفحص الثلاثة — لكنه فحص في العميل، وهو ما يتخطّاه
 * عميل معدَّل أو استدعاء SDK مباشر. هذه الاختبارات تثبت أن الخادم يفحصها.
 */

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { setDoc, updateDoc, doc } = require('firebase/firestore');

let testEnv;

const DOCTOR = 'val_doctor';
const PATIENT = 'val_patient';
const NEWBIE = 'val_newbie';

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'drd-user-values-test',
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
    await setDoc(doc(db, 'users', DOCTOR), {
      role: 'doctor', name: 'د. أحمد', phone: '201000000001',
      specialization: 'باطنة', price: 200, sessionDuration: 30,
      maxPatientsPerSlot: 4, bookingSystemType: 'Individual',
    });
    await setDoc(doc(db, 'users', PATIENT), {
      role: 'patient', name: 'مريض', phone: '201000000002',
    });
  });
});

const as = (uid) => testEnv.authenticatedContext(uid).firestore();
const editDoctor = (patch) => updateDoc(doc(as(DOCTOR), 'users', DOCTOR), patch);

describe('القيم السليمة تمرّ كما كانت', () => {
  test('الطبيب يعدّل بياناته الطبيعية', async () => {
    await assertSucceeds(editDoctor({
      name: 'د. أحمد يوسف',
      bio: 'استشاري باطنة بخبرة 12 عاماً',
      price: 250,
      sessionDuration: 20,
      maxPatientsPerSlot: 6,
      bookingSystemType: 'Grouped',
      workingHours: '09:00 ص - 05:00 م',
      workingDays: { 'السبت (Saturday)': true },
    }));
  });

  test('المريض يعدّل اسمه', async () => {
    await assertSucceeds(
      updateDoc(doc(as(PATIENT), 'users', PATIENT), { name: 'مريض جديد' })
    );
  });

  test('التسجيل يمرّ ببيانات فارغة اختيارية', async () => {
    // `birthDate` و`gender` يُكتبان `null` حين لا يدخلهما المستخدم.
    await assertSucceeds(setDoc(doc(as(NEWBIE), 'users', NEWBIE), {
      role: 'patient',
      name: 'مستخدم جديد',
      phone: '201000000003',
      email: 'new@example.com',
      birthDate: null,
      gender: null,
    }));
  });

  test('قيمة عشرية قديمة للمدة ما زالت مقبولة', async () => {
    // بيانات قديمة قد تحمل 30.0 بدل 30؛ منعُها يحبس صاحبها عن تعديل ملفه.
    await assertSucceeds(editDoctor({ sessionDuration: 30.0 }));
  });
});

describe('١ — السعر: النوع يكسر الدليل لكل المرضى', () => {
  test('سعر نصّي يُرفض', async () => {
    await assertFails(editDoctor({ price: 'مجاناً' }));
  });

  test('سعر منطقي يُرفض', async () => {
    await assertFails(editDoctor({ price: true }));
  });

  test('سعر سالب يُرفض', async () => {
    await assertFails(editDoctor({ price: -100 }));
  });

  test('سعر خيالي يُرفض', async () => {
    await assertFails(editDoctor({ price: 99999999 }));
  });
});

describe('٢ — مدة الجلسة: الصفر يجمّد شاشة الحجز', () => {
  test('صفر يُرفض', async () => {
    await assertFails(editDoctor({ sessionDuration: 0 }));
  });

  test('قيمة سالبة تُرفض', async () => {
    await assertFails(editDoctor({ sessionDuration: -30 }));
  });

  test('نصّ يُرفض', async () => {
    await assertFails(editDoctor({ sessionDuration: '30' }));
  });

  test('مدة أطول من يوم عمل تُرفض', async () => {
    await assertFails(editDoctor({ sessionDuration: 100000 }));
  });

  test('سعة صفر للخانة تُرفض', async () => {
    // سعة صفر تعني خانة لا تقبل أحداً، فيبدو الطبيب متاحاً بلا مواعيد.
    await assertFails(editDoctor({ maxPatientsPerSlot: 0 }));
  });
});

describe('٣ — النصوص الضخمة تتضخّم في كل نسخة', () => {
  const huge = 'ا'.repeat(5000);

  test('نبذة ضخمة تُرفض', async () => {
    await assertFails(editDoctor({ bio: huge }));
  });

  test('اسم ضخم يُرفض', async () => {
    // الاسم يُنسخ في كل لقطة مشاركة وفي الملف العام.
    await assertFails(editDoctor({ name: huge }));
  });

  test('اسم عيادة ضخم يُرفض', async () => {
    await assertFails(editDoctor({ clinicNameAr: huge }));
  });

  test('موقع عيادة ضخم يُرفض', async () => {
    await assertFails(editDoctor({ clinicLocation: huge }));
  });

  test('ساعات عمل ضخمة تُرفض', async () => {
    await assertFails(editDoctor({ workingHours: huge }));
  });

  test('نصّ بطول مقبول يمرّ', async () => {
    await assertSucceeds(editDoctor({ bio: 'ا'.repeat(900) }));
  });
});

describe('٤ — أنواع أخرى', () => {
  test('نظام حجز غير معروف يُرفض', async () => {
    // شاشة الحجز تتفرّع على هذه القيمة؛ قيمة ثالثة تعني سلوكاً غير معرَّف.
    await assertFails(editDoctor({ bookingSystemType: 'Whatever' }));
  });

  test('أيام العمل بغير شكل خريطة تُرفض', async () => {
    await assertFails(editDoctor({ workingDays: 'كل يوم' }));
  });

  test('اسم رقمي يُرفض', async () => {
    await assertFails(editDoctor({ name: 12345 }));
  });

  test('تخصّص ضخم يُرفض', async () => {
    await assertFails(editDoctor({ specialization: 'ب'.repeat(500) }));
  });
});

describe('الحماية القائمة لم تتغيّر', () => {
  test('الدور ما زال غير قابل للكتابة من العميل', async () => {
    await assertFails(
      updateDoc(doc(as(PATIENT), 'users', PATIENT), { role: 'doctor' })
    );
  });

  test('التقييم ما زال من اختصاص الخادم', async () => {
    await assertFails(editDoctor({ rating: 5 }));
  });

  test('لا أحد يعدّل مستند غيره ولو بقيم سليمة', async () => {
    await assertFails(
      updateDoc(doc(as(PATIENT), 'users', DOCTOR), { price: 100 })
    );
  });
});
