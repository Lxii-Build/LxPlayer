// 顶层构建文件：只声明插件版本，具体配置在 :app。
plugins {
    alias(libs.plugins.agp.app) apply false
    alias(libs.plugins.compose.compiler) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}

// SDK 基线集中在一处，避免 app 模块和 CI 各写一份导致漂移。
// compileSdk 用 36：CI 的 setup-android 与本机 SDK 都有 android-36，
// 37 只在部分环境可用，会让「云端能过、别处不能过」。
extra["androidMinSdkVersion"] = 28
extra["androidTargetSdkVersion"] = 36
extra["androidCompileSdkVersion"] = 36
extra["androidBuildToolsVersion"] = "36.0.0"
extra["androidSourceCompatibility"] = JavaVersion.VERSION_21
extra["androidTargetCompatibility"] = JavaVersion.VERSION_21
