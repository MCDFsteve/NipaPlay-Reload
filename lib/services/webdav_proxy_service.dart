import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/webdav_http_auth.dart';

/// WebDAV 本地认证代理。
///
/// MDK/Media Kit 等播放内核只能拿到一个裸 HTTP URL，无法在 401 挑战时完成
/// Digest 协商（MDK 的 `avio.headers` 是静态头，写死后不会随挑战刷新）。
/// 与 SMBProxyService 同型：起一个仅监听回环地址的 shelf 服务，由本服务
/// 代表播放器与 WebDAV 服务器协商 Basic/Digest，并把 Range 请求原样透传为
/// 206 流式响应，保证播放器的 seek/探测行为不受影响。
class WebDAVProxyService {
  static const String _portKey = 'webdav_proxy_port';
  static const int _defaultPort = 33222;
  static const String _userAgent = 'WebDAVFS/3.0 (NipaPlay)';

  WebDAVProxyService._();

  static final WebDAVProxyService instance = WebDAVProxyService._();

  HttpServer? _server;
  int _port = 0;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  int get port => _port;

  Future<void>? _initializing;

  Future<void> initialize() async {
    if (_isRunning || kIsWeb) return;
    final pending = _initializing ??= _initialize();
    try {
      await pending;
    } finally {
      if (identical(_initializing, pending)) _initializing = null;
    }
  }

  Future<void> _initialize() async {
    if (_isRunning) return;

    final router = Router()
      ..add('GET', '/webdav/stream', _handleStream)
      ..add('HEAD', '/webdav/stream', _handleStreamHead)
      ..get('/webdav/health', (Request request) => Response.ok('ok'));

    final handler = const Pipeline().addHandler(router.call);

    final prefs = await SharedPreferences.getInstance();
    final savedPort = prefs.getInt(_portKey);

    final portsToTry = <int>[];
    void addPort(int? value) {
      if (value == null) return;
      if (portsToTry.contains(value)) return;
      portsToTry.add(value);
    }

    addPort(savedPort);
    addPort(_defaultPort);
    addPort(0);

    Object? lastError;
    for (final candidatePort in portsToTry) {
      try {
        _server = await shelf_io.serve(
          handler,
          InternetAddress.loopbackIPv4,
          candidatePort,
        );
        _port = _server!.port;
        _isRunning = true;
        try {
          await prefs.setInt(_portKey, _port);
        } catch (error) {
          debugPrint('WebDAV proxy port preference could not be saved: $error');
        }
        return;
      } catch (e) {
        lastError = e;
      }
    }

    throw StateError('WebDAVProxyService failed to start: $lastError');
  }

  Future<void> stop() async {
    await _initializing;
    await _server?.close(force: true);
    _server = null;
    _port = 0;
    _isRunning = false;
  }

  /// 解析稳定路径（webdav://conn/rel 或旧式直链）并生成代理流地址。
  ///
  /// 无法识别路径或找不到连接时返回 null，交由调用方决定回退方式。
  Future<String?> buildStreamUrlForMediaPath(String mediaPath) async {
    await initialize();
    final resolved = WebDAVService.instance.resolveMediaPath(mediaPath);
    if (resolved == null) return null;
    return buildStreamUrl(resolved.connection, resolved.relativePath);
  }

