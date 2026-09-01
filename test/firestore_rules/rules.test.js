/**
 * اختبارات قواعد أمان Firestore.
 *
 * تعمل على محاكي Firestore الحقيقي، فتُثبت أن القواعد تمنع ما يجب منعه
 * فعلاً — لا بمجرد قراءة الملف.
 *
 *   firebase emulators:exec --only firestore "npm --prefix test/firestore_rules test"
 *
 * اختبارات «المرحلة صفر» تحاكي المسار الحقيقي للتطبيق: الحجز يكتب القفل
 * والموعد في **معاملة واحدة**، ولذلك تُستخدم هنا `writeBatch` و
 * `runTransaction` بدل كتابات منفردة — وإلا لاختُبرت قواعد لا تشبه الواقع.
 */

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  setDoc,
  getDoc,
  updateDoc,
  doc,
  deleteDoc,
  writeBatch,
  runTransaction,
  arrayUnion,
  arrayRemove,
  collection,
  query,
  where,
  getDocs,
} = require('firebase/firestore');

let testEnv;
/** نفس القواعد بعد قلب مفتاح إقفال الحجز المباشر — راجع describe الأخير. */
let lockedEnv;
/** نفس القواعد بعد قلب مفتاح إقفال **الإلغاء** المباشر (المرحلة 1ب). */
let cancelLockedEnv;

const DOCTOR = 'doctor_1';
const GROUP_DOCTOR = 'doctor_grouped';
const UNVERIFIED = 'doctor_unverified';
const PATIENT = 'patient_1';
const OTHER = 'patient_2';
const ADMIN = 'admin_1';

const PATIENT_EMAIL = 'p@example.com';
const OTHER_EMAIL = 'o@example.com';

// نفس صيغة `SlotId` في lib/core/utils/slot_id.dart.
const slotId = (doctorId, date, time) =>
  `${doctorId}_${date}_${time.replace(':', '-')}`;
const apptId = (doctorId, date, time, patientId) =>
  `${slotId(doctorId, date, time)}__${patientId}`;

const BOOKED_SLOT = slotId(DOCTOR, '2030-01-01', '09:00');
const BOOKED_APPT = apptId(DOCTOR, '2030-01-01', '09:00', PATIENT);
const DONE_APPT = apptId(DOCTOR, '2029-01-01', '09:00', PATIENT);

const RULES = fs.readFileSync(
  path.resolve(__dirname, '../../firestore.rules'),
  'utf8'
);

/**
 * نفس ملف القواعد بعد إقفال الحجز المباشر من العميل.
 *
 * الإقفال خطوة نشر مستقلة (لا تُنفَّذ قبل أن يستخدم العميل المنشور الدالة)،
 * لكن سلوكه يجب أن يكون مُثبَتاً قبل ذلك لا بعده. لذلك يُشغَّل نفس الملف
 * مرتين بدل الاحتفاظ بنسختين تتباعدان.
 */
const LOCKED_RULES = RULES.replace(
  'function clientDirectBookingEnabled() { return true; }',
  'function clientDirectBookingEnabled() { return false; }'
);

/**
 * نفس ملف القواعد بعد إقفال الإلغاء المباشر من العميل (المرحلة 1ب) —
 * بمعزل عن مفتاح الحجز، حتى يُثبَت أن كل مفتاح يعمل باستقلال عن الآخر.
 */
const CANCEL_LOCKED_RULES = RULES.replace(
  'function clientDirectCancelEnabled() { return true; }',
  'function clientDirectCancelEnabled() { return false; }'
);

beforeAll(async () => {
  if (LOCKED_RULES === RULES) {
    throw new Error('تعذّر قلب مفتاح clientDirectBookingEnabled — تغيّرت صيغته؟');
  }
  if (CANCEL_LOCKED_RULES === RULES) {
    throw new Error('تعذّر قلب مفتاح clientDirectCancelEnabled — تغيّرت صيغته؟');
  }

  testEnv = await initializeTestEnvironment({
    projectId: 'drd-rules-test',
    firestore: { host: '127.0.0.1', port: 8080, rules: RULES },
  });

  lockedEnv = await initializeTestEnvironment({
    projectId: 'drd-rules-locked',
    firestore: { host: '127.0.0.1', port: 8080, rules: LOCKED_RULES },
  });

  cancelLockedEnv = await initializeTestEnvironment({
    projectId: 'drd-rules-cancel-locked',
    firestore: { host: '127.0.0.1', port: 8080, rules: CANCEL_LOCKED_RULES },
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
  if (lockedEnv) await lockedEnv.cleanup();
  if (cancelLockedEnv) await cancelLockedEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();

  // بذور البيانات تُكتب بتجاوز القواعد، لتمثيل حالة قاعدة بيانات قائمة.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    await setDoc(doc(db, 'users', DOCTOR), {
      role: 'doctor', name: 'د. أحمد', phone: '201000000001',
      email: 'd@example.com', isVerified: true,
      bookingSystemType: 'Individual', sessionDuration: 30, price: 200,
      rating: 4, reviews: 10,
    });
    await setDoc(doc(db, 'users', GROUP_DOCTOR), {
      role: 'doctor', name: 'د. مجمّع', isVerified: true,
      bookingSystemType: 'Grouped', maxPatientsPerSlot: 4,
    });
    // طبيب موجود لكنه لم يُوثَّق بعد — لا يجوز الحجز عنده.
    await setDoc(doc(db, 'users', UNVERIFIED), {
      role: 'doctor', name: 'د. غير موثّق', bookingSystemType: 'Individual',
    });
    await setDoc(doc(db, 'users', PATIENT), {
      role: 'patient', name: 'مريض', phone: '201000000002',
      email: PATIENT_EMAIL, birthDate: '1990-01-01',
    });

    await setDoc(doc(db, 'slots', BOOKED_SLOT), {
      doctorId: DOCTOR, appointmentDate: '2030-01-01', startTime: '09:00',
      capacity: 1, bookedCount: 1, patientIds: [PATIENT],
    });
    await setDoc(doc(db, 'appointments', BOOKED_APPT), {
      doctorId: DOCTOR, patientId: PATIENT, slotId: BOOKED_SLOT,
      appointmentDate: '2030-01-01', startTime: '09:00', status: 'Booked',
      price: 200, notes: '', reason: 'كشف',
    });
    // موعد مكتمل — شرط كتابة المراجعة.
    await setDoc(doc(db, 'appointments', DONE_APPT), {
      doctorId: DOCTOR, patientId: PATIENT, slotId: slotId(DOCTOR, '2029-01-01', '09:00'),
      appointmentDate: '2029-01-01', startTime: '09:00', status: 'Completed',
    });
  });
});

const asPatient = () =>
  testEnv.authenticatedContext(PATIENT, { email: PATIENT_EMAIL }).firestore();
const asOther = () =>
  testEnv.authenticatedContext(OTHER, { email: OTHER_EMAIL }).firestore();
const asDoctor = () => testEnv.authenticatedContext(DOCTOR).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();
// المرحلة 2: `admin` هنا Custom Claim، يُمرَّر كخيار مصادقة تماماً كالبريد —
// نفس ما يحمله رمز Firebase Auth الحقيقي بعد `create_admin.js`.
const asAdminUser = () =>
  testEnv.authenticatedContext(ADMIN, { admin: true }).firestore();

/**
 * حجز كما يفعله التطبيق تماماً: القفل والموعد في معاملة واحدة.
 * يُرجع الوعد ليُمرَّر إلى assertSucceeds/assertFails.
 */
function bookInOneBatch(db, {
  doctorId, patientId, date, time, capacity = 1,
  appointmentIdOverride, slotIdOverride, status = 'Booked',
}) {
  const sid = slotIdOverride || slotId(doctorId, date, time);
  const aid = appointmentIdOverride || `${sid}__${patientId}`;
  const batch = writeBatch(db);
  batch.set(doc(db, 'slots', sid), {
    doctorId, appointmentDate: date, startTime: time,
    capacity, bookedCount: 1, patientIds: [patientId],
  });
  batch.set(doc(db, 'appointments', aid), {
    doctorId, patientId, slotId: sid,
    appointmentDate: date, startTime: time, status,
  });
  return batch.commit();
}

describe('users — إنشاء الحساب والدور', () => {
  test('زائر غير مسجَّل لا يقرأ بيانات أي مريض', async () => {
    // هذا هو الفرق الجوهري عن القاعدة القديمة `allow read: if true`،
    // التي كانت تكشف كل الأسماء والأرقام وتواريخ الميلاد للإنترنت كله.
    await assertFails(getDoc(doc(asAnon(), 'users', PATIENT)));
  });

  test('زائر غير مسجَّل لا ينشئ أي حساب — ولا حساب طبيب', async () => {
    await assertFails(setDoc(doc(asAnon(), 'users', 'anon_doctor'), {
      role: 'doctor', name: 'منتحل',
    }));
  });

  test('مستخدم لا يستطيع إنشاء حسابه بدور طبيب', async () => {
    // الثغرة الأخطر قبل المرحلة صفر: شاشة التسجيل كانت تعرض خيار «طبيب»
    // للجميع، والقاعدة تقبله — فيظهر المنتحل في قائمة الأطباء ويستقبل
    // حجوزات ويقرأ أعراض المرضى.
    await assertFails(setDoc(doc(asOther(), 'users', OTHER), {
      role: 'doctor', name: 'منتحل', email: OTHER_EMAIL,
    }));
  });

  test('إنشاء حساب مريض مسموح', async () => {
    await assertSucceeds(setDoc(doc(asOther(), 'users', OTHER), {
      role: 'patient', name: 'مريض جديد', email: OTHER_EMAIL,
    }));
  });

  test('لا يمكن إنشاء حساب موثَّق ذاتياً', async () => {
    await assertFails(setDoc(doc(asOther(), 'users', OTHER), {
      role: 'patient', name: 'مريض', isVerified: true,
    }));
  });

  test('لا يمكن إنشاء حساب بمعرّف شخص آخر', async () => {
    await assertFails(setDoc(doc(asOther(), 'users', 'someone_else'), {
      role: 'patient', name: 'انتحال',
    }));
  });

  test('مريض لا يقرأ بيانات مريض آخر', async () => {
    await assertFails(getDoc(doc(asOther(), 'users', PATIENT)));
  });

  test('المريض يقرأ مستنده', async () => {
    await assertSucceeds(getDoc(doc(asPatient(), 'users', PATIENT)));
  });

  test('أي مستخدم مسجَّل يقرأ بيانات الأطباء (لازم للحجز)', async () => {
    await assertSucceeds(getDoc(doc(asPatient(), 'users', DOCTOR)));
  });

  test('المريض لا يستطيع ترقية نفسه إلى طبيب', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', PATIENT), {
      role: 'doctor',
    }));
  });

  test('الطبيب لا يستطيع توثيق نفسه', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'users', UNVERIFIED), {
      isVerified: true,
    }));
  });

  test('المستخدم لا يغيّر بريده من العميل', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', PATIENT), {
      email: 'hijack@example.com',
    }));
  });

  test('المريض يعدّل اسمه', async () => {
    await assertSucceeds(updateDoc(doc(asPatient(), 'users', PATIENT), {
      name: 'اسم جديد',
    }));
  });

  test('الطبيب يحفظ إعدادات عيادته', async () => {
    // شاشة إعدادات الطبيب تكتب بـ set(merge: true) — يجب أن تبقى تعمل.
    await assertSucceeds(setDoc(doc(asDoctor(), 'users', DOCTOR), {
      clinicNameAr: 'عيادة النور', specialization: 'أسنان',
      sessionDuration: 20, price: 250, workingHours: '09:00 AM - 05:00 PM',
    }, { merge: true }));
  });
});

