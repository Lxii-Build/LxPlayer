plugins {
    alias(libs.plugins.agp.app)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.kotlin.serialization)
}

val androidMinSdkVersion = rootProject.extra["androidMinSdkVersion"] as Int
val androidTargetSdkVersion = rootProject.extra["androidTargetSdkVersion"] as Int
val androidCompileSdkVersion = rootProject.extra["androidCompileSdkVersion"] as Int
val androidCompileSdkVersionMinor = rootProject.extra["androidCompileSdkVersionMinor"] as Int
val androidSourceCompatibility = rootProject.extra["androidSourceCompatibility"] as JavaVersion
val androidTargetCompatibility = rootProject.extra["androidTargetCompatibility"] as JavaVersion

// 构建期可注入（CI 的 -P 参数 / gradle.properties）；缺省值保证本地无参也能配置成功。
val propBaseUrl = (project.findProperty("BASE_URL") as String?)?.takeIf { it.isNotBlank() }
    ?: "https://lxplayer.lxii.cc/api/v1"
val propVersionName = (project.findProperty("VERSION_NAME") as String?)?.takeIf { it.isNotBlank() }
    ?: "1.0.0"
val propVersionCode = (project.findProperty("VERSION_CODE") as String?)?.toIntOrNull() ?: 1

// ---- 签名：debug 与 release 必须共用同一张证书 ----
//
// 为什么不能让 release 去 getByName("debug")：CI runner 每次都是全新机器，
// ~/.android/debug.keystore 每次自动重新生成 → 每次构建指纹都不同，
// 装不上也覆盖不了已装版本。所以密钥库必须是确定的文件，而不是自动生成的。
//
// 优先用 CI 从 Secret 解码落盘的密钥库（-PKEYSTORE_FILE 注入路径）；
// 未提供时回退到随仓库提交的 keystore/lxplayer-debug.p12。
// debug 密钥按安卓惯例是公开的（口令固定 android），提交它是为了让
// 本地与 CI 的 debug 包指纹也恒定，调试时不必卸载重装丢数据。
//
// 关键点：无论走哪条路径，debug 和 release 都指向同一个 storeFile，
// 所以两个变体的签名必然一致。CI 会用 apksigner 提取两者指纹并逐字节比对来证明这一点。
val committedKeystore = rootProject.file("keystore/lxplayer-debug.p12")
val injectedKeystore = (project.findProperty("KEYSTORE_FILE") as String?)
    ?.takeIf { it.isNotBlank() }
    ?.let(::file)
    ?.takeIf { it.isFile }

val signingStoreFile = injectedKeystore ?: committedKeystore
val signingStorePassword = (project.findProperty("KEYSTORE_PASSWORD") as String?)
    ?.takeIf { injectedKeystore != null } ?: "android"
val signingKeyAlias = (project.findProperty("KEY_ALIAS") as String?)
    ?.takeIf { injectedKeystore != null && it.isNotBlank() } ?: "lxplayer"
val signingKeyPassword = (project.findProperty("KEY_PASSWORD") as String?)
    ?.takeIf { injectedKeystore != null } ?: "android"

android {
    namespace = "cc.lxii.player"
    compileSdk {
        version = release(androidCompileSdkVersion) {
            minorApiLevel = androidCompileSdkVersionMinor
        }
    }
    // 不固定 buildToolsVersion：CI 上装到的具体小版本可能不同，
    // 写死会在版本不匹配时直接失败。AGP 会挑一个它支持的版本。

    signingConfigs {
        create("unified") {
            storeFile = signingStoreFile
            storeType = "PKCS12"
            storePassword = signingStorePassword
            keyAlias = signingKeyAlias
            keyPassword = signingKeyPassword
            // v1 已废弃且拖慢构建；v2/v3 覆盖全部支持机型，v4 便于增量安装。
            enableV1Signing = false
            enableV2Signing = true
            enableV3Signing = true
            enableV4Signing = true
        }
    }

    defaultConfig {
        applicationId = "cc.lxii.player"
        minSdk = androidMinSdkVersion
        targetSdk = androidTargetSdkVersion
        versionCode = propVersionCode
        versionName = propVersionName

        // 服务端地址在构建期注入。APK 可被解包，因此不编入任何共享密钥，
        // 客户端只使用 HTTPS 与用户自己的 JWT。
        buildConfigField("String", "BASE_URL", "\"$propBaseUrl\"")
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("unified")
            isMinifyEnabled = false
        }
        release {
            signingConfig = signingConfigs.getByName("unified")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    lint {
        abortOnError = true
        checkReleaseBuilds = true
        disable += setOf(
            "MissingTranslation",
            "GoogleAppIndexingWarning",
            "IconMissingDensityFolder",
            "VectorPath",
            "IconLauncherShape",
            "UnusedResources",
        )
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    compileOptions {
        sourceCompatibility = androidSourceCompatibility
        targetCompatibility = androidTargetCompatibility
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/{AL2.0,LGPL2.1}",
                "META-INF/DEPENDENCIES",
                "kotlin/**",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
        freeCompilerArgs.addAll(
            "-opt-in=androidx.compose.material3.ExperimentalMaterial3Api",
            "-opt-in=androidx.compose.foundation.ExperimentalFoundationApi",
            "-opt-in=androidx.media3.common.util.UnstableApi",
        )
    }
}

dependencies {
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation.compose)

    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)

    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.session)
    implementation(libs.androidx.media3.datasource)
    implementation(libs.androidx.media3.datasource.okhttp)

    implementation(libs.androidx.datastore.preferences)
    implementation(libs.androidx.palette)
    implementation(libs.androidx.security.crypto)

    implementation(libs.okhttp)
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
