// android/settings.gradle.kts

pluginManagement {
    // Lee ruta del SDK de Flutter
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val path = properties.getProperty("flutter.sdk")
            require(path != null) { "flutter.sdk not set in local.properties" }
            path
        }

    // Carga herramientas de Flutter
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    // Repos para resolver plugins (incluye Google Services)
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // (Opcional) repo de artefactos de Flutter también aquí
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

// Declara versiones de plugins
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("com.google.gms.google-services") version "4.4.4" apply false
}

// Repos para dependencias normales (preferimos los de settings)
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        // ✅ necesario para io.flutter:flutter_embedding_* y arm64_v8a_*
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

rootProject.name = "artattoo"
include(":app")