describe('تقييم الطبيب (الحقول المجمَّعة) — خادمية بالكامل (المرحلة 4)', () => {
  // حتى المرحلة 3 كانت القواعد تسمح لأي مستخدم مسجَّل بتحديث `rating` و
  // `reviews` على أي طبيب شرط زيادة العدّاد بواحد وقيمة بين 0 و5 — بلا أي
  // ربط بمراجعة حقيقية. أي أن تحريك تقييم طبيب لم يكن يحتاج زيارة، وتكراره
  // يهبط بتقييم منافس إلى الصفر.
  //
  // الآن لا استثناء لأحد: المُجمَّع يتغيّر داخل معاملة `createReview` وحدها.

  test('المريض لا يستطيع تحديث متوسط الطبيب — ولو بزيادة «شرعية»', async () => {
    // كان هذا الطلب بالذات مقبولاً قبل المرحلة 4.
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 4.2, reviews: 11,
    }));
  });

  test('لا يمكن تزوير عدد المراجعات', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 5, reviews: 99999,
    }));
  });

  test('لا يمكن وضع تقييم خارج 0..5', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 99, reviews: 11,
    }));
  });

  test('لا يمكن إنزال تقييم طبيب منافس', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 0, reviews: 11,
    }));
  });

  test('الطبيب لا يرفع تقييم نفسه', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      rating: 5, reviews: 11,
    }));
  });

  test('الطبيب لا يعدّل عدد مراجعاته وحده', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      reviews: 500,
    }));
  });

  test('لا أحد يكتب ratingSum — مجموع النجوم مصدر الحقيقة', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      ratingSum: 9999,
    }));
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      ratingSum: 9999,
    }));
  });

  test('الطبيب يعدّل إعدادات عيادته دون أن يمسّ المُجمَّع', async () => {
    // الإقفال يجب ألا يكسر التعديل المشروع للملف الشخصي.
    await assertSucceeds(setDoc(doc(asDoctor(), 'users', DOCTOR), {
      clinicNameAr: 'عيادة النور', price: 250,
    }, { merge: true }));
  });

  test('لا يمكن تمرير حقول أخرى مع التقييم', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 4.2, reviews: 11, price: 0,
    }));
  });

  test('حتى الأدمن لا يكتب المُجمَّع من العميل', async () => {
    // الإدارة تعمل عبر دوال الخادم؛ لا كتابة مباشرة على المُجمَّع من التطبيق.
    await assertFails(updateDoc(doc(asAdminUser(), 'users', DOCTOR), {
      rating: 5, reviews: 100,
    }));
  });
});

