import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import './abstract_player.dart';
import './player_data_models.dart';
import './player_enums.dart';

/// Harmony 平台原生播放器适配器，通过 MethodChannel 桥接 ArkTS 侧实现。
/// 当前实现以安全兜底为主，即便原生侧尚未完成也不会阻塞 Flutter 逻辑。
class OhosPlayerAdapter implements AbstractPlayer {
  OhosPlayerAdapter() : _playerId = 'ohos_player_${_idSeed++}' {
    _channel = MethodChannel('nipaplay/ohos_player/$_playerId');
    _bootstrapFuture = _bootstrapNativeLayer();
  }

  static int _idSeed = 0;
  static const String _defaultEventChannelPrefix =
      'nipaplay/ohos_player/events';

  final String _playerId;
  late final MethodChannel _channel;
  EventChannel? _eventChannel;
  StreamSubscription<dynamic>? _eventSubscription;
  Future<void>? _bootstrapFuture;
  bool _nativeReady = false;

  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);

  PlayerPlaybackState _state = PlayerPlaybackState.stopped;
  double _volume = 1.0;
  double _playbackRate = 1.0;
  String _mediaPath = '';
  int _position = 0;
  PlayerMediaInfo _mediaInfo = PlayerMediaInfo(
      duration: 0, video: const [], audio: const [], subtitle: const []);

  final Map<PlayerMediaType, List<String>> _decoders = {
    PlayerMediaType.video: ['auto'],
    PlayerMediaType.audio: ['auto'],
    PlayerMediaType.subtitle: ['auto'],
    PlayerMediaType.unknown: ['auto'],
  };

  final Map<String, String> _properties = {};
  final List<int> _activeSubtitleTracks = [];
  final List<int> _activeAudioTracks = [];

  Map<String, String> _normalizeMetadata(dynamic source) {
    if (source is Map) {
      return Map<String, String>.fromEntries(
        source.entries
            .map((entry) => MapEntry('${entry.key}', '${entry.value}')),
      );
    }
    return const {};
  }

  /// 保证原生层已创建播放器实例。
  Future<void> _ensureReady() async {
    _bootstrapFuture ??= _bootstrapNativeLayer();
    await _bootstrapFuture;
  }

  Future<void> _bootstrapNativeLayer() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'create',
        _withBaseArgs(),
      );

      _nativeReady = true;

      if (result != null) {
        final textureId = result['textureId'];
        if (textureId is int) {
          _textureIdNotifier.value = textureId;
        }

        final eventChannelName = (result['eventChannel'] as String?) ??
            '$_defaultEventChannelPrefix/$_playerId';
        _attachEventChannel(eventChannelName);
      } else {
        _attachEventChannel('$_defaultEventChannelPrefix/$_playerId');
      }
    } on MissingPluginException {
      debugPrint('[OhosPlayerAdapter] 未检测到原生Harmony播放器插件，使用安全兜底。');
      _nativeReady = false;
    } catch (e) {
      debugPrint('[OhosPlayerAdapter] 初始化原生播放器失败: $e');
      _nativeReady = false;
    }
  }

  void _attachEventChannel(String channelName) {
    _eventChannel = EventChannel(channelName);
    _eventSubscription?.cancel();
    _eventSubscription =
        _eventChannel?.receiveBroadcastStream(_withBaseArgs()).listen(
      _handleNativeEvent,
      onError: (error) {
        debugPrint('[OhosPlayerAdapter] 原生事件流错误: $error');
      },
    );
  }

  Map<String, dynamic> _withBaseArgs([Map<String, dynamic>? extra]) {
    final result = <String, dynamic>{'playerId': _playerId};
    if (extra != null) {
      result.addAll(extra);
    }
    return result;
  }

  Future<T?> _invokeMethod<T>(String method,
      [Map<String, dynamic>? arguments]) async {
    try {
      await _ensureReady();
      if (!_nativeReady) {
        return null;
      }
      return await _channel.invokeMethod<T>(method, _withBaseArgs(arguments));
    } on MissingPluginException {
      debugPrint('[OhosPlayerAdapter] MethodChannel "$method" 未实现');
      return null;
    } catch (e) {
      debugPrint('[OhosPlayerAdapter] 调用 "$method" 出错: $e');
      return null;
    }
  }

  void _handleNativeEvent(dynamic event) {
    if (event is! Map) {
      return;
    }
    final type = event['type'];
    if (type is! String) {
      return;
    }

    switch (type) {
      case 'state':
        final stateValue = event['value'];
        if (stateValue is String) {
          _state = _decodePlaybackState(stateValue);
        }
        break;
      case 'position':
        final positionValue = event['position'];
        if (positionValue is num) {
          _position = positionValue.toInt();
        }
        break;
      case 'texture':
        final textureId = event['textureId'];
        if (textureId is int) {
          _textureIdNotifier.value = textureId;
        }
        break;
      case 'mediaInfo':
        final infoRaw = event['info'];
        if (infoRaw is Map) {
          _mediaInfo = _parseMediaInfo(infoRaw);
        }
        break;
      case 'volume':
        final volumeRaw = event['value'];
        if (volumeRaw is num) {
          _volume = volumeRaw.clamp(0.0, 1.0).toDouble();
        }
        break;
      case 'playbackRate':
        final rateRaw = event['value'];
        if (rateRaw is num) {
          _playbackRate = rateRaw.toDouble();
        }
        break;
      case 'subtitleTracks':
        final tracks = event['tracks'];
        if (tracks is List) {
          _activeSubtitleTracks
            ..clear()
            ..addAll(tracks.whereType<num>().map((e) => e.toInt()));
        }
        break;
      case 'audioTracks':
        final tracks = event['tracks'];
        if (tracks is List) {
          _activeAudioTracks
            ..clear()
            ..addAll(tracks.whereType<num>().map((e) => e.toInt()));
        }
        break;
      default:
        break;
    }
  }

  PlayerPlaybackState _decodePlaybackState(String value) {
    switch (value.toLowerCase()) {
      case 'playing':
        return PlayerPlaybackState.playing;
      case 'paused':
        return PlayerPlaybackState.paused;
      case 'stopped':
      default:
        return PlayerPlaybackState.stopped;
    }
  }

  PlayerMediaInfo _parseMediaInfo(Map<dynamic, dynamic> raw) {
    final duration = (raw['duration'] as num?)?.toInt() ?? _mediaInfo.duration;

    List<PlayerVideoStreamInfo>? video;
    final rawVideo = raw['video'];
    if (rawVideo is List) {
      video = rawVideo.whereType<Map>().map<PlayerVideoStreamInfo>((item) {
        final codecMap = item['codec'];
        final codec = codecMap is Map
            ? PlayerVideoCodecParams(
                width: (codecMap['width'] as num? ?? 0).toInt(),
                height: (codecMap['height'] as num? ?? 0).toInt(),
                name: codecMap['name'] as String?,
              )
            : PlayerVideoCodecParams(width: 0, height: 0, name: 'unknown');
        return PlayerVideoStreamInfo(
          codec: codec,
          codecName: item['codecName'] as String?,
        );
      }).toList();
    }

    List<PlayerAudioStreamInfo>? audio;
    final rawAudio = raw['audio'];
    if (rawAudio is List) {
      audio = rawAudio.whereType<Map>().map<PlayerAudioStreamInfo>((item) {
        final codecMap = item['codec'];
        final codec = PlayerAudioCodecParams(
          name: codecMap is Map ? codecMap['name'] as String? : null,
          bitRate:
              codecMap is Map ? (codecMap['bitRate'] as num?)?.toInt() : null,
          channels:
              codecMap is Map ? (codecMap['channels'] as num?)?.toInt() : null,
          sampleRate: codecMap is Map
              ? (codecMap['sampleRate'] as num?)?.toInt()
              : null,
        );
        return PlayerAudioStreamInfo(
          codec: codec,
          title: item['title'] as String?,
          language: item['language'] as String?,
          metadata: _normalizeMetadata(item['metadata']),
          rawRepresentation:
              item['rawRepresentation']?.toString() ?? 'Audio Track',
        );
      }).toList();
    }

    List<PlayerSubtitleStreamInfo>? subtitle;
    final rawSubtitle = raw['subtitle'];
    if (rawSubtitle is List) {
      subtitle = rawSubtitle
          .whereType<Map>()
          .map<PlayerSubtitleStreamInfo>((item) => PlayerSubtitleStreamInfo(
                title: item['title'] as String?,
                language: item['language'] as String?,
                metadata: _normalizeMetadata(item['metadata']),
                rawRepresentation:
                    item['rawRepresentation']?.toString() ?? 'Subtitle Track',
              ))
          .toList();
    }

    final errorMessage = raw['error'] as String?;

    return PlayerMediaInfo(
      duration: duration,
      video: video ?? _mediaInfo.video,
      audio: audio ?? _mediaInfo.audio,
      subtitle: subtitle ?? _mediaInfo.subtitle,
      specificErrorMessage: errorMessage,
    );
  }

  String _encodeMediaType(PlayerMediaType type) {
    switch (type) {
      case PlayerMediaType.video:
        return 'video';
      case PlayerMediaType.audio:
        return 'audio';
      case PlayerMediaType.subtitle:
        return 'subtitle';
      case PlayerMediaType.unknown:
        return 'unknown';
    }
  }

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value.clamp(0.0, 1.0);
    unawaited(_invokeMethod('setVolume', {'value': _volume}));
  }

  @override
  double get playbackRate => _playbackRate;

  @override
  set playbackRate(double value) {
    _playbackRate = value;
    unawaited(_invokeMethod('setPlaybackRate', {'rate': value}));
  }

  @override
  PlayerPlaybackState get state => _state;

  @override
  set state(PlayerPlaybackState value) {
    _state = value;
    switch (value) {
      case PlayerPlaybackState.playing:
        unawaited(playDirectly());
        break;
      case PlayerPlaybackState.paused:
        unawaited(pauseDirectly());
        break;
      case PlayerPlaybackState.stopped:
        unawaited(_invokeMethod('stop'));
        break;
    }
  }

  @override
  ValueListenable<int?> get textureId => _textureIdNotifier;

  @override
  String get media => _mediaPath;

  @override
  set media(String value) {
    if (value == _mediaPath) {
      return;
    }
    _mediaPath = value;
    unawaited(_invokeMethod('setMedia', {
      'path': value,
      'type': _encodeMediaType(PlayerMediaType.video),
    }));
  }

  @override
  PlayerMediaInfo get mediaInfo => _mediaInfo;

  @override
  List<int> get activeSubtitleTracks =>
      List.unmodifiable(_activeSubtitleTracks);

  @override
  set activeSubtitleTracks(List<int> value) {
    _activeSubtitleTracks
      ..clear()
      ..addAll(value);
    unawaited(_invokeMethod('selectSubtitleTracks', {'tracks': value}));
  }

  @override
  List<int> get activeAudioTracks => List.unmodifiable(_activeAudioTracks);

  @override
  set activeAudioTracks(List<int> value) {
    _activeAudioTracks
      ..clear()
      ..addAll(value);
    unawaited(_invokeMethod('selectAudioTracks', {'tracks': value}));
  }

  @override
  int get position => _position;

  @override
  bool get supportsExternalSubtitles => true;

  @override
  Future<int?> updateTexture() async {
    await _ensureReady();
    if (_textureIdNotifier.value != null) {
      return _textureIdNotifier.value;
    }
    final texture = await _invokeMethod<int>('ensureTexture');
    if (texture != null) {
      _textureIdNotifier.value = texture;
    }
    return _textureIdNotifier.value;
  }

  @override
  void setMedia(String path, PlayerMediaType type) {
    _mediaPath = path;
    unawaited(_invokeMethod('setMedia', {
      'path': path,
      'type': _encodeMediaType(type),
    }));
  }

  @override
  Future<void> prepare() async {
    await _invokeMethod<void>('prepare');
  }

  @override
  void seek({required int position}) {
    _position = position;
    unawaited(_invokeMethod('seek', {'position': position}));
  }

  @override
  void dispose() {
    final subscription = _eventSubscription;
    _eventSubscription = null;
    subscription?.cancel();
    _nativeReady = false;
    _bootstrapFuture = null;
    unawaited(_invokeMethod('dispose'));
  }

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    final result = await _invokeMethod<Map<dynamic, dynamic>>('snapshot', {
      'width': width,
      'height': height,
    });
    if (result == null) {
      return null;
    }

    final bytes = result['bytes'];
    if (bytes is Uint8List) {
      final frameWidth = (result['width'] as num?)?.toInt() ?? width;
      final frameHeight = (result['height'] as num?)?.toInt() ?? height;
      return PlayerFrame(width: frameWidth, height: frameHeight, bytes: bytes);
    }
    return null;
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {
    _decoders[type] = List<String>.from(decoders);
    unawaited(_invokeMethod('setDecoders', {
      'type': _encodeMediaType(type),
      'decoders': decoders,
    }));
  }

  @override
  List<String> getDecoders(PlayerMediaType type) {
    return List<String>.from(_decoders[type] ?? const ['auto']);
  }

  @override
  String? getProperty(String key) => _properties[key];

  @override
  void setProperty(String key, String value) {
    _properties[key] = value;
    unawaited(_invokeMethod('setProperty', {
      'key': key,
      'value': value,
    }));
  }

  @override
  Future<void> setVideoSurfaceSize({int? width, int? height}) async {
    await _invokeMethod<void>('setVideoSurfaceSize', {
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    });
  }

  @override
  Future<void> playDirectly() async {
    await _invokeMethod<void>('play');
    _state = PlayerPlaybackState.playing;
  }

  @override
  Future<void> pauseDirectly() async {
    await _invokeMethod<void>('pause');
    _state = PlayerPlaybackState.paused;
  }

  @override
  void setPlaybackRate(double rate) {
    _playbackRate = rate;
    unawaited(_invokeMethod('setPlaybackRate', {'rate': rate}));
  }
}
