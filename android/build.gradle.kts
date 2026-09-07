allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.google.gms.google-services") version "4.4.1" apply false
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// نسخة أدوات البناء لكل وحدات أندرويد — التطبيق وكل إضافة.
//
// كل وحدة تحمل قيمتها الخاصة، وافتراضها هو النسخة المربوطة بـ AGP 9.1.0 أي
// 36.0.0، وهي غير مثبَّتة هنا. وضبطها في app/build.gradle.kts وحده أعبَر
// البناءَ وحدةَ :app ثم أوقفه عند :cloud_firestore بالخطأ نفسه — فالإضافات
// وحدات Gradle مستقلة لا ترث إعداد التطبيق. تُضبط هنا مرة واحدة للجميع.
val androidBuildTools = providers.gradleProperty("drd.buildToolsVersion").get()

subprojects {
    plugins.withId("com.android.application") {
        extensions.getByType(com.android.build.api.dsl.ApplicationExtension::class.java)
            .buildToolsVersion = androidBuildTools
    }
    plugins.withId("com.android.library") {
        extensions.getByType(com.android.build.api.dsl.LibraryExtension::class.java)
            .buildToolsVersion = androidBuildTools
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