describe('slots — منع الحجز المزدوج', () => {
  test('لا يمكن تجاوز سعة الخانة', async () => {
    // جوهر الضمان: الخانة سعتها 1 ومحجوزة بالفعل.
    await assertFails(updateDoc(doc(asOther(), 'slots', BOOKED_SLOT), {
      bookedCount: 2, patientIds: [PATIENT, OTHER],
    }));
  });

  test('لا يمكن توسيع السعة للتحايل', async () => {
    await assertFails(updateDoc(doc(asOther(), 'slots', BOOKED_SLOT), {
      capacity: 99, bookedCount: 2, patientIds: [PATIENT, OTHER],
    }));
  });

  test('صاحب الحجز يُلغي فيَنقص العدّاد', async () => {
    await assertSucceeds(updateDoc(doc(asPatient(), 'slots', BOOKED_SLOT), {
      bookedCount: 0, patientIds: arrayRemove(PATIENT),
    }));
  });

  test('مستخدم آخر لا يستطيع إنقاص عدّاد خانة ليست له', async () => {
    // كانت هذه الفقرة بلا تحقق هوية إطلاقاً: أي حساب مسجَّل يُفرغ أي خانة،
    // فتبدو متاحة ويُحجز فوقها، أو يُحرم صاحبها من مكانه.
    await assertFails(updateDoc(doc(asOther(), 'slots', BOOKED_SLOT), {
      bookedCount: 0, patientIds: [],
    }));
  });

  describe('خانة مجموعة فيها مريضان', () => {
    const gslot = slotId(GROUP_DOCTOR, '2030-04-04', '10:00');

    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'slots', gslot), {
          doctorId: GROUP_DOCTOR, appointmentDate: '2030-04-04',
          startTime: '10:00', capacity: 4, bookedCount: 2,
          patientIds: [PATIENT, OTHER],
        });
      });
    });

    test('لا يمكن إخراج مريض آخر عند الإلغاء', async () => {
      // OTHER يُلغي حجزه لكنه يحذف PATIENT أيضاً — يُخلي له مكاناً أو
      // يحرمه من موعده بينما يبقى مستند موعده قائماً.
      await assertFails(updateDoc(doc(asOther(), 'slots', gslot), {
        bookedCount: 1, patientIds: [],
      }));
    });

    test('الإلغاء السليم يُخرج صاحب الطلب وحده', async () => {
      await assertSucceeds(updateDoc(doc(asOther(), 'slots', gslot), {
        bookedCount: 1, patientIds: arrayRemove(OTHER),
      }));
    });
  });

  test('الطبيب يدير خانات عيادته', async () => {
    await assertSucceeds(updateDoc(doc(asDoctor(), 'slots', BOOKED_SLOT), {
      bookedCount: 0, patientIds: [],
    }));
  });

  describe('تشديد صلاحيات الطبيب على خانته (المرحلة 1ج)', () => {
    // الاكتشاف: `|| isUser(resource.data.doctorId)` كانت تمنح الطبيب حرية
    // مطلقة على `bookedCount` و`patientIds` — لا حد أعلى، ولا حد أدنى، ولا
    // تحقق من أن أي مريض مُزال كان محجوزاً فعلاً. أُثبت هذا بكتابة فعلية
    // على المحاكي قبل الإصلاح (نجحت كل الحالات أدناه)، وبعده (تُرفض كلها
    // إلا ما يطابق الاستخدام الحقيقي في `cancelAsDoctor`).
    const gslot = slotId(GROUP_DOCTOR, '2030-04-05', '11:00');
    const asGroupDoctor = () =>
      testEnv.authenticatedContext(GROUP_DOCTOR).firestore();

    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'slots', gslot), {
          doctorId: GROUP_DOCTOR, appointmentDate: '2030-04-05',
          startTime: '11:00', capacity: 4, bookedCount: 2,
          patientIds: [PATIENT, OTHER],
        });
      });
    });

    test('الطبيب لا يستطيع تعيين bookedCount بقيمة عشوائية', async () => {
      // BOOKED_SLOT: capacity 1, bookedCount 1 فعلاً.
      await assertFails(updateDoc(doc(asDoctor(), 'slots', BOOKED_SLOT), {
        bookedCount: 999,
      }));
    });

    test('الطبيب لا يستطيع تعيين bookedCount سالباً', async () => {
      await assertFails(updateDoc(doc(asDoctor(), 'slots', BOOKED_SLOT), {
        bookedCount: -1,
      }));
    });

    test('الطبيب لا يستطيع زيادة bookedCount بلا حجز مقابل', async () => {
      // لا يضيف نفسه كمريض (وإلا لطابق فرع الحجز الشرعي — أي مستخدم مسجَّل
      // يحق له حجز نفسه كمريض عند طبيب آخر)؛ فقط يرفع العدّاد وحده.
      await assertFails(updateDoc(doc(asGroupDoctor(), 'slots', gslot), {
        bookedCount: 3,
      }));
    });

    test('الطبيب لا ينقص العدّاد بأكثر من واحد دفعة واحدة', async () => {
      // خانة مجموعة فيها اثنان — محاولة إخلائها بالكامل في تحديث واحد.
      await assertFails(updateDoc(doc(asGroupDoctor(), 'slots', gslot), {
        bookedCount: 0, patientIds: [],
      }));
    });

    test('الطبيب لا يستطيع حقن مريض لم يحجز', async () => {
      await assertFails(updateDoc(doc(asGroupDoctor(), 'slots', gslot), {
        bookedCount: 3, patientIds: [PATIENT, OTHER, 'شخص_لم_يحجز'],
      }));
    });

    test('الطبيب لا يستطيع استبدال patientIds بقائمة أخرى بنفس الطول', async () => {
      await assertFails(updateDoc(doc(asGroupDoctor(), 'slots', gslot), {
        patientIds: ['شخص_مزيَّف_١', 'شخص_مزيَّف_٢'],
      }));
    });

    test('الطبيب لا يستطيع تفريغ الخانة برقم عدّاد لا يطابق الحذف الفعلي', async () => {
      // يحذف مريضاً واحداً من القائمة، لكن يترك bookedCount كما هو —
      // يكسر تطابق bookedCount مع طول patientIds.
      await assertFails(updateDoc(doc(asGroupDoctor(), 'slots', gslot), {
        bookedCount: 2, patientIds: [OTHER],
      }));
    });

    test('الطبيب يزيل مريضاً واحداً بعينه — نفس شكل cancelAsDoctor بالضبط', async () => {
      await assertSucceeds(updateDoc(doc(asGroupDoctor(), 'slots', gslot), {
        bookedCount: 1, patientIds: arrayRemove(PATIENT),
      }));
    });

    test('آخر مريض يغادر يُعيد الخانة صفراً بالكامل', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'slots', gslot), {
          doctorId: GROUP_DOCTOR, appointmentDate: '2030-04-05',
          startTime: '11:00', capacity: 4, bookedCount: 1,
          patientIds: [OTHER],
        });
      });
      await assertSucceeds(updateDoc(doc(asGroupDoctor(), 'slots', gslot), {
        bookedCount: 0, patientIds: arrayRemove(OTHER),
      }));
    });

    test('طبيب آخر لا يستطيع تعديل خانة ليست له', async () => {
      // GROUP_DOCTOR هو صاحب gslot — DOCTOR طبيب آخر تماماً.
      await assertFails(updateDoc(doc(asDoctor(), 'slots', gslot), {
        bookedCount: 1, patientIds: arrayRemove(PATIENT),
      }));
    });

    test('طبيب آخر لا يستطيع حذف خانة ليست له', async () => {
      await assertFails(deleteDoc(doc(asDoctor(), 'slots', gslot)));
    });

    test('حذف خانة فارغة يملكها الطبيب مقبول', async () => {
      const emptySlot = slotId(DOCTOR, '2030-04-06', '09:00');
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'slots', emptySlot), {
          doctorId: DOCTOR, appointmentDate: '2030-04-06', startTime: '09:00',
          capacity: 1, bookedCount: 0, patientIds: [],
        });
      });
      await assertSucceeds(deleteDoc(doc(asDoctor(), 'slots', emptySlot)));
    });

    test('حذف خانة عليها حجز فعلي مرفوض', async () => {
      // BOOKED_SLOT محجوزة فعلاً (bookedCount: 1) — لا يجوز أن تختفي دون
      // المرور بإلغاء الحجز أولاً.
      await assertFails(deleteDoc(doc(asDoctor(), 'slots', BOOKED_SLOT)));
    });

    test('معاملة cancelAsDoctor الحقيقية (موعد + خانة معاً) تنجح بعد التشديد', async () => {
      // نفس المعاملة حرفياً التي تنفّذها BookingService.cancelAsDoctor:
      // قراءة الموعد، ثم تحديث الخانة والموعد معاً في معاملة واحدة. تُثبت
      // أن التشديد لم يكسر الاستخدام الحقيقي، لا مجرّد استدعاءات معزولة.
      const db = asDoctor();
      await assertSucceeds(runTransaction(db, async (tx) => {
        const apptRef = doc(db, 'appointments', BOOKED_APPT);
        const apptSnap = await tx.get(apptRef);
        const slotRef = doc(db, 'slots', apptSnap.data().slotId);
        const slotSnap = await tx.get(slotRef);
        const bookedCount = slotSnap.data().bookedCount;
        tx.update(slotRef, {
          bookedCount: Math.max(0, bookedCount - 1),
          patientIds: arrayRemove(PATIENT),
        });
        tx.update(apptRef, {
          status: 'Cancelled', cancelledAt: new Date(), cancelledBy: 'doctor',
        });
      }));
    });
  });

  test('لا يمكن إنشاء خانة محجوزة باسم شخص آخر', async () => {
    await assertFails(setDoc(
      doc(asOther(), 'slots', slotId(DOCTOR, '2030-03-03', '10:00')), {
        doctorId: DOCTOR, appointmentDate: '2030-03-03', startTime: '10:00',
        capacity: 1, bookedCount: 1, patientIds: [PATIENT],
      }));
  });

  test('لا يمكن رفع السعة عند إنشاء الخانة', async () => {
    // الطبيب فردي، فالسعة المسموحة 1 مهما أرسل العميل.
    await assertFails(setDoc(
      doc(asOther(), 'slots', slotId(DOCTOR, '2030-03-04', '10:00')), {
        doctorId: DOCTOR, appointmentDate: '2030-03-04', startTime: '10:00',
        capacity: 99, bookedCount: 1, patientIds: [OTHER],
      }));
  });

  test('السعة المطابقة لإعدادات طبيب المجموعات مقبولة', async () => {
    await assertSucceeds(setDoc(
      doc(asOther(), 'slots', slotId(GROUP_DOCTOR, '2030-03-05', '10:00')), {
        doctorId: GROUP_DOCTOR, appointmentDate: '2030-03-05',
        startTime: '10:00', capacity: 4, bookedCount: 1, patientIds: [OTHER],
      }));
  });

  test('سعة أكبر من إعدادات طبيب المجموعات مرفوضة', async () => {
    await assertFails(setDoc(
      doc(asOther(), 'slots', slotId(GROUP_DOCTOR, '2030-03-06', '10:00')), {
        doctorId: GROUP_DOCTOR, appointmentDate: '2030-03-06',
        startTime: '10:00', capacity: 40, bookedCount: 1, patientIds: [OTHER],
      }));
  });

  test('معرّف الخانة يجب أن يطابق حقولها', async () => {
    // بمعرّف حر يستطيع المهاجم إنشاء قفل موازٍ لنفس الوقت المحجوز.
    await assertFails(setDoc(doc(asOther(), 'slots', 'random_slot_id'), {
      doctorId: DOCTOR, appointmentDate: '2030-01-01', startTime: '09:00',
      capacity: 1, bookedCount: 1, patientIds: [OTHER],
    }));
  });

  test('لا يمكن إنشاء خانة عند طبيب غير موثَّق', async () => {
    await assertFails(setDoc(
      doc(asOther(), 'slots', slotId(UNVERIFIED, '2030-03-07', '10:00')), {
        doctorId: UNVERIFIED, appointmentDate: '2030-03-07',
        startTime: '10:00', capacity: 1, bookedCount: 1, patientIds: [OTHER],
      }));
  });
});

describe('appointments — الحجز مربوط بقفل', () => {
  test('طرف ثالث لا يقرأ موعد غيره', async () => {
    await assertFails(getDoc(doc(asOther(), 'appointments', BOOKED_APPT)));
  });

  test('المريض والطبيب يقرآن الموعد', async () => {
    await assertSucceeds(getDoc(doc(asPatient(), 'appointments', BOOKED_APPT)));
    await assertSucceeds(getDoc(doc(asDoctor(), 'appointments', BOOKED_APPT)));
  });

  test('المسار الحقيقي: القفل والموعد في معاملة واحدة ينجح', async () => {
    // يُثبت أن `getAfter` في القواعد ترى الخانة المكتوبة في نفس المعاملة،
    // أي أن التشديد لم يكسر الحجز الطبيعي.
    await assertSucceeds(bookInOneBatch(asOther(), {
      doctorId: DOCTOR, patientId: OTHER, date: '2030-06-01', time: '11:00',
    }));
  });

  test('المسار الحقيقي عبر runTransaction ينجح أيضاً', async () => {
    const db = asOther();
    await assertSucceeds(runTransaction(db, async (tx) => {
      const sid = slotId(DOCTOR, '2030-06-02', '12:00');
      const sref = doc(db, 'slots', sid);
      await tx.get(sref);
      tx.set(sref, {
        doctorId: DOCTOR, appointmentDate: '2030-06-02', startTime: '12:00',
        capacity: 1, bookedCount: 1, patientIds: [OTHER],
      });
      tx.set(doc(db, 'appointments', `${sid}__${OTHER}`), {
        doctorId: DOCTOR, patientId: OTHER, slotId: sid,
        appointmentDate: '2030-06-02', startTime: '12:00', status: 'Booked',
      });
    }));
  });

  test('حجز ثانٍ في خانة مجموعة عبر arrayUnion ينجح', async () => {
    const sid = slotId(GROUP_DOCTOR, '2030-07-01', '10:00');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'slots', sid), {
        doctorId: GROUP_DOCTOR, appointmentDate: '2030-07-01',
        startTime: '10:00', capacity: 4, bookedCount: 1,
        patientIds: [PATIENT],
      });
    });

    const db = asOther();
    const batch = writeBatch(db);
    batch.update(doc(db, 'slots', sid), {
      bookedCount: 2, patientIds: arrayUnion(OTHER),
    });
    batch.set(doc(db, 'appointments', `${sid}__${OTHER}`), {
      doctorId: GROUP_DOCTOR, patientId: OTHER, slotId: sid,
      appointmentDate: '2030-07-01', startTime: '10:00', status: 'Booked',
    });
    await assertSucceeds(batch.commit());
  });

  test('موعد بلا قفل خانة مرفوض', async () => {
    // الباب الخلفي الذي كان مفتوحاً: كتابة مستند موعد مباشرة تتخطى القفل
    // كلياً، والطبيب يراه في جدوله لأن الجدول يُقرأ من appointments.
    const sid = slotId(DOCTOR, '2030-05-05', '11:00');
    await assertFails(setDoc(
      doc(asOther(), 'appointments', `${sid}__${OTHER}`), {
        doctorId: DOCTOR, patientId: OTHER, slotId: sid,
        appointmentDate: '2030-05-05', startTime: '11:00', status: 'Booked',
      }));
  });

  test('موعد معلَّق على قفل مريض آخر مرفوض', async () => {
    await assertFails(setDoc(
      doc(asOther(), 'appointments', `${BOOKED_SLOT}__${OTHER}`), {
        doctorId: DOCTOR, patientId: OTHER, slotId: BOOKED_SLOT,
        appointmentDate: '2030-01-01', startTime: '09:00', status: 'Booked',
      }));
  });

  test('معرّف موعد عشوائي مرفوض حتى مع قفل صحيح', async () => {
    // بدون تقييد المعرّف يستطيع مريض تعليق مواعيد متعددة على قفل واحد.
    await assertFails(bookInOneBatch(asOther(), {
      doctorId: DOCTOR, patientId: OTHER, date: '2030-06-03', time: '11:00',
      appointmentIdOverride: 'random_appointment_id',
    }));
  });

  test('لا يمكن إنشاء موعد باسم مريض آخر', async () => {
    await assertFails(bookInOneBatch(asOther(), {
      doctorId: DOCTOR, patientId: PATIENT, date: '2030-06-04', time: '11:00',
    }));
  });

  test('لا يمكن إنشاء موعد بحالة "مكتمل" مباشرة', async () => {
    await assertFails(bookInOneBatch(asOther(), {
      doctorId: DOCTOR, patientId: OTHER, date: '2030-06-05', time: '11:00',
      status: 'Completed',
    }));
  });

  test('لا يمكن الحجز عند طبيب غير موثَّق', async () => {
    await assertFails(bookInOneBatch(asOther(), {
      doctorId: UNVERIFIED, patientId: OTHER, date: '2030-06-06', time: '11:00',
    }));
  });
});

