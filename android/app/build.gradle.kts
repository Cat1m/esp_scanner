plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android") // thay vì "kotlin-android"
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.esp_scanner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Khuyến nghị Java 17 với AGP mới
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.esp_scanner"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Ký tạm bằng debug để flutter run --release hoạt động
            signingConfig = signingConfigs.getByName("debug")
            // có thể thêm minify/proguard nếu cần
            // isMinifyEnabled = false
        }
    }
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    // (tuỳ chọn) logging interceptor khi debug:
    // implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
}

flutter {
    source = "../.."
}
