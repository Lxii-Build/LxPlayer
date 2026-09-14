import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:file_picker/file_picker.dart';
import '../../services/window_background_service.dart';
import '../../services/auth_service.dart';
import '../../utils/theme_manager.dart';

/// 窗口背景设置对话框（赞助用户独享）
///
/// 修复历史 bug：本组件原先在 `build()` 里**无条件**返回 `fluent_ui.ContentDialog`。
/// 而 `fluent_ui` 的 `ContentDialog` 依赖 `FluentTheme` 祖先（内部会执行
/// `FluentTheme.of(context)`，在缺少该 InheritedWidget 时对空值做 `!` 解引用而崩溃）。
/// 桌面端「Material 框架」以及任何非 Fluent 根（`main.dart` 里只有 Desktop+Fluent
/// 才使用 `FluentApp`）都没有 `FluentTheme` 祖先，于是点了「窗口背景」直接抛异常。
///
/// 现在按当前框架分支：Fluent 用 `ContentDialog`，其余用 Material `AlertDialog`，
/// 底层的开关/滑块/按钮等叶子控件也相应分支。逻辑与观感保持不变。
class WindowBackgroundDialog extends StatefulWidget {
  final VoidCallback onChanged;

  const WindowBackgroundDialog({super.key, required this.onChanged});

  @override
  State<WindowBackgroundDialog> createState() => _WindowBackgroundDialogState();
}

class _WindowBackgroundDialogState extends State<WindowBackgroundDialog> {
  /// 是否处于桌面端 Fluent UI 上下文。
  bool get _isFluent => ThemeManager().isDesktopFluentUI;

