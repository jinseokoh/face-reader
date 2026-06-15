pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    // END: FlutterFire Configuration
    // Kotlin 2.2.20 명시 — 의존성(firebase/play-services)이 2.2.x 메타데이터로
    // 컴파일돼 있어, 제거하면 기본 2.0.0 으로 떨어져 compileKotlin 이 깨진다.
    // (현재 Flutter 는 built-in Kotlin 미지원 — 향후 지원 시 재검토.)
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
