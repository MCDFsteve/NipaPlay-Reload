import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'abstract_player.dart';
import 'player_data_models.dart';
import 'player_enums.dart';
import 'package:libnipa/libnipa.dart';

/// 基于 Rust libnipa 的软解播放器适配器。
class NipaPlayerAdapter implements AbstractPlayer {
  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);
  final NipaSoftDecoder _decoder = NipaSoftDecoder();

  String _mediaPath = '';
  PlayerPlaybackState _state = PlayerPlaybackState.stopped;
  double _volume = 1.0;
  double _playbackRate = 1.0;
  PlayerMediaInfo _mediaInfo = PlayerMediaInfo(duration: 0);
  final Map<PlayerMediaType, List<String>> _decoders = {
    PlayerMediaType.video: const ['nipa_soft'],
  };
  final Map<String, String> _properties = {};

  Timer? _framePumpTimer;
  int _positionMs = 0;
  Uint8List? _latestFrameBytes;
  ui.Image? _currentImage;
  int _width = 0;
  int _height = 0;

  final ValueNotifier<ui.Image?> _frameStream = ValueNotifier(null);

  ValueListenable<ui.Image?> get frameStream => _frameStream;

  @override
  double get volume => _volume;
  @override
  set volume(double value) => _volume = value.clamp(0.0, 1.0);

  @override
  double get playbackRate => _playbackRate;
  @override
  set playbackRate(double value) => _playbackRate = value;

  @override
  PlayerPlaybackState get state => _state;
  @override
  set state(PlayerPlaybackState value) {
    if (value == _state) return;
    switch (value) {
      case PlayerPlaybackState.playing:
        playDirectly();
        break;
      case PlayerPlaybackState.paused:
        pauseDirectly();
        break;
      case PlayerPlaybackState.stopped:
        pauseDirectly();
        break;
    }
    _state = value;
  }

  @override
  ValueListenable<int?> get textureId => _textureIdNotifier;

  @override
  String get media => _mediaPath;
  @override
  set media(String value) {
    _mediaPath = value;
  }

  @override
  PlayerMediaInfo get mediaInfo => _mediaInfo;

  @override
  List<int> get activeSubtitleTracks => const [];
  @override
  set activeSubtitleTracks(List<int> value) {}

  @override
  List<int> get activeAudioTracks => const [];
  @override
  set activeAudioTracks(List<int> value) {}

  @override
  int get position => _positionMs;

  @override
  bool get supportsExternalSubtitles => false;

  @override
  Future<int?> updateTexture() async => _textureIdNotifier.value;

  @override
  void setMedia(String path, PlayerMediaType type) {
    _mediaPath = path;
  }

  @override
  Future<void> prepare() async {
    if (_mediaPath.isEmpty) return;
    _decoder.close();
    if (!_decoder.open(_mediaPath)) {
      _state = PlayerPlaybackState.stopped;
      return;
    }
    _width = _decoder.width();
    _height = _decoder.height();
    _mediaInfo = PlayerMediaInfo(
      duration: 0,
      video: [
        PlayerVideoStreamInfo(
          codec: PlayerVideoCodecParams(width: _width, height: _height, name: 'nipa_soft'),
        )
      ],
    );
    _state = PlayerPlaybackState.paused;
  }

  @override
  void seek({required int position}) {}

  @override
  void dispose() {
    _stopFramePump();
    _decoder.close();
    _textureIdNotifier.dispose();
    _currentImage?.dispose();
    _frameStream.dispose();
  }

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    final frame = _latestFrameBytes;
    if (frame == null) return null;
    return PlayerFrame(width: _width, height: _height, bytes: Uint8List.fromList(frame));
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {
    _decoders[type] = decoders;
  }

  @override
  List<String> getDecoders(PlayerMediaType type) => _decoders[type] ?? const [];

  @override
  String? getProperty(String key) => _properties[key];

  @override
  void setProperty(String key, String value) {
    _properties[key] = value;
  }

  @override
  Future<void> setVideoSurfaceSize({int? width, int? height}) async {}

  @override
  Future<void> playDirectly() async {
    if (_state == PlayerPlaybackState.playing) return;
    _decoder.play();
    _startFramePump();
    _state = PlayerPlaybackState.playing;
  }

  @override
  Future<void> pauseDirectly() async {
    _decoder.pause();
    _stopFramePump();
    _state = PlayerPlaybackState.paused;
  }

  @override
  void setPlaybackRate(double rate) {
    _playbackRate = rate;
  }

  void _startFramePump() {
    _framePumpTimer?.cancel();
    _framePumpTimer = Timer.periodic(const Duration(milliseconds: 33), (_) async {
      final frame = _decoder.nextFrame();
      if (frame == null) {
        return;
      }
      _positionMs = (_decoder.positionSeconds() * 1000).toInt();
      _latestFrameBytes = frame.bgra;
      ui.decodeImageFromPixels(
        frame.bgra,
        frame.width,
        frame.height,
        ui.PixelFormat.bgra8888,
        (image) {
          _currentImage?.dispose();
          _currentImage = image;
          _frameStream.value = image;
        },
      );
    });
  }

  void _stopFramePump() {
    _framePumpTimer?.cancel();
    _framePumpTimer = null;
  }
}
