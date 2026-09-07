import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// ─────────────────────────────────────────────────────────────────────────────
// توقيع نسخة الإصدار
//
// كانت كتلة release تحمل `signingConfig = signingConfigs.getByName("debug")`.
// مفتاح التصحيح مشترك بين كل مشاريع أندرويد على الجهاز ومعروف للجميع، وGoogle
// Play يرفض أي حزمة موقَّعة به. والأسوأ أن الإعداد كان **صامتاً**: البناء ينجح
// وتُنتَج حزمة تبدو سليمة ولا تُكتشف إلا عند الرفع.
//
// المفتاح وكلمات مروره لا تدخل المستودع أبداً. تُقرأ من `android/key.properties`
// وهو مستثنى في .gitignore، وقالبه في `android/key.properties.example`.
//
// وإن غاب الملف: نسخة التصحيح تعمل كالمعتاد، ونسخة الإصدار **تفشل برسالة
// واضحة** بدل أن تُنتج حزمة غير موقَّعة أو موقَّعة خطأً. الفشل الصريح هو المطلوب
// هنا — البناء الصامت الخاطئ هو ما سبّب المشكلة أصلاً.
// ─────────────────────────────────────────────────────────────────────────────
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

fun requiredKeystoreProperty(name: String): String =
    keystoreProperties.getProperty(name)
        ?: throw GradleException(
            "android/key.properties موجود لكنه لا يحتوي على `$name`. " +
                "راجع android/key.properties.example."
        )

if (!hasReleaseKeystore) {
    // الفحص وقت بناء الرسم البياني للمهام لا وقت الإعداد: لولا ذلك لفشل حتى
    // `flutter run` و`flutter test`، وهما لا يحتاجان مفتاح إصدار.
    gradle.taskGraph.whenReady {
        val releaseTask = allTasks.firstOrNull { task ->
            task.name.contains("Release") &&
                (
                    task.name.startsWith("assemble") ||
                        task.name.startsWith("bundle") ||
                        task.name.startsWith("package")
                    )
        }
        if (releaseTask != null) {
            throw GradleException(
                """
                |
                |╭──────────────────────────────────────────────────────────────╮
                |│  تعذّر بناء نسخة الإصدار: لا يوجد مفتاح توقيع                 │
                |╰──────────────────────────────────────────────────────────────╯
                |
                |المهمة المطلوبة: ${releaseTask.name}
                |الملف الناقص:   ${keystorePropertiesFile.absolutePath}
                |
                |الخطوات (تُنفَّذ مرة واحدة، على جهازك أو في خزنة أسرار CI):
                |
                |  1. أنشئ مخزن المفاتيح — احتفظ به إلى الأبد، فبفقده لا يمكن
                |     تحديث التطبيق على Google Play مطلقاً:
                |
                |       keytool -genkey -v -keystore ~/drd-release.jks \
                |         -keyalg RSA -keysize 2048 -validity 10000 -alias drd
                |
                |  2. أنشئ android/key.properties بالمحتوى التالي:
                |
                |       storeFile=/absolute/path/to/drd-release.jks
                |       storePassword=…
                |       keyAlias=drd
                |       keyPassword=…
                |
                |     القالب جاهز في android/key.properties.example.
                |     الملف مستثنى في .gitignore ولا يُلتزم أبداً.
                |
                |لبناء نسخة تصحيح بدل ذلك: flutter build apk --debug
                """.trimMargin()
            )
        }
    }
}

android {
    // ما زال قالب Flutter الافتراضي. تغييره يستلزم نقل
    // MainActivity.kt إلى الحزمة الجديدة معاً، وإلا لم يُعثر على النشاط
    // وانهار التطبيق عند الإقلاع. مؤجَّل — راجع docs/RELEASE.md.
    // ولا أثر له على المتجر: Google Play يعتمد applicationId أدناه.
    namespace = "com.example.medical_appointment_app"
    compileSdk = flutter.compileSdkVersion
    // لا ndkVersion هنا عن قصد.
    //
    // طلبها يجعل AGP يتحقّق من وجود الحزمة وقت الإعداد، فيستدعي sdkmanager
    // ليُنزّلها. وsdkmanager مهجور الآن ويُحوَّل إلى Android CLI الجديدة، وهي
    // تقرأ `ndk;28.2.13676358` كحزمتين منفصلتين ثم تنهار
    // (NTSTATUS 0xC0000409) — فيفشل كل بناء قبل أن يبدأ.
    //
    // والحزمة أصلاً بلا عمل: لا كود native على أندرويد في هذا المشروع — لا
    // externalNativeBuild ولا CMakeLists ولا abiFilters — وإضافات Firebase
    // وurl_launcher وshared_preferences كلها تشحن مكتبات مبنية مسبقاً. ملفات
    // C++ الوحيدة في المستودع هي مُشغّل windows/ لسطح المكتب.
    //
    // إن أضيفت لاحقاً إضافة تبني native، سيطلب AGP نسخة NDK برسالة صريحة —
    // حينها تُثبَّت الحزمة يدوياً من SDK Manager ويعود هذا السطر.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // معرّف التطبيق على Google Play. يطابق `package_name` في
        // android/app/google-services.json، ولا يمكن تغييره بعد أول نشر.
        applicationId = "heldoc.com"

        // من Flutter لا رقماً متجمّداً.
        //
        // كان `23` مكتوباً بالرقم، وهو **تحت** أرضية Flutter المدعومة: يُبلّغ
        // `DependencyVersionChecker` عن تحذير لكل ما هو دون 24، ويبقى التحذير
        // قائماً في كل بناء. والقيمة هنا تساوي 24 اليوم
        // (FlutterExtension.kt: `val minSdkVersion: Int = 24`) وتتبع Flutter
        // تلقائياً عند أي ترقية، فلا تتخلّف عنه بصمت.
        //
        // المقابل صريح: أجهزة أندرويد 6.0 (API 23) لم تعد مدعومة. نسبتها
        // اليوم دون 1٪، ولا تدعمها Flutter نفسها أصلاً.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(requiredKeystoreProperty("storeFile"))
                storePassword = requiredKeystoreProperty("storePassword")
                keyAlias = requiredKeystoreProperty("keyAlias")
                keyPassword = requiredKeystoreProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // بلا احتياطي إلى مفتاح التصحيح. غياب المفتاح يوقف البناء عند
            // الحارس أعلاه برسالة تشرح الخطوة الناقصة.
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// الصيغة الحديثة بدل `kotlinOptions` القديمة (مهجورة تدريجياً منذ Kotlin
// Gradle Plugin 2.x) — تطابق ما يولّده `flutter create` الآن بـ KGP 2.4.0.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
