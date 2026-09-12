import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/lx_music_runtime_service.dart';

/// 洛雪音源运行时测试页面
/// 
/// 用于验证 WebView 沙箱执行洛雪音源脚本的可行性
class LxMusicRuntimeTestPage extends StatefulWidget {
  const LxMusicRuntimeTestPage({super.key});

  @override
  State<LxMusicRuntimeTestPage> createState() => _LxMusicRuntimeTestPageState();
}

class _LxMusicRuntimeTestPageState extends State<LxMusicRuntimeTestPage> {
  final LxMusicRuntimeService _runtime = LxMusicRuntimeService();
  
  bool _isInitializing = false;
  bool _isLoading = false;
  bool _isRequesting = false;
  
  String _status = '未初始化';
  String _scriptInfo = '';
  String _result = '';
  List<String> _logs = [];
  
  // 测试参数
  String _testSource = 'wy';
  String _testSongId = '2613671926';
  String _testQuality = '320k';

  @override
  void dispose() {
    _runtime.dispose();
    super.dispose();
  }

  void _log(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_logs.length > 100) {
        _logs.removeAt(0);
      }
    });
    print(message);
  }

  /// 初始化运行时
  Future<void> _initializeRuntime() async {
    if (_isInitializing) return;
    
    setState(() {
      _isInitializing = true;
      _status = '正在初始化...';
    });
    
    try {
      _log('🚀 开始初始化 WebView 沙箱...');
      await _runtime.initialize();
      _log('✅ WebView 沙箱初始化成功');
      
      setState(() {
        _status = '已初始化，等待加载脚本';
      });
    } catch (e) {
      _log('❌ 初始化失败: $e');
      setState(() {
        _status = '初始化失败: $e';
      });
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  /// 从文件加载脚本
  Future<void> _loadScriptFromFile() async {
    if (!_runtime.isInitialized) {
      _log('⚠️ 请先初始化运行时');
      return;
    }
    
    if (_isLoading) return;
    
    try {
      // 选择文件
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['js'],
        allowMultiple: false,
      );
      
      if (result == null || result.files.isEmpty) {
        _log('⚠️ 用户取消选择');
        return;
      }
      
      setState(() {
        _isLoading = true;
        _status = '正在加载脚本...';
      });
      
      final file = result.files.first;
      String scriptContent;
      
      if (file.path != null) {
        scriptContent = await File(file.path!).readAsString();
        _log('📂 已选择文件: ${file.name}');
      } else if (file.bytes != null) {
        scriptContent = String.fromCharCodes(file.bytes!);
        _log('📂 已选择文件: ${file.name}');
      } else {
        throw Exception('无法读取文件内容');
      }
      
      _log('📜 脚本大小: ${scriptContent.length} 字符');
      
      // 加载脚本
      _log('⏳ 正在执行脚本...');
      final scriptInfo = await _runtime.loadScript(scriptContent);
      
      if (scriptInfo != null) {
        _log('✅ 脚本加载成功!');
        _log('   名称: ${scriptInfo.name}');
        _log('   版本: ${scriptInfo.version}');
        _log('   作者: ${scriptInfo.author}');
        
        setState(() {
          _status = '脚本已就绪';
          _scriptInfo = '''
脚本名称: ${scriptInfo.name}
版本: ${scriptInfo.version}
作者: ${scriptInfo.author}
描述: ${scriptInfo.description}
''';
        });
      } else {
        _log('❌ 脚本加载失败');
        setState(() {
          _status = '脚本加载失败';
        });
      }
    } catch (e) {
      _log('❌ 加载脚本出错: $e');
      setState(() {
        _status = '加载失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 测试获取音乐 URL
  Future<void> _testGetMusicUrl() async {
    if (!_runtime.isScriptReady) {
      _log('⚠️ 脚本未就绪');
      return;
    }
    
    if (_isRequesting) return;
    
    setState(() {
      _isRequesting = true;
      _result = '请求中...';
    });
    
    try {
      _log('🎵 请求音乐 URL:');
      _log('   音源: $_testSource');
      _log('   歌曲ID: $_testSongId');
      _log('   音质: $_testQuality');
      
      final url = await _runtime.getMusicUrl(
        source: _testSource,
        songId: _testSongId,
        quality: _testQuality,
      );
      
      if (url != null) {
        _log('✅ 获取成功!');
        _log('   URL: $url');
        setState(() {
          _result = '成功获取到 URL:\n$url';
        });
      } else {
        _log('❌ 获取失败');
        setState(() {
          _result = '获取失败';
        });
      }
    } catch (e) {
      _log('❌ 请求出错: $e');
      setState(() {
        _result = '请求出错: $e';
      });
    } finally {
      setState(() {
        _isRequesting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('洛雪音源运行时测试'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 状态卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _runtime.isInitialized
                              ? Icons.check_circle
                              : Icons.pending,
                          color: _runtime.isInitialized
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '状态: $_status',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (_scriptInfo.isNotEmpty) ...[
                      const Divider(),
                      Text(
                        _scriptInfo,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 操作按钮
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _isInitializing ? null : _initializeRuntime,
                  icon: _isInitializing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.rocket_launch),
                  label: const Text('初始化运行时'),
                ),
                ElevatedButton.icon(
                  onPressed: _runtime.isInitialized && !_isLoading
                      ? _loadScriptFromFile
                      : null,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_open),
                  label: const Text('加载脚本'),
                ),
                ElevatedButton.icon(
                  onPressed: _runtime.isScriptReady && !_isRequesting
                      ? _testGetMusicUrl
                      : null,
                  icon: _isRequesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.music_note),
                  label: const Text('测试获取 URL'),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // 测试参数
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '测试参数',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _testSource,
                            decoration: const InputDecoration(
                              labelText: '音源',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'wy', child: Text('网易云')),
                              DropdownMenuItem(value: 'tx', child: Text('QQ音乐')),
                              DropdownMenuItem(value: 'kg', child: Text('酷狗')),
                              DropdownMenuItem(value: 'kw', child: Text('酷我')),
                              DropdownMenuItem(value: 'mg', child: Text('咪咕')),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _testSource = value!;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _testQuality,
                            decoration: const InputDecoration(
                              labelText: '音质',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: '128k', child: Text('128k')),
                              DropdownMenuItem(value: '320k', child: Text('320k')),
                              DropdownMenuItem(value: 'flac', child: Text('FLAC')),
                              DropdownMenuItem(value: 'flac24bit', child: Text('Hi-Res')),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _testQuality = value!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _testSongId,
                      decoration: const InputDecoration(
                        labelText: '歌曲 ID',
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: '例如: 2613671926',
                      ),
                      onChanged: (value) {
                        _testSongId = value;
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 结果显示
            if (_result.isNotEmpty)
              Card(
                color: _result.startsWith('成功')
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '请求结果',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _result,
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          color: _result.startsWith('成功')
                              ? Colors.green[700]
                              : Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 16),
            
            // 日志区域
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '运行日志',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _logs.clear();
                            });
                          },
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                    const Divider(),
                    Container(
                      height: 300,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          Color color = Colors.white;
                          if (log.contains('✅')) {
                            color = Colors.greenAccent;
                          } else if (log.contains('❌')) {
                            color = Colors.redAccent;
                          } else if (log.contains('⚠️')) {
                            color = Colors.orangeAccent;
                          } else if (log.contains('🚀') || log.contains('🎵')) {
                            color = Colors.cyanAccent;
                          }
                          
                          return Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: color,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
