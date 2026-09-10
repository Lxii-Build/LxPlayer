import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'url_service.dart';

class DonateService {

  static String _generateOutTradeNo() {
    final now = DateTime.now().toUtc();
    final ts = now.millisecondsSinceEpoch;
    final rand = Random().nextInt(900000) + 100000; // 6 digits
    return '$ts$rand';
  }

  static String deviceType() {
    if (Platform.isAndroid || Platform.isIOS) return 'mobile';
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return 'pc';
    return 'pc';
  }

  // v2 签名在后端进行，前端不再参与

  static Future<Map<String, dynamic>> createOrder({
    required String type, // 'alipay' | 'wxpay'
    required String money, // e.g. '1.00'
    required String name, // product name
    required String clientIp,
    String? outTradeNo,
    String? notifyUrl,
    String? returnUrl,
    String? device,
    String? param,
  }) async {
    final url = UrlService().payCreateUrl;
    final req = <String, dynamic>{
      'type': type,
      'name': name,
      'money': money,
      'clientip': clientIp,
      'out_trade_no': outTradeNo ?? _generateOutTradeNo(),
      'method': 'web',
      'device': (device ?? deviceType()),
      if (param != null) 'param': param,
      if (notifyUrl != null) 'notify_url': notifyUrl,
      if (returnUrl != null) 'return_url': returnUrl,
    };

    try {
      print('[DonateService] POST $url');
      print('[DonateService] Request: $req');

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: jsonEncode(req),
          )
          .timeout(const Duration(seconds: 15));

      print('[DonateService] Status: ${response.statusCode}');
      print('[DonateService] Body: ${response.body}');

      final body = response.body;
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      print('[DonateService] Exception: $e');
      rethrow;
    }
  }

  /// 查询订单状态（v2）
  /// 返回: {'code': 0, 'status': 1} 表示支付成功；兼容旧返回{'code': 1, 'status': '1'}
  static Future<Map<String, dynamic>> queryOrder({
    required String outTradeNo,
  }) async {
    final url = UrlService().payQueryUrl;
    final req = <String, dynamic>{
      'out_trade_no': outTradeNo,
    };

    try {
      print('[DonateService] Query order: $outTradeNo');

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: jsonEncode(req),
          )
          .timeout(const Duration(seconds: 10));

      print('[DonateService] Query Status: ${response.statusCode}');
      print('[DonateService] Query Body: ${response.body}');

      final body = response.body;
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      print('[DonateService] Query Exception: $e');
      rethrow;
    }
  }

  /// 创建赞助记录
  static Future<Map<String, dynamic>> createDonationRecord({
    required int userId,
    required String outTradeNo,
    required double amount,
    required String paymentType,
  }) async {
    final baseUrl = UrlService().baseUrl;
    final url = '$baseUrl/sponsors/create';
    
    final req = <String, dynamic>{
      'userId': userId,
      'outTradeNo': outTradeNo,
      'amount': amount,
      'paymentType': paymentType,
    };

    try {
      print('[DonateService] Creating donation record: $outTradeNo');

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: jsonEncode(req),
          )
          .timeout(const Duration(seconds: 10));

      print('[DonateService] Create donation Status: ${response.statusCode}');
      print('[DonateService] Create donation Body: ${response.body}');

      final body = response.body;
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      print('[DonateService] Create donation Exception: $e');
      rethrow;
    }
  }

  /// 查询用户赞助状态
  static Future<Map<String, dynamic>> getSponsorStatus({
    required int userId,
  }) async {
    final baseUrl = UrlService().baseUrl;
    final url = '$baseUrl/sponsors/status/$userId';

    try {
      print('[DonateService] Query sponsor status for user: $userId');

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      print('[DonateService] Sponsor status: ${response.statusCode}');
      print('[DonateService] Sponsor body: ${response.body}');

      final body = response.body;
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      print('[DonateService] Query sponsor status Exception: $e');
      rethrow;
    }
  }

  /// 获取所有赞助用户列表
  static Future<Map<String, dynamic>> getSponsorList() async {
    final baseUrl = UrlService().baseUrl;
    final url = '$baseUrl/sponsors/list';

    try {
      print('[DonateService] Query sponsor list');

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      print('[DonateService] Sponsor list status: ${response.statusCode}');
      print('[DonateService] Sponsor list body: ${response.body}');

      final body = response.body;
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      print('[DonateService] Query sponsor list Exception: $e');
      rethrow;
    }
  }
}
