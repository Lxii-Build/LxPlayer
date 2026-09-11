import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 本地媒体读取权限的请求结果。
///
/// 用于「读取本地音乐」场景：UI 依据该结果决定是继续导入还是给出明确提示。
enum MediaPermissionStatus {
  /// 已获得（或当前平台不需要）媒体读取权限，可以继续。
  granted,

  /// 本次请求被用户拒绝。
  denied,

  /// 被永久拒绝，需要引导用户到系统设置里手动开启。
  permanentlyDenied,
}

/// 权限管理服务
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// 请求通知权限（Android 13+）
  Future<bool> requestNotificationPermission() async {
    // 只在 Android 平台请求
    if (!Platform.isAndroid) {
      return true; // 其他平台默认有权限
    }

    try {
      final status = await Permission.notification.status;
      
      if (status.isGranted) {
        print('✅ [PermissionService] 通知权限已授予');
        return true;
      }

      if (status.isDenied) {
        print('🔔 [PermissionService] 请求通知权限...');
        final result = await Permission.notification.request();
        
        if (result.isGranted) {
          print('✅ [PermissionService] 用户授予了通知权限');
          return true;
        } else if (result.isPermanentlyDenied) {
          print('❌ [PermissionService] 用户永久拒绝了通知权限');
          return false;
        } else {
          print('⚠️ [PermissionService] 用户拒绝了通知权限');
          return false;
        }
      }

      if (status.isPermanentlyDenied) {
        print('❌ [PermissionService] 通知权限被永久拒绝，需要打开设置');
        return false;
      }

      return false;
    } catch (e) {
      print('❌ [PermissionService] 请求通知权限失败: $e');
      return false;
    }
  }

  /// 请求忽略电池优化 (Android 专用)
  /// 这有助于防止后台播放因 CPU 被挂起而卡顿
  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;

    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) {
        print('✅ [PermissionService] 电池优化已忽略');
        return true;
      }

      print('🔋 [PermissionService] 尝试请求忽略电池优化...');
      // 弹出请求对话框
      final result = await Permission.ignoreBatteryOptimizations.request();
      
      if (result.isGranted) {
        print('✅ [PermissionService] 用户授予了忽略电池优化权限');
        return true;
      } else {
        print('⚠️ [PermissionService] 用户未授予忽略电池优化权限');
        return false;
      }
    } catch (e) {
      print('❌ [PermissionService] 请求电池优化异常: $e');
      return false;
    }
  }

  /// 请求「读取本地音乐」所需的媒体权限（Android）。
  ///
  /// 按系统版本分级（由 permission_handler 把 permission group 映射到底层权限）：
  /// - Android 13+（API 33+）→ `READ_MEDIA_AUDIO`（对应 `Permission.audio`）
  /// - Android 12 及以下      → `READ_EXTERNAL_STORAGE`（对应 `Permission.storage`）
  ///
  /// 在不适用的系统版本上，对应的请求是 no-op（不会弹出第二个系统框），
  /// 所以这里**两个都请求、任一授予即视为通过**——即可覆盖两种版本，
  /// 无需再额外引入「读取系统版本」的设备信息依赖。
  ///
  /// 非 Android 平台直接返回 [MediaPermissionStatus.granted]：
  /// iOS 的本地文件访问由系统文件选择器接管，桌面端没有该运行时权限。
  Future<MediaPermissionStatus> requestAudioPermission() async {
    if (!Platform.isAndroid) {
      return MediaPermissionStatus.granted;
    }

    try {
      // 已经是授予状态就直接返回，避免重复弹框。
      if (await Permission.audio.isGranted) {
        print('✅ [PermissionService] 媒体音频权限已授予 (READ_MEDIA_AUDIO)');
        return MediaPermissionStatus.granted;
      }
      if (await Permission.storage.isGranted) {
        print('✅ [PermissionService] 存储读取权限已授予 (READ_EXTERNAL_STORAGE)');
        return MediaPermissionStatus.granted;
      }

      // Android 13+：READ_MEDIA_AUDIO。
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) {
        print('✅ [PermissionService] 用户授予了媒体音频权限 (READ_MEDIA_AUDIO)');
        return MediaPermissionStatus.granted;
      }

      // Android 12 及以下：READ_EXTERNAL_STORAGE（在 13+ 上此请求为 no-op）。
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) {
        print('✅ [PermissionService] 用户授予了存储读取权限 (READ_EXTERNAL_STORAGE)');
        return MediaPermissionStatus.granted;
      }

      final permanentlyDenied =
          audioStatus.isPermanentlyDenied || storageStatus.isPermanentlyDenied;
      print('❌ [PermissionService] 媒体读取权限被拒绝: '
          'audio=$audioStatus, storage=$storageStatus, permanent=$permanentlyDenied');
      return permanentlyDenied
          ? MediaPermissionStatus.permanentlyDenied
          : MediaPermissionStatus.denied;
    } catch (e) {
      print('❌ [PermissionService] 请求媒体读取权限异常: $e');
      return MediaPermissionStatus.denied;
    }
  }

  /// 显示权限说明对话框并跳转到设置
  Future<void> showPermissionDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要通知权限'),
        content: const Text(
          'LxPlayer 需要通知权限来显示播放控制器。\n\n'
          '请在设置中允许通知权限，以便：\n'
          '• 在通知栏显示播放控制器\n'
          '• 在锁屏界面控制播放\n'
          '• 接收媒体按钮事件',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('打开设置'),
          ),
        ],
      ),
    );
  }

  /// 本地媒体权限缺失时的明确提示对话框。
  ///
  /// [permanentlyDenied] 为 true 时说明系统不会再主动弹框，引导用户去设置页开启；
  /// 否则提示用户重新授权即可。
  Future<void> showMediaPermissionDialog(
    BuildContext context, {
    bool permanentlyDenied = false,
  }) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要媒体访问权限'),
        content: Text(
          permanentlyDenied
              ? 'LxPlayer 读取本地音频文件的权限已被拒绝，系统不会再自动询问。\n\n'
                  '请前往系统设置，为 LxPlayer 开启音频/存储权限后重试。'
              : 'LxPlayer 需要读取本地音频文件的权限，才能扫描并导入本地音乐。\n\n'
                  '请允许访问音频/存储权限后重试。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: Text(permanentlyDenied ? '打开设置' : '去授权'),
          ),
        ],
      ),
    );
  }

  /// 检查并请求所有必要的权限
  Future<bool> checkAndRequestPermissions(BuildContext context) async {
    if (!Platform.isAndroid) {
      return true; // 非 Android 平台不需要
    }

    final hasNotificationPermission = await requestNotificationPermission();
    
    if (!hasNotificationPermission) {
      // 显示说明对话框
      if (context.mounted) {
        await showPermissionDialog(context);
      }
    }

    // 🍎 额外请求忽略电池优化（非强制，不阻断面流程）
    await requestIgnoreBatteryOptimizations();

    return hasNotificationPermission;
  }
}

