import 'dart:async';
import 'dart:math' as math;

import '../game/chess_game.dart';
import 'sfx_synth.dart';
import 'thunder_synth.dart';
import 'voice_catalog.dart';

/// Platform bağımsız [BattleAudio] ortak durumu, kura torbası ve zamanlama mantığı.
abstract class BattleAudioBase {
  bool sfxEnabled = true;
  bool voiceEnabled = true;
  bool bgmEnabled = true;

  double voiceVolume = 0.90;
  double sfxVolume = 0.85;
  double bgmVolume = 0.55;
  double thunderVolume = 1.0;

  /// Karakter konuşurken fon müziği bu orana kısılır (Audio Ducking).
  static const double bgmDuckRatio = 0.18;

  static const List<String> bgmCandidateNames = [
    'bgm.mp3',
    'bgm.wav',
    'soundtrack.mp3',
    'soundtrack.wav',
    'dark_fantasy_soundtrack.wav',
    'ambient.mp3',
    'ambient.wav',
  ];

  bool bgmDucked = false;
  Timer? voiceDuckTimer;
  DateTime? voiceStartTime;
  int currentVoiceDurationMs = 0;
  int _lastStepMs = 0;

  final Map<PieceType, VoiceShuffleBag> _voiceBags = {};

  bool get voiceAudible => voiceEnabled && voiceVolume > 0.001;

  double get effectiveBgmVolume =>
      bgmVolume.clamp(0.0, 1.0) * (bgmDucked ? bgmDuckRatio : 1.0);

  double gainOfSfx(SfxKind k) =>
      (SfxSynth.isVoiceSfx(k) ? voiceVolume : sfxVolume).clamp(0.0, 1.0);

  bool get isBgmPlaying;

  bool get isVoicePlaying {
    if (!voiceAudible) return false;
    final start = voiceStartTime;
    if (start == null) return false;
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    return elapsed < currentVoiceDurationMs;
  }

  int get remainingVoiceMs {
    final start = voiceStartTime;
    if (start == null) return 0;
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    return math.max(0, currentVoiceDurationMs - elapsed);
  }

  VoiceShuffleBag bagOf(PieceType kind) =>
      _voiceBags.putIfAbsent(kind, () => VoiceShuffleBag(size: 6));

  void recordVoiceTiming(int durationMs) {
    voiceStartTime = DateTime.now();
    currentVoiceDurationMs = durationMs;
  }

  /// Çok sık adım seslerinin üst üste binmesini önler.
  bool shouldThrottleStep(SfxKind kind) {
    final isStep = kind == SfxKind.stepArmor ||
        kind == SfxKind.stepStealth ||
        kind == SfxKind.stepStomp ||
        kind == SfxKind.wingFlap ||
        kind == SfxKind.magicGlide;
    if (!isStep) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastStepMs < 135) return true;
    _lastStepMs = now;
    return false;
  }

  static double sanitizeLevel(double v) => v.isFinite ? math.max(0.0, v) : 0.0;

  void init();
  void startBgm();
  void stopBgm();
  void setBgmVolume(double v);
  void setBgmEnabled(bool enabled);
  void toggleBgm() => setBgmEnabled(!bgmEnabled);
  void setVoiceVolume(double v);
  void setSfxVolume(double v);
  int countAvailableElevenLabsFiles();
  bool hasVoiceFile(String id);
  VoiceLine speakMoveWithBag(PieceType kind, {bool isAttack = false});
  VoiceLine previewVoice(PieceType kind) => speakMoveWithBag(kind);

  /// Karakter konuşmasını / savaş narasını tetikler.
  /// Kural: Yalnızca hareket ve saldırı başladığında konuşma sesi çalınır.
  VoiceLine speak(PieceType kind, VoiceEvent event) {
    if (event == VoiceEvent.march || event == VoiceEvent.attack) {
      return speakMoveWithBag(kind, isAttack: event == VoiceEvent.attack);
    }
    return voiceLineOf(kind, event);
  }

  void playSfx(SfxKind kind);
  void playThunder(ThunderKind kind);
  void setStormAmbience({required double wind, required double ghost});
  void dispose();
}

