import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../game/chess_game.dart';
import 'battle_audio_base.dart';
import 'sfx_synth.dart';
import 'thunder_synth.dart';
import 'voice_catalog.dart';

/// Windows dışı yerel platformlar (Android, macOS, iOS, Linux) için
/// `audioplayers` tabanlı çok kanallı ses arka ucu.
class NativeAudioBackend {
  NativeAudioBackend(this._owner);

  final BattleAudioBase _owner;

  static const int _thunderVersion = 2;
  static const int _ambienceVersion = 1;
  static const int _thunderVariants = 3;
  static const int _thunderChannels = 4;

  bool _disposed = false;
  bool _ready = false;

  Directory? _cacheDir;
  final List<String> _searchDirs = [];
  Set<String> _bundleAssets = const {};

  _LoopChannel? _bgmChannel;
  _LoopChannel? _windChannel;
  _LoopChannel? _ghostChannel;
  AudioPlayer? _voicePlayer;
  List<AudioPlayer> _thunderPlayers = const [];
  final Map<SfxKind, AudioPlayer> _sfxPlayers = {};
  final Map<SfxKind, String> _sfxPaths = {};
  AudioContext? _mixContext;

  final Map<ThunderKind, List<String>> _thunderFiles = {
    ThunderKind.close: [],
    ThunderKind.distant: [],
  };
  final Map<ThunderKind, int> _lastThunder = {};
  final math.Random _thunderRng = math.Random();
  int _thunderIndex = 0;

  String? _windLoopPath;
  String? _ghostLoopPath;
  double _windLevel = 0.0;
  double _ghostLevel = 0.0;

  final Map<String, String> _boosted = {};
  final Set<String> _boostJobs = {};

  bool get isBgmPlaying => _bgmChannel?.isActive ?? false;

  Future<void> init() async {
    _disposed = false;
    final mixContext = AudioContextConfig(
      focus: AudioContextConfigFocus.mixWithOthers,
    ).build();
    _mixContext = mixContext;
    try {
      await AudioPlayer.global.setAudioContext(mixContext);
    } catch (_) {}
    if (_disposed) return;

    // Tüm oynatıcılar `mixWithOthers` odak bağlamı ayarlandıktan SONRA oluşturulur;
    // aksi hâlde kanallar birbirinin ses odağını keser.
    _bgmChannel = _LoopChannel('whc_bgm', mixContext);
    _windChannel = _LoopChannel('whc_wind', mixContext);
    _ghostChannel = _LoopChannel('whc_ghost', mixContext);
    _voicePlayer = AudioPlayer(playerId: 'whc_voice');
    _thunderPlayers = List.generate(
      _thunderChannels,
      (i) => AudioPlayer(playerId: 'whc_thunder_$i'),
    );

    _setupSearchDirs();
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      if (_disposed) return;
      _bundleAssets = manifest
          .listAssets()
          .where((k) => k.startsWith('assets/audio/'))
          .toSet();
    } catch (_) {}

    try {
      final tmp = await getTemporaryDirectory();
      if (_disposed) return;
      final dir = Directory(p.join(tmp.path, 'whc_audio'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _cacheDir = dir;
    } catch (_) {}

    await _prepareSfxWavFiles();
    if (_disposed) return;
    _ready = true;

    if (_owner.bgmEnabled) {
      startBgm();
    }
    _applyAmbience();
    unawaited(_prewarmSfxPlayers());
    unawaited(_prepareStormAudio());
  }

  void _setupSearchDirs() {
    final cwd = Directory.current.path;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      p.join(cwd, 'assets', 'audio'),
      p.join(cwd, 'voices'),
      p.join(cwd, 'assets', 'voices'),
      p.join(exeDir, 'assets', 'audio'),
      p.join(exeDir, 'voices'),
    ];
    for (final d in candidates) {
      if (!_searchDirs.contains(d)) _searchDirs.add(d);
    }
  }

  Future<void> _prepareSfxWavFiles() async {
    final dir = _cacheDir;
    if (dir == null) return;
    for (final kind in SfxKind.values) {
      if (_disposed) return;
      try {
        final file = File(p.join(dir.path, 'sfx_${kind.name}.wav'));
        if (!file.existsSync() || file.lengthSync() < 64) {
          final pcm = SfxSynth.synthesize(kind);
          final wav = SfxSynth.encodeWav(pcm, SfxSynth.sampleRate, gain: 1.0);
          await file.writeAsBytes(wav, flush: true);
        }
        _sfxPaths[kind] = file.path;
      } catch (_) {}
    }
  }