describe('appointments — الحقول المحمية عند التعديل', () => {
  const patientUpdate = (data) =>
    updateDoc(doc(asPatient(), 'appointments', BOOKED_APPT), data);

  test('المريض يلغي موعده', async () => {
    await assertSucceeds(patientUpdate({ status: 'Cancelled' }));
  });

  test('المريض لا يعلّم موعده مكتملاً', async () => {
    await assertFails(patientUpdate({ status: 'Completed' }));
  });

  test('المريض لا يغيّر السعر', async () => {
    await assertFails(patientUpdate({ price: 0 }));
  });

  test('المريض لا يكتب فوق الملاحظة الطبية', async () => {
    // `notes` سجل طبي يكتبه الطبيب — تعديله من المريض تزوير سجل.
    await assertFails(patientUpdate({ notes: 'ملاحظة مزيّفة' }));
  });

  test('المريض لا ينقل الموعد لطبيب آخر', async () => {
    await assertFails(patientUpdate({ doctorId: GROUP_DOCTOR }));
  });

  test('المريض لا ينقل الموعد لمريض آخر', async () => {
    await assertFails(patientUpdate({ patientId: OTHER }));
  });

  test('المريض لا ينقل الموعد لتاريخ آخر', async () => {
    await assertFails(patientUpdate({ appointmentDate: '2030-02-02' }));
  });

  test('المريض لا ينقل الموعد لوقت آخر', async () => {
    await assertFails(patientUpdate({ startTime: '08:00' }));
  });

  test('المريض لا يغيّر قفل الخانة المرتبط', async () => {
    await assertFails(patientUpdate({ slotId: 'other_slot' }));
  });

  test('المريض لا يمرّر حقلاً إضافياً مع الإلغاء', async () => {
    await assertFails(patientUpdate({ status: 'Cancelled', price: 0 }));
  });

  test('الطبيب يُنهي الموعد', async () => {
    await assertSucceeds(updateDoc(
      doc(asDoctor(), 'appointments', BOOKED_APPT), { status: 'Completed' }));
  });

  test('الطبيب يلغي موعد مريضه — نفس الحقول التي تكتبها cancelAsDoctor بالضبط', async () => {
    // يطابق شكل الكتابة في BookingService.cancelAsDoctor حرفياً — لا مجرّد
    // status وحدها. كان cancelledBy مفقوداً من القائمة المسموحة فتُرفض هذه
    // الكتابة بالكامل رغم أن الطبيب يملك حق الإلغاء أصلاً (اكتُشف أثناء
    // بوابة التحقق قبل النشر، المرحلة 1ب).
    await assertSucceeds(updateDoc(
      doc(asDoctor(), 'appointments', BOOKED_APPT), {
        status: 'Cancelled', cancelledAt: new Date(), cancelledBy: 'doctor',
      }));
  });

  test('الطبيب يكتب ملاحظة طبية', async () => {
    await assertSucceeds(updateDoc(
      doc(asDoctor(), 'appointments', BOOKED_APPT), { notes: 'ضغط مرتفع' }));
  });

  test('الطبيب لا يغيّر السعر بعد الحجز', async () => {
    await assertFails(updateDoc(
      doc(asDoctor(), 'appointments', BOOKED_APPT), { price: 9999 }));
  });

  // المرحلة 6: بقيّة الحقول التي لا يجوز للطبيب لمسها من العميل. المسارات
  // الخادمية (`bookAppointment`/`rescheduleAppointment`) وحدها تحرّكها.
  test('الطبيب لا ينقل الموعد إلى تاريخ أو وقت آخر', async () => {
    await assertFails(updateDoc(
      doc(asDoctor(), 'appointments', BOOKED_APPT),
      { appointmentDate: '2030-02-02' }));
    await assertFails(updateDoc(
      doc(asDoctor(), 'appointments', BOOKED_APPT), { startTime: '11:00' }));
  });

  test('الطبيب لا يبدّل هوية المريض ولا ملكية الخانة', async () => {
    await assertFails(updateDoc(
      doc(asDoctor(), 'appointments', BOOKED_APPT), { patientId: OTHER }));
    await assertFails(updateDoc(
      doc(asDoctor(), 'appointments', BOOKED_APPT), { slotId: 'other_slot' }));
    await assertFails(updateDoc(
      doc(asDoctor(), 'appointments', BOOKED_APPT), { doctorId: GROUP_DOCTOR }));
  });

  test('الطبيب لا يكتب حالة خارج القائمة المعتمدة', async () => {
    await assertFails(updateDoc(
      doc(asDoctor(), 'appointments', BOOKED_APPT), { status: 'Refunded' }));
  });

  test('حقل مسموح مع حقل ممنوع في نفس الطلب = رفض', async () => {
    // `hasOnly` تُقيَّم على الطلب كله، فلا يمرّ السعر متسلّلاً مع الملاحظة.
    await assertFails(updateDoc(
      doc(asDoctor(), 'appointments', BOOKED_APPT),
      { notes: 'ملاحظة', price: 1 }));
  });

  test('طرف ثالث لا يعدّل الموعد', async () => {
    await assertFails(updateDoc(
      doc(asOther(), 'appointments', BOOKED_APPT), { status: 'Cancelled' }));
  });

  test('حذف الموعد ممنوع — يبقى السجل كاملاً', async () => {
    await assertFails(deleteDoc(doc(asPatient(), 'appointments', BOOKED_APPT)));
  });
});

describe('phone_index', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'phone_index', '201000000002'), {
        uid: PATIENT, email: PATIENT_EMAIL,
      });
    });
  });

  test('قراءة مدخل واحد متاحة قبل تسجيل الدخول (يلزم للدخول بالرقم)', async () => {
    await assertSucceeds(getDoc(doc(asAnon(), 'phone_index', '201000000002')));
  });

  test('لا يمكن اختطاف مدخل رقم شخص آخر', async () => {
    // لو نجح هذا لاستطاع مهاجم توجيه رقم أي مريض إلى بريده هو، فيمنع صاحب
    // الرقم من تسجيل الدخول نهائياً.
    await assertFails(updateDoc(doc(asOther(), 'phone_index', '201000000002'), {
      uid: OTHER, email: OTHER_EMAIL,
    }));
  });

  test('المستخدم يكتب مدخله عند التسجيل', async () => {
    await assertSucceeds(setDoc(doc(asOther(), 'phone_index', '201000000003'), {
      uid: OTHER, email: OTHER_EMAIL, createdAt: new Date(),
    }));
  });

  test('لا يمكن توجيه رقم إلى بريد ليس بريد صاحب الطلب', async () => {
    await assertFails(setDoc(doc(asOther(), 'phone_index', '201000000004'), {
      uid: OTHER, email: 'someone@example.com',
    }));
  });
});

describe('إعدادات العيادة — حدود لا يكسرها العميل (المرحلة 6)', () => {
  // الطبيب يملك هذه الحقول، لكن القواعد والخادم يقرآنها لبناء الخانات
  // وسعتها. الحدّ الأدنى محروس في الخادم؛ الأعلى لم يكن محروساً في أي مكان.

  test('الإعدادات المعقولة تُحفظ', async () => {
    await assertSucceeds(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      sessionDuration: 20, maxPatientsPerSlot: 6, price: 350,
    }));
  });

  test('سعة خيالية مرفوضة', async () => {
    // بلا سقف يقبل قفل الخانة الواحد مليون معرّف مريض.
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      maxPatientsPerSlot: 1000000,
    }));
  });

  test('مدة جلسة خارج المدى مرفوضة', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      sessionDuration: 1,
    }));
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      sessionDuration: 5000,
    }));
  });

  test('سعر سالب مرفوض', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      price: -1,
    }));
  });

  test('الحقول غير الرقمية لا تُعطّل الحفظ — توافق مع مستندات قديمة', async () => {
    // الخادم يعامل النصّ كقيمة غائبة فيسقط إلى الافتراضي؛ رفضه هنا كان
    // سيكسر أطباء كُتبت مستنداتهم قبل توحيد الأنواع.
    await assertSucceeds(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      sessionDuration: '30',
    }));
  });

  test('أيام الإغلاق تُحفظ', async () => {
    await assertSucceeds(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      closedDates: ['2030-05-01', '2030-05-02'],
    }));
  });

  test('قائمة إغلاق ضخمة مرفوضة', async () => {
    // مستند الطبيب يُقرأ في كل استعلام إتاحة.
    const huge = Array.from({ length: 500 }, (_, i) => `2030-01-${i}`);
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      closedDates: huge,
    }));
  });

  test('الحدود لا تفتح باباً على الحقول المحميّة', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      sessionDuration: 20, isVerified: true, role: 'admin',
    }));
  });
});

