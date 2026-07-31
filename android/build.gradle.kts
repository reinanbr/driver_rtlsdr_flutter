group = "com.rtlsdrmobile.driver_rtlsdr"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.rtlsdrmobile.driver_rtlsdr"

    compileSdk = 36
    // Explicitly pinned (not flutter.ndkVersion, this module has no
    // access to the host app's `flutter` object) — same version used and
    // validated by the main app (rtl-sdr mobile/android/app/build.gradle.kts).
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        // 26 required by Oboe/AAudio's low-latency path.
        minSdk = 26

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")

            // Opt-in only (ORG_GRADLE_PROJECT_driverRtlsdrCiAbis=true, set by
            // ci.yml's integration job): adds x86_64 so the plugin's .so can
            // load on the KVM-accelerated x86_64 emulator GitHub Actions
            // actually runs. Never set for release builds/consumers — arm64
            // and armv7 are the only ABIs real Android/RTL-SDR devices use.
            if (project.hasProperty("driverRtlsdrCiAbis")) {
                abiFilters += "x86_64"
            }
        }

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += "-DANDROID_STL=c++_shared"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // Prefab exposes Oboe's C++ headers/libs (AAR) to CMake via
    // find_package(oboe CONFIG) — see src/main/cpp/CMakeLists.txt.
    buildFeatures {
        prefab = true
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.google.oboe:oboe:1.10.0")
    // FileProvider, for sharing a plain-file recording (legacy-Android
    // fallback or a developer's own buildFilePath) via Intent.ACTION_SEND —
    // Android has blocked raw file:// URIs in share intents since API 24.
    implementation("androidx.core:core-ktx:1.15.0")
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
