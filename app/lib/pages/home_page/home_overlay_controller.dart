import 'package:flutter/foundation.dart';

/// 控制首页内部二级页面/覆盖层的返回行为
class HomeOverlayController extends ChangeNotifier {
  static final HomeOverlayController _instance =
      HomeOverlayController._internal();

  factory HomeOverlayController() => _instance;

  HomeOverlayController._internal();

  VoidCallback? _backHandler;

  /// 是否存在可返回的二级页面
  bool get canPop => _backHandler != null;

  /// 设置当前的返回处理器
  void setBackHandler(VoidCallback? handler) {
    if (_backHandler == handler) return;
    _backHandler = handler;
    notifyListeners();
  }

  /// 触发返回操作
  bool handleBack() {
    final handler = _backHandler;
    if (handler != null) {
      handler();
      return true;
    }
    return false;
  }
}