describe('التحليلات — لا مسار قراءة جانبي (المرحلة 8)', () => {
  // تحليلات المنصّة تمرّ عبر `getAdminAnalytics` وهي تفحص `token.admin`.
  // هذه الاختبارات تحرس ألّا يوجد **طريق التفاف** عبر القواعد: أي أن
  // المستخدم العادي لا يستطيع جمع نفس الأرقام بقراءة مباشرة.

  test('المستخدم العادي لا يقرأ مستندات المرضى الآخرين', async () => {
    // عدّ المرضى أو تصفّحهم من العميل مستحيل ما دامت القراءة محصورة.
    await assertFails(getDoc(doc(asOther(), 'users', PATIENT)));
  });

  test('المستخدم العادي لا يقرأ طلبات التوثيق', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'doctorApplications', 'app1'), {
        uid: PATIENT, status: 'pending', submittedAt: new Date(),
      });
    });
    await assertFails(getDoc(doc(asPatient(), 'doctorApplications', 'app1')));
    await assertFails(getDoc(doc(asDoctor(), 'doctorApplications', 'app1')));
  });

  test('المدير يقرأ طلبات التوثيق', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'doctorApplications', 'app1'), {
        uid: PATIENT, status: 'pending', submittedAt: new Date(),
      });
    });
    await assertSucceeds(getDoc(doc(asAdminUser(), 'doctorApplications', 'app1')));
  });

  test('المريض لا يقرأ مواعيد مريض آخر — ولو باستعلام مجموعة', async () => {
    // أساس تحليلات المريض: النطاق على الخادم `patientId == uid`، وهنا
    // نتحقّق أن القراءة المباشرة لا تفتح باباً موازياً.
    await assertFails(getDocs(query(
      collection(asOther(), 'appointments'),
      where('patientId', '==', PATIENT),
    )));
  });

  test('الطبيب لا يقرأ مواعيد طبيب آخر', async () => {
    await assertFails(getDocs(query(
      collection(asPatient(), 'appointments'),
      where('doctorId', '==', DOCTOR),
    )));
  });

  test('صاحب النطاق يقرأ نطاقه هو', async () => {
    await assertSucceeds(getDocs(query(
      collection(asPatient(), 'appointments'),
      where('patientId', '==', PATIENT),
    )));
    await assertSucceeds(getDocs(query(
      collection(asDoctor(), 'appointments'),
      where('doctorId', '==', DOCTOR),
    )));
  });

  test('التحليلات لا تفتح أي مسار كتابة', async () => {
    // التحليلات رصد لا سلطة: لا شيء فيها يكتب، والقواعد تبقى كما هي.
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      rating: 5, reviews: 999,
    }));
    await assertFails(updateDoc(
      doc(asDoctor(), 'appointments', BOOKED_APPT), { price: 1 }));
  });
});

describe('ratings — بيانات طبية', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'ratings', 'r1'), {
        appointmentId: BOOKED_APPT, fromUserId: DOCTOR, toUserId: PATIENT,
        ratingType: 'doctor_to_patient', healthConditionRating: 3,
      });
    });
  });

  test('طرف ثالث لا يقرأ تقييم الحالة الصحية لمريض', async () => {
    await assertFails(getDoc(doc(asOther(), 'ratings', 'r1')));
  });

  test('المريض والطبيب يقرآن التقييم', async () => {
    await assertSucceeds(getDoc(doc(asPatient(), 'ratings', 'r1')));
    await assertSucceeds(getDoc(doc(asDoctor(), 'ratings', 'r1')));
  });

  test('لا يمكن كتابة تقييم باسم شخص آخر', async () => {
    await assertFails(setDoc(doc(asOther(), 'ratings', 'r2'), {
      appointmentId: BOOKED_APPT, fromUserId: DOCTOR, toUserId: PATIENT,
      ratingType: 'doctor_to_patient', healthConditionRating: 5,
    }));
  });

  // ===== المرحلة 6: إغلاق ثغرة `doctor_to_patient` =====
  //
  // كانت القاعدة تكتفي بأن الكاتب مسجَّل وأنه لا ينتحل `fromUserId`. فأي
  // مستخدم كان يكتب «تقييم حالة صحية» باسمه إلى أي مستخدم آخر، بلا صفة
  // طبيب وبلا موعد بينهما. هذه الاختبارات تحرس الإغلاق.

  const healthRating = (extra) => ({
    appointmentId: DONE_APPT, fromUserId: DOCTOR, toUserId: PATIENT,
    ratingType: 'doctor_to_patient', healthConditionRating: 4,
    healthConditionComment: 'ملاحظة', ...extra,
  });

  test('غير المسجَّل لا يكتب تقييماً صحياً', async () => {
    await assertFails(setDoc(doc(asAnon(), 'ratings', 'new'), healthRating()));
  });

  test('المريض لا يكتب تقييماً صحياً عن نفسه', async () => {
    // العطب الأصلي بالضبط: مستخدم عادي يكتب مستنداً يبدو ملاحظة طبية.
    await assertFails(setDoc(doc(asPatient(), 'ratings', 'new'), healthRating({
      fromUserId: PATIENT, toUserId: DOCTOR,
    })));
  });

  test('مستخدم غريب لا يكتب تقييماً صحياً عن مريض لا يعرفه', async () => {
    await assertFails(setDoc(doc(asOther(), 'ratings', 'new'), healthRating({
      fromUserId: OTHER, toUserId: PATIENT,
    })));
  });

  test('الطبيب يكتب تقييماً صحياً لمريضه في موعد حقيقي', async () => {
    await assertSucceeds(
      setDoc(doc(asDoctor(), 'ratings', 'new'), healthRating()),
    );
  });

  test('الطبيب لا يكتبه لمريض ليس طرفاً في ذلك الموعد', async () => {
    await assertFails(setDoc(doc(asDoctor(), 'ratings', 'new'), healthRating({
      toUserId: OTHER,
    })));
  });

  test('الطبيب لا يكتبه على موعد غير موجود', async () => {
    await assertFails(setDoc(doc(asDoctor(), 'ratings', 'new'), healthRating({
      appointmentId: 'appointment_does_not_exist',
    })));
  });

  test('حقل الدور المزوَّر في المستند لا ينفع', async () => {
    // الصفة تُقرأ من مستند المستخدم، لا مما يرسله الكاتب.
    await assertFails(setDoc(doc(asPatient(), 'ratings', 'new'), healthRating({
      fromUserId: PATIENT, toUserId: OTHER, role: 'doctor', isDoctor: true,
    })));
  });

  test('الطبيب الموقوف لا يكتب ملاحظة صحية جديدة', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', DOCTOR), {
        role: 'doctor', isVerified: true, disabled: true,
      }, { merge: true });
    });
    await assertFails(setDoc(doc(asDoctor(), 'ratings', 'new'), healthRating()));
  });

  test('تقييم المريض للخدمة يبقى مسموحاً على موعده', async () => {
    await assertSucceeds(setDoc(doc(asPatient(), 'ratings', 'new'), {
      appointmentId: DONE_APPT, fromUserId: PATIENT, toUserId: DOCTOR,
      ratingType: 'patient_to_doctor', serviceRating: 5, serviceComment: 'ممتاز',
    }));
  });

  test('المريض لا يقيّم خدمة طبيب لا موعد له عنده', async () => {
    await assertFails(setDoc(doc(asOther(), 'ratings', 'new'), {
      appointmentId: DONE_APPT, fromUserId: OTHER, toUserId: DOCTOR,
      ratingType: 'patient_to_doctor', serviceRating: 5,
    }));
  });

  test('تقييم الخدمة لا يحمل حقولاً صحّية', async () => {
    // وإلا صار الباب معكوساً: مستند «طبي» كتبه غير طبيب.
    await assertFails(setDoc(doc(asPatient(), 'ratings', 'new'), {
      appointmentId: DONE_APPT, fromUserId: PATIENT, toUserId: DOCTOR,
      ratingType: 'patient_to_doctor', serviceRating: 5,
      healthConditionComment: 'تشخيص مزيَّف',
    }));
  });

  test('لا يُحوَّل تقييم خدمة قائم إلى تقييم صحي بالتعديل', async () => {
    // بدون تثبيت `ratingType` و`appointmentId` يلتفّ المريض على قاعدة
    // الإنشاء كلها: يكتب تقييم خدمة مشروعاً ثم يبدّل نوعه.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'ratings', 'svc'), {
        appointmentId: DONE_APPT, fromUserId: PATIENT, toUserId: DOCTOR,
        ratingType: 'patient_to_doctor', serviceRating: 5,
      });
    });
    await assertFails(updateDoc(doc(asPatient(), 'ratings', 'svc'), {
      ratingType: 'doctor_to_patient', healthConditionRating: 1,
    }));
    await assertFails(updateDoc(doc(asPatient(), 'ratings', 'svc'), {
      appointmentId: BOOKED_APPT,
    }));
  });

  test('صاحب التقييم يعدّل محتواه ضمن نوعه', async () => {
    await assertSucceeds(updateDoc(doc(asDoctor(), 'ratings', 'r1'), {
      healthConditionRating: 5,
    }));
  });

  test('طرف ثالث لا يعدّل تقييماً ليس له', async () => {
    await assertFails(updateDoc(doc(asOther(), 'ratings', 'r1'), {
      healthConditionRating: 1,
    }));
  });
});

