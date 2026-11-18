plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.lychnion.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lychnion.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // llama.cpp ships arm64-v8a and x86_64 only; API 28 matches the connector's tested floor.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.clear()
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    // The upload key lives only in 1Password; tool/build_release.sh reads
    // it into a temporary file and sets these variables. Without them
    // (development, CI), release builds are signed with the debug key.
    val uploadStore = System.getenv("LYCHNION_UPLOAD_KEYSTORE")
    signingConfigs {
        if (uploadStore != null) {
            create("upload") {
                storeFile = file(uploadStore)
                storeType = "pkcs12"
                storePassword = System.getenv("LYCHNION_UPLOAD_PASSWORD")
                keyAlias = System.getenv("LYCHNION_UPLOAD_ALIAS") ?: "upload"
                keyPassword = System.getenv("LYCHNION_UPLOAD_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (uploadStore != null) "upload" else "debug",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
