'use strict';

/**
 * عامل الخدمة (Service Worker) الخاص بتطبيق DrD.
 *
 * ## لماذا ملف مكتوب يدوياً؟
 *
 * كان Flutter يولّد `flutter_service_worker.js` يتكفّل بالتخزين المؤقت. في
 * الإصدارات الحديثة (3.35 فما فوق) تخلّى Flutter عن ذلك: الملف المولَّد الآن
 * مجرّد بذرة تُلغي تسجيل نفسها ولا تخزّن شيئاً. أي أن بناء الويب الافتراضي
 * **لا يعمل بلا اتصال إطلاقاً** ولا يستوفي شروط تثبيت PWA الكاملة.
 *
 * ولمنع تعارض بذرة Flutter مع هذا الملف (الاثنان يُسجَّلان على النطاق الجذر
 * `/`، فالأخير يستبدل الأول ثم يُلغي نفسه) يستدعي `web/flutter_bootstrap.js`
 * الدالة `_flutter.loader.load()` بلا وسائط، فلا يسجّل Flutter عامله أصلاً.
 * هذا العامل يُسجَّل يدوياً من `index.html`.
 *
 * ## الاستراتيجية
 *
 * - **التنقّل بين الصفحات**: الشبكة أولاً، ثم الذاكرة، ثم صفحة "بلا اتصال".
 *   الشبكة أولاً لأن هذا تطبيق حجز — عرض مواعيد قديمة أسوأ من عرض رسالة خطأ.
 * - **ملفات البناء والأيقونات**: من الذاكرة أولاً مع تحديث في الخلفية
 *   (stale-while-revalidate)، فالإقلاع يصبح فورياً.
 * - **طلبات Firebase**: لا تُخزَّن أبداً. مواعيد الأطباء وحالة الحجز يجب أن
 *   تأتي من الخادم دائماً، وإلا حجز المريض خانة سبق أن أُخذت.
 */

// ⚠️ ارفع هذا الرقم مع كل إصدار جديد. تغييره يُبطل كل الذاكرة المؤقتة القديمة.
const VERSION = 'v3';

const SHELL_CACHE = `drd-shell-${VERSION}`;
const ASSETS_CACHE = `drd-assets-${VERSION}`;
const OFFLINE_URL = 'offline.html';

/**
 * الحد الأدنى الذي يجعل التطبيق قابلاً للفتح بلا اتصال.
 *
 * القائمة مقصودة القِصَر: ملفات بناء Flutter تتغير أسماؤها ومحتواها مع كل
 * إصدار، فمحاولة تعدادها هنا تعني تعطّل التثبيت كلما فشل تحميل ملف واحد.
 * البقية تُخزَّن عند أول استخدام فعلي.
 */
const SHELL_ASSETS = [
  'index.html',
  'manifest.json',
  OFFLINE_URL,
  'privacy.html',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/apple-touch-icon.png',
];

/** نطاقات لا يجوز تخزين ردودها مطلقاً. */
const NEVER_CACHE_HOSTS = [
  'firestore.googleapis.com',
  'identitytoolkit.googleapis.com',
  'securetoken.googleapis.com',
  'firebaseinstallations.googleapis.com',
  'www.googleapis.com',
  'firebase.googleapis.com',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(SHELL_CACHE);
      // `addAll` تفشل كلها لو فشل ملف واحد، لذا نضيف كل ملف على حدة حتى لا
      // يمنع أصلٌ واحد مفقود تثبيت العامل بأكمله.
      await Promise.all(
        SHELL_ASSETS.map((url) =>
          cache.add(new Request(url, { cache: 'reload' })).catch(() => {
            console.warn('[sw] تعذّر تخزين:', url);
          })
        )
      );
      // لا نستدعي skipWaiting هنا: النسخة الجديدة تنتظر موافقة المستخدم عبر
      // الشريط الذي يظهر في index.html، فلا يُعاد تحميل الصفحة أثناء حجزه.
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((key) => key.startsWith('drd-') && !key.endsWith(VERSION))
          .map((key) => caches.delete(key))
      );

      // تسريع التنقّل بلا اتصال على المتصفحات التي تدعمه.
      if (self.registration.navigationPreload) {
        await self.registration.navigationPreload.enable();
      }

      await self.clients.claim();
    })()
  );
});

// رسالة من الصفحة عند ضغط المستخدم على زر "تحديث".
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

