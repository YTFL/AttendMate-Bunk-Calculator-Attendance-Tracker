plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ytfl.bunkattendance"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ytfl.bunkattendance"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Set explicit minimum SDK to ensure plugin compatibility and predictable builds
        minSdk = 24 // Android 7.0 (Nougat) and above required for update system
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Only build for 64-bit ARM devices (modern Android devices)
        // Excludes 32-bit ARM and x86/x86_64 architectures
        ndk {
            abiFilters.addAll(listOf("arm64-v8a"))
        }
    }

    signingConfigs {
        create("release") {
            val keystoreFile = rootProject.file("app-release-key.jks")
            if (keystoreFile.exists()) {
                storeFile = keystoreFile
                storePassword = project.findProperty("KEYSTORE_PASSWORD") as String? ?: "flutter123"
                keyAlias = project.findProperty("KEY_ALIAS") as String? ?: "app-key"
                keyPassword = project.findProperty("KEY_PASSWORD") as String? ?: "flutter123"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (file("app-release-key.jks").exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            
            // Enable optimization flags for smaller APK size
            isMinifyEnabled = true
            isShrinkResources = true
            
            // Use the default ProGuard rules plus optimizations
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}
