import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cc.lxii.player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // 启用核心库脱糖支持（flutter_local_notifications 需要）
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "cc.lxii.player"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion  // 核心库脱糖需要至少 API 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 默认应用名称
        manifestPlaceholders["appName"] = "LxPlayer"
    }

    // ---- 签名：debug 与 release 共用同一张证书 ----
    //
    // 为什么不能让 debug 走自动生成的 debug.keystore：CI runner 每次都是全新机器，
    // ~/.android/debug.keystore 每次自动重新生成 → 每次构建指纹都不同，
    // 装不上也覆盖不了已装版本。所以密钥库必须是确定的文件。
    //
    // 优先用 CI 从 Secret 解码落盘的密钥库（key.properties 注入路径）；
    // 未提供时回退到随仓库提交的 keys/lxplayer-release.p12。
    // 无论走哪条路径两个变体都指向同一个 storeFile，签名必然一致，
    // CI 会用 apksigner 提取两者指纹逐字节比对来证明这一点。
    signingConfigs {
        create("unified") {
            val committed = rootProject.file("keys/lxplayer-release.p12")
            val injected = keystoreProperties["storeFile"]
                ?.takeIf { it.toString().isNotBlank() }
                ?.let { rootProject.file(it.toString()) }
                ?.takeIf { it.isFile }

            storeFile = injected ?: committed
            storeType = "PKCS12"
            storePassword = if (injected != null) {
                keystoreProperties["storePassword"]?.toString() ?: "lxplayer"
            } else {
                "lxplayer"
            }
            keyAlias = if (injected != null) {
                keystoreProperties["keyAlias"]?.toString()?.takeIf { it.isNotBlank() } ?: "lxplayer"
            } else {
                "lxplayer"
            }
            keyPassword = if (injected != null) {
                keystoreProperties["keyPassword"]?.toString() ?: "lxplayer"
            } else {
                "lxplayer"
            }
            // v1 已废弃且拖慢构建；v2/v3 覆盖全部支持机型，v4 便于增量安装。
            enableV1Signing = false
            enableV2Signing = true
            enableV3Signing = true
            enableV4Signing = true
        }
    }

    buildTypes {
        debug {
            // 不加 applicationIdSuffix：debug 与 release 必须是同一个应用、
            // 同一张签名，才能互相覆盖安装而不丢数据。
            signingConfig = signingConfigs.getByName("unified")
            manifestPlaceholders["appName"] = "LxPlayer"

            // 显式声明 debug 的 ABI，内容与 Flutter 插件原本的默认列表一致
            // （FlutterPluginConstants.kt 的 DEFAULT_PLATFORMS = ARM32/ARM64/X86_64）。
            //
            // 为什么必须写出来：gradle.properties 里关掉了插件的 ABI 过滤
            // （disable-abi-filtering=true，为了 release 能只打 ARM），
            // 于是 debug 不再被插件限制，AGP 会放进全部 4 个 ABI —— 多出的 32 位
            // x86 让 debug 包从 129MiB 涨到 253MiB，纯浪费。
            // 这里显式写回 3 个，既恢复原状又保留 x86_64 模拟器调试能力。
            ndk {
                abiFilters.clear()
                abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a", "x86_64"))
            }
        }

        release {
            signingConfig = signingConfigs.getByName("unified")
            manifestPlaceholders["appName"] = "LxPlayer"

            // release 只打 ARM 两个 ABI。
            //
            // x86_64 是**模拟器专用**架构，真实 Android 设备全是 ARM；而 APK 里
            // x86_64 那部分（libapp.so / libflutter.so / libmpv.so / libbarhopper.so）
            // 永远不会被真机加载。实测该目录一度占 48.0MiB。
            //
            // 注意这里必须配合 android/gradle.properties 里的 disable-abi-filtering=true：
            // 否则 Flutter 插件会把 defaultConfig 的 abiFilters 清空重设，把 x86_64 加回来。
            // 也正因为那个开关，debug 变体不受影响、仍保留全 ABI，x86_64 模拟器照常调试。
            //
            // 保留 armeabi-v7a 是兼容性取舍：它覆盖老旧 32 位设备。
            ndk {
                abiFilters.clear()
                abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a"))
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 核心库脱糖支持（flutter_local_notifications 需要 2.1.4+）
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // 媒体兼容库：提供 MediaBrowserCompat / MediaControllerCompat / MediaStyle 等
    implementation("androidx.media:media:1.7.0")
    
    // Android 12+ Splash Screen API 向后兼容库
    implementation("androidx.core:core-splashscreen:1.0.1")
}
