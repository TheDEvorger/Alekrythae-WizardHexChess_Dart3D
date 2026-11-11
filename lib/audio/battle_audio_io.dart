import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../game/chess_game.dart';
import 'battle_audio_base.dart';
import 'battle_audio_native.dart';
import 'sfx_synth.dart';
import 'thunder_synth.dart';
import 'voice_catalog.dart';

typedef _PlaySoundNative = Int32 Function(
  Pointer<Uint8> pszSound,
  IntPtr hmod,
  Uint32 fdwSound,
);
typedef _PlaySoundDart = int Function(
  Pointer<Uint8> pszSound,
  int hmod,
  int fdwSound,
);

typedef _MciSendStringNative = Uint32 Function(
  Pointer<Utf16> lpszCommand,
  Pointer<Utf16> lpszReturnString,
  Uint32 cchReturn,
  IntPtr hwndCallback,
);
typedef _MciSendStringDart = int Function(
  Pointer<Utf16> lpszCommand,
  Pointer<Utf16> lpszReturnString,
  int cchReturn,
  int hwndCallback,
);

const int _sndAsync = 0x0001;
const int _sndNoDefault = 0x0002;
const int _sndMemory = 0x0004;

/// Yerel platform ses motoru:
/// - Windows'ta düşük gecikmeli `winmm.dll` (`PlaySoundW` + `mciSendStringW`) kullanır.
/// - Android, macOS, iOS ve Linux'ta `NativeAudioBackend` (`audioplayers`) kullanır.
class BattleAudio extends BattleAudioBase {
  bool _initialized = false;
  bool _bgmPlaying = false;

  NativeAudioBackend? _nativeBackend;

  // Windows winmm.dll durumu
  _PlaySoundDart? _playSound;
  _MciSendStringDart? _mciSend;
  final Map<SfxKind, Pointer<Uint8>> _wavPtrs = {};
  final Map<SfxKind, Float64List> _sfxPcm = {};
  final List<String> _searchDirs = [];

  @override
  bool get isBgmPlaying =>
      _nativeBackend != null ? _nativeBackend!.isBgmPlaying : _bgmPlaying;

  @override
  void init() {
    if (_initialized) return;
    _initialized = true;
    // Flutter test ortamında ses donanımını meşgul etmemek için güvenli kontrol
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    if (!Platform.isWindows) {
      final backend = NativeAudioBackend(this);
      _nativeBackend = backend;
      unawaited(backend.init());
      return;
    }

    try {
      final winmm = DynamicLibrary.open('winmm.dll');
      _playSound = winmm.lookupFunction<_PlaySoundNative, _PlaySoundDart>('PlaySoundW');
      _mciSend = winmm.lookupFunction<_MciSendStringNative, _MciSendStringDart>('mciSendStringW');
      _setupVoiceSearchDirs();
      _buildProceduralBank();
      unawaited(_prepareStormAudio());
      if (bgmEnabled) {
        startBgm();
      }
    } catch (_) {
      _playSound = null;
      _mciSend = null;
    }
  }

  void _setupVoiceSearchDirs() {
    final cwd = Directory.current.path;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final rootDir = Directory(exeDir).parent.parent.parent.parent.parent.path;
    final candidates = <String>[
      '$cwd\\assets\\audio',
      '$cwd\\voices',
      '$cwd\\assets\\voices',
      '$exeDir\\data\\flutter_assets\\assets\\audio',
      '$exeDir\\data\\flutter_assets\\assets\\voices',
      '$exeDir\\assets\\audio',
      '$exeDir\\voices',
      '$rootDir\\assets\\audio',
      '$rootDir\\voices',
    ];
    for (final d in candidates) {
      if (!_searchDirs.contains(d)) _searchDirs.add(d);
    }
  }

  File? _resolveBgmFile() {
    for (final dir in _searchDirs) {
      for (final name in BattleAudioBase.bgmCandidateNames) {
        final f = File('$dir\\$name');
        if (f.existsSync() && f.lengthSync() > 1024) return f;
      }
    }
    return null;
  }

