plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sanyzrn.nexexperiments.local_ai_bench"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sanyzrn.nexexperiments.local_ai_bench"
        // Matches apps/client's floor rather than Flutter's default — this
        // harness is arm64-v8a only anyway (see android/app/libs/README.md),
        // so there is no reason to support older API levels here either.
        minSdk = 24
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

// llama_cpp_dart ships no native binaries in its Dart package, so the
// llama.cpp runtime lib/main.dart loads has to be added here by hand — see
// android/app/libs/README.md for where it comes from. Conditional on
// purpose: this file is never committed, so a fresh checkout still builds
// (and just fails at model-load time) without it.
dependencies {
    val llamaCppAar = file("libs/llama-cpp-dart.aar")
    if (llamaCppAar.exists()) {
        implementation(files(llamaCppAar))
    }
}

flutter {
    source = "../.."
}
