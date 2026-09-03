import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // This module has Kotlin sources (MainActivity, CaptureWidgetProvider) and
    // configures the Kotlin compiler below, but never applied the plugin —
    // settings.gradle.kts declares it `apply false` and nothing applied it here.
    // Without it the `kotlin { }` extension does not exist, so Gradle resolved
    // the block against DependencyHandler.kotlin(...) and failed to compile the
    // script at all.
    id("org.jetbrains.kotlin.android")
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
    // Pinned above flutter.ndkVersion: shared_preferences_android and
    // sqlite3_flutter_libs both require 28.2.13676358, and the Flutter default
    // (27.0.12077973) fails the manifest merge. NDK releases are backward
    // compatible, so the highest requirement wins.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications, which uses java.time on a
        // minSdk of 24 where the platform does not have it. Without this the
        // build fails at dexing with a message about the plugin's own class
        // files rather than about this line, which is why it is worth naming
        // the reason here.
        isCoreLibraryDesugaringEnabled = true
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

    // 09-ai.md / ADR-031: "ai" is the only flavor whose entry point
    // (lib/main_ai.dart) may depend on nex_ai. CI's ai-deletion-proof job
    // enforces that nothing else does, and that deleting packages/ai plus
    // its two apps/client integration points still leaves "standard"
    // building. applicationIdSuffix lets both install side by side.
    flavorDimensions += "distribution"
    productFlavors {
        create("standard") {
            dimension = "distribution"
        }
        create("ai") {
            dimension = "distribution"
            // No applicationIdSuffix, deliberately, and this is a reversal of
            // what ADR-031 originally wrote down. The suffix let both flavors
            // sit on one phone, which is useful while developing and wrong for
            // shipping: "ai" is the flavor people actually install, so a
            // suffix would make it a *different app* from the one they already
            // have — same icon, none of their notes, and an in-app updater
            // offering an APK that cannot install over it, because Android
            // refuses an update across applicationIds. That is the 0.9.1
            // install failure again, by another route.
            //
            // What is given up is side-by-side installation, which the debug
            // build type can restore for whoever needs it. Nothing does today.
        }
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

dependencies {
    // The desugaring runtime `isCoreLibraryDesugaringEnabled` above needs.
    // Exactly the version flutter_local_notifications itself declares, so
    // the resolved graph gains no new artifact — Gradle already had this one.
    // Pinned rather than floating for the same reason it matters at all:
    // this decides which JDK APIs exist at runtime on old devices.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
