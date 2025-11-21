// android/app/build.gradle.kts — módulo :app

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // Aplica Google Services aquí (sin versión)
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.artattoo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.artattoo"   // Debe calzar con google-services.json
        minSdk = maxOf(21, flutter.minSdkVersion) // Asegura >= 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // Java 17 + DESUGARING (requerido por flutter_local_notifications)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildTypes {
        release {
            // Firma de prueba; ajusta para tu release real
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // (Opcional) BoM de Firebase; NO agregues firebase-messaging directo (lo trae Flutter)
    implementation(platform("com.google.firebase:firebase-bom:34.4.0"))

    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.core:core-ktx:1.13.1")

    // Desugaring (necesario para flutter_local_notifications) - actualizar a >= 2.1.4
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