self.addEventListener('fetch', (event) => {
  const request = event.request;

  // الطلبات غير GET (تسجيل دخول، حجز موعد) تمر مباشرة للشبكة.
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  if (NEVER_CACHE_HOSTS.some((host) => url.hostname.endsWith(host))) return;

  // طلبات النطاقات الأخرى تُترك للمتصفح تفادياً لتخزين ردود مبهمة.
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith(handleNavigation(event));
    return;
  }

  // ملفات التطبيق نفسها تُجلب من الشبكة أولاً.
  //
  // السبب مهم: Flutter بيبني `main.dart.js` بنفس الاسم في كل مرة، بلا أي
  // بصمة محتوى في اسم الملف. فلو عُرض من الذاكرة أولاً، المستخدم يفضل
  // شايف **النسخة القديمة من التطبيق بعد كل نشر** — والتحديث ميوصلش إلا
  // في الفتحة اللي بعدها. ده حصل فعلاً: نُشر تصميم جديد والمستخدم فضل
  // شايف القديم.
  //
  // باقي الأصول (canvaskit، الخطوط، الأيقونات) مسارها بيتغيّر مع كل إصدار
  // من Flutter، فتخزينها أولاً آمن وبيخلّي الإقلاع فورياً.
  if (isAppShellAsset(url.pathname)) {
    event.respondWith(networkFirst(request));
    return;
  }

  event.respondWith(staleWhileRevalidate(request));
});

/** هل الملف من ملفات التطبيق اللي اسمها ثابت بين الإصدارات؟ */
function isAppShellAsset(pathname) {
  return (
    /\/(main\.dart\.js|flutter_bootstrap\.js|flutter\.js|version\.json|manifest\.json)$/
      .test(pathname) ||
    pathname.startsWith('/assets/')
  );
}

/**
 * الشبكة أولاً مع رجوع للذاكرة عند انقطاع الاتصال.
 *
 * بكده المستخدم دايماً على آخر نسخة وهو متصل، ولسه التطبيق بيفتح بلا
 * إنترنت من آخر نسخة اتخزّنت.
 */
async function networkFirst(request) {
  const cache = await caches.open(ASSETS_CACHE);
  try {
    const response = await fetch(request);
    if (response && response.status === 200) {
      cache.put(request, response.clone()).catch(() => {});
    }
    return response;
  } catch (error) {
    const cached = await cache.match(request);
    if (cached) return cached;
    throw error;
  }
}

/**
 * التنقّل: الشبكة أولاً مع رجوع إلى النسخة المخزَّنة ثم صفحة بلا اتصال.
 */
async function handleNavigation(event) {
  try {
    const preloaded = await event.preloadResponse;
    if (preloaded) {
      void updateShell(preloaded.clone());
      return preloaded;
    }

    const network = await fetch(event.request);
    void updateShell(network.clone());
    return network;
  } catch (error) {
    // التطبيق صفحة واحدة (SPA)، فأي مسار يُخدَم من index.html المخزَّنة.
    const cached = await caches.match('index.html');
    if (cached) return cached;

    const offline = await caches.match(OFFLINE_URL);
    if (offline) return offline;

    return new Response('التطبيق غير متاح بلا اتصال', {
      status: 503,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    });
  }
}

/** حفظ آخر نسخة ناجحة من الصفحة الرئيسية للاستخدام بلا اتصال. */
async function updateShell(response) {
  if (!response || !response.ok) return;
  try {
    const cache = await caches.open(SHELL_CACHE);
    await cache.put('index.html', response);
  } catch (error) {
    // تجاوز حصة التخزين مثلاً — ليس سبباً لتعطيل التصفّح.
  }
}

/**
 * الأصول الثابتة: تُعرض من الذاكرة فوراً ويُحدَّث المخزون في الخلفية.
 */
async function staleWhileRevalidate(request) {
  const cache = await caches.open(ASSETS_CACHE);
  const cached = await cache.match(request);

  const network = fetch(request)
    .then((response) => {
      // `status === 200` فقط: الردود الجزئية (206) والمبهمة لا تصلح للتخزين.
      if (response && response.status === 200) {
        cache.put(request, response.clone()).catch(() => {});
      }
      return response;
    })
    .catch(() => null);

  if (cached) {
    // لا ننتظر الشبكة — التحديث يجري في الخلفية لإقلاع فوري.
    // `network` تلتقط أخطاءها أصلاً وتُرجع null، فلا وعد مرفوض معلّقاً هنا.
    return cached;
  }

  const response = await network;
  if (response) return response;

  return new Response('', { status: 504, statusText: 'Gateway Timeout' });
}