  /// 生成指定连接文件的回环代理 URL。
  String buildStreamUrl(WebDAVConnection connection, String relativePath) {
    if (!_isRunning) {
      throw StateError(
          'WebDAV proxy must be initialized before building a stream URL');
    }
    final connReference = connection.id.trim().isNotEmpty
        ? connection.id
        : connection.name.trim();

    final resolvedPort = _port > 0 ? _port : _defaultPort;
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: resolvedPort,
      path: '/webdav/stream',
      queryParameters: {
        'conn': connReference,
        'path': relativePath,
      },
    ).toString();
  }

  Future<Response> _handleStream(Request request) {
    return _handleStreamInternal(request, headOnly: false);
  }

  Future<Response> _handleStreamHead(Request request) {
    return _handleStreamInternal(request, headOnly: true);
  }

  Future<Response> _handleStreamInternal(
    Request request, {
    required bool headOnly,
  }) async {
    final connReference = request.url.queryParameters['conn']?.trim();
    final rawPath = request.url.queryParameters['path']?.trim();
    if (connReference == null ||
        connReference.isEmpty ||
        rawPath == null ||
        rawPath.isEmpty) {
      return Response(HttpStatus.badRequest, body: 'Missing conn or path');
    }

    final connection =
        WebDAVService.instance.getConnectionByIdOrName(connReference);
    if (connection == null) {
      return Response(HttpStatus.notFound, body: 'WebDAV connection not found');
    }

    final directUrl = WebDAVService.instance.getFileUrl(connection, rawPath);
    final directUri = Uri.parse(directUrl);
    final rangeHeader = request.headers['range'];

    HttpClient? client;
    HttpClientResponse? upstream;
    try {
      var currentUri = directUri.replace(userInfo: '');
      var auth = WebDavChallengeAuth(
        username: connection.username,
        password: connection.password,
      );
      var redirects = 0;
      const maxRedirects = 5;

      while (true) {
        final method = headOnly ? 'HEAD' : 'GET';
        final authorization =
            auth.authorizationHeader(method, webDavDigestRequestTarget(currentUri));

        final req = await client!.getUrl(currentUri);
        req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
        req.headers.set(HttpHeaders.acceptHeader, '*/*');
        if (rangeHeader != null) {
          req.headers.set(HttpHeaders.rangeHeader, rangeHeader);
        }
        if (authorization != null) {
          req.headers.set(HttpHeaders.authorizationHeader, authorization);
        }

        final resp = await req.close().timeout(const Duration(seconds: 30));

        if (resp.statusCode == HttpStatus.unauthorized) {
          if (auth.tryHandleUnauthorized(
            resp.headers.value(HttpHeaders.wwwAuthenticateHeader),
          )) {
            await _drainAndAbort(resp, req);
            continue; // 按新认证方案重发同一请求
          }
          await _drainAndAbort(resp, req);
          return Response(
            HttpStatus.unauthorized,
            body: 'WebDAV server rejected credentials',
          );
        }

        if (resp.statusCode >= 300 &&
            resp.statusCode < 400 &&
            redirects < maxRedirects) {
          final location = resp.headers.value(HttpHeaders.locationHeader);
          if (location != null) {
            final nextUri = currentUri.resolve(location);
            await _drainAndAbort(resp, req);
            // 跨主机跳转不携带凭证，也不做乐观 Basic（避免外泄）。
            if (nextUri.host.toLowerCase() != currentUri.host.toLowerCase()) {
              auth = WebDavChallengeAuth.unauthenticated();
            }
            currentUri = nextUri;
            redirects++;
            continue;
          }
        }

        if (resp.statusCode >= HttpStatus.badRequest) {
          final status = resp.statusCode;
          await _drainAndAbort(resp, req);
          return Response(status, body: 'WebDAV upstream error (HTTP $status)');
        }

        upstream = resp;
        break;
      }

      final statusCode = upstream.statusCode;
      final contentType =
          upstream.headers.value(HttpHeaders.contentTypeHeader) ??
              'application/octet-stream';
      final contentRange =
          upstream.headers.value(HttpHeaders.contentRangeHeader);
      final acceptRanges =
          upstream.headers.value(HttpHeaders.acceptRangesHeader) ?? 'bytes';

      final passthroughHeaders = <String, String>{
        'Content-Type': contentType,
        'Accept-Ranges': acceptRanges,
        if (contentRange != null) 'Content-Range': contentRange,
        'Cache-Control': 'no-cache',
      };

      // contentLength >= 0 时透传；-1（未知/chunked）交给 shelf 走 chunked。
      if (upstream.contentLength >= 0) {
        passthroughHeaders['Content-Length'] = '${upstream.contentLength}';
      }

      if (headOnly) {
        await _drainAndAbort(upstream, null);
        return Response(statusCode, headers: passthroughHeaders);
      }

      final bodyStream =
          _bindClientToStream(upstream.cast<List<int>>(), client);
      upstream = null;
      return Response(statusCode, body: bodyStream, headers: passthroughHeaders);
    } on TimeoutException {
      return Response(
        HttpStatus.gatewayTimeout,
        body: 'WebDAV upstream timeout',
      );
    } catch (e) {
      return Response.internalServerError(body: 'WebDAV stream error: $e');
    } finally {
      upstream = null;
      if (headOnly) {
        // client 在此分支已被赋值；空值只可能是异常路径，防御性关闭。
        try {
          if (client != null) client.close(force: true);
        } catch (_) {}
      }
      // 非流式路径由 _bindClientToStream 在流结束时关闭 client。
    }
  }

  /// 把上游响应流包装为在完成/出错时关闭 [client] 的流，
  /// 保证播放器 seek 断开连接后 HttpClient 资源被回收。
  Stream<List<int>> _bindClientToStream(
    Stream<List<int>> source,
    HttpClient client,
  ) async* {
    try {
      await for (final chunk in source) {
        yield chunk;
      }
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  Future<void> _drainAndAbort(
    HttpClientResponse response,
    HttpClientRequest? request,
  ) async {
    try {
      await response.listen(null).cancel();
    } catch (_) {}
    try {
      request?.abort();
    } catch (_) {}
  }
}
