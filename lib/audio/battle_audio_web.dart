import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import '../game/chess_game.dart';
import 'battle_audio_base.dart';
import 'sfx_synth.dart';
import 'thunder_synth.dart';
import 'voice_catalog.dart';

@JS('__whcAudio')
external _WhcAudioBridge? get _jsAudio;

extension type _WhcAudioBridge(JSObject _) implements JSObject {
  external void init();
  external bool hasBuffer(String key);
  external void setPcmBuffer(
    String key,
    JSFloat32Array left,
    JSFloat32Array? right,
    int sampleRate,
  );
  external JSPromise<JSBoolean> decodeBytes(String key, JSUint8Array bytes);
  external void playOneShot(
    String key,
    double volume,
    String channel,
    bool softClip,
  );
  external void setLoop(
    String channel,
    String key,
    double volume,
    bool enabled,
    bool softClip,
  );
  external void updateLoopVolume(String channel, double volume);
  external void dispose();
}

/// Tarayıcı (Web Audio API) ses motoru.
///
/// `assets/audio/` içindeki MP3/WAV kayıtlarını `rootBundle` üzerinden yükleyip
/// Web Audio `AudioBuffer` olarak çözer; adım/silah efektleri, fırtına ambiyansı
/// ve gök gürültülerini sıfır gecikmeyle sentezleyip çalar.
class BattleAudio extends BattleAudioBase {
  bool _initialized = false;
  bool _disposed = false;
  bool _bgmPlaying = false;
  String? _bgmKey;
  int _voiceToken = 0;

  Set<String> _bundleAssets = const {};
  final Map<String, Future<bool>> _assetDecodeJobs = {};

  final Map<ThunderKind, List<String>> _thunderKeys = {
    ThunderKind.close: [],
    ThunderKind.distant: [],
  };
  final Map<ThunderKind, int> _lastThunder = {};
  final math.Random _thunderRng = math.Random();

  double _windLevel = 0.0;
  double _ghostLevel = 0.0;

  @override
  bool get isBgmPlaying => _bgmPlaying;

  @override
  void init() {
    if (_initialized) return;
    _initialized = true;
    _disposed = false;

    final bridge = _jsAudio;
    bridge?.init();

    // Kısa adım ve savaş efektlerini anında PCM tamponlarına yükle.
    if (bridge != null) {
      for (final kind in SfxKind.values) {
        final f32 = SfxSynth.toFloat32(SfxSynth.synthesize(kind));
        bridge.setPcmBuffer('sfx_${kind.name}', f32.toJS, null, SfxSynth.sampleRate);
      }
    }

    unawaited(_loadManifestAndPrewarm());
    if (bgmEnabled) {
      startBgm();
    }
    unawaited(_prepareStormAudio());
  }

