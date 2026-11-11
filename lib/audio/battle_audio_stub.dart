import '../game/chess_game.dart';
import 'battle_audio_base.dart';
import 'thunder_synth.dart';
import 'voice_catalog.dart';

class BattleAudio extends BattleAudioBase {
  @override
  bool get isBgmPlaying => false;

  @override
  void init() {}

  @override
  void startBgm() {}

  @override
  void stopBgm() {}

  @override
  void setBgmVolume(double v) => bgmVolume = v.clamp(0.0, 1.0);

  @override
  void setBgmEnabled(bool enabled) => bgmEnabled = enabled;

  @override
  void setVoiceVolume(double v) => voiceVolume = v.clamp(0.0, 1.0);

  @override
  void setSfxVolume(double v) => sfxVolume = v.clamp(0.0, 1.0);

  @override
  int countAvailableElevenLabsFiles() => 0;

  @override
  bool hasVoiceFile(String id) => false;

  @override
  VoiceLine speakMoveWithBag(PieceType kind, {bool isAttack = false}) {
    final drawnIndex = bagOf(kind).draw();
    return moveVoiceLineOf(kind, drawnIndex, isAttack: isAttack);
  }

  @override
  void playSfx(SfxKind kind) {}

  @override
  void playThunder(ThunderKind kind) {}

  @override
  void setStormAmbience({required double wind, required double ghost}) {}

  @override
  void dispose() {}
}
