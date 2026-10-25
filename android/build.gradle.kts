allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// نرفع compileSdk للمكتبات القديمة (Agora) ولتطبيقنا (permission_handler محتاجة 37)
subprojects {
    afterEvaluate {
        val target = when (name) {
            "agora_rtc_engine", "iris_method_channel" -> 36
            "app" -> 37
            else -> null
        }
        if (target != null) {
            val ext = extensions.findByName("android")
            ext?.javaClass?.methods
                ?.firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
                ?.invoke(ext, target)
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}