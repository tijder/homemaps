plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "nl.tijder.homemaps"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "nl.tijder.homemaps"
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

    // Eén vaste sleutel voor elke release: Android weigert een update die met een
    // andere sleutel is ondertekend. De release-workflow zet hem uit de secrets
    // neer; lokaal (zonder die variabelen) blijft het de debug-sleutel, zodat
    // `flutter run --release` gewoon werkt.
    val sleutelbestand = System.getenv("HOMEMAPS_KEYSTORE")
    signingConfigs {
        if (sleutelbestand != null) {
            create("release") {
                storeFile = file(sleutelbestand)
                storePassword = System.getenv("HOMEMAPS_KEYSTORE_WACHTWOORD")
                keyAlias = System.getenv("HOMEMAPS_SLEUTEL_ALIAS")
                keyPassword = System.getenv("HOMEMAPS_KEYSTORE_WACHTWOORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (sleutelbestand != null) "release" else "debug",
            )
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
