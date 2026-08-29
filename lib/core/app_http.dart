import 'dart:convert';

import 'package:http/http.dart' as http;

/// 全データソース共通の HTTP アクセス。
///
/// 外部の無償 API（気象庁・P2P地震情報・USGS・NASA）に対して、
/// タイムアウトと User-Agent を必ず付けて叩く。
/// 相手はいずれもボランティア運営や公共機関のため、
/// 短時間の連打をしないこと・素性を名乗ることを設計上の約束にしている。
class AppHttp {
  AppHttp({http.Client? client, this.timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const String userAgent = 'disaster-map/0.1 (personal portfolio app)';

  Future<String> getText(Uri url) async {
    // Web ではブラウザが User-Agent を上書きするため、付けても無害な範囲で送る。
    final response = await _client.get(url, headers: const {
      'User-Agent': userAgent,
      'Accept': 'application/json, text/xml, */*',
    }).timeout(timeout);

    if (response.statusCode != 200) {
      throw HttpFailure(url: url, statusCode: response.statusCode);
    }
    // 気象庁の JSON は UTF-8 だが charset が付かない場合があるため明示的に解釈する。
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<dynamic> getJson(Uri url) async => jsonDecode(await getText(url));

  void close() => _client.close();
}

class HttpFailure implements Exception {
  const HttpFailure({required this.url, required this.statusCode});

  final Uri url;
  final int statusCode;

  @override
  String toString() => 'HTTP $statusCode: $url';
}
