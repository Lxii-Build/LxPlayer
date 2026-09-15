import '../../models/track.dart';

/// 首页「个性化新歌」接口项的稳健解析。
///
/// 背景（为什么需要单独一份）：
/// 网易云 `/personalized/newsong` 的每一项在不同后端 / 代理下有多种形态——
///
///   1. `{ song: { name, al, ar } }`         新式键（`song/detail` 那套 key）
///   2. `{ song: { name, album, artists } }` 旧式键（`music.163.com` 原始返回即此形态）
///   3. `{ name, al/album, ar/artists }`     已拍平
///   4. 顶层通常还带 `name` / `picUrl`，内层缺失时要能回落到它
///
/// 首页三处收口（[MobileNewsongList] / [NewsongCards] / `OculusNewSongsWidget`）
/// 此前各抄了一份解析，并且都用 `(x ?? {}) as Map<String, dynamic>`——`{}` 会被
/// 静态推断成 `Map<dynamic, dynamic>`，**一旦该项缺 `al` / `album` 就抛 `_TypeError`**
/// （`_Map<dynamic, dynamic>` 不是 `Map<String, dynamic>` 的子类型），整行来不及渲染
/// 就失败（页面上就是「空盒子」）。
///
/// 这里把它收敛成**一份、永不抛异常、逐级回落**的实现：取不到的字段一律回落成
/// 空串 / 空列表，取得到的按「内层 → 外层」优先级拼接。三处调用点共用它，
/// 就不会再出现「桌面版对、移动版错」这类分叉。
class NewsongItem {
  const NewsongItem({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.picUrl,
    required this.raw,
  });

  /// 歌曲 id（网易云为 int，保留 dynamic 以兼容其它来源）。
  final dynamic id;

  /// 歌名。取不到时为空串。
  final String name;

  /// 歌手，多歌手以 ` / ` 连接。取不到时为空串。
  final String artists;

  /// 专辑名。取不到时为空串。
  final String album;

  /// 封面地址。内层专辑的 `picUrl` 优先，其次回落到顶层的 `picUrl`。
  final String picUrl;

  /// 内层歌曲对象（`song` 拍平后的 map），交给 `PlayerService` 播放时复用。
  final Map<String, dynamic> raw;

  /// 是否拿到了可展示的歌名（空项可直接跳过渲染）。
  bool get hasData => name.isNotEmpty || artists.isNotEmpty || picUrl.isNotEmpty;

  /// 转成播放器使用的 [Track]。字段与 `convertToTrack` 保持逐字一致，
  /// 保证「解析出来的东西」和「点播放听到的东西」是同一个。
  Track toTrack() => Track(
        id: id,
        name: name,
        artists: artists,
        album: album,
        picUrl: picUrl,
        source: MusicSource.netease,
      );

  /// 解析单个接口项。**任何输入都不抛异常**。
  factory NewsongItem.fromJson(Map<String, dynamic> item) {
    // 1) 优先取内层 `song`（新歌接口项形如 {..., song: {...}}）；
    //    没有内层（商品已拍平）时就地取外层。
    final inner = _asMap(item['song']);
    final song = inner.isEmpty ? item : inner;

    // 2) 专辑：内层 al（新式）→ 内层 album（旧式）→ 外层 al → 外层 album。
    Map<String, dynamic> albumMap = _asMap(song['al']);
    if (albumMap.isEmpty) albumMap = _asMap(song['album']);
    if (albumMap.isEmpty) albumMap = _asMap(item['al']);
    if (albumMap.isEmpty) albumMap = _asMap(item['album']);

    // 3) 歌手：内层 ar（新式）→ 内层 artists（旧式）→ 外层 ar → 外层 artists。
    List<dynamic> arList = _asList(song['ar']);
    if (arList.isEmpty) arList = _asList(song['artists']);
    if (arList.isEmpty) arList = _asList(item['ar']);
    if (arList.isEmpty) arList = _asList(item['artists']);

    final name = _firstNonEmpty([song['name'], item['name']]);
    // 封面三级回落：内层专辑 picUrl → 内层顶层 picUrl → 外层 picUrl。
    final picUrl = _firstNonEmpty([albumMap['picUrl'], song['picUrl'], item['picUrl']]);
    final albumName = _firstNonEmpty([albumMap['name']]);
    final artists = arList
        .map((e) => e is Map ? (e['name']?.toString() ?? '') : (e?.toString() ?? ''))
        .where((s) => s.isNotEmpty)
        .join(' / ');

    return NewsongItem(
      id: song['id'] ?? item['id'] ?? 0,
      name: name,
      artists: artists,
      album: albumName,
      picUrl: picUrl,
      // 播放用原始 map：优先内层 `song`，缺失时用外层项本身，
      // 保证下游（`PlayerService`）总能拿到 id。
      raw: inner.isEmpty ? item : song,
    );
  }

  /// 安全取 map：非 Map / null 一律回落到不可变空 map，绝不抛出。
  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  /// 安全取 list：非 List / null 一律回落到空 list。
  static List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    return const <dynamic>[];
  }

  /// 取第一个非空字符串；全为空则返回空串。
  static String _firstNonEmpty(Iterable<dynamic> values) {
    for (final value in values) {
      final s = value?.toString() ?? '';
      if (s.isNotEmpty) return s;
    }
    return '';
  }
}
