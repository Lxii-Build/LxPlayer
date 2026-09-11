import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart' show User;
import 'developer_mode_service.dart';
import 'url_service.dart';

/// 账号后端模式。
enum AccountBackendMode {
  /// 现有第三方后端（**默认**）。行为与历史版本完全一致。
  official,

  /// 自研 Go 后端（opt-in）。需用户自行部署后，在「设置 → 网络」里把「自定义源」
  /// 指向该后端地址才会生效。
  selfHosted,
}

/// 当账号后端不支持某个操作时抛出。
///
/// 自研后端目前**只有** 登录 / 获取用户信息 两个能力，其余能力用它明确失败，
/// 绝不静默降级成「看起来能用」。
class UnsupportedAccountOperationException implements Exception {
  UnsupportedAccountOperationException(this.operation);

  /// 被拒绝的能力名（用于提示文案）。
  final String operation;

  String get message => '当前账号后端不支持「$operation」'
      '（自研后端目前仅支持登录 / 获取用户信息）';

  @override
  String toString() => message;
}

/// 自研后端的网络 / 协议错误。
class AccountBackendException implements Exception {
  AccountBackendException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次登录的结果（已映射到 App 现有的 [User] 模型）。
class AccountAuthResult {
  const AccountAuthResult({
    required this.user,
    required this.token,
    required this.message,
  });

  final User user;
  final String token;
  final String message;
}

/// **全应用唯一的账号后端选择点。**
///
/// 它只做两件事：
/// 1. 依据 [UrlService] 里既有的「自定义源」配置判断当前该走哪个后端（不另造配置读取）；
/// 2. 为自研后端（`selfHosted`）提供 login / me 的实现，并对其它能力显式报不支持。
///
/// `official`（默认）模式的请求实现仍在 [AuthService] 内，保持**逐字节不变**——
/// 本服务只在其为 `selfHosted` 时接管，官方链路一个字都不动。
class AccountBackendService {
  static final AccountBackendService _instance = AccountBackendService._internal();
  factory AccountBackendService() => _instance;
  AccountBackendService._internal();

  /// 请求超时。仅作用于自研后端请求；官方链路不受影响。
  static const Duration _timeout = Duration(seconds: 15);

  /// 当前账号后端模式。
  ///
  /// 只有当用户**显式**设置了非空自定义源地址时才是 [AccountBackendMode.selfHosted]；
  /// 否则一律 [AccountBackendMode.official]（与今天完全一致）。
  AccountBackendMode get mode {
    final url = UrlService();
    final hasCustom =
        url.sourceType == BackendSourceType.custom && url.customBaseUrl.isNotEmpty;
    return hasCustom ? AccountBackendMode.selfHosted : AccountBackendMode.official;
  }

  /// 是否使用官方后端（默认）。
  bool get isOfficial => mode == AccountBackendMode.official;

  /// 是否使用自研后端（opt-in）。
  bool get isSelfHosted => mode == AccountBackendMode.selfHosted;

  /// 不支持能力的统一提示文案（供 UI 直接展示）。
  String unsupportedMessage(String operation) =>
      UnsupportedAccountOperationException(operation).message;

  // Go 后端固定端点（见 server/main.go:101-106）。
  String get _selfHostedBase => UrlService().customBaseUrl;
  String get _loginPath => '$_selfHostedBase/api/v1/auth/login';
  String get _mePath => '$_selfHostedBase/api/v1/me';

  /// 自研后端登录：`POST /api/v1/auth/login`，body `{email, password}`。
  ///
  /// 把 Go 后端响应 `{token, user:{id, email}}` 映射到现有 [User]。
  /// 说明：Go 后端不返回 username，[User.username] 用 **email 的本地部分**做回退
  /// （这是回退值，**不是真实用户名**）；其余字段取中性默认值，不编造。
  Future<AccountAuthResult> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse(_loginPath);
    DeveloperModeService().addLog('🌐 [AccountBackend] POST $uri');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);

    DeveloperModeService().addLog('📥 [AccountBackend] 状态码: ${response.statusCode}');

    final data = _decode(response.body);
    if (response.statusCode != 200) {
      throw AccountBackendException(_errorMessage(data, '登录失败'));
    }

    final userJson = data['user'];
    final token = data['token'];
    if (userJson is! Map || token is! String || token.isEmpty) {
      throw AccountBackendException('登录响应缺少必要字段');
    }

    return AccountAuthResult(
      user: _mapUser(userJson.cast<String, dynamic>()),
      token: token,
      message: '登录成功',
    );
  }

  /// 自研后端获取当前用户：`GET /api/v1/me`（需 `Authorization: Bearer <token>`）。
  ///
  /// 用于替代官方后端的 `/auth/validate-token`。映射规则同 [login]。
  Future<User> fetchMe(String token) async {
    final uri = Uri.parse(_mePath);
    DeveloperModeService().addLog('🌐 [AccountBackend] GET $uri');

    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(_timeout);

    DeveloperModeService().addLog('📥 [AccountBackend] 状态码: ${response.statusCode}');

    if (response.statusCode != 200) {
      throw AccountBackendException('获取用户信息失败');
    }
    return _mapUser(_decode(response.body));
  }

  /// 把 Go 后端的 user JSON（`{id, email}`）映射到现有 [User]。
  ///
  /// Go 后端没有 username / 验证状态 / 头像 / 赞助信息：
  /// - `username` 用 email 本地部分回退（**回退值，非真实用户名**）；
  /// - 其余字段给中性默认值（false / null），不编造。
  User _mapUser(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt() ?? 0;
    final email = (json['email'] as String?) ?? '';
    return User(
      id: id,
      email: email,
      username: _fallbackUsername(email),
      isVerified: false,
      lastLogin: null,
      avatarUrl: null,
      isSponsor: false,
      sponsorSince: null,
    );
  }

  /// 回退用户名：email 中 `@` 之前的部分；无法解析时用固定占位。
  static String _fallbackUsername(String email) {
    final at = email.indexOf('@');
    final local = at > 0 ? email.substring(0, at) : email;
    return local.isEmpty ? 'user' : local;
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 落到下面的空 Map，由调用方按状态码处理。
    }
    return const <String, dynamic>{};
  }

  /// 兼容 Go 后端的 `{error}` 与官方的 `{message}` 两种错误字段。
  String _errorMessage(Map<String, dynamic> data, String fallback) {
    final error = data['error'];
    if (error is String && error.isNotEmpty) return error;
    final message = data['message'];
    if (message is String && message.isNotEmpty) return message;
    return fallback;
  }
}
