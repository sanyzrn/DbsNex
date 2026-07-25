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

// Force plugins (e.g. file_picker) onto compileSdk 36 for AAR metadata checks.
subprojects {
    afterEvaluate {
        val androidExt = project.extensions.findByName("android") ?: return@afterEvaluate
        try {
            val setCompileSdk =
                androidExt.javaClass.methods.firstOrNull {
                    it.name == "setCompileSdkVersion" || it.name == "setCompileSdk"
                }
            setCompileSdk?.invoke(androidExt, 36)
        } catch (_: Exception) {
            // Best-effort — app module already sets compileSdk = 36.
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