describe('reviews — الكتابة من الخادم وحده (المرحلة 4)', () => {
  // كانت القواعد تسمح للمريض بكتابة مراجعته مباشرة بعد التحقق من زيارة
  // مكتملة. ذلك أغلق «مراجعة بلا زيارة»، لكن بقيت ثلاث فجوات لا تسدّها
  // قاعدة: لا ذرّية بين المراجعة والمُجمَّع، والمتوسط يُحسب على العميل،
  // وإعادة الإرسال ترفع العدّاد مرتين.
  //
  // الآن `createReview` (Admin SDK) هي المسار الوحيد، وكل كتابة من العميل
  // مرفوضة — حتى الصحيحة منها، فوجود بابين لنفس الغرض يعني أن أضعفهما هو
  // الذي سيُستخدم.

  const review = (extra = {}) => ({
    doctorId: DOCTOR, patientId: PATIENT, appointmentId: DONE_APPT,
    rating: 5, comment: 'ممتاز', ...extra,
  });

  const seedReview = async (extra = {}) => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'reviews', DONE_APPT), review(extra));
    });
  };

  test('المريض لا يكتب مراجعته مباشرة — ولو عن زيارة مكتملة فعلاً', async () => {
    // كان هذا الطلب بالذات مقبولاً قبل المرحلة 4.
    await assertFails(
      setDoc(doc(asPatient(), 'reviews', DONE_APPT), review()));
  });

  test('مراجعة بلا موعد مكتمل مرفوضة', async () => {
    await assertFails(setDoc(doc(asPatient(), 'reviews', BOOKED_APPT),
      review({ appointmentId: BOOKED_APPT })));
  });

  test('مراجعة عن موعد شخص آخر مرفوضة', async () => {
    await assertFails(setDoc(doc(asOther(), 'reviews', DONE_APPT),
      review({ patientId: OTHER })));
  });

  test('مراجعة عن موعد غير موجود مرفوضة', async () => {
    await assertFails(setDoc(doc(asPatient(), 'reviews', 'ghost_appt'),
      review({ appointmentId: 'ghost_appt' })));
  });

  test('مراجعة لطبيب غير طبيب الموعد مرفوضة', async () => {
    await assertFails(setDoc(doc(asPatient(), 'reviews', DONE_APPT),
      review({ doctorId: GROUP_DOCTOR })));
  });

  test('معرّف مراجعة عشوائي مرفوض', async () => {
    await assertFails(setDoc(doc(asPatient(), 'reviews', 'rev_random'),
      review()));
  });

  test('التقييم خارج 1..5 مرفوض', async () => {
    await assertFails(setDoc(doc(asPatient(), 'reviews', DONE_APPT),
      review({ rating: 100 })));
  });

  test('الطبيب لا يكتب مراجعة لنفسه', async () => {
    await assertFails(setDoc(doc(asDoctor(), 'reviews', DONE_APPT),
      review({ patientId: DOCTOR })));
  });

  test('حتى الأدمن لا يكتب مراجعة من العميل', async () => {
    await assertFails(setDoc(doc(asAdminUser(), 'reviews', DONE_APPT), review()));
  });

  test('لا مراجعة ثانية لنفس الموعد من شخص آخر', async () => {
    await seedReview();
    await assertFails(setDoc(doc(asOther(), 'reviews', DONE_APPT),
      review({ patientId: OTHER })));
  });

  // ===== المراجعة غير قابلة للتعديل بعد كتابتها =====

  test('صاحب المراجعة لا يعدّل نجومه بعد الإرسال', async () => {
    await seedReview();
    await assertFails(updateDoc(doc(asPatient(), 'reviews', DONE_APPT), {
      rating: 4, comment: 'جيد',
    }));
  });

  test('لا يمكن تعديل هوية الموعد أو الطبيب أو المريض', async () => {
    await seedReview();
    const db = asPatient();
    await assertFails(updateDoc(doc(db, 'reviews', DONE_APPT), {
      doctorId: GROUP_DOCTOR,
    }));
    await assertFails(updateDoc(doc(db, 'reviews', DONE_APPT), {
      patientId: OTHER,
    }));
    await assertFails(updateDoc(doc(db, 'reviews', DONE_APPT), {
      appointmentId: BOOKED_APPT,
    }));
  });

  test('لا يمكن تزوير verifiedVisit', async () => {
    await seedReview();
    await assertFails(updateDoc(doc(asPatient(), 'reviews', DONE_APPT), {
      verifiedVisit: true,
    }));
    await assertFails(setDoc(doc(asPatient(), 'reviews', 'forged_visit'),
      review({ appointmentId: 'forged_visit', verifiedVisit: true })));
  });

  test('لا يمكن تزوير createdAt', async () => {
    await seedReview();
    await assertFails(updateDoc(doc(asPatient(), 'reviews', DONE_APPT), {
      createdAt: new Date('2020-01-01'),
    }));
  });

  test('مريض آخر لا يعدّل مراجعة غيره', async () => {
    await seedReview();
    await assertFails(updateDoc(doc(asOther(), 'reviews', DONE_APPT), {
      rating: 1,
    }));
  });

  test('الطبيب لا يعدّل مراجعة كُتبت عنه', async () => {
    await seedReview();
    await assertFails(updateDoc(doc(asDoctor(), 'reviews', DONE_APPT), {
      rating: 5, comment: 'ممتاز جداً',
    }));
  });

  // ===== الحذف =====

  test('لا أحد يحذف مراجعة من العميل', async () => {
    await seedReview();
    await assertFails(deleteDoc(doc(asPatient(), 'reviews', DONE_APPT)));
    await assertFails(deleteDoc(doc(asOther(), 'reviews', DONE_APPT)));
    await assertFails(deleteDoc(doc(asDoctor(), 'reviews', DONE_APPT)));
    await assertFails(deleteDoc(doc(asAdminUser(), 'reviews', DONE_APPT)));
  });

  // ===== القراءة =====

  test('المستخدم المسجَّل يقرأ المراجعات — جزء من اختيار الطبيب', async () => {
    await seedReview();
    await assertSucceeds(getDoc(doc(asOther(), 'reviews', DONE_APPT)));
    await assertSucceeds(getDoc(doc(asDoctor(), 'reviews', DONE_APPT)));
  });

  test('غير المسجَّل لا يقرأ المراجعات', async () => {
    await seedReview();
    await assertFails(getDoc(doc(asAnon(), 'reviews', DONE_APPT)));
  });

  test('مستند المراجعة لا يحمل هاتف المريض ولا بريده', async () => {
    // ما يكتبه الخادم (functions/reviews.js) لا يتضمّن أياً منهما؛ هذا
    // الاختبار يحرس ذلك من انحدار مستقبلي في شكل المستند.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'reviews', DONE_APPT), {
        appointmentId: DONE_APPT, doctorId: DOCTOR, patientId: PATIENT,
        patientName: 'مريض', rating: 5, comment: 'ممتاز',
        verifiedVisit: true, createdAt: new Date(),
      });
    });
    const snap = await getDoc(doc(asOther(), 'reviews', DONE_APPT));
    const data = snap.data();
    expect(data.patientPhone).toBeUndefined();
    expect(data.patientEmail).toBeUndefined();
    expect(data.notes).toBeUndefined();
  });
});

describe('notifications', () => {
  test('العميل لا يستطيع إنشاء إشعار باسم العيادة', async () => {
    await assertFails(setDoc(doc(asOther(), 'notifications', 'n1'), {
      userId: PATIENT, title: 'رسالة مزيّفة', body: 'احضر الآن', read: false,
    }));
  });

  test('العميل لا يستطيع إنشاء إشعار حتى بالحقل الجديد recipientId', async () => {
    await assertFails(setDoc(doc(asPatient(), 'notifications', 'n_new'), {
      recipientId: PATIENT, recipientRole: 'patient', type: 'booking_confirmed',
      title: 'مزيّف', body: 'مزيّف', isRead: false,
    }));
  });

  describe('إشعار قائم (recipientId)', () => {
    const NOTIF_ID = 'notif_1';
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'notifications', NOTIF_ID), {
          recipientId: PATIENT, recipientRole: 'patient',
          type: 'booking_confirmed', title: 'تم التأكيد', body: '...',
          appointmentId: 'appt_x', isRead: false, createdAt: new Date(),
          readAt: null,
        });
      });
    });

    test('المستلم يقرأ إشعاره', async () => {
      await assertSucceeds(getDoc(doc(asPatient(), 'notifications', NOTIF_ID)));
    });

    test('مستخدم آخر لا يقرأ إشعار ليس له', async () => {
      await assertFails(getDoc(doc(asOther(), 'notifications', NOTIF_ID)));
    });

    test('المستلم يعلّم إشعاره كمقروء', async () => {
      await assertSucceeds(updateDoc(doc(asPatient(), 'notifications', NOTIF_ID), {
        isRead: true, readAt: new Date(),
      }));
    });

    test('مستخدم آخر لا يستطيع تعليم إشعار ليس له كمقروء', async () => {
      await assertFails(updateDoc(doc(asOther(), 'notifications', NOTIF_ID), {
        isRead: true,
      }));
    });

    test('المستلم لا يستطيع تغيير recipientId', async () => {
      await assertFails(updateDoc(doc(asPatient(), 'notifications', NOTIF_ID), {
        recipientId: OTHER,
      }));
    });

    test('المستلم لا يستطيع تغيير type', async () => {
      await assertFails(updateDoc(doc(asPatient(), 'notifications', NOTIF_ID), {
        type: 'booking_cancelled',
      }));
    });

    test('المستلم لا يستطيع تغيير body أو title', async () => {
      await assertFails(updateDoc(doc(asPatient(), 'notifications', NOTIF_ID), {
        body: 'نص مزيَّف',
      }));
    });

    test('المستلم لا يستطيع تغيير appointmentId', async () => {
      await assertFails(updateDoc(doc(asPatient(), 'notifications', NOTIF_ID), {
        appointmentId: 'appt_other',
      }));
    });

    test('المستلم لا يستطيع تغيير createdAt', async () => {
      await assertFails(updateDoc(doc(asPatient(), 'notifications', NOTIF_ID), {
        createdAt: new Date('2020-01-01'),
      }));
    });

    test('لا يمكن تمرير حقل ممنوع مع isRead في نفس الطلب', async () => {
      await assertFails(updateDoc(doc(asPatient(), 'notifications', NOTIF_ID), {
        isRead: true, type: 'booking_cancelled',
      }));
    });

    test('طرف آخر لا يستطيع حذف إشعار ليس له', async () => {
      await assertFails(deleteDoc(doc(asOther(), 'notifications', NOTIF_ID)));
    });

    test('المستلم يستطيع حذف إشعاره', async () => {
      await assertSucceeds(deleteDoc(doc(asPatient(), 'notifications', NOTIF_ID)));
    });
  });
});