  int get _bgmMciVolume => (effectiveBgmVolume * 1000).round();

  @override
  void startBgm() {
    if (_nativeBackend != null) {
      _nativeBackend!.startBgm();
      return;
    }
    if (!Platform.isWindows || _mciSend == null) return;
    if (!bgmEnabled) return;
    final f = _resolveBgmFile();
    if (f == null) return;
    try {
      final path = f.path.replaceAll('"', '');
      _mci('close whc_bgm');
      _bgmPlaying = false;
      if (_mci('open "$path" type mpegvideo alias whc_bgm') != 0) return;
      _mci('setaudio whc_bgm volume to $_bgmMciVolume');
      if (_mci('play whc_bgm repeat') != 0) {
        _mci('close whc_bgm');
        return;
      }
      _bgmPlaying = true;
    } catch (_) {}
  }

  @override
  void stopBgm() {
    if (_nativeBackend != null) {
      _nativeBackend!.stopBgm();
      return;
    }
    if (!Platform.isWindows || _mciSend == null) return;
    try {
      _mci('stop whc_bgm');
      _mci('close whc_bgm');
    } catch (_) {}
    _bgmPlaying = false;
  }

  @override
  void setBgmVolume(double v) {
    bgmVolume = v.clamp(0.0, 1.0);
    if (_nativeBackend != null) {
      _nativeBackend!.updateBgmVolume();
      return;
    }
    if (!_bgmPlaying || _mciSend == null) return;
    _mci('setaudio whc_bgm volume to $_bgmMciVolume');
  }

  @override
  void setBgmEnabled(bool enabled) {
    if (enabled == bgmEnabled && enabled == isBgmPlaying) return;
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
    if (_nativeBackend != null) {
      _nativeBackend!.updateVoiceVolume();
      return;
    }
    if (_mciSend != null) {
      _mci('setaudio whc_voice volume to ${(voiceVolume * 1000).round()}');
    }
    _rescaleBank(voice: true);
  }

  @override
  void setSfxVolume(double v) {
    sfxVolume = v.clamp(0.0, 1.0);
    if (_nativeBackend != null) return;
    _rescaleBank(voice: false);
  }

  final math.Random _voiceRng = math.Random();
  final Map<String, int> _lastVoiceVariation = {};

  File? _resolvePieceVoiceFile(PieceType kind, int variationIndex) {
    final prefixes = pieceVoicePrefixes(kind);
    final suffixes = ['_$variationIndex', '$variationIndex'];
    const exts = ['wav', 'mp3'];

    for (final dir in _searchDirs) {
      for (final prefix in prefixes) {
        for (final suffix in suffixes) {
          for (final ext in exts) {
            final f = File('$dir\\$prefix$suffix.$ext');
            if (f.existsSync() && f.lengthSync() > 128) {
              return f;
            }
          }
        }
      }
    }
    return null;
  }

  File? _resolveVoiceFile(String id) {
    final variations = <File>[];
    for (final dir in _searchDirs) {
      for (var v = 1; v <= 6; v++) {
        for (final suffix in ['_$v', '$v']) {
          for (final ext in const ['wav', 'mp3']) {
            final f = File('$dir\\$id$suffix.$ext');
            if (f.existsSync() && f.lengthSync() > 128) {
              variations.add(f);
            }
          }
        }
      }
      for (final ext in const ['wav', 'mp3']) {
        final f = File('$dir\\$id.$ext');
        if (f.existsSync() && f.lengthSync() > 128) {
          variations.add(f);
        }
      }
    }

    if (variations.isNotEmpty) {
      if (variations.length == 1) return variations.first;
      final lastIdx = _lastVoiceVariation[id] ?? -1;
      var pickIdx = _voiceRng.nextInt(variations.length);
      if (pickIdx == lastIdx && variations.length > 1) {
        pickIdx = (pickIdx + 1) % variations.length;
      }
      _lastVoiceVariation[id] = pickIdx;
      return variations[pickIdx];
    }
    return null;
  }

