plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.medical_appointment_app"
    compileSdk = flutter.compileSdkVersion
    // كانت مثبَّتة يدوياً على 27.0.12077973 — الآن تتبع القيمة الموصى بها من
    // Flutter نفسه (تُحدَّث تلقائياً مع كل ترقية لأداة Flutter، بدل تثبيت
    // رقم قد يصبح أقل من أدنى إصدار تطلبه أحد الإضافات لاحقاً).
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "heldoc.com"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
