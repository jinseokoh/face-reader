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
    // built-in Kotlin(AGP 9) 전환은 gradle.properties 의 android.builtInKotlin=false
    // 로 opt-out 중 — kakao_flutter_sdk 등 KGP 쓰는 플러그인이 전부 마이그레이션되기
    // 전에 켜면 빌드가 실패한다. 전부 마이그레이션되면 이 pin 과 함께 제거.
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
