// 顶层构建文件：只声明插件版本，具体配置在 :app。
plugins {
    alias(libs.plugins.agp.app) apply false
    alias(libs.plugins.compose.compiler) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}

// SDK 基线集中在一处，避免 app 模块和 CI 各写一份导致漂移。
// Compose BOM 2026.06.01 / Material3 1.5 要求 compileSdk ≥ 37。
// targetSdk 仍为 36：compileSdk 只管编译期 API，不改变运行时行为。
extra["androidMinSdkVersion"] = 28
extra["androidTargetSdkVersion"] = 36
extra["androidCompileSdkVersion"] = 37
extra["androidCompileSdkVersionMinor"] = 0
extra["androidSourceCompatibility"] = JavaVersion.VERSION_21
extra["androidTargetCompatibility"] = JavaVersion.VERSION_21