  @override
  Widget build(BuildContext context) {
    final service = WindowBackgroundService();
    final isSponsor = AuthService().currentUser?.isSponsor ?? false;

    final content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildContent(context, service, isSponsor),
      ),
    );

    if (_isFluent) {
      return fluent_ui.ContentDialog(
        title: _buildTitle(isSponsor),
        content: content,
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: _buildTitle(isSponsor),
      content: SizedBox(width: double.maxFinite, child: content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  /// 标题（含「赞助独享」标记）
  Widget _buildTitle(bool isSponsor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.photo_size_select_actual_outlined),
        const SizedBox(width: 8),
        const Flexible(child: Text('窗口背景设置')),
        if (!isSponsor) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.orange, width: 1),
            ),
            child: const Text(
              '赞助独享',
              style: TextStyle(fontSize: 10, color: Colors.orange),
            ),
          ),
        ],
      ],
    );
  }

  /// 内容区（各框架共用同一份结构，仅叶子控件按框架分支）
  List<Widget> _buildContent(
    BuildContext context,
    WindowBackgroundService service,
    bool isSponsor,
  ) {
    return [
      // 赞助提示（非赞助用户）
      if (!isSponsor) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '此功能为赞助用户独享，成为赞助用户即可使用自定义窗口背景（图片或视频）',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],

      // 启用开关
      Row(
        children: [
          const Expanded(child: Text('启用窗口背景')),
          _buildToggle(
            checked: service.enabled && isSponsor,
            onChanged: isSponsor
                ? (value) async {
                    await service.setEnabled(value);
                    setState(() {});
                    widget.onChanged();
                  }
                : null,
          ),
        ],
      ),

      const SizedBox(height: 8),
      const Text(
        '为整个窗口设置背景图片或视频（独立于播放器背景）',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ),

      if (service.enabled && isSponsor) ...[
        const SizedBox(height: 16),
        _buildDivider(),
        const SizedBox(height: 16),

        // 媒体文件选择
        Row(
          children: [
            Expanded(
              child: _buildFilledButton(
                onPressed: _selectBackgroundImage,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      service.isVideo
                          ? Icons.videocam_outlined
                          : Icons.photo_library_outlined,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      service.mediaPath != null
                          ? (service.isVideo ? '更换视频' : '更换图片')
                          : '选择图片/视频',
                    ),
                  ],
                ),
              ),
            ),
            if (service.mediaPath != null) ...[
              const SizedBox(width: 8),
              _buildIconButton(
                icon: Icons.clear,
                onPressed: () async {
                  await service.clearMedia();
                  setState(() {});
                  widget.onChanged();
                },
              ),
            ],
          ],
        ),

        if (service.mediaPath != null) ...[
          const SizedBox(height: 8),
          Text(
            '当前${service.isVideo ? '视频' : '图片'}: ${service.mediaPath!.split(Platform.pathSeparator).last}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        const SizedBox(height: 16),

        // 模糊程度
        Text('模糊程度: ${service.blurAmount.toStringAsFixed(0)}'),
        const SizedBox(height: 8),
        _buildSlider(
          value: service.blurAmount,
          min: 0,
          max: 50,
          divisions: 50,
          label: service.blurAmount.toStringAsFixed(0),
          onChanged: (value) async {
            await service.setBlurAmount(value);
            setState(() {});
            widget.onChanged();
          },
        ),
        const Text(
          '0 = 清晰，50 = 最模糊',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),

        const SizedBox(height: 16),

        // 不透明度
        Text('不透明度: ${(service.opacity * 100).toStringAsFixed(0)}%'),
        const SizedBox(height: 8),
        _buildSlider(
          value: service.opacity,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          label: '${(service.opacity * 100).toStringAsFixed(0)}%',
          onChanged: (value) async {
            await service.setOpacity(value);
            setState(() {});
            widget.onChanged();
          },
        ),
        const Text(
          '0% = 完全透明，100% = 完全不透明',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),

        const SizedBox(height: 16),

        // 预览
        if (service.hasValidMedia) ...[
          const Text('预览', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: service.isVideo
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.videocam_outlined,
                            size: 48,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '视频背景\n${service.mediaPath!.split(Platform.pathSeparator).last}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          service.getMediaFile()!,
                          fit: BoxFit.cover,
                        ),
                        BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: service.blurAmount,
                            sigmaY: service.blurAmount,
                          ),
                          child: Container(
                            color: Colors.black.withOpacity(1 - service.opacity),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ],
    ];
  }

  /// 开关：Fluent 用 `ToggleSwitch`，Material 用 `Switch`
  Widget _buildToggle({
    required bool checked,
    required ValueChanged<bool>? onChanged,
  }) {
    if (_isFluent) {
      return fluent_ui.ToggleSwitch(checked: checked, onChanged: onChanged);
    }
    return Switch(value: checked, onChanged: onChanged);
  }

  /// 分隔线
  Widget _buildDivider() =>
      _isFluent ? const fluent_ui.Divider() : const Divider();

  /// 主按钮
  Widget _buildFilledButton({
    required VoidCallback onPressed,
    required Widget child,
  }) {
    if (_isFluent) {
      return fluent_ui.FilledButton(onPressed: onPressed, child: child);
    }
    return FilledButton(onPressed: onPressed, child: child);
  }

  /// 图标按钮
  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    if (_isFluent) {
      return fluent_ui.IconButton(icon: Icon(icon), onPressed: onPressed);
    }
    return IconButton(icon: Icon(icon), onPressed: onPressed);
  }

  /// 滑块
  Widget _buildSlider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    if (_isFluent) {
      return fluent_ui.Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
      );
    }
    return Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      label: label,
      onChanged: onChanged,
    );
  }

  /// 选择背景媒体文件（图片或视频）
  Future<void> _selectBackgroundImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'bmp',
        'webp',
        'mp4',
        'mov',
        'avi',
        'mkv',
        'webm',
        'm4v',
      ],
      dialogTitle: '选择窗口背景（图片或视频）',
    );

    if (result != null && result.files.single.path != null) {
      final mediaPath = result.files.single.path!;
      final service = WindowBackgroundService();

      await service.setMediaPath(mediaPath);
      setState(() {});
      widget.onChanged();

      if (mounted) {
        final isVideo = service.isVideoFile(mediaPath);
        _showMediaSetFeedback(isVideo);
      }
    }
  }

  /// 提示「背景已设置」——各框架用各自的原生反馈控件
  void _showMediaSetFeedback(bool isVideo) {
    if (_isFluent) {
      fluent_ui.displayInfoBar(
        context,
        builder: (context, close) => fluent_ui.InfoBar(
          title: Text(isVideo ? '背景视频已设置' : '背景图片已设置'),
          severity: fluent_ui.InfoBarSeverity.success,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isVideo ? '背景视频已设置' : '背景图片已设置')),
    );
  }
}
