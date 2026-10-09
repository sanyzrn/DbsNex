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

// CI's pull-request job builds the shipping artifact (the ai flavor, release
// App Bundle) only to prove it assembles (REL-10). That build is thrown away,
// so it may use the debug key; this variable is never set by release.yml.
val ciVerifyOnly = System.getenv("NEX_CI_VERIFY_RELEASE_BUILD") == "true"

// The versionCode the release pipeline stamps for a version name:
// (major*10000 + minor*100 + patch) * 10000 — see release.yml and
// docs/06-development.md. A plain local `flutter build` used Flutter's own,
// far smaller number instead, so a hotfix built by hand could never install
// over a released build (REL-13). The larger of the two is used, which is
// exactly the release number whenever the pipeline passes one.
fun nexReleaseVersionCode(versionName: String): Int {
    val parts = versionName.substringBefore('-').split('.').map { it.toIntOrNull() }
    if (parts.size != 3 || parts.any { it == null }) return 0
    val major = parts[0]!!
    val minor = parts[1]!!
    val patch = parts[2]!!
    if (minor > 99 || patch > 99) return 0
    return (major * 10000 + minor * 100 + patch) * 10000
}

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
        versionCode = maxOf(flutter.versionCode, nexReleaseVersionCode(flutter.versionName))
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
            if (!keyFile.exists() && isReleaseTask && isCi && !ciVerifyOnly) {
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
    // The search model's runtime (NexEmbedder.kt). Declared here rather than
    // reached through the chat plugin, so this module's own code compiles
    // whatever happens to that plugin; the version is the root build's, the
    // one every module is held to.
    implementation(
        "com.google.ai.edge.litertlm:litertlm-android:${rootProject.extra["litertlmVersion"]}",
    )
}
