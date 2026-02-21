import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb_bindings;

import '../player_abstraction/abstract_player.dart';
import '../player_abstraction/player_enums.dart';
import '../player_abstraction/player_data_models.dart';
import '../rust/api.dart' as rust_api;
import '../rust/frb_generated.dart' as frb;

/// NipaPlay Next (Rust + GStreamer) kernel adapter.
class NipaPlayNextKernel implements AbstractPlayer {
  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<ui.Image?> _frameNotifier = ValueNotifier<ui.Image?>(null);
  final List<int> _activeSubtitleTracks = [];
  final List<int> _activeAudioTracks = [];
  final Map<PlayerMediaType, List<String>> _decoders = {
    PlayerMediaType.video: [],
    PlayerMediaType.audio: [],
    PlayerMediaType.subtitle: [],
    PlayerMediaType.unknown: [],
  };
  final Map<String, String> _properties = {};

  String _mediaPath = '';
  PlayerMediaInfo _mediaInfo = PlayerMediaInfo(duration: 0);
  PlayerPlaybackState _state = PlayerPlaybackState.stopped;
  double _volume = 1.0;
  double _playbackRate = 1.0;
  int _positionMs = 0;
  int _bufferedPositionMs = 0;
  Timer? _pollTimer;
  Timer? _frameTimer;
  bool _rustReady = false;
  bool _disposed = false;
  Future<void>? _loadFuture;
  bool _isFrameDecoding = false;

  NipaPlayNextKernel() {
    unawaited(_initRust());
  }

  Future<void> _initRust() async {
    if (_rustReady || _disposed) return;
    try {
      final libPath = _resolveRustLibraryPath();
      if (libPath == null) {
        debugPrint('[NipaPlayNextKernel] Rust library not found, using default loader');
      }
      final externalLibrary = libPath == null
          ? null
          : frb_bindings.ExternalLibrary.open(libPath);
      await frb.RustLib.init(externalLibrary: externalLibrary);
      await rust_api.init();
      _rustReady = true;
      _ensurePolling();
    } catch (e) {
      debugPrint('[NipaPlayNextKernel] init failed: $e');
    }
  }

  String? _resolveRustLibraryPath() {
    const stem = 'flutter_bridge';
    final String libName;
    if (Platform.isWindows) {
      libName = '$stem.dll';
    } else if (Platform.isMacOS) {
      libName = 'lib$stem.dylib';
    } else {
      libName = 'lib$stem.so';
    }

    final candidates = <String>[
      path.join(
        Directory.current.path,
        'rust',
        'target',
        'release',
        libName,
      ),
      path.join(
        Directory.current.path,
        'rust',
        'target',
        'debug',
        libName,
      ),
      path.join(
        Directory.current.path,
        'rust',
        'flutter_bridge',
        'target',
        'release',
        libName,
      ),
      path.join(
        Directory.current.path,
        'rust',
        'flutter_bridge',
        'target',
        'debug',
        libName,
      ),
    ];

    if (Platform.isMacOS) {
      final execDir = path.dirname(Platform.resolvedExecutable);
      candidates.addAll([
        path.join(execDir, '..', 'Frameworks', libName),
        path.join(execDir, '..', 'Resources', libName),
      ]);
    } else if (Platform.isLinux) {
      final execDir = path.dirname(Platform.resolvedExecutable);
      candidates.addAll([
        path.join(execDir, libName),
        path.join(execDir, 'lib', libName),
      ]);
    } else if (Platform.isWindows) {
      final execDir = path.dirname(Platform.resolvedExecutable);
      candidates.add(path.join(execDir, libName));
    }

    for (final candidate in candidates) {
      final file = File(path.normalize(candidate));
      if (file.existsSync()) {
        return file.path;
      }
    }
    return null;
  }

  Future<void> _ensureRustReady() async {
    if (_rustReady) return;
    await _initRust();
  }

