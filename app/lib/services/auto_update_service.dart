import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/version_info.dart';
import 'developer_mode_service.dart';
import 'persistent_storage_service.dart';
import 'url_service.dart';

/// 自动更新服务
class AutoUpdateService extends ChangeNotifier {
  static final AutoUpdateService _instance = AutoUpdateService._internal();
  factory AutoUpdateService() => _instance;
  AutoUpdateService._internal();

  static const String _storageKey = 'auto_update_enabled';

  bool _isInitialized = false;
  bool _enabled = false;
  bool _isUpdating = false;
  bool _requiresRestart = false;
  double _progress = 0.0;
  String _statusMessage = '未开始';
  String? _lastError;
  VersionInfo? _pendingVersion;
  DateTime? _lastSuccessAt;

  /// 初始化自动更新服务
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      final storedValue = PersistentStorageService().getBool(_storageKey);
      _enabled = storedValue ?? false;
      _isInitialized = true;
      DeveloperModeService().addLog('🔄 自动更新服务初始化，当前状态: ${_enabled ? '已开启' : '已关闭'}');
    } catch (e) {
      DeveloperModeService().addLog('❌ 自动更新服务初始化失败: $e');
    }
  }

  bool get isInitialized => _isInitialized;
  bool get isEnabled => _enabled;
  bool get isUpdating => _isUpdating;
  bool get requiresRestart => _requiresRestart;
  double get progress => _progress;
  String get statusMessage => _statusMessage;
  String? get lastError => _lastError;
  VersionInfo? get pendingVersion => _pendingVersion;
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// 当前平台是否支持自动更新
  bool get isPlatformSupported => Platform.isWindows || Platform.isAndroid;

  /// 设置自动更新开关
  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;

    _enabled = value;
    notifyListeners();

    final saved = await PersistentStorageService().setBool(_storageKey, value);
    if (!saved) {
      DeveloperModeService().addLog('⚠️ 自动更新状态保存失败');
    }

    DeveloperModeService().addLog(value ? '⚙️ 自动更新已开启' : '⏸️ 自动更新已关闭');

    if (value && _pendingVersion != null && !_isUpdating && isPlatformSupported) {
      // 延迟触发，确保调用方已有机会更新 UI
      unawaited(Future.delayed(const Duration(milliseconds: 200), () {
        startUpdate(versionInfo: _pendingVersion!, autoTriggered: true);
      }));
    }
  }

  /// 监听到新版本信息
  void onNewVersionDetected(VersionInfo versionInfo) {
    _pendingVersion = versionInfo;
    _lastError = null;
    _requiresRestart = false;
    notifyListeners();

    if (_enabled && !_isUpdating && isPlatformSupported && !versionInfo.forceUpdate) {
      startUpdate(versionInfo: versionInfo, autoTriggered: true);
    }
  }

  /// 清除待更新版本（例如确认已是最新版本时）
  void clearPendingVersion() {
    if (_pendingVersion == null) return;
    _pendingVersion = null;
    notifyListeners();
  }

  /// 手动或自动触发更新
  Future<void> startUpdate({VersionInfo? versionInfo, bool autoTriggered = false}) async {
    versionInfo ??= _pendingVersion;

    if (versionInfo == null) {
      _statusMessage = '未检测到可用更新';
      _lastError = '没有可用的版本信息';
      notifyListeners();
      return;
    }

    if (!isPlatformSupported) {
      _statusMessage = '当前平台暂不支持自动更新';
      _lastError = _statusMessage;
      notifyListeners();
      return;
    }

    if (_isUpdating) {
      DeveloperModeService().addLog('⚠️ 自动更新任务已在执行中，跳过重复触发');
      return;
    }

    final downloadUrl = _resolveDownloadUrl(versionInfo);
    if (downloadUrl == null) {
      final message = '后端未提供当前平台的更新包链接';
      _statusMessage = message;
      _lastError = message;
      notifyListeners();
      DeveloperModeService().addLog('❌ $message');
      return;
    }

    _isUpdating = true;
    _progress = 0.0;
    _lastError = null;
    _requiresRestart = false;
    _statusMessage = autoTriggered ? '正在后台自动下载更新...' : '正在下载更新包...';
    notifyListeners();

    DeveloperModeService().addLog('⬇️ 原始下载URL: $downloadUrl');
    DeveloperModeService().addLog('🌐 当前后端baseUrl: ${UrlService().baseUrl}');

    try {
      final normalizedUrl = _normalizeDownloadUrl(downloadUrl);
      DeveloperModeService().addLog('🔄 归一化后URL: $normalizedUrl');
      final downloadedFile = await _downloadToFile(normalizedUrl);

      _statusMessage = '下载完成，正在安装...';
      _progress = 1.0;
      notifyListeners();

      if (Platform.isWindows) {
        await _installOnDesktop(downloadedFile, versionInfo);
      } else if (Platform.isAndroid) {
        await _installOnAndroid(downloadedFile);
      } else {
        // 兜底处理
        await _openFile(downloadedFile);
      }

      _statusMessage = '更新安装完成，请重启应用生效';
      _requiresRestart = Platform.isWindows;
      _lastSuccessAt = DateTime.now();
      DeveloperModeService().addLog('✅ 自动更新完成，等待用户重启应用');
    } catch (e, stackTrace) {
      _lastError = e.toString();
      _statusMessage = '更新失败: $e';
      DeveloperModeService().addLog('❌ 自动更新失败: $e');
      DeveloperModeService().addLog(stackTrace.toString());
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  /// 辅助方法：根据平台解析下载地址
  String? _resolveDownloadUrl(VersionInfo versionInfo) {
    if (Platform.isWindows) {
      return versionInfo.platformDownloadUrl('windows') ?? versionInfo.downloadUrl;
    }
    if (Platform.isAndroid) {
      return versionInfo.platformDownloadUrl('android') ?? versionInfo.downloadUrl;
    }
    if (Platform.isIOS) {
      return versionInfo.platformDownloadUrl('ios') ?? versionInfo.downloadUrl;
    }
    if (Platform.isMacOS) {
      return versionInfo.platformDownloadUrl('macos') ?? versionInfo.downloadUrl;
    }
    if (Platform.isLinux) {
      return versionInfo.platformDownloadUrl('linux') ?? versionInfo.downloadUrl;
    }
    return versionInfo.downloadUrl;
  }

  /// 归一化下载地址：支持相对路径和绝对路径
  /// 如果URL是完整URL但host不匹配，则使用当前baseUrl替换
  String _normalizeDownloadUrl(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      
      // 如果有scheme（完整URL），检查是否需要替换host
      if (uri.hasScheme) {
        final currentBaseUrl = UrlService().baseUrl;
        final currentUri = Uri.parse(currentBaseUrl);
        
        // 如果host不匹配，使用当前baseUrl替换
        if (uri.host != currentUri.host || uri.port != currentUri.port || uri.scheme != currentUri.scheme) {
          final path = uri.path;
          final normalized = '$currentBaseUrl${path.startsWith('/') ? '' : '/'}$path';
          DeveloperModeService().addLog('🔄 URL host不匹配，替换为: $normalized');
          return normalized;
        }
        return rawUrl;
      }

      // 相对路径，使用baseUrl拼接
      final base = UrlService().baseUrl;
      final cleanedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      return '$cleanedBase${rawUrl.startsWith('/') ? '' : '/'}$rawUrl';
    } catch (e) {
      DeveloperModeService().addLog('❌ URL归一化失败: $e, 原始URL: $rawUrl');
      // 如果解析失败，尝试直接拼接
      final base = UrlService().baseUrl;
      final cleanedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      return '$cleanedBase${rawUrl.startsWith('/') ? '' : '/'}$rawUrl';
    }
  }

  /// 下载文件到临时目录
  Future<File> _downloadToFile(String url) async {
    DeveloperModeService().addLog('📥 开始下载，URL: $url');
    
    final uri = Uri.parse(url);
    final fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'update.bin';

    final downloadDir = await _resolveDownloadDirectory();
    final file = File(p.join(downloadDir.path, fileName));

    if (await file.exists()) {
      await file.delete();
    }

    DeveloperModeService().addLog('📁 下载目录: ${downloadDir.path}');
    DeveloperModeService().addLog('📄 文件名: $fileName');

    final request = http.Request('GET', uri);
    DeveloperModeService().addLog('🌐 发送请求: ${request.method} ${request.url}');
    
    final response = await request.send();
    
    DeveloperModeService().addLog('📥 收到响应: 状态码 ${response.statusCode}');
    DeveloperModeService().addLog('📥 响应头: ${response.headers}');

    if (response.statusCode != 200) {
      final errorMsg = '下载失败，状态码: ${response.statusCode}, URL: $url';
      DeveloperModeService().addLog('❌ $errorMsg');
      throw HttpException(errorMsg);
    }

    final contentLength = response.contentLength ?? 0;
    int received = 0;

    final sink = file.openWrite();
    await for (final chunk in response.stream) {
      received += chunk.length;
      sink.add(chunk);

      if (contentLength > 0) {
        _progress = received / contentLength;
        notifyListeners();
      }
    }

    await sink.close();
    return file;
  }

  Future<Directory> _resolveDownloadDirectory() async {
    Directory baseDir;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final installDir = Directory(_resolveInstallDirectory());
      baseDir = Directory(p.join(installDir.path, 'updates'));
    } else {
      final supportDir = await getApplicationSupportDirectory();
      baseDir = Directory(p.join(supportDir.path, 'updates'));
    }

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
  }

  String _resolveInstallDirectory() {
    try {
      final executable = File(Platform.resolvedExecutable);
      final executableName = executable.uri.pathSegments.isNotEmpty
          ? executable.uri.pathSegments.last.toLowerCase()
          : '';

      if (executableName.contains('flutter') || executableName.contains('dart')) {
        return Directory.current.path;
      }
      return executable.parent.path;
    } catch (_) {
      return Directory.current.path;
    }
  }

  Future<void> _installOnDesktop(File archiveFile, VersionInfo versionInfo) async {
    if (!archiveFile.path.endsWith('.zip')) {
      // 非 Zip 包直接尝试打开
      await _openFile(archiveFile);
      return;
    }

    _statusMessage = '正在解压更新包...';
    notifyListeners();

    final bytes = await archiveFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);

    // 在 Windows 上，解压到临时目录并启动独立更新器
    if (Platform.isWindows) {
      await _installOnWindowsWithUpdater(archive, archiveFile);
      return;
    }

    // 其他桌面平台：直接解压到安装目录
    final installDir = Directory(_resolveInstallDirectory());
    final rootSegments = <String>{};
    for (final entry in archive) {
      final sanitizedName = _sanitizeArchiveEntry(entry.name);
      if (sanitizedName.isEmpty) continue;
      final parts = sanitizedName.split('/');
      if (parts.isNotEmpty) {
        rootSegments.add(parts.first);
      }
    }

    final shouldStripRoot = rootSegments.length == 1 && rootSegments.first.isNotEmpty;
    final rootToStrip = shouldStripRoot ? '${rootSegments.first}/' : null;

    int successCount = 0;
    int skipCount = 0;
    final skippedFiles = <String>[];

    for (final entry in archive) {
      var sanitizedName = _sanitizeArchiveEntry(entry.name);
      if (sanitizedName.isEmpty) {
        continue;
      }

      if (rootToStrip != null && sanitizedName.startsWith(rootToStrip)) {
        sanitizedName = sanitizedName.substring(rootToStrip.length);
      }

      if (sanitizedName.isEmpty) {
        continue;
      }

      final outputPath = p.join(installDir.path, sanitizedName);

      if (entry.isDirectory) {
        final directory = Directory(outputPath);
        if (!directory.existsSync()) {
          try {
            directory.createSync(recursive: true);
            successCount++;
          } catch (e) {
            DeveloperModeService().addLog('⚠️ 创建目录失败: $outputPath - $e');
            skipCount++;
          }
        }
      } else {
        final file = File(outputPath);
        try {
          file.parent.createSync(recursive: true);
          final data = entry.content as List<int>;
          
          await file.writeAsBytes(data, flush: true);
          successCount++;
          DeveloperModeService().addLog('✅ 更新文件: $sanitizedName');
        } catch (e) {
          DeveloperModeService().addLog('⚠️ 更新文件失败: $sanitizedName - $e');
          skipCount++;
          skippedFiles.add(sanitizedName);
        }
      }
    }

    DeveloperModeService().addLog('📦 解压完成: 成功 $successCount 个，跳过 $skipCount 个');
    if (skippedFiles.isNotEmpty) {
      DeveloperModeService().addLog('⏭️ 跳过的文件: ${skippedFiles.take(10).join(', ')}${skippedFiles.length > 10 ? '...' : ''}');
    }
    
    archiveFile.delete().ignore();
    
    if (skipCount > 0) {
      _statusMessage = '更新完成（部分文件将在重启后生效）';
    } else {
      _statusMessage = '更新文件已覆盖，等待重启';
    }
    notifyListeners();
  }

  /// Windows 平台使用独立更新器安装
  Future<void> _installOnWindowsWithUpdater(Archive archive, File archiveFile) async {
    try {
      final installDir = Directory(_resolveInstallDirectory());
      
      // 创建临时更新目录
      final tempUpdateDir = Directory(p.join(installDir.path, 'updates', 'temp_${DateTime.now().millisecondsSinceEpoch}'));
      if (!await tempUpdateDir.exists()) {
        await tempUpdateDir.create(recursive: true);
      }
      
      DeveloperModeService().addLog('📁 临时更新目录: ${tempUpdateDir.path}');
      
      // 分析压缩包结构，判断是否需要去除顶层目录
      final rootSegments = <String>{};
      for (final entry in archive) {
        final sanitizedName = _sanitizeArchiveEntry(entry.name);
        if (sanitizedName.isEmpty) continue;
        final parts = sanitizedName.split('/');
        if (parts.isNotEmpty) {
          rootSegments.add(parts.first);
        }
      }
      
      final shouldStripRoot = rootSegments.length == 1 && rootSegments.first.isNotEmpty;
      final rootToStrip = shouldStripRoot ? '${rootSegments.first}/' : null;
      
      DeveloperModeService().addLog('📦 解压结构分析: ${shouldStripRoot ? "去除顶层目录 '$rootToStrip'" : "保持原结构"}');
      
      // 解压所有文件到临时目录
      int extractCount = 0;
      for (final entry in archive) {
        var sanitizedName = _sanitizeArchiveEntry(entry.name);
        if (sanitizedName.isEmpty) continue;
        
        // 去除顶层目录（如果需要）
        if (rootToStrip != null && sanitizedName.startsWith(rootToStrip)) {
          sanitizedName = sanitizedName.substring(rootToStrip.length);
        }
        
        if (sanitizedName.isEmpty) continue;
        
        final outputPath = p.join(tempUpdateDir.path, sanitizedName);
        
        if (entry.isDirectory) {
          final directory = Directory(outputPath);
          if (!directory.existsSync()) {
            directory.createSync(recursive: true);
          }
        } else {
          final file = File(outputPath);
          file.parent.createSync(recursive: true);
          final data = entry.content as List<int>;
          await file.writeAsBytes(data, flush: true);
          extractCount++;
          
          // 每50个文件输出一次进度
          if (extractCount % 50 == 0) {
            DeveloperModeService().addLog('📦 已解压 $extractCount 个文件...');
          }
        }
      }
      
      DeveloperModeService().addLog('✅ 解压完成，共 $extractCount 个文件');
      
      // 删除下载的压缩包
      archiveFile.delete().ignore();
      
      // 从 assets 加载更新器脚本并写入到临时文件
      DeveloperModeService().addLog('📝 加载更新器脚本...');
      
      String updaterScriptContent;
      try {
        // 尝试从新版本的文件中读取（如果存在）
        final newUpdaterPath = File(p.join(tempUpdateDir.path, 'data', 'flutter_assets', 'windows', 'runner', 'updater.ps1'));
        if (await newUpdaterPath.exists()) {
          updaterScriptContent = await newUpdaterPath.readAsString();
          DeveloperModeService().addLog('✅ 使用新版本的更新器脚本');
        } else {
          // 从当前版本的 assets 加载
          updaterScriptContent = await rootBundle.loadString('windows/runner/updater.ps1');
          DeveloperModeService().addLog('✅ 使用当前版本的更新器脚本');
        }
      } catch (e) {
        DeveloperModeService().addLog('❌ 加载更新器脚本失败: $e');
        throw Exception('无法加载更新器脚本: $e');
      }
      
      // 将脚本写入到临时文件
      final updaterScriptFile = File(p.join(tempUpdateDir.parent.path, 'updater_${DateTime.now().millisecondsSinceEpoch}.ps1'));
      await updaterScriptFile.writeAsString(updaterScriptContent);
      DeveloperModeService().addLog('📝 更新器脚本已写入: ${updaterScriptFile.path}');
      
      // 验证文件是否真的存在
      if (!await updaterScriptFile.exists()) {
        throw Exception('更新器脚本文件写入失败');
      }
      DeveloperModeService().addLog('✓ 已验证脚本文件存在');
      
      File updaterToUse = updaterScriptFile;
      
      // 准备更新器参数
      final exePath = Platform.resolvedExecutable;
      
      // 确保路径格式正确
      final installDirPath = installDir.path.replaceAll('/', '\\');
      final updateDirPath = tempUpdateDir.path.replaceAll('/', '\\');
      final exePathClean = exePath.replaceAll('/', '\\');
      final scriptPath = updaterToUse.path.replaceAll('/', '\\');
      
      // 先创建一个批处理文件来启动更新器（最可靠的方式）
      final batchFile = File(p.join(tempUpdateDir.parent.path, 'start_updater.bat'));
      final batchContent = '''@echo off
:: Check for administrator privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    :: Already running as administrator
    goto :RunUpdater
) else (
    :: Request administrator privileges
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:RunUpdater
echo ========================================
echo LxPlayer Updater
echo ========================================
echo.
echo Script: $scriptPath
echo Install: $installDirPath
echo Update: $updateDirPath
echo.
echo Starting updater with administrator privileges...
echo.

powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File "$scriptPath" -InstallDir "$installDirPath" -UpdateDir "$updateDirPath" -ExePath "$exePathClean" -WaitSeconds 3

echo.
echo Update completed
echo Window will close automatically in 2 seconds...
timeout /t 2 /nobreak >nul
exit
''';
      
      // 使用 ASCII 编码写入批处理文件（避免中文编码问题）
      await batchFile.writeAsString(batchContent, encoding: latin1);
      DeveloperModeService().addLog('📝 批处理文件已创建: ${batchFile.path}');
      
      DeveloperModeService().addLog('🚀 启动更新器...');
      DeveloperModeService().addLog('   批处理文件: ${batchFile.path}');
      DeveloperModeService().addLog('   更新器脚本: $scriptPath');
      DeveloperModeService().addLog('   安装目录: $installDirPath');
      DeveloperModeService().addLog('   更新目录: $updateDirPath');
      DeveloperModeService().addLog('   主程序: $exePathClean');
      
      try {
        // 方式1: 直接运行批处理文件（最简单可靠）
        final process = await Process.start(
          batchFile.path,
          [],
          mode: ProcessStartMode.detached,
          runInShell: true,
        );
        
        DeveloperModeService().addLog('✅ 更新器批处理已启动 (PID: ${process.pid})');
      } catch (e) {
        DeveloperModeService().addLog('❌ 批处理启动失败: $e');
        DeveloperModeService().addLog('尝试方式2: 使用 cmd 启动批处理');
        
        // 方式2: 使用 cmd /c 启动
        try {
          final process = await Process.start(
            'cmd.exe',
            ['/c', batchFile.path],
            mode: ProcessStartMode.detached,
            runInShell: false,
          );
          
          DeveloperModeService().addLog('✅ 更新器批处理已启动 (方式2, PID: ${process.pid})');
        } catch (e2) {
          DeveloperModeService().addLog('❌ 方式2也失败: $e2');
          DeveloperModeService().addLog('尝试方式3: 直接启动 PowerShell');
          
          // 方式3: 直接启动 PowerShell（最后的备用方案）
          final arguments = [
            '-WindowStyle', 'Hidden',
            '-ExecutionPolicy', 'Bypass',
            '-NoProfile',
            '-File', scriptPath,
            '-InstallDir', installDirPath,
            '-UpdateDir', updateDirPath,
            '-ExePath', exePathClean,
            '-WaitSeconds', '3',
          ];
          
          try {
            final process = await Process.start(
              'powershell.exe',
              arguments,
              mode: ProcessStartMode.detached,
            );
            
            DeveloperModeService().addLog('✅ 更新器进程已启动 (方式3, PID: ${process.pid})');
          } catch (e3) {
            DeveloperModeService().addLog('❌ 所有方式都失败了');
            DeveloperModeService().addLog('   错误1: $e');
            DeveloperModeService().addLog('   错误2: $e2');
            DeveloperModeService().addLog('   错误3: $e3');
            throw Exception('无法启动更新器进程，请查看日志了解详情');
          }
        }
      }
      
      _statusMessage = '更新器已启动，应用即将重启';
      _requiresRestart = true;
      notifyListeners();
      
      DeveloperModeService().addLog('⏳ 等待 2 秒确保更新器完全启动...');
      
      // 增加等待时间，确保更新器完全启动
      await Future.delayed(const Duration(seconds: 2));
      
      DeveloperModeService().addLog('👋 退出应用 - exit(0)');
      
      // 退出应用
      exit(0);
      
    } catch (e, stackTrace) {
      DeveloperModeService().addLog('❌ Windows 更新器启动失败: $e');
      DeveloperModeService().addLog(stackTrace.toString());
      rethrow;
    }
  }

  Future<void> _installOnAndroid(File packageFile) async {
    if (!packageFile.path.endsWith('.apk')) {
      await _openFile(packageFile);
      return;
    }

    _statusMessage = '准备安装更新...';
    notifyListeners();

    try {
      // 检查并请求安装权限（Android 8.0+）
      if (Platform.isAndroid) {
        DeveloperModeService().addLog('📱 检查安装权限...');
        // OpenFilex 会自动处理权限请求
      }

      _statusMessage = '正在调用系统安装程序...';
      notifyListeners();

      // 使用 OpenFilex 打开 APK 文件
      // type: 1 表示强制使用 APK 安装器
      final result = await OpenFilex.open(
        packageFile.path,
        type: 'application/vnd.android.package-archive',
        uti: 'com.android.package-archive',
      );
      
      DeveloperModeService().addLog('📱 APK 安装结果: ${result.message}');
      DeveloperModeService().addLog('📱 结果类型: ${result.type}');
      
      if (result.type == ResultType.done) {
        _statusMessage = '已打开安装程序，请按照提示完成安装';
        DeveloperModeService().addLog('✅ 安装程序已打开');
      } else if (result.type == ResultType.noAppToOpen) {
        _statusMessage = '无法打开安装程序';
        _lastError = '系统无法找到 APK 安装器';
        DeveloperModeService().addLog('❌ 无法打开安装程序');
      } else if (result.type == ResultType.permissionDenied) {
        _statusMessage = '权限被拒绝';
        _lastError = '需要授予"安装未知应用"权限才能更新';
        DeveloperModeService().addLog('❌ 安装权限被拒绝');
      } else {
        _statusMessage = '打开安装程序时出错';
        _lastError = result.message;
        DeveloperModeService().addLog('⚠️ 安装出错: ${result.message}');
      }
    } catch (e, stackTrace) {
      _statusMessage = '安装失败';
      _lastError = e.toString();
      DeveloperModeService().addLog('❌ 安装异常: $e');
      DeveloperModeService().addLog(stackTrace.toString());
    }
    
    notifyListeners();
  }

  Future<void> _openFile(File file) async {
    await OpenFilex.open(file.path);
  }

  String _sanitizeArchiveEntry(String originalName) {
    var name = originalName.replaceAll('\\', '/');
    name = p.normalize(name);

    while (name.startsWith('../')) {
      name = name.substring(3);
    }
    while (name.startsWith('./')) {
      name = name.substring(2);
    }

    if (name.contains('..')) {
      return '';
    }
    return name;
  }
}

extension on Future<void> {
  void ignore() {}
}

