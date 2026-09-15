import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'developer_mode_service.dart';

/// 头像获取服务
/// 
/// 使用隐藏的 WebView 获取需要特殊认证的头像（如 Linux Do 的 Cloudflare 保护）
/// 获取成功后缓存到本地
class AvatarFetchService {
  static final AvatarFetchService _instance = AvatarFetchService._internal();
  factory AvatarFetchService() => _instance;
  AvatarFetchService._internal();

  /// HeadlessInAppWebView 实例
  HeadlessInAppWebView? _headlessWebView;
  
  /// WebView 控制器
  InAppWebViewController? _webViewController;
  
  /// 是否已初始化
  bool _isInitialized = false;
  
  /// 是否正在获取
  bool _isFetching = false;
  
  /// 当前获取任务的 Completer
  Completer<Uint8List?>? _fetchCompleter;
  
  /// 缓存目录
  Directory? _cacheDir;
  
  // ==================== Getters ====================
  
  bool get isInitialized => _isInitialized;
  bool get isFetching => _isFetching;

  // ==================== 公开方法 ====================
  
  /// 获取头像数据
  /// 
  /// [url] - 头像 URL
  /// [cacheKey] - 缓存 key，用于本地存储
  /// 
  /// 返回头像的字节数据，如果获取失败返回 null
  Future<Uint8List?> fetchAvatar(String url, {String? cacheKey}) async {
    // 先检查缓存
    final cached = await _getFromCache(cacheKey ?? _generateCacheKey(url));
    if (cached != null) {
      print('✅ [AvatarFetch] 从缓存加载头像: $cacheKey');
      DeveloperModeService().addLog('✅ [AvatarFetch] 从缓存加载头像 ($cacheKey)');
      return cached;
    }
    
    DeveloperModeService().addLog('🔄 [AvatarFetch] 准备获取新头像: $url');
    
    // 初始化 WebView（如果尚未初始化）
    if (!_isInitialized) {
      DeveloperModeService().addLog('🚀 [AvatarFetch] WebView 未初始化，正在启动...');
      await _initialize();
    }
    
    // 如果正在获取其他头像，等待完成
    if (_isFetching) {
      print('⚠️ [AvatarFetch] 正在获取其他头像，等待...');
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isFetching) {
        print('⚠️ [AvatarFetch] 等待超时');
        return null;
      }
    }
    
