import 'package:flutter/foundation.dart';

/// 请求首页显示搜索覆盖层的事件
class HomeSearchRequest {
  final int id;
  final String? keyword;

  const HomeSearchRequest({
    required this.id,
    this.keyword,
  });
}

/// 首页搜索调度服务
///
/// 用于在应用的其它位置（例如标题栏搜索框）触发首页的搜索子页面显示。
class HomeSearchService extends ChangeNotifier {
  static final HomeSearchService _instance = HomeSearchService._internal();

  factory HomeSearchService() => _instance;

  HomeSearchService._internal();

  int _counter = 0;
  HomeSearchRequest? _latestRequest;

  /// 触发一次搜索请求
  void requestSearch({String? keyword}) {
    _counter += 1;
    _latestRequest = HomeSearchRequest(id: _counter, keyword: keyword);
    notifyListeners();
  }

  /// 最近一次的搜索请求（可能已经被处理）
  HomeSearchRequest? get latestRequest => _latestRequest;

  /// 清空当前请求（用于手动重置）
  void clear() {
    _latestRequest = null;
  }

  /// 当前是否存在尚未清空的请求
  bool get hasPendingRequest => _latestRequest != null;
}