  Future<AudioPlayer?> _ensureSfxPlayer(SfxKind kind) async {
    final existing = _sfxPlayers[kind];
    if (existing != null) return existing;
    final path = _sfxPaths[kind];
    if (path == null || _disposed) return null;
    try {
      final player = AudioPlayer(playerId: 'whc_sfx_${kind.name}');
      final ctx = _mixContext;
      if (ctx != null) {
        await player.setAudioContext(ctx);
      }
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSourceDeviceFile(path);
      if (_disposed) {
        unawaited(player.dispose().catchError((_) {}));
        return null;
      }
      _sfxPlayers[kind] = player;
      return player;
    } catch (_) {
      return null;
    }
  }

  Future<void> _prewarmSfxPlayers() async {
    // Açılıştan sonra SoundPool çözücülerini tek tek ve aralıklarla ısındır.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    for (final kind in SfxKind.values) {
      if (_disposed) return;
      await _ensureSfxPlayer(kind);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  Source? _resolveBgmSource() {
    for (final dir in _searchDirs) {
      for (final name in BattleAudioBase.bgmCandidateNames) {
        final f = File(p.join(dir, name));
        if (f.existsSync() && f.lengthSync() > 1024) {
          return DeviceFileSource(f.path);
        }
      }
    }
    for (final name in BattleAudioBase.bgmCandidateNames) {
      final assetPath = 'assets/audio/$name';
      if (_bundleAssets.contains(assetPath)) {
        return AssetSource('audio/$name');
      }
    }
    if (_bundleAssets.isEmpty) {
      return AssetSource('audio/dark_fantasy_soundtrack.wav');
    }
    return null;
  }

  void startBgm() {
    if (_disposed || !_owner.bgmEnabled) return;
    final channel = _bgmChannel;
    final src = _resolveBgmSource();
    if (channel == null || src == null) return;
    final key = src.toString();
    channel.apply(
      source: src,
      key: key,
      volume: _owner.effectiveBgmVolume,
      enabled: true,
    );
  }

  void stopBgm() {
    _bgmChannel?.apply(source: null, key: null, volume: 0.0, enabled: false);
  }

  void updateBgmVolume() {
    if (!_owner.bgmEnabled) return;
    _bgmChannel?.setVolume(_owner.effectiveBgmVolume);
  }

  int countAvailableElevenLabsFiles() {
    final bases = <String>{};
    for (final asset in _bundleAssets) {
      final name = p.basename(asset).toLowerCase();
      if (name.endsWith('.mp3') || name.endsWith('.wav')) {
        bases.add(p.basenameWithoutExtension(name));
      }
    }
    for (final dir in _searchDirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      try {
        for (final f in d.listSync()) {
          if (f is File) {
            final lower = f.path.toLowerCase();
            if (lower.endsWith('.mp3') || lower.endsWith('.wav')) {
              bases.add(p.basenameWithoutExtension(lower));
            }
          }
        }
      } catch (_) {}
    }
    bases.removeWhere(
      (b) => BattleAudioBase.bgmCandidateNames.any((m) => m.startsWith('$b.')),
    );
    return bases.isNotEmpty ? bases.length : 36;
  }

  bool hasVoiceFile(String id) {
    final lower = id.toLowerCase();
    for (final asset in _bundleAssets) {
      final name = p.basename(asset).toLowerCase();
      if (name.startsWith(lower) && (name.endsWith('.mp3') || name.endsWith('.wav'))) {
        return true;
      }
    }
    for (final dir in _searchDirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      try {
        for (final f in d.listSync()) {
          if (f is File) {
            final name = p.basename(f.path).toLowerCase();
            if (name.startsWith(lower) && (name.endsWith('.mp3') || name.endsWith('.wav'))) {
              return true;
            }
          }
        }
      } catch (_) {}
    }
    return false;
  }

  Source? _resolvePieceVoiceSource(PieceType kind, int variationIndex) {
    final prefixes = pieceVoicePrefixes(kind);
    final suffixes = ['_$variationIndex', '$variationIndex'];
    const exts = ['wav', 'mp3'];

    for (final dir in _searchDirs) {
      for (final prefix in prefixes) {
        for (final suffix in suffixes) {
          for (final ext in exts) {
            final f = File(p.join(dir, '$prefix$suffix.$ext'));
            if (f.existsSync() && f.lengthSync() > 128) {
              return DeviceFileSource(f.path);
            }
          }
        }
      }
    }

    // Paketli assetlerde mobil/masaüstü için kompakt MP3 tercih edilir
    const assetExts = ['mp3', 'wav'];
    for (final prefix in prefixes) {
      for (final suffix in suffixes) {
        for (final ext in assetExts) {
          final assetKey = 'assets/audio/$prefix$suffix.$ext';
          if (_bundleAssets.isEmpty || _bundleAssets.contains(assetKey)) {
            return AssetSource('audio/$prefix$suffix.$ext');
          }
        }
      }
    }
    return null;
  }

  void playPieceVoice(PieceType kind, int variationIndex) {
    if (_disposed) return;
    final src = _resolvePieceVoiceSource(kind, variationIndex);
    if (src == null) {
      playSfx(SfxSynth.fallbackVoiceSfx(kind));
      return;
    }
    unawaited(_playVoiceSource(src, _owner.voiceVolume.clamp(0.0, 1.0), kind));
  }

  Future<void> _playVoiceSource(Source src, double volume, PieceType kind) async {
    final player = _voicePlayer;
    if (player == null || _disposed) return;
    try {
      await player.stop();
      if (_disposed) return;
      await player.setReleaseMode(ReleaseMode.stop);
      await player.play(src, volume: volume);
    } catch (_) {
      playSfx(SfxSynth.fallbackVoiceSfx(kind));
    }
  }

  void updateVoiceVolume() {
    final player = _voicePlayer;
    if (_disposed || player == null) return;
    unawaited(player.setVolume(_owner.voiceVolume.clamp(0.0, 1.0)).catchError((_) {}));
  }

  void playSfx(SfxKind kind) {
    if (_disposed || !_ready) return;
    final path = _sfxPaths[kind];
    if (path == null) return;
    final vol = _owner.gainOfSfx(kind);
    if (vol <= 0.001) return;
    unawaited(_replaySfx(kind, path, vol));
  }

  Future<void> _replaySfx(SfxKind kind, String path, double vol) async {
    try {
      final player = await _ensureSfxPlayer(kind);
      if (player == null || _disposed) return;
      await player.stop();
      if (_disposed) return;
      await player.play(DeviceFileSource(path), volume: vol);
    } catch (_) {}
  }

  static double _boostStep(double level) =>
      level <= 4.0 ? (level * 4).ceil() / 4 : level.ceilToDouble();

  String? _boostedPath(String path, double gain) {
    if (!path.toLowerCase().endsWith('.wav')) return null;
    final key = '$path@${gain.toStringAsFixed(2)}';
    final ready = _boosted[key];
    if (ready != null) return ready;
    final dir = _cacheDir;
    if (dir != null && _boostJobs.add(key)) {
      unawaited(_prepareBoost(path, gain, key, dir));
    }
    return null;
  }

  Future<void> _prepareBoost(String path, double gain, String key, Directory dir) async {
    try {
      final id = path.toLowerCase().hashCode.toUnsigned(32).toRadixString(16);
      final out = File(p.join(dir.path, 'boost_${id}_${(gain * 100).round()}.wav'));
      if (!out.existsSync() || out.lengthSync() < 1024) {
        final src = await File(path).readAsBytes();
        final bytes = await _renderBoost(src, gain);
        if (bytes == null || _disposed) return;
        await out.writeAsBytes(bytes, flush: true);
      }
      _boosted[key] = out.path;
      _applyAmbience();
    } catch (_) {
    } finally {
      _boostJobs.remove(key);
    }
  }

  static Future<Uint8List?> _renderBoost(Uint8List src, double gain) async {
    try {
      return await Isolate.run(() => ThunderSynth.boostWav(src, gain));
    } catch (_) {
      return ThunderSynth.boostWav(src, gain);
    }
  }

  (String, double) _resolveLevel(String path, double level, {String? fallback}) {
    if (level <= 1.0) return (path, level.clamp(0.0, 1.0));
    final step = _boostStep(level);
    final boosted = _boostedPath(path, step);
    if (boosted == null) return (fallback ?? path, 1.0);
    return (boosted, math.min(1.0, level / step));
  }

  Future<void> _prepareStormAudio() async {
    for (final dir in _searchDirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      try {
        for (final f in d.listSync()) {
          if (f is! File) continue;
          final name = p.basename(f.path).toLowerCase();
          if (!(name.endsWith('.wav') || name.endsWith('.mp3'))) continue;
          if (f.lengthSync() < 1024) continue;
          if (name.startsWith('thunder_close') || name.startsWith('thunder_near')) {
            _addThunderFile(ThunderKind.close, f.path);
          } else if (name.startsWith('thunder_far') || name.startsWith('thunder_distant')) {
            _addThunderFile(ThunderKind.distant, f.path);
          } else if (name.startsWith('storm_wind')) {
            _windLoopPath ??= f.path;
          } else if (name.startsWith('storm_ghost')) {
            _ghostLoopPath ??= f.path;
          }
        }
      } catch (_) {}
    }

    final dir = _cacheDir;
    if (dir == null || _disposed) return;

    try {
      if (_windLoopPath == null) {
        final f = File(p.join(dir.path, 'storm_wind_v$_ambienceVersion.wav'));
        if (!f.existsSync() || f.lengthSync() < 1024) {
          await f.writeAsBytes(await _renderAmbience(ghost: false), flush: true);
        }
        if (_disposed) return;
        _windLoopPath = f.path;
      }
      if (_ghostLoopPath == null) {
        final f = File(p.join(dir.path, 'storm_ghost_v$_ambienceVersion.wav'));
        if (!f.existsSync() || f.lengthSync() < 1024) {
          await f.writeAsBytes(await _renderAmbience(ghost: true), flush: true);
        }
        if (_disposed) return;
        _ghostLoopPath = f.path;
      }
      _applyAmbience();
    } catch (_) {}

    final missing = ThunderKind.values.where((k) => _thunderFiles[k]!.isEmpty).toList();
    try {
      for (final kind in missing) {
        for (var v = 0; v < _thunderVariants; v++) {
          if (_disposed) return;
          final file = File(p.join(dir.path, 'thunder_v${_thunderVersion}_${kind.name}_$v.wav'));
          if (!file.existsSync() || file.lengthSync() < 1024) {
            final seed = (kind == ThunderKind.close ? 101 : 503) + v * 7919;
            final bytes = await _renderThunder(kind, seed);
            if (_disposed) return;
            await file.writeAsBytes(bytes, flush: true);
          }
          _addThunderFile(kind, file.path);
        }
      }
    } catch (_) {}
  }

  static Future<Uint8List> _renderThunder(ThunderKind kind, int seed) async {
    try {
      return await Isolate.run(() => ThunderSynth.renderWav(kind, seed));
    } catch (_) {
      return ThunderSynth.renderWav(kind, seed);
    }
  }

  static Future<Uint8List> _renderAmbience({required bool ghost}) async {
    Uint8List job() =>
        ghost ? StormAmbience.renderGhostLoopWav(23) : StormAmbience.renderWindLoopWav(11);
    try {
      return await Isolate.run(job);
    } catch (_) {
      return job();
    }
  }

  void _addThunderFile(ThunderKind kind, String path) {
    final list = _thunderFiles[kind]!;
    if (!list.contains(path)) list.add(path);
  }

  void playThunder(ThunderKind kind) {
    if (_disposed) return;
    final level = BattleAudioBase.sanitizeLevel(_owner.thunderVolume);
    if (level <= 0.001) return;
    final files = _thunderFiles[kind]!;
    if (files.isEmpty) return;

    var pick = _thunderRng.nextInt(files.length);
    if (files.length > 1 && pick == _lastThunder[kind]) {
      pick = (pick + 1) % files.length;
    }
    _lastThunder[kind] = pick;

    if (_thunderPlayers.isEmpty) return;
    final gain = kind == ThunderKind.close ? 1.0 : 0.8;
    final (file, vol) = _resolveLevel(files[pick], level * gain);
    final player = _thunderPlayers[_thunderIndex++ % _thunderPlayers.length];
    unawaited(_playThunderOn(player, file, vol));
  }

  Future<void> _playThunderOn(AudioPlayer player, String file, double vol) async {
    try {
      await player.stop();
      if (_disposed) return;
      await player.setReleaseMode(ReleaseMode.stop);
      await player.play(DeviceFileSource(file), volume: vol);
    } catch (_) {}
  }

  void setStormAmbience({required double wind, required double ghost}) {
    _windLevel = BattleAudioBase.sanitizeLevel(wind);
    _ghostLevel = BattleAudioBase.sanitizeLevel(ghost);
    _applyAmbience();
  }

  void _applyAmbience() {
    if (_disposed) return;
    final wind = _windChannel;
    final ghost = _ghostChannel;
    if (wind != null) _applyLoopChannel(wind, _windLoopPath, _windLevel);
    if (ghost != null) _applyLoopChannel(ghost, _ghostLoopPath, _ghostLevel);
  }

  void _applyLoopChannel(_LoopChannel channel, String? path, double level) {
    if (path == null) return;
    if (level <= 0.001) {
      channel.apply(source: null, key: null, volume: 0.0, enabled: false);
      return;
    }
    final (file, vol) = _resolveLevel(path, level, fallback: channel.activeKey);
    channel.apply(
      source: DeviceFileSource(file),
      key: file,
      volume: vol,
      enabled: true,
    );
  }

  void dispose() {
    _disposed = true;
    final bgm = _bgmChannel;
    final wind = _windChannel;
    final ghost = _ghostChannel;
    final voice = _voicePlayer;
    if (bgm != null) unawaited(bgm.dispose());
    if (wind != null) unawaited(wind.dispose());
    if (ghost != null) unawaited(ghost.dispose());
    if (voice != null) unawaited(voice.dispose().catchError((_) {}));
    for (final p in _thunderPlayers) {
      unawaited(p.dispose().catchError((_) {}));
    }
    for (final p in _sfxPlayers.values) {
      unawaited(p.dispose().catchError((_) {}));
    }
    _sfxPlayers.clear();
  }
}

/// Döngüsel kanallar (BGM, rüzgâr, uğultu) için sıra kontrollü `AudioPlayer` sarmalayıcısı.
class _LoopChannel {
  _LoopChannel(String id, AudioContext mixContext)
      : _player = AudioPlayer(playerId: id) {
    unawaited(_player.setAudioContext(mixContext).catchError((_) {}));
  }

