plugins {
    id("com.android.application")
    id("kotlin-android")
    // El plugin de Flutter debe ir después de Android y Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.tattoo_live"

    // Requerido por los plugins (camera / mlkit / permission_handler)
    compileSdk = 36

    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.tattoo_live"

        // Compatibilidad amplia
        minSdk = flutter.minSdkVersion
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Firma de debug para poder correr `flutter run --release`
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // (Opcional si luego añades modelos .tflite)
    // androidResources {
    //     noCompress += listOf("tflite", "lite")
    // }

    // (Solo si llegas a tener choques de libs nativas)
    // packaging {
    //     resources {
    //         pickFirsts += listOf("**/libc++_shared.so")
    //     }
    // }
}

flutter {
    source = "../.."
}
