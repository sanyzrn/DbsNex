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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
