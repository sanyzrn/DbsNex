import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keys = Properties()
val keyFile = rootProject.file("key.properties")
if (keyFile.exists()) keys.load(FileInputStream(keyFile))

// A release build without signing material must fail loudly. The debug keystore
// is a well-known, publicly shared key (password "android"): an APK signed with
// it can be trivially impersonated, cannot update a properly signed install,
// and is rejected by Play.
val isReleaseTask = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
val isCi = System.getenv("CI") != null

android {
    namespace = "com.sanyzrn.nex"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.sanyzrn.nex"
        // Pinned explicitly rather than inherited from the Flutter SDK, so a
        // plugin raising its own floor (record 6.x needs API 23+) surfaces as a
        // clear constraint violation instead of an opaque manifest-merger error.
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyFile.exists()) {
            create("release") {
                keyAlias = keys["keyAlias"] as String
                keyPassword = keys["keyPassword"] as String
                storeFile = file(keys["storeFile"] as String)
                storePassword = keys["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (!keyFile.exists() && isReleaseTask && isCi) {
                throw GradleException(
                    "android/key.properties is missing - refusing to produce a " +
                        "debug-signed release artifact. See docs/06-development.md " +
                        "section 'Cutting a Release'."
                )
            }

            signingConfig = if (keyFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Local developer convenience only; CI is blocked above.
                signingConfigs.getByName("debug")
            }

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter { source = "../.." }
