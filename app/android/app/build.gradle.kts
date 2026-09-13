import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

/// 本次构建是否启用了按 ABI 分片。
///
/// Flutter 在收到 `--split-per-abi` 时会向 Gradle 传 `-Psplit-per-abi=true`
/// （见 FlutterPluginUtils.kt 的 `PROP_SPLIT_PER_ABI`），这里读同一个属性。
///
/// 用途：AGP 在配置阶段就会校验「splits.abi 启用时不能存在与之不一致的
/// ndk.abiFilters」，所以 debug 变体的 abiFilters 必须按构建方式条件设置——
/// 详见下面 `buildTypes.debug` 里的说明。
val splitPerAbi = project.findProperty("split-per-abi")?.toString()?.toBoolean() ?: false

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

    // 给原生库启用压缩（默认是 Stored 未压缩）。
    //
    // 数据：APK 里所有 .so 目前都是 0% 压缩。实测这些库 deflate 后只占原来的
    // **43.3%**（libapp.so 39.9% / libflutter.so 46.5% / libmpv.so 45.1%），
    // 因此 arm64 分片包体从约 41.2MiB 降到约 21.8MiB、armeabi 从 37.2 降到约 20MiB
    // —— 相当于文件体积再砍一半，且不删任何功能、不动任何架构。
    //
    // 代价（必须知悉，这不是白拿的）：
    // 开启后系统会在**安装时把库解压到设备上**，于是
    //   包体（下载/分享的大小）↓ 一半
    //   安装后设备占用       ↑ 约 15MiB（解压出来的库 + 包内仍保留的压缩副本）
    //   安装耗时            略增（多一步解压）
    // 也就是说这是「文件更小」与「设备占用更小」之间的取舍，二者不可兼得。
    // 若更在意安装后占用，把下面这行改成 false 即可（其余配置无需改动）。
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        debug {
            // 不加 applicationIdSuffix：debug 与 release 必须是同一个应用、
            // 同一张签名，才能互相覆盖安装而不丢数据。
            signingConfig = signingConfigs.getByName("unified")
            manifestPlaceholders["appName"] = "LxPlayer"

            // debug 显式声明 ABI，内容与 Flutter 插件原本的默认列表一致
            // （FlutterPluginConstants.kt 的 DEFAULT_PLATFORMS = ARM32/ARM64/X86_64）。
            //
            // 为什么必须写出来：gradle.properties 里关了插件的 ABI 过滤
            // （disable-abi-filtering=true），debug 不再被插件限制，AGP 会放进
            // 全部 4 个 ABI —— 多出的 32 位 x86 让 debug 包从 129MiB 涨到 253MiB。
            //
            // 为什么外面套 if (!splitPerAbi)：AGP 在**配置阶段**就做全局校验，
            // 「splits.abi 启用时任何变体都不能带 ndk.abiFilters，除非两者完全一致」。
            // release 走 --split-per-abi 时，这里若仍写着 x86_64 会直接让构建失败：
            //   Conflicting configuration : 'armeabi-v7a,arm64-v8a,x86_64' in ndk abiFilters
            //   cannot be present when splits abi filters are set : armeabi-v7a,arm64-v8a
            // 而 debug 又必须保留 x86_64（模拟器调试），两者只能按构建方式二选一。
            if (!splitPerAbi) {
                ndk {
                    abiFilters.clear()
                    abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a", "x86_64"))
                }
            }
        }

        release {
            signingConfig = signingConfigs.getByName("unified")
            manifestPlaceholders["appName"] = "LxPlayer"

            // release **刻意不设置 ndk.abiFilters**。
            //
            // 原因：release 走 `--split-per-abi`（见 .github/workflows/ci.yml），
            // 由 Flutter 的 Gradle 插件去配置 `splits.abi`，再由
            // `--target-platform android-arm,android-arm64` 决定产出哪两个分片。
            // FlutterPlugin.kt 里明确写了「abiFilters 与 splits-per-abi 会配置冲突」，
            // 所以这里不能再写 abiFilters，否则构建会失败。
            //
            // 代价（需知悉）：若本地直接 `flutter build apk --release`（不带 --split-per-abi），
            // 因为上面 gradle.properties 关了插件的 ABI 过滤、这里又没设 abiFilters，
            // 会打进全部 4 个 ABI、体积约 135MiB。**release 必须带 --split-per-abi**
            // （CI 已经这么做），否则请自行加 --target-platform android-arm,android-arm64。
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
