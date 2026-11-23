import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseProps = Properties()
val releasePropsFile = rootProject.file("key.properties")
if (releasePropsFile.exists()) {
    FileInputStream(releasePropsFile).use(releaseProps::load)
}

// CI release jobs must never silently produce an unsigned bundle.
val requireReleaseSigning = providers.environmentVariable("SADOHOD_REQUIRE_RELEASE_SIGNING")
    .orElse("false").get().equals("true", ignoreCase = true)
if (requireReleaseSigning) {
    val requiredKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
    val missing = requiredKeys.filter { releaseProps.getProperty(it).isNullOrBlank() }
    require(missing.isEmpty()) {
        "Android release signing is not configured: ${missing.joinToString(", ")}"
    }
    require(file(releaseProps.getProperty("storeFile")).isFile) {
        "Android release keystore file is missing"
    }
}


android {
    namespace = "ru.sadohod.seller"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Distinct from the buyer application. Confirm ID before first store release.
        applicationId = "ru.sadohod.seller"
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

    signingConfigs {
        if (releasePropsFile.exists()) {
            create("sellerRelease") {
                keyAlias = releaseProps.getProperty("keyAlias")
                keyPassword = releaseProps.getProperty("keyPassword")
                storeFile = file(releaseProps.getProperty("storeFile"))
                storePassword = releaseProps.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Never sign a Play Store build with the debug key. Without
            // android/key.properties this output is unsigned until configured.
            signingConfig = if (releasePropsFile.exists())
                signingConfigs.getByName("sellerRelease") else null
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
