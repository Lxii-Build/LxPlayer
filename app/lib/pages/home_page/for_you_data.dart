import 'dart:convert';

/// 为你推荐数据模型
/// 用于缓存和传递首页推荐数据
class ForYouData {
  final List<Map<String, dynamic>> dailySongs;
  final List<Map<String, dynamic>> fm;
  final List<Map<String, dynamic>> dailyPlaylists;
  final List<Map<String, dynamic>> personalizedPlaylists;
  final List<Map<String, dynamic>> radarPlaylists;
  final List<Map<String, dynamic>> personalizedNewsongs;

  ForYouData({
    required this.dailySongs,
    required this.fm,
    required this.dailyPlaylists,
    required this.personalizedPlaylists,
    required this.radarPlaylists,
    required this.personalizedNewsongs,
  });

  Map<String, dynamic> toJson() => {
    'dailySongs': dailySongs,
    'fm': fm,
    'dailyPlaylists': dailyPlaylists,
    'personalizedPlaylists': personalizedPlaylists,
    'radarPlaylists': radarPlaylists,
    'personalizedNewsongs': personalizedNewsongs,
  };

  String toJsonString() => jsonEncode(toJson());

  static ForYouData fromJson(Map<String, dynamic> json) {
    return ForYouData(
      dailySongs: (json['dailySongs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      fm: (json['fm'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      dailyPlaylists: (json['dailyPlaylists'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      personalizedPlaylists: (json['personalizedPlaylists'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      radarPlaylists: (json['radarPlaylists'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      personalizedNewsongs: (json['personalizedNewsongs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
    );
  }

  static ForYouData fromJsonString(String s) {
    final map = jsonDecode(s) as Map<String, dynamic>;
    return fromJson(map);
  }
}