describe('users/{uid}/devices — رموز Push (المرحلة 3)', () => {
  const deviceDoc = () => doc(asPatient(), 'users', PATIENT, 'devices', 'token_abc');

  test('المستخدم يسجّل جهازه الخاص', async () => {
    await assertSucceeds(setDoc(deviceDoc(), {
      token: 'token_abc', platform: 'android', updatedAt: new Date(),
    }));
  });

  test('لا يمكن تسجيل رمز بلا platform صالحة', async () => {
    await assertFails(setDoc(deviceDoc(), {
      token: 'token_abc', platform: 'windows', updatedAt: new Date(),
    }));
  });

  test('لا يمكن تسجيل رمز فارغ', async () => {
    await assertFails(setDoc(deviceDoc(), {
      token: '', platform: 'android', updatedAt: new Date(),
    }));
  });

  test('مستخدم لا يستطيع تسجيل جهاز باسم مستخدم آخر', async () => {
    await assertFails(setDoc(
      doc(asOther(), 'users', PATIENT, 'devices', 'token_xyz'), {
        token: 'token_xyz', platform: 'ios', updatedAt: new Date(),
      }));
  });

  describe('جهاز مسجَّل', () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'users', PATIENT, 'devices', 'token_abc'), {
          token: 'token_abc', platform: 'android', updatedAt: new Date(),
        });
      });
    });

    test('صاحب الجهاز يقرأ قائمة أجهزته', async () => {
      await assertSucceeds(getDoc(deviceDoc()));
    });

    test('مستخدم آخر لا يقرأ أجهزة غيره', async () => {
      await assertFails(getDoc(doc(asOther(), 'users', PATIENT, 'devices', 'token_abc')));
    });

    test('مستخدم آخر لا يستطيع الكتابة فوق رمز مستخدم آخر', async () => {
      await assertFails(setDoc(
        doc(asOther(), 'users', PATIENT, 'devices', 'token_abc'), {
          token: 'token_abc', platform: 'ios', updatedAt: new Date(),
        }));
    });

    test('صاحب الجهاز يحذف رمزه (تسجيل خروج مثلاً)', async () => {
      await assertSucceeds(deleteDoc(deviceDoc()));
    });

    test('مستخدم آخر لا يستطيع حذف رمز ليس له', async () => {
      await assertFails(deleteDoc(doc(asOther(), 'users', PATIENT, 'devices', 'token_abc')));
    });
  });
});

describe('users — لا ترقية ذاتية عبر حقول توثيق الطبيب الجديدة (المرحلة 2)', () => {
  // `role` و`isVerified` كانا محميين بالفعل. هذه تُثبت أن `disabled` و
  // `verificationStatus` — الحقلين اللذين يقرّران الأهلية الفعلية للحجز —
  // محميان بنفس الصرامة، وأن لا مسار عميل يعيد تفعيل طبيب موقوف بنفسه.
  test('طبيب موقوف لا يستطيع إعادة تفعيل نفسه بتحديث ملفه', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', DOCTOR), {
        role: 'doctor', name: 'د. أحمد', isVerified: true, disabled: true,
        verificationStatus: 'suspended', suspensionReason: 'شكوى',
      });
    });
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      disabled: false,
    }));
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      verificationStatus: 'approved',
    }));
  });

  test('طبيب لا يستطيع تزوير سجل التحقق (verifiedBy) لنفسه', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      verifiedBy: DOCTOR, verifiedAt: new Date(),
    }));
  });

  test('تعديل حقل عادي (الاسم) لا يزال يعمل رغم الحماية الجديدة', async () => {
    await assertSucceeds(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      name: 'د. أحمد المحدَّث',
    }));
  });
});

describe('doctorApplications — طلب توثيق الطبيب (المرحلة 2)', () => {
  test('مريض يقدّم طلباً صحيحاً', async () => {
    await assertSucceeds(setDoc(doc(asPatient(), 'doctorApplications', PATIENT), {
      uid: PATIENT, status: 'pending', specialization: 'أسنان',
      note: 'خبرة 5 سنوات', submittedAt: new Date(),
    }));
  });

  test('لا يمكن التقديم بمعرّف مستخدم آخر', async () => {
    await assertFails(setDoc(doc(asOther(), 'doctorApplications', PATIENT), {
      uid: PATIENT, status: 'pending', specialization: 'أسنان',
    }));
  });

  test('لا يمكن التقديم بحالة غير pending (تجاوز المراجعة مباشرة)', async () => {
    await assertFails(setDoc(doc(asPatient(), 'doctorApplications', PATIENT), {
      uid: PATIENT, status: 'approved', specialization: 'أسنان',
    }));
  });

  test('التخصص إلزامي', async () => {
    await assertFails(setDoc(doc(asPatient(), 'doctorApplications', PATIENT), {
      uid: PATIENT, status: 'pending', specialization: '',
    }));
  });

  test('لا يمكن تمرير حقل إداري عند التقديم الأول', async () => {
    await assertFails(setDoc(doc(asPatient(), 'doctorApplications', PATIENT), {
      uid: PATIENT, status: 'pending', specialization: 'أسنان',
      reviewedBy: PATIENT, // محاولة اعتماد نفسه مسبقاً.
    }));
  });

  describe('طلب قائم', () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'doctorApplications', PATIENT), {
          uid: PATIENT, status: 'pending', specialization: 'أسنان',
          submittedAt: new Date(),
        });
      });
    });

    test('صاحب الطلب يقرأ طلبه', async () => {
      await assertSucceeds(getDoc(doc(asPatient(), 'doctorApplications', PATIENT)));
    });

    test('مستخدم آخر لا يقرأ طلب غيره', async () => {
      await assertFails(getDoc(doc(asOther(), 'doctorApplications', PATIENT)));
    });

    test('الإدارة تقرأ أي طلب', async () => {
      await assertSucceeds(getDoc(doc(asAdminUser(), 'doctorApplications', PATIENT)));
    });

    test('صاحب الطلب يعدّل نص طلبه أثناء الانتظار', async () => {
      await assertSucceeds(updateDoc(doc(asPatient(), 'doctorApplications', PATIENT), {
        specialization: 'عظام', status: 'pending',
      }));
    });

    // «application cannot self-approve» — لا مسار عميل، حتى صاحب الطلب
    // نفسه، يستطيع كتابة status: approved مباشرة.
    test('صاحب الطلب لا يستطيع اعتماد طلبه لنفسه', async () => {
      await assertFails(updateDoc(doc(asPatient(), 'doctorApplications', PATIENT), {
        status: 'approved',
      }));
    });

    test('طرف آخر لا يستطيع تعديل طلب ليس له', async () => {
      await assertFails(updateDoc(doc(asOther(), 'doctorApplications', PATIENT), {
        specialization: 'عظام',
      }));
    });

    test('الإدارة (عبر العميل مباشرة) لا تستطيع اعتماد الطلب — الاعتماد عبر Admin SDK فقط', async () => {
      // `isAdmin()` يمنح القراءة فقط هنا؛ الكتابة الإدارية تمر حصراً بـ
      // `approveDoctor`/`rejectDoctor` اللتين تعملان بـ Admin SDK وتتجاوزان
      // القواعد أصلاً — لا حاجة لفتح مسار كتابة إداري مباشر في القواعد.
      await assertFails(updateDoc(doc(asAdminUser(), 'doctorApplications', PATIENT), {
        status: 'approved',
      }));
    });

    test('حذف الطلب ممنوع', async () => {
      await assertFails(deleteDoc(doc(asPatient(), 'doctorApplications', PATIENT)));
    });
  });

  describe('طلب مرفوض سابقاً', () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'doctorApplications', PATIENT), {
          uid: PATIENT, status: 'rejected', specialization: 'أسنان',
          submittedAt: new Date(), reviewedAt: new Date(),
          reviewedBy: ADMIN, rejectionReason: 'بيانات ناقصة',
        });
      });
    });

    test('صاحب الطلب يعيد التقديم فتعود الحالة pending', async () => {
      await assertSucceeds(updateDoc(doc(asPatient(), 'doctorApplications', PATIENT), {
        status: 'pending', specialization: 'أسنان وفكّ',
      }));
    });

    test('إعادة التقديم لا تمسّ سجل الرفض السابق', async () => {
      await updateDoc(doc(asPatient(), 'doctorApplications', PATIENT), {
        status: 'pending', specialization: 'أسنان وفكّ',
      });
      // صاحب الطلب نفسه يقرأ — لا حاجة لتعطيل القواعد لمجرد القراءة.
      const snap = await getDoc(doc(asPatient(), 'doctorApplications', PATIENT));
      expect(snap.data().rejectionReason).toBe('بيانات ناقصة');
      expect(snap.data().reviewedBy).toBe(ADMIN);
    });

    test('محاولة تزوير سجل الرفض أثناء إعادة التقديم مرفوضة', async () => {
      await assertFails(updateDoc(doc(asPatient(), 'doctorApplications', PATIENT), {
        status: 'pending', rejectionReason: 'لم يُرفض أصلاً',
      }));
    });
  });
});

describe('auditLogs — سجل التدقيق (المرحلة 2)', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'auditLogs', 'log_1'), {
        actorAdminId: ADMIN, action: 'doctor.approved',
        targetType: 'doctor', targetId: PATIENT, metadata: {},
      });
    });
  });

  test('الإدارة تقرأ السجل', async () => {
    await assertSucceeds(getDoc(doc(asAdminUser(), 'auditLogs', 'log_1')));
  });

  test('مستخدم عادي لا يقرأ السجل', async () => {
    await assertFails(getDoc(doc(asPatient(), 'auditLogs', 'log_1')));
  });

  test('طبيب لا يقرأ السجل', async () => {
    await assertFails(getDoc(doc(asDoctor(), 'auditLogs', 'log_1')));
  });

  // client cannot fabricate/modify/delete — حتى صاحب claim إداري لا يكتب
  // من العميل، لأن الكتابة الحقيقية تمر بـ Admin SDK داخل المعاملة نفسها
  // التي تنفّذ الإجراء، لا بكتابة منفصلة يمكن تزييفها.
  test('لا أحد — ولا حتى الإدارة من العميل — يستطيع إنشاء سجل تدقيق', async () => {
    await assertFails(setDoc(doc(asAdminUser(), 'auditLogs', 'fake'), {
      actorAdminId: ADMIN, action: 'doctor.approved',
      targetType: 'doctor', targetId: OTHER, metadata: {},
    }));
  });

  test('لا يمكن تعديل سجل قائم', async () => {
    await assertFails(updateDoc(doc(asAdminUser(), 'auditLogs', 'log_1'), {
      action: 'doctor.rejected',
    }));
  });

  test('لا يمكن حذف سجل', async () => {
    await assertFails(deleteDoc(doc(asAdminUser(), 'auditLogs', 'log_1')));
  });
});

