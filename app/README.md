
# LxPlayer 🎵

一个功能完善的跨平台音乐播放器，使用 Flutter 开发。


> [!CAUTION]
> 根据版权合规要求，项目已经移除了内置音源，您需要先导入音源才能正常使用！兼容洛雪音源，TuneHub，OmniParse。



## 📱 支持平台

- ✅ Windows
- ✅ Android
- ✅ Linux
- ✅ macOS
- ✅ iOS

## 🚀 快速开始

### 下载预编译版本

前往 [Releases](https://github.com/your-repo/releases) 页面下载对应平台的安装包。

### 本地开发运行

```bash
# 安装依赖
flutter pub get

# 运行应用（自动选择连接的设备）
flutter run

# 指定平台运行
flutter run -d windows
flutter run -d linux
flutter run -d macos
flutter run -d android
```

### 手动构建

```bash
# Windows
flutter build windows --release

# Linux
flutter build linux --release

# macOS
flutter build macos --release

# Android APK
flutter build apk --release --split-per-abi

# iOS (需要 macOS)
flutter build ios --release
```

### 自动构建（GitHub Actions）

推送版本标签即可自动构建所有平台：

```bash
git tag v1.0.4
git push origin v1.0.4
```

详细说明请查看 [GitHub Actions 构建指南](docs/GITHUB_ACTIONS_BUILD.md)。

### 后端运行

```bash
cd backend

# 安装依赖
bun install

# 启动服务器
bun run src/index.ts
```

### 自研后端（可选，需自行部署）

除默认的第三方后端外，仓库内还带一个自研 Go 后端（[`server/`](../server)）。它是**可选项**：
**必须自己部署之后才能在 App 里启用**；未配置时 App 的行为与今天完全一致，登录不会受影响。

- 部署方式、端点、以及**与 App 的能力兼容矩阵**见 [`server/README.md`](../server/README.md)。
- 启用方式：自研后端由**独立的账号后端开关**控制（持久化键 `account_backend_mode` /
  `account_backend_base_url`），与「自定义源」配置**互不影响**。只有当模式为 `selfHosted`
  且地址非空时才生效；其它情况一律走官方后端（存量用户升级后零行为变化）。
  本轮先提供持久化配置 + 文档，设置页可视化开关在下一轮加入。
- 能力边界：自研后端目前**只支持「登录 / 获取用户信息」**。注册、重置密码、修改用户名、
  第三方账号绑定、LinuxDo 登录、IP 归属地更新等在 selfHosted 模式下会**明确提示「该后端不支持」**，
  不会静默成功。