  Future<void> _loadManifestAndPrewarm() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      if (_disposed) return;
      _bundleAssets = manifest
          .listAssets()
          .where((k) => k.startsWith('assets/audio/'))
          .toSet();
    } catch (_) {}
  }

  String _resolveBgmAssetPath() {
    for (final name in BattleAudioBase.bgmCandidateNames) {
      final p = 'assets/audio/$name';
      if (_bundleAssets.contains(p)) return p;
    }
    return 'assets/audio/dark_fantasy_soundtrack.wav';
  }

  Future<bool> _ensureAssetDecoded(String key, String assetPath) {
    final bridge = _jsAudio;
    if (bridge == null || _disposed) return Future.value(false);
    if (bridge.hasBuffer(key)) return Future.value(true);
    return _assetDecodeJobs.putIfAbsent(key, () async {
      try {
        final data = await rootBundle.load(assetPath);
        if (_disposed) return false;
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final ok = await bridge.decodeBytes(key, bytes.toJS).toDart;
        return ok.toDart;
      } catch (_) {
        return false;
      } finally {
        _assetDecodeJobs.remove(key);
      }
    });
  }

  @override
  void startBgm() {
    if (!bgmEnabled || _disposed) return;
    _bgmPlaying = true;
    final assetPath = _resolveBgmAssetPath();
    final key = 'bgm:$assetPath';
    _bgmKey = key;

    final bridge = _jsAudio;
    if (bridge == null) return;
    bridge.setLoop('bgm', key, effectiveBgmVolume, true, false);
    if (!bridge.hasBuffer(key)) {
      unawaited(_ensureAssetDecoded(key, assetPath).then((ok) {
        if (!ok || _disposed || !bgmEnabled || !_bgmPlaying) return;
        _jsAudio?.setLoop('bgm', key, effectiveBgmVolume, true, false);
      }));
    }
  }

  @override
  void stopBgm() {
    _bgmPlaying = false;
    _jsAudio?.setLoop('bgm', _bgmKey ?? '', 0.0, false, false);
  }

  @override
  void setBgmVolume(double v) {
    bgmVolume = v.clamp(0.0, 1.0);
    if (!_bgmPlaying) return;
    _jsAudio?.updateLoopVolume('bgm', effectiveBgmVolume);
  }

  @override
  void setBgmEnabled(bool enabled) {
    if (enabled == bgmEnabled && enabled == _bgmPlaying) return;
    bgmEnabled = enabled;
    if (enabled) {
      startBgm();
    } else {
      stopBgm();
    }
  }

  @override
  void setVoiceVolume(double v) {
    voiceVolume = v.clamp(0.0, 1.0);
  }

  @override
  void setSfxVolume(double v) {
    sfxVolume = v.clamp(0.0, 1.0);
  }

  @override
  int countAvailableElevenLabsFiles() {
    if (_bundleAssets.isNotEmpty) {
      final bases = <String>{};
      for (final p in _bundleAssets) {
        final name = p.split('/').last.toLowerCase();
        if (name.endsWith('.mp3') || name.endsWith('.wav')) {
          bases.add(name.substring(0, name.length - 4));
        }
      }
      // Müzik dosyasını replik sayacından hariç tut
      bases.removeWhere((b) => BattleAudioBase.bgmCandidateNames.any((m) => m.startsWith('$b.')));
      return bases.length;
    }
    // pubspec.yaml ile 36 replik varsayılan olarak paketlidir
    return 36;
  }

  @override
  bool hasVoiceFile(String id) {
    if (_bundleAssets.isEmpty) return false;
    final lowerId = id.toLowerCase();
    for (final p in _bundleAssets) {
      final name = p.split('/').last.toLowerCase();
      if (name.startsWith(lowerId) && (name.endsWith('.mp3') || name.endsWith('.wav'))) {
        return true;
      }
    }
    return false;
  }

  void _duckBgmFor(int durationMs) {
    if (!_bgmPlaying) return;
    bgmDucked = true;
    _jsAudio?.updateLoopVolume('bgm', effectiveBgmVolume);
    voiceDuckTimer?.cancel();
    voiceDuckTimer = Timer(Duration(milliseconds: durationMs + 280), () {
      bgmDucked = false;
      if (_bgmPlaying && !_disposed) {
        _jsAudio?.updateLoopVolume('bgm', effectiveBgmVolume);
      }
    });
  }

  String? _resolvePieceVoiceAsset(PieceType kind, int variationIndex) {
    final prefixes = pieceVoicePrefixes(kind);
    final suffixes = ['_$variationIndex', '$variationIndex'];
    const exts = ['mp3', 'wav'];

    if (_bundleAssets.isNotEmpty) {
      for (final prefix in prefixes) {
        for (final suffix in suffixes) {
          for (final ext in exts) {
            final path = 'assets/audio/$prefix$suffix.$ext';
            if (_bundleAssets.contains(path)) return path;
          }
        }
      }
    }
    return 'assets/audio/${prefixes.first}_$variationIndex.mp3';
  }

  @override
  VoiceLine speakMoveWithBag(PieceType kind, {bool isAttack = false}) {
    if (!_initialized) init();
    final drawnIndex = bagOf(kind).draw();
    final line = moveVoiceLineOf(kind, drawnIndex, isAttack: isAttack);
    recordVoiceTiming(line.durationMs);

    if (!voiceAudible) return line;
    _duckBgmFor(line.durationMs);

    final token = ++_voiceToken;
    final assetPath = _resolvePieceVoiceAsset(kind, drawnIndex);
    if (assetPath != null) {
      final key = 'voice:$assetPath';
      final bridge = _jsAudio;
      if (bridge != null) {
        if (bridge.hasBuffer(key)) {
          bridge.playOneShot(key, voiceVolume, 'voice', false);
          return line;
        }
        unawaited(_ensureAssetDecoded(key, assetPath).then((ok) {
          if (_disposed || token != _voiceToken || !voiceAudible) return;
          if (ok) {
            _jsAudio?.playOneShot(key, voiceVolume, 'voice', false);
          } else {
            final fallbackKey = 'sfx_${SfxSynth.fallbackVoiceSfx(kind).name}';
            _jsAudio?.playOneShot(fallbackKey, voiceVolume, 'voice', false);
          }
        }));
        return line;
      }
    }

    final fallbackKey = 'sfx_${SfxSynth.fallbackVoiceSfx(kind).name}';
    _jsAudio?.playOneShot(fallbackKey, voiceVolume, 'voice', false);
    return line;
  }

  @override
  void playSfx(SfxKind kind) {
    if (!_initialized) init();
    if (!sfxEnabled) return;
    if (shouldThrottleStep(kind)) return;
    _jsAudio?.playOneShot('sfx_${kind.name}', gainOfSfx(kind), '', false);
  }

  Future<void> _prepareStormAudio() async {
    // Açılış sahnesini kilitlememek için sentez adımlarını kısa aralıklarla çalıştır.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (_disposed) return;

    final bridge = _jsAudio;
    if (bridge == null) return;

    try {
      final windWav = StormAmbience.renderWindLoopWav(11);
      await bridge.decodeBytes('storm_wind', windWav.toJS).toDart;
      if (_disposed) return;
      _applyAmbience();
    } catch (_) {}

    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (_disposed) return;

    try {
      final ghostWav = StormAmbience.renderGhostLoopWav(23);
      await bridge.decodeBytes('storm_ghost', ghostWav.toJS).toDart;
      if (_disposed) return;
      _applyAmbience();
    } catch (_) {}

    // İlk olarak her türden 1'er gök gürültüsü hazırla, ardından kalan varyasyonları üret.
    for (var v = 0; v < 3; v++) {
      for (final kind in ThunderKind.values) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (_disposed) return;
        try {
          final seed = (kind == ThunderKind.close ? 101 : 503) + v * 7919;
          final wav = ThunderSynth.renderWav(kind, seed);
          final key = 'thunder_${kind.name}_$v';
          final ok = (await bridge.decodeBytes(key, wav.toJS).toDart).toDart;
          if (ok && !_disposed) {
            _thunderKeys[kind]!.add(key);
          }
        } catch (_) {}
      }
    }
  }

  @override
  void playThunder(ThunderKind kind) {
    if (!_initialized) init();
    final level = BattleAudioBase.sanitizeLevel(thunderVolume);
    if (level <= 0.001) return;
    final keys = _thunderKeys[kind]!;
    if (keys.isEmpty) return;

    var pick = _thunderRng.nextInt(keys.length);
    if (keys.length > 1 && pick == _lastThunder[kind]) {
      pick = (pick + 1) % keys.length;
    }
    _lastThunder[kind] = pick;
    final gain = kind == ThunderKind.close ? 1.0 : 0.8;
    _jsAudio?.playOneShot(keys[pick], level * gain, '', true);
  }

  @override
  void setStormAmbience({required double wind, required double ghost}) {
    _windLevel = BattleAudioBase.sanitizeLevel(wind);
    _ghostLevel = BattleAudioBase.sanitizeLevel(ghost);
    _applyAmbience();
  }

  void _applyAmbience() {
    final bridge = _jsAudio;
    if (bridge == null || _disposed) return;
    bridge.setLoop('wind', 'storm_wind', _windLevel, _windLevel > 0.001, true);
    bridge.setLoop('ghost', 'storm_ghost', _ghostLevel, _ghostLevel > 0.001, true);
  }

  @override
  void dispose() {
    _disposed = true;
    voiceDuckTimer?.cancel();
    _bgmPlaying = false;
    _jsAudio?.dispose();
  }
}
