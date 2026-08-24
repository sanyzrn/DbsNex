allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Flutter plugin packages ship their own Gradle scripts, and some of them —
// audio_session 0.2.4, reached through just_audio — configure the Kotlin
// compiler with a bare `kotlin { }` block without applying the Kotlin plugin
// themselves:
//
//   Build file '.../audio_session-0.2.4/android/build.gradle.kts' line: 73
//   Extension of type 'KotlinAndroidProjectExtension' does not exist.
//
// They relied on something else having applied it for them, which no longer
// happens under Gradle 9 / AGP 9. Applying it to every Android subproject
// restores the extension those scripts expect. The plugin is already on the
// classpath — settings.gradle.kts declares it — so this only applies it, it
// does not add a dependency.
subprojects {
    plugins.withId("com.android.library") {
        plugins.apply("org.jetbrains.kotlin.android")
    }
}

// Not every plugin package pins a JVM target for its Kotlin sources, so the
// Kotlin compiler falls back to the JDK Gradle itself is running on — 21 here,
// because Android Lint needs 21 — while AGP compiles that same module's Java at
// 17. Gradle refuses the mismatch:
//
//   Execution failed for task ':file_picker:compileReleaseKotlin'
//   Inconsistent JVM-target compatibility detected for tasks
//   'compileReleaseJavaWithJavac' (17) and 'compileReleaseKotlin' (21).
//
// The app's own bytecode target is 17 and is not moving, so every subproject is
// held to the same number instead of inheriting whichever JDK happens to be
// running the build. Lazy on purpose: these tasks are registered later, when
// each plugin's own script is evaluated.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions.jvmTarget.set(
            org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
        )
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
