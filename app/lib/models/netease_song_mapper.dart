import 'track.dart';

/// 把网易云的原始歌曲 JSON 转成 [Track]。
///
/// 网易云返回的字段有两套写法（新接口 `al`/`ar`，旧接口 `album`/`artists`），
/// 且歌手是数组。这份转换原先在日推详情页里重复了两遍，滑动推荐卡需要用时
/// 提取到这里，避免再抄第三份——字段一旦漏改，界面就会出现空标题或空封面。
Track neteaseSongToTrack(Map<String, dynamic> song) {
  final album = (song['al'] ?? song['album'] ?? const {}) as Map<String, dynamic>;
  final artists = (song['ar'] ?? song['artists'] ?? const []) as List<dynamic>;

  return Track(
    id: song['id'] ?? 0,
    name: song['name']?.toString() ?? '',
    artists: artists
        .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .join(' / '),
    album: album['name']?.toString() ?? '',
    picUrl: album['picUrl']?.toString() ?? '',
    source: MusicSource.netease,
  );
}