    return _fetchFromWebView(url, cacheKey ?? _generateCacheKey(url));
  }
  
  /// 获取本地缓存的头像路径
  /// 
  /// 如果头像已缓存，返回本地文件路径；否则返回 null
  Future<String?> getCachedAvatarPath(String url, {String? cacheKey}) async {
    await _ensureCacheDir();
    final key = cacheKey ?? _generateCacheKey(url);
    final file = File('${_cacheDir!.path}/$key.png');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }
  
  /// 清除缓存
  Future<void> clearCache() async {
    await _ensureCacheDir();
    if (await _cacheDir!.exists()) {
      await _cacheDir!.delete(recursive: true);
      await _cacheDir!.create();
    }
    print('🗑️ [AvatarFetch] 缓存已清除');
  }
  
  /// 销毁服务
  Future<void> dispose() async {
    print('🗑️ [AvatarFetch] 销毁 WebView...');
    _isInitialized = false;
    _isFetching = false;
    _fetchCompleter?.complete(null);
    _fetchCompleter = null;
    
    await _headlessWebView?.dispose();
    _headlessWebView = null;
    _webViewController = null;
  }

  // ==================== 私有方法 ====================
  
  /// 初始化 WebView
  Future<void> _initialize() async {
    if (_isInitialized) return;
    
    print('🚀 [AvatarFetch] 初始化 WebView...');
    
    final initCompleter = Completer<bool>();
    
    _headlessWebView = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: _generateHtml(),
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        cacheEnabled: true,
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        _registerHandlers(controller);
        print('✅ [AvatarFetch] WebView 创建成功');
      },
      onLoadStop: (controller, url) {
        print('✅ [AvatarFetch] WebView 加载完成');
        _isInitialized = true;
        if (!initCompleter.isCompleted) {
          initCompleter.complete(true);
        }
      },
      onConsoleMessage: (controller, message) {
        print('🌐 [AvatarFetch Console] ${message.message}');
        DeveloperModeService().addLog('🌐 [AvatarFetch JS] ${message.message}');
      },
      onLoadError: (controller, url, code, message) {
        print('❌ [AvatarFetch] 加载错误: $code - $message');
        if (!initCompleter.isCompleted) {
          initCompleter.complete(false);
        }
      },
    );
    
    await _headlessWebView!.run();
    await initCompleter.future;
    
    print('✅ [AvatarFetch] 初始化完成');
  }
  
  /// 注册 JavaScript 处理器
  void _registerHandlers(InAppWebViewController controller) {
    // 接收头像数据
    controller.addJavaScriptHandler(
      handlerName: 'onAvatarLoaded',
      callback: (args) {
        if (args.isEmpty) {
          print('❌ [AvatarFetch] 未收到数据');
          _fetchCompleter?.complete(null);
          return;
        }
        
        final data = args[0];
        if (data == null || data == '') {
          print('❌ [AvatarFetch] 数据为空');
          _fetchCompleter?.complete(null);
          return;
        }
        
        try {
          // data 是 Base64 编码的图片数据
          final base64Data = data.toString().split(',').last;
          final bytes = base64Decode(base64Data);
          print('✅ [AvatarFetch] 收到头像数据: ${bytes.length} bytes');
          DeveloperModeService().addLog('📥 [AvatarFetch] 成功接收头像数据 (${bytes.length} bytes)');
          _fetchCompleter?.complete(bytes);
        } catch (e) {
          print('❌ [AvatarFetch] 解码失败: $e');
          DeveloperModeService().addLog('❌ [AvatarFetch] 数据解码失败: $e');
          _fetchCompleter?.complete(null);
        }
      },
    );
    
    // 加载失败
    controller.addJavaScriptHandler(
      handlerName: 'onAvatarError',
      callback: (args) {
        final error = args.isNotEmpty ? args[0] : 'Unknown error';
        print('❌ [AvatarFetch] 加载失败: $error');
        DeveloperModeService().addLog('❌ [AvatarFetch] WebView 内部加载失败: $error');
        _fetchCompleter?.complete(null);
      },
    );
  }
  
  /// 通过 WebView 获取头像
  Future<Uint8List?> _fetchFromWebView(String url, String cacheKey) async {
    if (_webViewController == null) {
      print('❌ [AvatarFetch] WebView 控制器不可用');
      return null;
    }
    
    _isFetching = true;
    _fetchCompleter = Completer<Uint8List?>();
    
    print('🔄 [AvatarFetch] 开始获取头像: $url');
    
    try {
      // 在 WebView 中加载图片并获取 Base64 数据
      await _webViewController!.evaluateJavascript(source: '''
        (function() {
          const url = '$url';
          console.log('[AvatarFetch] 开始加载: ' + url);
          
          const img = new Image();
          img.crossOrigin = 'anonymous';
          
          img.onload = function() {
            console.log('[AvatarFetch] 图片加载成功');
            try {
              const canvas = document.createElement('canvas');
              canvas.width = img.naturalWidth || img.width;
              canvas.height = img.naturalHeight || img.height;
              const ctx = canvas.getContext('2d');
              ctx.drawImage(img, 0, 0);
              const dataUrl = canvas.toDataURL('image/png');
              console.log('[AvatarFetch] 转换完成，长度: ' + dataUrl.length);
              window.flutter_inappwebview.callHandler('onAvatarLoaded', dataUrl);
            } catch (e) {
              console.error('[AvatarFetch] Canvas 操作失败: ' + e.message);
              window.flutter_inappwebview.callHandler('onAvatarError', e.message);
            }
          };
          
          img.onerror = function(e) {
            console.error('[AvatarFetch] 图片加载失败');
            window.flutter_inappwebview.callHandler('onAvatarError', 'Image load failed');
          };
          
          // 添加时间戳避免缓存
          img.src = url + (url.includes('?') ? '&' : '?') + '_t=' + Date.now();
        })();
      ''');
      
      // 等待结果（最多 30 秒）
      final result = await _fetchCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('⚠️ [AvatarFetch] 获取超时');
          return null;
        },
      );
      
      _isFetching = false;
      
      // 如果成功，保存到缓存
      if (result != null) {
        await _saveToCache(cacheKey, result);
      }
      
      return result;
    } catch (e) {
      print('❌ [AvatarFetch] 获取失败: $e');
      _isFetching = false;
      return null;
    }
  }
  
  /// 生成 HTML
  String _generateHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Avatar Fetcher</title>
</head>
<body>
<script>
  console.log('[AvatarFetch] 页面已加载');
</script>
</body>
</html>
''';
  }
  
  /// 确保缓存目录存在
  Future<void> _ensureCacheDir() async {
    if (_cacheDir != null) return;
    
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/avatar_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
  }
  
  /// 从缓存获取
  Future<Uint8List?> _getFromCache(String key) async {
    await _ensureCacheDir();
    final file = File('${_cacheDir!.path}/$key.png');
    if (await file.exists()) {
      return file.readAsBytes();
    }
    return null;
  }
  
  /// 保存到缓存
  Future<void> _saveToCache(String key, Uint8List data) async {
    await _ensureCacheDir();
    final file = File('${_cacheDir!.path}/$key.png');
    await file.writeAsBytes(data);
    print('💾 [AvatarFetch] 头像已缓存: $key');
  }
  
  /// 生成缓存 key
  String _generateCacheKey(String url) {
    // 使用 URL 的 hash 作为 key
    return url.hashCode.toRadixString(16);
  }
}
