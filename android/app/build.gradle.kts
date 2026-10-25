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

    // All build variants share the same permanent Android application ID.
    // CI-only smoke builds use a temporary key and are never distributed.
    val playStoreBuild = System.getenv("PLAY_STORE_BUILD") == "true"
    val ciSmokeBuild = System.getenv("MASARI_CI_SMOKE_BUILD") == "true"

    defaultConfig {
        applicationId = "com.mohammedemad333.masari"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val playSigningRequested = !ciSmokeBuild
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

    if (!ciSmokeBuild && playSigningAvailable) {
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
            // CI smoke APKs are not distributed; official builds use upload signing.
            signingConfig = if (!ciSmokeBuild) {
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
