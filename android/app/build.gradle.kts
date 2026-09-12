import java.util.Properties

val envProps = Properties()
val rootEnvFile = rootProject.file("../.env")
val androidEnvFile = rootProject.file(".env")

if (rootEnvFile.exists()) {
    rootEnvFile.inputStream().use { envProps.load(it) }
} else if (androidEnvFile.exists()) {
    androidEnvFile.inputStream().use { envProps.load(it) }
}

val mapsApiKey: String = envProps.getProperty("MAPS_API_KEY")
    ?: System.getenv("MAPS_API_KEY")
    ?: (project.findProperty("MAPS_API_KEY") as String?)
    ?: "YOUR_GOOGLE_MAPS_API_KEY"

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun readGoogleClientId(jsonFileName: String): String {
    val jsonFile = rootProject.file("../$jsonFileName")
    val localJsonFile = rootProject.file(jsonFileName)
    val targetFile = if (jsonFile.exists()) jsonFile else if (localJsonFile.exists()) localJsonFile else null
    if (targetFile == null || !targetFile.exists()) return ""
    val jsonText = targetFile.readText()
    val clientIdMatch = Regex("\"client_id\"\\s*:\\s*\"([^\"]+)\"").find(jsonText)
    return clientIdMatch?.groupValues?.get(1) ?: ""
}

android {
    namespace = "com.ytfl.attendmate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ytfl.attendmate"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // Android 7.0 (Nougat) and above required for update system
        targetSdk = 36 // Android 16 (API 36)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        manifestPlaceholders["appName"] = "AttendMate"
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    signingConfigs {
        create("release") {
            val keystoreFile = rootProject.file("app-release-key.jks")
            storeFile = keystoreFile
            storePassword = project.findProperty("KEYSTORE_PASSWORD") as String? ?: "flutter123"
            keyAlias = project.findProperty("KEY_ALIAS") as String? ?: "app-key"
            keyPassword = project.findProperty("KEY_PASSWORD") as String? ?: "flutter123"
        }
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appName"] = "AttendMate - Debug"
            val googleClientId = readGoogleClientId("client_secret_debug.json")
            buildConfigField("String", "GOOGLE_CLIENT_ID", "\"$googleClientId\"")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            
            val googleClientId = readGoogleClientId("client_secret_release.json")
            buildConfigField("String", "GOOGLE_CLIENT_ID", "\"$googleClientId\"")
            
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
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("com.github.woheller69:FreeDroidWarn:V1.14")
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}
