group = "dev.macss.face_gesture_detector"
version = "1.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply(plugin = "com.android.library")
apply(plugin = "kotlin-android")

configure<com.android.build.gradle.LibraryExtension> {
    namespace = "dev.macss.face_gesture_detector"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    // 0.10.26+ ships native libraries (libmediapipe_tasks_vision_jni.so)
    // aligned to 16 KB pages — required by Google Play for apps targeting
    // Android 15+ since 2025-11-01. 0.10.21 was aligned to 4 KB.
    "implementation"("com.google.mediapipe:tasks-vision:0.10.26.1")
    // EXIF orientation of captured JPEGs (processCapturedPhoto).
    "implementation"("androidx.exifinterface:exifinterface:1.4.1")
    "testImplementation"("junit:junit:4.13.2")
}
