plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.moodle_reminder"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // Keep GitHub APKs compatible with existing installations. The official
    // Play Store build uses the new, permanently registered application ID.
    val playStoreBuild = System.getenv("PLAY_STORE_BUILD") == "true"

    defaultConfig {
        applicationId = if (playStoreBuild) {
            "com.mohammedemad333.masari"
        } else {
            "com.example.moodle_reminder"
        }
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val playSigningRequested = playStoreBuild
    val playKeystorePath = System.getenv("PLAY_KEYSTORE_PATH")
    val playStorePassword = System.getenv("PLAY_STORE_PASSWORD")
    val playKeyAlias = System.getenv("PLAY_KEY_ALIAS")
    val playKeyPassword = System.getenv("PLAY_KEY_PASSWORD")
    val playSigningAvailable = listOf(
        playKeystorePath, playStorePassword, playKeyAlias, playKeyPassword
    ).all { !it.isNullOrBlank() }

    if (playSigningRequested && !playSigningAvailable) {
        throw GradleException("Missing Play signing environment variables")
    }

    if (playStoreBuild && playSigningAvailable) {
        signingConfigs {
            create("playRelease") {
                storeFile = file(playKeystorePath!!)
                storePassword = playStorePassword
                keyAlias = playKeyAlias
                keyPassword = playKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // GitHub test APKs keep working; Play builds require upload signing.
            signingConfig = if (playStoreBuild) {
                signingConfigs.getByName("playRelease")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