  @override
  bool hasVoiceFile(String id) {
    if (_nativeBackend != null) return _nativeBackend!.hasVoiceFile(id);
    return _resolveVoiceFile(id) != null;
  }

  @override
  int countAvailableElevenLabsFiles() {
    if (_nativeBackend != null) return _nativeBackend!.countAvailableElevenLabsFiles();
    final found = <String>{};
    for (final dir in _searchDirs) {
      final d = Directory(dir);
      if (d.existsSync()) {
        try {
          for (final f in d.listSync()) {
            if (f is File) {
              final lower = f.path.toLowerCase();
              if (lower.endsWith('.mp3') || lower.endsWith('.wav')) {
                found.add(f.path);
              }
            }
          }
        } catch (_) {}
      }
    }
    return found.length;
  }

  int _mci(String cmd) {
    final fn = _mciSend;
    if (fn == null) return -1;
    final ptr = cmd.toNativeUtf16();
    try {
      return fn(ptr, nullptr, 0, 0);
    } finally {
      calloc.free(ptr);
    }
  }

  void _playMciVoice(File file) {
    if (_mciSend == null) return;
    try {
      final path = file.path.replaceAll('"', '');
      final vol = (voiceVolume.clamp(0.0, 1.0) * 1000).round();
      _mci('close whc_voice');
      if (_mci('open "$path" type mpegvideo alias whc_voice') == 0) {
        _mci('setaudio whc_voice volume to $vol');
      } else if (_mci('open "$path" type waveaudio alias whc_voice') != 0) {
        return;
      }
      _mci('play whc_voice from 0');
    } catch (_) {}
  }

  void _duckBgmFor(int durationMs) {
    if (_nativeBackend != null) {
      if (!_nativeBackend!.isBgmPlaying) return;
      bgmDucked = true;
      _nativeBackend!.updateBgmVolume();
      voiceDuckTimer?.cancel();
      voiceDuckTimer = Timer(Duration(milliseconds: durationMs + 280), () {
        bgmDucked = false;
        _nativeBackend?.updateBgmVolume();
      });
      return;
    }

    if (!_bgmPlaying || _mciSend == null) return;
    bgmDucked = true;
    _mci('setaudio whc_bgm volume to $_bgmMciVolume');
    voiceDuckTimer?.cancel();
    voiceDuckTimer = Timer(Duration(milliseconds: durationMs + 280), () {
      bgmDucked = false;
      if (_bgmPlaying && _mciSend != null) {
        _mci('setaudio whc_bgm volume to $_bgmMciVolume');
      }
    });
  }

  @override
  VoiceLine speakMoveWithBag(PieceType kind, {bool isAttack = false}) {
    if (!_initialized) init();
    final drawnIndex = bagOf(kind).draw();
    final line = moveVoiceLineOf(kind, drawnIndex, isAttack: isAttack);
    recordVoiceTiming(line.durationMs);

    if (!voiceAudible) return line;

    _duckBgmFor(line.durationMs);

    if (_nativeBackend != null) {
      _nativeBackend!.playPieceVoice(kind, drawnIndex);
      return line;
    }

    final customFile = _resolvePieceVoiceFile(kind, drawnIndex);
    if (customFile != null && _mciSend != null) {
      _playMciVoice(customFile);
      return line;
    }

    _playWav(SfxSynth.fallbackVoiceSfx(kind));
    return line;
  }

  @override
  void playSfx(SfxKind kind) {
    if (!_initialized) init();
    if (!sfxEnabled) return;
    if (shouldThrottleStep(kind)) return;
    if (_nativeBackend != null) {
      _nativeBackend!.playSfx(kind);
      return;
    }
    _playWav(kind);
  }

  // ------------------------------------------------------------ FIRTINA SESLERİ (Windows)
  static const int _thunderVersion = 2;
  static const int _ambienceVersion = 1;
  static const int _thunderVariants = 3;
  static const int _thunderChannels = 4;

