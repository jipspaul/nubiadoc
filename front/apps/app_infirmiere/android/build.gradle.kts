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

// Force compileSdk 36 on all Android subprojects (plugins like file_picker are
// pinned to an older compileSdk and break newer AGP metadata checks).
subprojects {
    val forceCompileSdk = {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                val m = androidExt.javaClass.methods.firstOrNull {
                    it.name == "compileSdkVersion" &&
                        it.parameterTypes.size == 1 &&
                        it.parameterTypes[0] == Int::class.javaPrimitiveType
                }
                m?.invoke(androidExt, 36)
            } catch (e: Throwable) {
            }
        }
        Unit
    }
    if (state.executed) {
        forceCompileSdk()
    } else {
        afterEvaluate { forceCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