describe('بعد إقفال الحجز المباشر (المرحلة 1أ)', () => {
  // الحالة النهائية بعد نشر الدالة والتحقق منها: الحجز من الخادم وحده.
  // Admin SDK يتجاوز القواعد، فالدالة تعمل بينما يُمنع العميل.

  const lockedAs = (uid, email) =>
    lockedEnv.authenticatedContext(uid, email ? { email } : {}).firestore();

  beforeEach(async () => {
    await lockedEnv.clearFirestore();
    await lockedEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users', DOCTOR), {
        role: 'doctor', name: 'د. أحمد', isVerified: true,
        bookingSystemType: 'Individual', price: 200,
      });
      await setDoc(doc(db, 'users', PATIENT), {
        role: 'patient', name: 'مريض', email: PATIENT_EMAIL,
      });
      await setDoc(doc(db, 'slots', BOOKED_SLOT), {
        doctorId: DOCTOR, appointmentDate: '2030-01-01', startTime: '09:00',
        capacity: 4, bookedCount: 1, patientIds: [PATIENT],
      });
      await setDoc(doc(db, 'appointments', BOOKED_APPT), {
        doctorId: DOCTOR, patientId: PATIENT, slotId: BOOKED_SLOT,
        appointmentDate: '2030-01-01', startTime: '09:00', status: 'Booked',
        price: 200, notes: '',
      });
    });
  });

  test('العميل لا يستطيع إنشاء موعد مباشرة — ولو بقفل صحيح', async () => {
    const db = lockedAs(OTHER, OTHER_EMAIL);
    const sid = slotId(DOCTOR, '2030-08-08', '09:00');
    const batch = writeBatch(db);
    batch.set(doc(db, 'slots', sid), {
      doctorId: DOCTOR, appointmentDate: '2030-08-08', startTime: '09:00',
      capacity: 1, bookedCount: 1, patientIds: [OTHER],
    });
    batch.set(doc(db, 'appointments', `${sid}__${OTHER}`), {
      doctorId: DOCTOR, patientId: OTHER, slotId: sid,
      appointmentDate: '2030-08-08', startTime: '09:00', status: 'Booked',
    });
    await assertFails(batch.commit());
  });

  test('العميل لا يستطيع إنشاء قفل خانة', async () => {
    await assertFails(setDoc(
      doc(lockedAs(OTHER), 'slots', slotId(DOCTOR, '2030-08-09', '09:00')), {
        doctorId: DOCTOR, appointmentDate: '2030-08-09', startTime: '09:00',
        capacity: 1, bookedCount: 1, patientIds: [OTHER],
      }));
  });

  test('العميل لا يستطيع زيادة عدّاد خانة', async () => {
    await assertFails(updateDoc(doc(lockedAs(OTHER), 'slots', BOOKED_SLOT), {
      bookedCount: 2, patientIds: arrayUnion(OTHER),
    }));
  });

  test('العميل لا يستطيع الحجز عبر خانة شخص آخر', async () => {
    await assertFails(setDoc(
      doc(lockedAs(OTHER), 'appointments', `${BOOKED_SLOT}__${OTHER}`), {
        doctorId: DOCTOR, patientId: OTHER, slotId: BOOKED_SLOT,
        appointmentDate: '2030-01-01', startTime: '09:00', status: 'Booked',
      }));
  });

  test('العميل لا يستطيع تجاوز التوثيق بأي حال', async () => {
    const db = lockedAs(PATIENT, PATIENT_EMAIL);
    // ترقية ذاتية كاملة.
    await assertFails(updateDoc(doc(db, 'users', PATIENT), {
      role: 'doctor', isVerified: true,
    }));
    // ثم توثيق ذاتي وحده.
    await assertFails(updateDoc(doc(db, 'users', PATIENT), {
      isVerified: true,
    }));
    // ولا حتى بإنشاء مستند جديد بدور طبيب.
    await assertFails(setDoc(doc(db, 'users', 'brand_new_doctor'), {
      role: 'doctor', isVerified: true, name: 'منتحل',
    }));
  });

  test('الحقول المحمية في الموعد تبقى مقفلة', async () => {
    const db = lockedAs(PATIENT, PATIENT_EMAIL);
    await assertFails(updateDoc(doc(db, 'appointments', BOOKED_APPT), {
      price: 0,
    }));
    await assertFails(updateDoc(doc(db, 'appointments', BOOKED_APPT), {
      status: 'Completed',
    }));
    await assertFails(updateDoc(doc(db, 'appointments', BOOKED_APPT), {
      notes: 'تزوير',
    }));
  });

  // الإقفال يجب ألا يكسر ما لم ينتقل للخادم بعد.

  test('الإلغاء من المريض يبقى يعمل', async () => {
    const db = lockedAs(PATIENT, PATIENT_EMAIL);
    await assertSucceeds(updateDoc(doc(db, 'appointments', BOOKED_APPT), {
      status: 'Cancelled',
    }));
    await assertSucceeds(updateDoc(doc(db, 'slots', BOOKED_SLOT), {
      bookedCount: 0, patientIds: arrayRemove(PATIENT),
    }));
  });

  test('الطبيب يُنهي الموعد ويدير خاناته', async () => {
    const db = lockedAs(DOCTOR);
    await assertSucceeds(updateDoc(doc(db, 'appointments', BOOKED_APPT), {
      status: 'Completed',
    }));
    await assertSucceeds(updateDoc(doc(db, 'slots', BOOKED_SLOT), {
      bookedCount: 0, patientIds: [],
    }));
  });

  test('قراءة المواعيد القائمة تبقى متاحة لصاحبها', async () => {
    await assertSucceeds(
      getDoc(doc(lockedAs(PATIENT, PATIENT_EMAIL), 'appointments', BOOKED_APPT)));
    await assertSucceeds(
      getDoc(doc(lockedAs(DOCTOR), 'appointments', BOOKED_APPT)));
  });
});

describe('بعد إقفال الإلغاء المباشر (المرحلة 1ب)', () => {
  // الحالة النهائية بعد نشر `cancelAppointment` والتحقق منه: الإلغاء من
  // الخادم وحده. Admin SDK يتجاوز القواعد، فالدالة تعمل بينما يُمنع العميل.
  //
  // مفتاح الحجز (`clientDirectBookingEnabled`) يبقى `true` هنا عمداً —
  // كل مفتاح يُختبَر باستقلال عن الآخر.

  const cancelLockedAs = (uid, email) =>
    cancelLockedEnv.authenticatedContext(uid, email ? { email } : {}).firestore();

  beforeEach(async () => {
    await cancelLockedEnv.clearFirestore();
    await cancelLockedEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users', DOCTOR), {
        role: 'doctor', name: 'د. أحمد', isVerified: true,
        bookingSystemType: 'Individual', price: 200,
      });
      await setDoc(doc(db, 'users', PATIENT), {
        role: 'patient', name: 'مريض', email: PATIENT_EMAIL,
      });
      await setDoc(doc(db, 'slots', BOOKED_SLOT), {
        doctorId: DOCTOR, appointmentDate: '2030-01-01', startTime: '09:00',
        capacity: 4, bookedCount: 1, patientIds: [PATIENT],
      });
      await setDoc(doc(db, 'appointments', BOOKED_APPT), {
        doctorId: DOCTOR, patientId: PATIENT, slotId: BOOKED_SLOT,
        appointmentDate: '2030-01-01', startTime: '09:00', status: 'Booked',
        price: 200, notes: '',
      });
    });
  });

  test('المريض لا يستطيع إلغاء موعده مباشرة بعد الإقفال', async () => {
    const db = cancelLockedAs(PATIENT, PATIENT_EMAIL);
    await assertFails(updateDoc(doc(db, 'appointments', BOOKED_APPT), {
      status: 'Cancelled',
    }));
  });

  test('العميل لا يستطيع إنقاص عدّاد خانة مباشرة بعد الإقفال', async () => {
    const db = cancelLockedAs(PATIENT, PATIENT_EMAIL);
    await assertFails(updateDoc(doc(db, 'slots', BOOKED_SLOT), {
      bookedCount: 0, patientIds: arrayRemove(PATIENT),
    }));
  });

  test('الحجز المباشر يبقى يعمل — مفتاح مستقلّ لم يُقفَل', async () => {
    const db = cancelLockedAs(OTHER, OTHER_EMAIL);
    await assertSucceeds(bookInOneBatch(db, {
      doctorId: DOCTOR, patientId: OTHER, date: '2030-09-09', time: '11:00',
    }));
  });

  test('الطبيب يبقى يدير خاناته ويُنهي المواعيد', async () => {
    const db = cancelLockedAs(DOCTOR);
    await assertSucceeds(updateDoc(doc(db, 'appointments', BOOKED_APPT), {
      status: 'Completed',
    }));
    await assertSucceeds(updateDoc(doc(db, 'slots', BOOKED_SLOT), {
      bookedCount: 0, patientIds: [],
    }));
  });

  test('قراءة المواعيد القائمة تبقى متاحة لصاحبها', async () => {
    await assertSucceeds(
      getDoc(doc(cancelLockedAs(PATIENT, PATIENT_EMAIL), 'appointments', BOOKED_APPT)));
  });
});

describe('otps — المجموعة المحذوفة', () => {
  test('لا يمكن كتابة رمز تحقق بلا مصادقة', async () => {
    // كانت `allow create: if true`، ودالة سحابية ترسل بريداً إلى العنوان
    // المكتوب كمعرّف للمستند — أي مرحّل بريد مفتوح باسم المشروع.
    await assertFails(setDoc(doc(asAnon(), 'otps', 'victim@example.com'), {
      code: '123456',
    }));
  });

  test('ولا حتى من مستخدم مسجَّل', async () => {
    await assertFails(setDoc(doc(asOther(), 'otps', 'victim@example.com'), {
      code: '123456',
    }));
  });
});