  final Map<ThunderKind, List<String>> _thunderFiles = {
    ThunderKind.close: [],
    ThunderKind.distant: [],
  };
  final Map<ThunderKind, int> _lastThunder = {};
  final math.Random _thunderRng = math.Random();
  int _thunderChannel = 0;

  String? _windLoopPath;
  String? _ghostLoopPath;
  double _windLevel = 0.0;
  double _ghostLevel = 0.0;
  String? _windPlaying;
  String? _ghostPlaying;

  final Map<String, String> _boosted = {};
  final Set<String> _boostJobs = {};
  Directory? _stormAudioDir;

  static double _boostStep(double level) =>
      level <= 4.0 ? (level * 4).ceil() / 4 : level.ceilToDouble();

  String? _boostedPath(String path, double gain) {
    if (!path.toLowerCase().endsWith('.wav')) return null;
    final key = '$path@${gain.toStringAsFixed(2)}';
    final ready = _boosted[key];
    if (ready != null) return ready;
    final dir = _stormAudioDir;
    if (dir != null && _boostJobs.add(key)) {
      unawaited(_prepareBoost(path, gain, key, dir));
    }
    return null;
  }

  Future<void> _prepareBoost(String path, double gain, String key, Directory dir) async {
    try {
      final id = path.toLowerCase().hashCode.toUnsigned(32).toRadixString(16);
      final out = File('${dir.path}\\boost_${id}_${(gain * 100).round()}.wav');
      if (!out.existsSync() || out.lengthSync() < 1024) {
        final bytes = await _renderBoost(await File(path).readAsBytes(), gain);
        if (bytes == null) return;
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

  (String, int) _resolveLevel(String path, double level, {String? fallback}) {
    if (level <= 1.0) return (path, (level.clamp(0.0, 1.0) * 1000).round());
    final step = _boostStep(level);
    final boosted = _boostedPath(path, step);
    if (boosted == null) return (fallback ?? path, 1000);
    return (boosted, (math.min(1.0, level / step) * 1000).round());
  }

  Future<void> _prepareStormAudio() async {
    for (final dir in _searchDirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      try {
        for (final f in d.listSync()) {
          if (f is! File) continue;
          final name = f.uri.pathSegments.last.toLowerCase();
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

    final Directory dir;
    try {
      dir = Directory('${Directory.systemTemp.path}\\WizardHexChess\\storm_audio');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _stormAudioDir = dir;
    } catch (_) {
      return;
    }

    try {
      if (_windLoopPath == null) {
        final f = File('${dir.path}\\storm_wind_v$_ambienceVersion.wav');
        if (!f.existsSync() || f.lengthSync() < 1024) {
          await f.writeAsBytes(await _renderAmbience(ghost: false), flush: true);
        }
        _windLoopPath = f.path;
      }
      if (_ghostLoopPath == null) {
        final f = File('${dir.path}\\storm_ghost_v$_ambienceVersion.wav');
        if (!f.existsSync() || f.lengthSync() < 1024) {
          await f.writeAsBytes(await _renderAmbience(ghost: true), flush: true);
        }
        _ghostLoopPath = f.path;
      }
      _applyAmbience();
    } catch (_) {}

    final missing = ThunderKind.values.where((k) => _thunderFiles[k]!.isEmpty).toList();
    try {
      for (final kind in missing) {
        for (var v = 0; v < _thunderVariants; v++) {
          final file = File('${dir.path}\\thunder_v${_thunderVersion}_${kind.name}_$v.wav');
          if (!file.existsSync() || file.lengthSync() < 1024) {
            final seed = (kind == ThunderKind.close ? 101 : 503) + v * 7919;
            final bytes = await _renderThunder(kind, seed);
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

  @override
  void playThunder(ThunderKind kind) {
    if (!_initialized) init();
    if (_nativeBackend != null) {
      _nativeBackend!.playThunder(kind);
      return;
    }
    if (_mciSend == null || thunderVolume <= 0.001) return;
    final files = _thunderFiles[kind]!;
    if (files.isEmpty) return;
    var pick = _thunderRng.nextInt(files.length);
    if (files.length > 1 && pick == _lastThunder[kind]) pick = (pick + 1) % files.length;
    _lastThunder[kind] = pick;

    final alias = 'whc_thunder${_thunderChannel++ % _thunderChannels}';
    final gain = kind == ThunderKind.close ? 1.0 : 0.8;
    final (file, vol) = _resolveLevel(
      files[pick],
      BattleAudioBase.sanitizeLevel(thunderVolume) * gain,
    );
    final path = file.replaceAll('"', '');
    _mci('close $alias');
    if (_mci('open "$path" type mpegvideo alias $alias') == 0) {
      _mci('setaudio $alias volume to $vol');
    } else if (_mci('open "$path" type waveaudio alias $alias') != 0) {
      return;
    }
    _mci('play $alias from 0');
  }

  @override
  void setStormAmbience({required double wind, required double ghost}) {
    if (!_initialized) init();
    if (_nativeBackend != null) {
      _nativeBackend!.setStormAmbience(wind: wind, ghost: ghost);
      return;
    }
    _windLevel = BattleAudioBase.sanitizeLevel(wind);
    _ghostLevel = BattleAudioBase.sanitizeLevel(ghost);
    _applyAmbience();
  }

  void _applyAmbience() {
    if (_mciSend == null) return;
    _windPlaying = _applyLoop('whc_wind', _windLoopPath, _windLevel, _windPlaying);
    _ghostPlaying = _applyLoop('whc_ghost', _ghostLoopPath, _ghostLevel, _ghostPlaying);
  }

  String? _applyLoop(String alias, String? path, double level, String? playing) {
    if (path == null) return playing;
    if (level <= 0.001) {
      if (playing != null) {
        _mci('stop $alias');
        _mci('close $alias');
      }
      return null;
    }
    final (file, vol) = _resolveLevel(path, level, fallback: playing);
    if (playing != file) {
      if (playing != null) {
        _mci('stop $alias');
        _mci('close $alias');
      }
      if (_mci('open "${file.replaceAll('"', '')}" type mpegvideo alias $alias') != 0) return null;
      _mci('setaudio $alias volume to $vol');
      _mci('play $alias repeat');
      return file;
    }
    _mci('setaudio $alias volume to $vol');
    return file;
  }

  void _playWav(SfxKind kind) {
    final fn = _playSound;
    final ptr = _wavPtrs[kind];
    if (fn == null || ptr == null) return;
    fn(ptr, 0, _sndMemory | _sndAsync | _sndNoDefault);
  }

  void _buildProceduralBank() {
    for (final k in SfxKind.values) {
      final pcm = SfxSynth.synthesize(k);
      _sfxPcm[k] = pcm;
      final bytes = SfxSynth.encodeWav(pcm, SfxSynth.sampleRate, gain: gainOfSfx(k));
      final ptr = calloc<Uint8>(bytes.length);
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      _wavPtrs[k] = ptr;
    }
  }

  void _rescaleBank({required bool voice}) {
    for (final entry in _sfxPcm.entries) {
      if (SfxSynth.isVoiceSfx(entry.key) != voice) continue;
      final ptr = _wavPtrs[entry.key];
      if (ptr == null) continue;
      final bytes = SfxSynth.encodeWav(
        entry.value,
        SfxSynth.sampleRate,
        gain: gainOfSfx(entry.key),
      );
      ptr.asTypedList(bytes.length).setAll(0, bytes);
    }
  }

  @override
  void dispose() {
    voiceDuckTimer?.cancel();
    if (_nativeBackend != null) {
      _nativeBackend!.dispose();
      _nativeBackend = null;
      return;
    }
    stopBgm();
    if (_mciSend != null) {
      _mci('close whc_voice');
      for (var c = 0; c < _thunderChannels; c++) {
        _mci('close whc_thunder$c');
      }
      _mci('close whc_wind');
      _mci('close whc_ghost');
    }
    for (final ptr in _wavPtrs.values) {
      calloc.free(ptr);
    }
    _wavPtrs.clear();
    _sfxPcm.clear();
  }
}
