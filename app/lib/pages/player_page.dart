import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import '../services/player_service.dart';
import '../services/layout_preference_service.dart';
import '../services/lyric_style_service.dart';
import '../utils/theme_manager.dart';
import '../models/lyric_line.dart';
import '../models/song_detail.dart';
import '../utils/lyric_parser.dart';
import 'mobile_player_page.dart';
import 'player_components/player_window_controls.dart';
import 'player_components/player_background.dart';
import 'player_components/player_karaoke_lyrics_panel.dart';
import 'player_components/player_fluid_cloud_lyrics_panel.dart';
import 'player_components/player_fluid_cloud_layout.dart'; // 导入新布局
import 'player_components/player_immersive_layout.dart'; // 导入沉浸样式布局
import 'player_components/minimal_lyric_flow_layout.dart'; // 极简歌词流布局
import 'player_components/player_playlist_panel.dart';
import 'player_components/player_control_center.dart';
import 'player_components/player_dialogs.dart';

/// 全屏播放器页面（重构版本）
/// 根据平台自动选择布局，现在使用组件化架构
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WindowListener, TickerProviderStateMixin {
  // 歌词相关
  List<LyricLine> _lyrics = [];
  int _currentLyricIndex = -1;
  String? _lastTrackId;
  
  // UI 状态
  bool _isMaximized = false;
  bool _showPlaylist = false;
  bool _showTranslation = true;
  bool _showControlCenter = false;
  
  // 动画控制器
  AnimationController? _playlistAnimationController;
  Animation<Offset>? _playlistSlideAnimation;
  AnimationController? _controlCenterAnimationController;
  Animation<double>? _controlCenterFadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupListeners();
    _initializeData();
  }

  @override
  void dispose() {
    _disposeAnimations();
    _removeListeners();
    super.dispose();
  }

  /// 初始化动画控制器
  void _initializeAnimations() {
    // 播放列表动画
    _playlistAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _playlistSlideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _playlistAnimationController!,
      curve: Curves.easeInOut,
    ));
    
    // 控制中心动画
    _controlCenterAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _controlCenterFadeAnimation = CurvedAnimation(
      parent: _controlCenterAnimationController!,
      curve: Curves.easeInOut,
    );
  }

  /// 设置监听器
  void _setupListeners() {
    PlayerService().addListener(_onPlayerStateChanged);
    LyricStyleService().addListener(_onLyricStyleChanged);
    
    if (Platform.isWindows) {
      LayoutPreferenceService().addListener(_onLayoutModeChanged);
      PlayerService().positionNotifier.addListener(_onPositionChanged);
      windowManager.addListener(this);
      _checkMaximizedState();
    }
  }

  /// 移除监听器
  void _removeListeners() {
    PlayerService().removeListener(_onPlayerStateChanged);
    LyricStyleService().removeListener(_onLyricStyleChanged);
    
    if (Platform.isWindows) {
      LayoutPreferenceService().removeListener(_onLayoutModeChanged);
      PlayerService().positionNotifier.removeListener(_onPositionChanged);
      windowManager.removeListener(this);
    }
  }

  /// 释放动画控制器
  void _disposeAnimations() {
    _playlistAnimationController?.dispose();
    _controlCenterAnimationController?.dispose();
  }

  /// 初始化数据
  void _initializeData() {
    LyricStyleService().initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentTrack = PlayerService().currentTrack;
      _lastTrackId = currentTrack != null 
          ? '${currentTrack.source.name}_${currentTrack.id}' 
          : null;
      _loadLyrics();
    });
  }

  /// 检查窗口是否最大化
  Future<void> _checkMaximizedState() async {
    if (Platform.isWindows) {
      final isMaximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() {
          _isMaximized = isMaximized;
        });
      }
    }
  }

  @override
  void onWindowMaximize() {
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      _isMaximized = false;
    });
  }

  /// 布局模式变化回调
  void _onLayoutModeChanged() {
    if (mounted) {
      setState(() {
        print('🖥️ [PlayerPage] 布局模式已变化，刷新播放器页面');
      });
    }
  }

  /// 歌词样式变化回调
  void _onLyricStyleChanged() {
    if (mounted) {
      setState(() {
        print('🎤 [PlayerPage] 歌词样式已变化，刷新歌词面板');
      });
    }
  }

  /// 播放进度变化回调
  void _onPositionChanged() {
    if (!mounted) return;
    _updateCurrentLyric();
  }

  /// 播放器状态变化回调
  void _onPlayerStateChanged() {
    if (!mounted) return;
    
    final currentTrack = PlayerService().currentTrack;
    final currentTrackId = currentTrack != null 
        ? '${currentTrack.source.name}_${currentTrack.id}' 
        : null;
    
    if (currentTrackId != _lastTrackId) {
      // 歌曲已切换，重新加载歌词
      print('🎵 [PlayerPage] 检测到歌曲切换，重新加载歌词');
      _lastTrackId = currentTrackId;
      _lyrics = [];
      _currentLyricIndex = -1;
      _loadLyrics();
      setState(() {});
    } else {
      // 只更新歌词行索引
      _updateCurrentLyric();
    }
  }

  /// 切换播放列表显示状态
  void _togglePlaylist() {
    setState(() {
      _showPlaylist = !_showPlaylist;
      if (_showPlaylist) {
        _playlistAnimationController?.forward();
      } else {
        _playlistAnimationController?.reverse();
      }
    });
  }
  
  /// 切换控制中心显示状态
  void _toggleControlCenter() {
    setState(() {
      _showControlCenter = !_showControlCenter;
      if (_showControlCenter) {
        _controlCenterAnimationController?.forward();
      } else {
        _controlCenterAnimationController?.reverse();
      }
    });
  }

  /// 切换译文显示
  void _toggleTranslation() {
    setState(() {
      _showTranslation = !_showTranslation;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_showTranslation ? '已显示译文' : '已隐藏译文'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// 加载歌词（异步执行，不阻塞 UI）
  Future<void> _loadLyrics() async {
    final currentTrack = PlayerService().currentTrack;
    if (currentTrack == null) return;

    print('🔍 [PlayerPage] 开始加载歌词，当前 Track: ${currentTrack.name}');

    // 等待 currentSong 更新
    SongDetail? song;
    final startTime = DateTime.now();
    
    while (song == null && DateTime.now().difference(startTime).inSeconds < 3) {
      song = PlayerService().currentSong;
      
      if (song != null) {
        final songId = song.id.toString();
        final trackId = currentTrack.id.toString();
        
        if (songId != trackId) {
          song = null;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    
    if (song == null) {
      print('❌ [PlayerPage] 等待歌曲详情超时！');
      return;
    }

    try {
      print('📝 [PlayerPage] 开始解析歌词');
      
      await Future.microtask(() {
        switch (song!.source.name) {
          case 'netease':
            _lyrics = LyricParser.parseNeteaseLyric(
              song.lyric,
              translation: song.tlyric.isNotEmpty ? song.tlyric : null,
              yrcLyric: song.yrc.isNotEmpty ? song.yrc : null,
              yrcTranslation: song.ytlrc.isNotEmpty ? song.ytlrc : null,
            );
            break;
          case 'qq':
            _lyrics = LyricParser.parseQQLyric(
              song.lyric,
              translation: song.tlyric.isNotEmpty ? song.tlyric : null,
              qrcLyric: song.qrc.isNotEmpty ? song.qrc : null,
              qrcTranslation: song.qrcTrans.isNotEmpty ? song.qrcTrans : null,
            );
            break;
          case 'kugou':
            _lyrics = LyricParser.parseKugouLyric(
              song.lyric,
              translation: song.tlyric.isNotEmpty ? song.tlyric : null,
            );
            break;
          default:
            // 默认使用网易云/标准 LRC 格式解析（适用于酷我等）
            _lyrics = LyricParser.parseNeteaseLyric(
              song.lyric,
              translation: song.tlyric.isNotEmpty ? song.tlyric : null,
              yrcLyric: song.yrc.isNotEmpty ? song.yrc : null,
              yrcTranslation: song.ytlrc.isNotEmpty ? song.ytlrc : null,
            );
            break;
        }
      });

      print('🎵 [PlayerPage] 加载歌词: ${_lyrics.length} 行 (${song.name})');
      
      if (_lyrics.isNotEmpty && mounted) {
        setState(() {
          _updateCurrentLyric();
        });
      }
    } catch (e) {
      print('❌ [PlayerPage] 加载歌词失败: $e');
    }
  }

  /// 更新当前歌词
  void _updateCurrentLyric() {
    if (_lyrics.isEmpty) return;
    
    final newIndex = LyricParser.findCurrentLineIndex(
      _lyrics,
      PlayerService().position,
    );

    if (newIndex != _currentLyricIndex && newIndex >= 0 && mounted) {
      setState(() {
        _currentLyricIndex = newIndex;
      });
    }
  }

  /// 根据样式选择构建歌词面板
  Widget _buildLyricPanel() {
    final lyricStyle = LyricStyleService().currentStyle;
    
    switch (lyricStyle) {
      case LyricStyle.defaultStyle:
        return PlayerKaraokeLyricsPanel(
          lyrics: _lyrics,
          currentLyricIndex: _currentLyricIndex,
          showTranslation: _showTranslation,
        );
      
      case LyricStyle.fluidCloud:
        return PlayerFluidCloudLyricsPanel(
          lyrics: _lyrics,
          currentLyricIndex: _currentLyricIndex,
          showTranslation: _showTranslation,
        );

      case LyricStyle.immersive:
        // 在沉浸模式下，歌词面板已集成在布局中或由布局单独处理
        // 这里返回空展示，真正的歌词显示逻辑在 PlayerImmersiveLayout 中
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 移动平台使用专门的移动端播放器布局
    if (Platform.isAndroid || Platform.isIOS) {
      return const MobilePlayerPage();
    }
    
    // Windows 平台：如果启用了移动布局模式，也使用移动端播放器布局
    if (Platform.isWindows && LayoutPreferenceService().isMobileLayout) {
      return const MobilePlayerPage();
    }
    
    // 桌面平台使用组件化的桌面布局
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;

    if (song == null && track == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: Text(
            '暂无播放内容',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    // 判断是否需要圆角裁剪（与主窗口逻辑保持一致）
    final effectEnabled = Platform.isWindows && ThemeManager().windowEffect != WindowEffect.disabled;
    final borderRadius = (_isMaximized || effectEnabled) ? BorderRadius.zero : BorderRadius.circular(12);
    
    Widget content = Stack(
          children: [
            // 主要内容区域 (根据样式切换)
            if (LyricStyleService().currentStyle == LyricStyle.fluidCloud)
              PlayerFluidCloudLayout(
                lyrics: _lyrics,
                currentLyricIndex: _currentLyricIndex,
                showTranslation: _showTranslation,
                isMaximized: _isMaximized,
                onBackPressed: () => Navigator.pop(context),
                onPlaylistPressed: _togglePlaylist,
                onVolumeControlPressed: _toggleControlCenter,
                onSleepTimerPressed: () => PlayerDialogs.showSleepTimer(context),
                onTranslationToggle: _toggleTranslation,
              )
            else if (LyricStyleService().currentStyle == LyricStyle.immersive)
              PlayerImmersiveLayout(
                lyrics: _lyrics,
                currentLyricIndex: _currentLyricIndex,
                showTranslation: _showTranslation,
                isMaximized: _isMaximized,
                onBackPressed: () => Navigator.pop(context),
                onPlaylistPressed: _togglePlaylist,
                onVolumeControlPressed: _toggleControlCenter,
                onSleepTimerPressed: () => PlayerDialogs.showSleepTimer(context),
                onTranslationToggle: _toggleTranslation,
              )
            else
              Stack(
                children: [
                  // 背景层
                  const PlayerBackground(),

                  // 极简歌词流（defaultStyle）：
                  //  - 封面占上半屏（按比例切分，不写死像素）
                  //  - 歌名/歌手叠在封面底边的渐隐带上，与封面自然融合
                  //  - 歌词从文字区下方一直铺满到窗口底部
                  //  - 切歌/播放/进度等控制键全部隐藏，改为点击封面唤出操作面板
                  MinimalLyricFlowLayout(
                    lyrics: _lyrics,
                    currentLyricIndex: _currentLyricIndex,
                    showTranslation: _showTranslation,
                    lyricsPanel: _buildLyricPanel(),
                    topBar: PlayerWindowControls(
                      isMaximized: _isMaximized,
                      onBackPressed: () => Navigator.pop(context),
                      onPlaylistPressed: _togglePlaylist,
                    ),
                    onPlaylistPressed: _togglePlaylist,
                    onSleepTimerPressed: () => PlayerDialogs.showSleepTimer(context),
                    onTranslationToggle: _toggleTranslation,
                  ),
                ],
              ),

            // 播放列表面板（带遮罩）
            if (_showPlaylist) ...[
              // 背景遮罩
              GestureDetector(
                onTap: _togglePlaylist,
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                ),
              ),
              // 播放列表内容
              PlayerPlaylistPanel(
                isVisible: _showPlaylist,
                slideAnimation: _playlistSlideAnimation,
                onClose: _togglePlaylist,
              ),
            ],
            
            // 控制中心面板
            PlayerControlCenter(
              isVisible: _showControlCenter,
              fadeAnimation: _controlCenterFadeAnimation,
              onClose: _toggleControlCenter,
            ),
          ],
        );
    
    // 仅在禁用窗口效果时应用圆角裁剪（与主窗口逻辑一致）
    if (!effectEnabled) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: content,
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: content,
    );
  }
}
