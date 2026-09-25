plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "nl.g4d.homemaps"
    // permission_handler 13 compiles against 37, above Flutter's default; only
    // the APIs the app can see change, targetSdk stays Flutter's.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "nl.g4d.homemaps"
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

    // One fixed key for every release: Android rejects an update signed with a
    // different key. The release workflow writes it from the secrets; locally
    // (without those variables) it stays the debug key, so `flutter run --release`
    // just works.
    val keystoreFile = System.getenv("HOMEMAPS_KEYSTORE")
    signingConfigs {
        if (keystoreFile != null) {
            create("release") {
                storeFile = file(keystoreFile)
                storePassword = System.getenv("HOMEMAPS_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("HOMEMAPS_KEY_ALIAS")
                keyPassword = System.getenv("HOMEMAPS_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (keystoreFile != null) "release" else "debug",
            )
        }
    }
}

dependencies {
    // Android Auto (see src/main/kotlin/nl/g4d/homemaps/car/).
    implementation("androidx.car.app:app:1.7.0")
    implementation("androidx.car.app:app-projected:1.7.0")
    // The map on the car's screen: the same SDK and version as maplibre_gl
    // brings for the phone (its android/build.gradle), so there is one copy.
    implementation("org.maplibre.gl:android-sdk-opengl:13.5.0")
    // The generated car contract (CarApi.g.kt) talks to Dart with coroutines.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