  void _ensurePolling() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      unawaited(_pollStatus());
    });
  }

  Future<void> _pollStatus() async {
    if (!_rustReady || _disposed) return;
    try {
      final position = await rust_api.positionMs();
      final duration = await rust_api.durationMs();
      final buffered = await rust_api.bufferedPositionMs();
      _positionMs = position;
      _bufferedPositionMs = buffered;
      _mediaInfo = PlayerMediaInfo(
        duration: duration,
        specificErrorMessage: _mediaInfo.specificErrorMessage,
      );
    } catch (_) {
      // Ignore polling errors for now.
    }
  }

  void _startFramePump() {
    if (_frameTimer != null) return;
    _frameTimer =
        Timer.periodic(const Duration(milliseconds: 33), (_) => _pullFrame());
  }

  void _stopFramePump() {
    _frameTimer?.cancel();
    _frameTimer = null;
  }

  Future<void> _pullFrame() async {
    if (_isFrameDecoding || !_rustReady || _disposed) return;
    _isFrameDecoding = true;
    try {
      final frame = await rust_api.tryPullFrame();
      if (frame == null) {
        return;
      }
      final int bytesPerRow =
          frame.stride > 0 ? frame.stride : frame.width * 4;
      final bytes = frame.data;
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        bytes,
        frame.width,
        frame.height,
        ui.PixelFormat.rgba8888,
        (image) => completer.complete(image),
        rowBytes: bytesPerRow,
      );
      final image = await completer.future;
      final previous = _frameNotifier.value;
      _frameNotifier.value = image;
      previous?.dispose();
    } catch (e) {
      debugPrint('[NipaPlayNextKernel] frame decode failed: $e');
    } finally {
      _isFrameDecoding = false;
    }
  }

  Future<void> _loadMedia(String path) async {
    if (path.isEmpty) return;
    await _ensureRustReady();
    if (!_rustReady) return;
    try {
      await rust_api.load(url: path);
      _ensurePolling();
      _state = PlayerPlaybackState.paused;
    } catch (e) {
      debugPrint('[NipaPlayNextKernel] load failed: $e');
    }
  }

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value.clamp(0.0, 1.0);
    unawaited(_ensureRustReady().then((_) {
      if (_rustReady) {
        return rust_api.setVolume(volume: _volume);
      }
    }));
  }

  @override
  double get playbackRate => _playbackRate;

  @override
  set playbackRate(double value) {
    _playbackRate = value;
    setPlaybackRate(value);
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
        unawaited(_ensureRustReady().then((_) async {
          if (_rustReady) {
            await rust_api.stop();
          }
        }));
        _stopFramePump();
        final previous = _frameNotifier.value;
        _frameNotifier.value = null;
        previous?.dispose();
        break;
    }
  }

  @override
  ValueListenable<int?> get textureId => _textureIdNotifier;

  @override
  String get media => _mediaPath;

  @override
  set media(String value) {
    if (value == _mediaPath) return;
    _mediaPath = value;
    _loadFuture = _loadMedia(value);
    unawaited(_loadFuture!);
  }

  @override
  PlayerMediaInfo get mediaInfo => _mediaInfo;

  @override
  List<int> get activeSubtitleTracks => _activeSubtitleTracks;

  @override
  set activeSubtitleTracks(List<int> value) {
    _activeSubtitleTracks
      ..clear()
      ..addAll(value);
  }

  @override
  List<int> get activeAudioTracks => _activeAudioTracks;

  @override
  set activeAudioTracks(List<int> value) {
    _activeAudioTracks
      ..clear()
      ..addAll(value);
  }

  @override
  int get position => _positionMs;

  @override
  int get bufferedPosition => _bufferedPositionMs;

  @override
  void setBufferRange({int minMs = -1, int maxMs = -1, bool drop = false}) {
    // Not supported in MVP.
  }

  @override
  bool get supportsExternalSubtitles => false;

  @override
  Future<int?> updateTexture() async => null;

  @override
  void setMedia(String path, PlayerMediaType type) {
    media = path;
  }

  @override
  Future<void> prepare() async {
    if (_loadFuture != null) {
      await _loadFuture;
    }
    await _ensureRustReady();
    if (_rustReady) {
      try {
        await rust_api.pause();
      } catch (e) {
        debugPrint('[NipaPlayNextKernel] prepare pause failed: $e');
      }
    }
  }

  @override
  void seek({required int position}) {
    _positionMs = position;
    unawaited(_ensureRustReady().then((_) {
      if (_rustReady) {
        return rust_api.seek(positionMs: position);
      }
    }));
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _stopFramePump();
    final previous = _frameNotifier.value;
    _frameNotifier.value = null;
    previous?.dispose();
    unawaited(_ensureRustReady().then((_) async {
      if (_rustReady) {
        await rust_api.stop();
      }
    }));
  }

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    return null;
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {
    _decoders[type] = List<String>.from(decoders);
  }

  @override
  List<String> getDecoders(PlayerMediaType type) {
    return List<String>.from(_decoders[type] ?? const []);
  }

  @override
  String? getProperty(String key) => _properties[key];

  @override
  void setProperty(String key, String value) {
    _properties[key] = value;
  }

  @override
  Future<void> setVideoSurfaceSize({int? width, int? height}) async {
    // MVP: no surface control.
  }

  @override
  Future<void> playDirectly() async {
    await _ensureRustReady();
    if (_rustReady) {
      await rust_api.play();
      _state = PlayerPlaybackState.playing;
      _startFramePump();
    }
  }

  @override
  Future<void> pauseDirectly() async {
    await _ensureRustReady();
    if (_rustReady) {
      await rust_api.pause();
      _state = PlayerPlaybackState.paused;
      _stopFramePump();
    }
  }

  @override
  void setPlaybackRate(double rate) {
    _playbackRate = rate;
    unawaited(_ensureRustReady().then((_) {
      if (_rustReady) {
        return rust_api.setPlaybackRate(rate: rate);
      }
    }));
  }

  ValueListenable<dynamic> get videoFrameNotifier => _frameNotifier;
}
