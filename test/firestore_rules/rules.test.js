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

describe('تقييم الطبيب (الحقول المجمَّعة)', () => {
  test('مراجعة صحيحة: زيادة واحدة وقيمة ضمن النطاق', async () => {
    await assertSucceeds(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 4.2, reviews: 11,
    }));
  });

  test('لا يمكن تزوير عدد المراجعات', async () => {
    // القاعدة القديمة كانت تسمح بهذا.
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 5, reviews: 99999,
    }));
  });

  test('لا يمكن وضع تقييم خارج 0..5', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 99, reviews: 11,
    }));
  });

  test('الطبيب لا يرفع تقييم نفسه', async () => {
    await assertFails(updateDoc(doc(asDoctor(), 'users', DOCTOR), {
      rating: 5, reviews: 11,
    }));
  });

  test('لا يمكن تمرير حقول أخرى مع التقييم', async () => {
    await assertFails(updateDoc(doc(asPatient(), 'users', DOCTOR), {
      rating: 4.2, reviews: 11, price: 0,
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
});

describe('reviews — مراجعة عن زيارة حدثت فعلاً', () => {
  const review = (extra = {}) => ({
    doctorId: DOCTOR, patientId: PATIENT, appointmentId: DONE_APPT,
    rating: 5, comment: 'ممتاز', ...extra,
  });

  test('مراجعة عن موعد مكتمل مقبولة', async () => {
    await assertSucceeds(
      setDoc(doc(asPatient(), 'reviews', DONE_APPT), review()));
  });

  test('مراجعة بلا موعد مكتمل مرفوضة', async () => {
    // الثغرة القديمة: أي حساب مسجَّل يكتب أي عدد من المراجعات لأي طبيب،
    // فيُسقط تقييم منافس إلى الصفر في دقائق.
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

  test('معرّف المراجعة يجب أن يكون معرّف الموعد', async () => {
    await assertFails(setDoc(doc(asPatient(), 'reviews', 'rev_random'),
      review()));
  });

  test('لا مراجعة ثانية لنفس الموعد من شخص آخر', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'reviews', DONE_APPT), review());
    });
    await assertFails(setDoc(doc(asOther(), 'reviews', DONE_APPT),
      review({ patientId: OTHER })));
  });

  test('صاحب المراجعة يعدّل نجومه وتعليقه فقط', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'reviews', DONE_APPT), review());
    });
    await assertSucceeds(updateDoc(doc(asPatient(), 'reviews', DONE_APPT), {
      rating: 4, comment: 'جيد',
    }));
    await assertFails(updateDoc(doc(asPatient(), 'reviews', DONE_APPT), {
      doctorId: GROUP_DOCTOR,
    }));
  });

  test('التقييم خارج 1..5 مرفوض', async () => {
    await assertFails(setDoc(doc(asPatient(), 'reviews', DONE_APPT),
      review({ rating: 100 })));
  });
});

describe('notifications', () => {
  test('العميل لا يستطيع إنشاء إشعار باسم العيادة', async () => {
    await assertFails(setDoc(doc(asOther(), 'notifications', 'n1'), {
      userId: PATIENT, title: 'رسالة مزيّفة', body: 'احضر الآن', read: false,
    }));
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