  final AudioPlayer _player;
  String? activeKey;
  double _targetVolume = 0.0;
  bool _targetEnabled = false;
  Source? _targetSource;
  String? _targetKey;
  bool _busy = false;
  bool _dirty = false;
  bool _disposed = false;

  bool get isActive => _targetEnabled && activeKey != null;

  void apply({
    required Source? source,
    required String? key,
    required double volume,
    required bool enabled,
  }) {
    _targetSource = source;
    _targetKey = key;
    _targetVolume = volume.clamp(0.0, 1.0);
    _targetEnabled = enabled;
    _scheduleSync();
  }

  void setVolume(double volume) {
    _targetVolume = volume.clamp(0.0, 1.0);
    if (activeKey != null && !_busy && !_disposed) {
      unawaited(_player.setVolume(_targetVolume).catchError((_) {}));
    } else {
      _scheduleSync();
    }
  }

  void _scheduleSync() {
    if (_disposed) return;
    if (_busy) {
      _dirty = true;
      return;
    }
    unawaited(_sync());
  }

  Future<void> _sync() async {
    _busy = true;
    try {
      do {
        _dirty = false;
        if (_disposed) break;
        final enabled = _targetEnabled;
        final source = _targetSource;
        final key = _targetKey;
        final vol = _targetVolume;

        if (!enabled || source == null || key == null || vol <= 0.001) {
          if (activeKey != null) {
            await _player.stop();
            activeKey = null;
          }
          continue;
        }

        if (activeKey == key) {
          await _player.setVolume(vol);
          continue;
        }

        await _player.stop();
        if (_disposed || _dirty) continue;
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.play(source, volume: vol);
        activeKey = key;
      } while (_dirty && !_disposed);
    } catch (_) {
      activeKey = null;
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    activeKey = null;
    try {
      await _player.dispose();
    } catch (_) {}
  }
}

