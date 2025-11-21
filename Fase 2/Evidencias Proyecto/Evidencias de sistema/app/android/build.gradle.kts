// android/build.gradle.kts — raíz

plugins {
    // No fijes versiones acá (ya están en settings.gradle.kts)
    id("com.android.application") apply false
    id("com.android.library") apply false
    id("org.jetbrains.kotlin.android") apply false
    // NO declares aquí google-services si ya lo pusiste en settings.gradle.kts
}

allprojects {
    repositories {
        google()
        mavenCentral()
        // Necesario para artefactos de Flutter (flutter_embedding_*, arm64_v8a_*, etc.)
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

// (Si usas build dir personalizado, deja este bloque)
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    layout.buildDirectory.value(newSubprojectBuildDir)
    evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
