import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keys = Properties()
val keyFile = rootProject.file("key.properties")
if (keyFile.exists()) keys.load(FileInputStream(keyFile))

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
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (keyFile.exists()) create("release") {
            keyAlias = keys["keyAlias"] as String
            keyPassword = keys["keyPassword"] as String
            storeFile = file(keys["storeFile"] as String)
            storePassword = keys["storePassword"] as String
        }
    }
    buildTypes {
        release {
            signingConfig = if (keyFile.exists())
                signingConfigs.getByName("release")
            else signingConfigs.getByName("debug")
        }
    }
}

kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
flutter { source = "../.." }