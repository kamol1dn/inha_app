import java.util.Properties

plugins {
    id("com.android.application")
    // Glance widgets are written in Compose.
    id("org.jetbrains.kotlin.plugin.compose")
    // The AppFunctions compiler generates the service and its schema.
    id("com.google.devtools.ksp")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (git-ignored) names a keystore kept
// outside the repository. See README.md, "Release APK".
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "uz.inha.kamol1dn.inha_app"
    // AppFunctions 1.0.0-beta01 needs compileSdk 37 (Flutter's default is 36). targetSdk stays Flutter's.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time APIs on older Android versions
        isCoreLibraryDesugaringEnabled = true
    }

    signingConfigs {
        if (keyProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        applicationId = "uz.inha.kamol1dn.inha_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Without key.properties (another machine), fall back to the debug key
            // so `flutter run --release` still works; that APK can't update a signed one.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // Home-screen widgets (docs/WIDGETS.md). home_widget brings the same Glance version.
    implementation("androidx.glance:glance-appwidget:1.2.0")

    // Gemini AppFunctions, Android 16+ (docs/APPFUNCTIONS.md).
    implementation("androidx.appfunctions:appfunctions:1.0.0-beta01")
    ksp("androidx.appfunctions:appfunctions-compiler:1.0.0-beta01")

    // The Kotlin data layer's unit tests run on the JVM, where android.jar's org.json is a stub.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
}

ksp {
    arg("appfunctions:aggregateAppFunctions", "true")
}
