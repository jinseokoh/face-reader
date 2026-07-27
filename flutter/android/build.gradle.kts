allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// NDK 단일화 — mediapipe_face_mesh 2.3.0 이 ndkVersion 26.3 을 하드코딩 pin 해
// Flutter 기본(28.2, 설치됨) 외에 NDK 를 통째로 추가 다운로드한다. 플러그인의
// cmake 산출물은 단순 C++17 wrapper(log/dl 링크, 16KB page 옵션 자체 지정)라
// 상위 NDK 로 빌드해도 무방 — 전 모듈을 :app 의 버전(= flutter.ndkVersion)으로
// 강제해 NDK 를 한 벌만 유지한다.
subprojects {
    // evaluationDependsOn(":app") 이 일부 모듈을 선평가하므로, 평가 완료 모듈은
    // 즉시 적용하고 나머지는 afterEvaluate 로 건다.
    val applyNdk: (org.gradle.api.Project) -> Unit = { p ->
        val appNdk = p.rootProject.project(":app")
            .extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
            ?.ndkVersion
        if (appNdk != null) {
            p.extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
                ?.ndkVersion = appNdk
        }
    }
    if (state.executed) applyNdk(this) else afterEvaluate { applyNdk(this) }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
