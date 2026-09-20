plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.rtlsdrmobile.rtlsdr_mobile"
    compileSdk = flutter.compileSdkVersion
    // Pinada explicitamente (em vez de flutter.ndkVersion) para build
    // reprodutível do lado nativo (o build nativo agora vem do plugin
    // driver_rtlsdr) — versão já instalada e testada neste ambiente. 28.2
    // (não 27.1) porque o plugin shared_preferences_android pede essa
    // versão especificamente; NDKs são retrocompatíveis.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.rtlsdrmobile.rtlsdr_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 26 exigido pelo caminho de baixa latência do Oboe/AAudio
        // usado pelo build nativo do plugin driver_rtlsdr.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // NotificationCompat — usado só pelo foreground service de streaming
    // (StreamingService.kt) pra manter o notification channel/builder
    // compatível com versões antigas do Android sem código condicional.
    implementation("androidx.core:core-ktx:1.15.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
