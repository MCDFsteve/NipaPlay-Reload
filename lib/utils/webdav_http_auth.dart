import 'dart:convert';

import 'package:webdav_client/webdav_client.dart' show AuthType, DigestAuth, DigestParts;

/// WebDAV HTTP 认证协商器。
///
/// 与 webdav_client 的 WdDio 行为一致：先发送乐观 Basic；收到 401 时按
/// WWW-Authenticate 挑战切换到 Digest（stale=true 时刷新 nonce 重试一次）。
/// Digest 计算直接复用 webdav_client 导出的 [DigestAuth]/[DigestParts]，
/// 保证与目录列表（webdav_client）对同一服务器的认证行为一致。
class WebDavChallengeAuth {
  WebDavChallengeAuth({
    required this.username,
    required this.password,
  });

  /// 无凭证模式：不发送 Authorization，仅在收到挑战后按需协商。
  WebDavChallengeAuth.unauthenticated()
      : username = '',
        password = '';

  final String username;
  final String password;

  AuthType _type = AuthType.BasicAuth;
  DigestParts? _digestParts;
  // 允许的 401 重试次数：一次 Basic→Digest 切换 + 一次 stale nonce 刷新。
  int _retryBudget = 2;

  bool get hasCredentials =>
      username.trim().isNotEmpty || password.isNotEmpty;

  /// 当前应发送的 Authorization 头；连接未配置凭证时返回 null。
  String? authorizationHeader(String method, String requestTarget) {
    if (!hasCredentials) return null;
    if (_type == AuthType.DigestAuth) {
      return DigestAuth(
        user: username,
        pwd: password,
        dParts: _digestParts ?? DigestParts(null),
      ).authorize(method, requestTarget);
    }
    return 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  }

  /// 生成携带当前认证方案的请求头集合。
  Map<String, String> authHeaders(String method, String requestTarget) {
    final value = authorizationHeader(method, requestTarget);
    return value == null ? const {} : <String, String>{'authorization': value};
  }

  /// 收到 401 时尝试按挑战更新认证方案。
  ///
  /// 返回 true 表示方案已更新、应当用新 Authorization 重发请求；
  /// 返回 false 表示凭证本身被拒（或重试预算耗尽），无重试价值。
  bool tryHandleUnauthorized(String? wwwAuthenticate) {
    if (_retryBudget <= 0) return false;
    final challenge = wwwAuthenticate?.toLowerCase() ?? '';
    if (_type == AuthType.DigestAuth) {
      // stale=true：nonce 过期，按新挑战参数刷新后重试。
      if (challenge.contains('digest') && challenge.contains('stale=true')) {
        _digestParts = DigestParts(wwwAuthenticate);
        _retryBudget--;
        return true;
      }
      return false;
    }
    if (challenge.contains('digest')) {
      _type = AuthType.DigestAuth;
      _digestParts = DigestParts(wwwAuthenticate);
      _retryBudget--;
      return true;
    }
    // Basic 挑战说明乐观 Basic 已被拒，凭证错误，重试无意义。
    return false;
  }
}

/// Digest 认证的 request-target（RFC 7616 的 uri 参数应为 path[?query]）。
String webDavDigestRequestTarget(Uri url) {
  final query = url.query;
  return query.isEmpty ? url.path : '${url.path}?$query';
}
