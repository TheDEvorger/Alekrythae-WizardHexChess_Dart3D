import 'dart:math' as math;
import 'dart:typed_data';

import 'voice_catalog.dart';

/// Prosedürel savaş, adım ve boru ses efektleri sentezleyicisi.
///
/// Saf Dart'tır; Windows, Android/macOS (`audioplayers`) ve Web Audio API
/// tarafından ortak kullanılır.
class SfxSynth {
  static const int sampleRate = 22050;

  static bool isVoiceSfx(SfxKind k) => switch (k) {
        SfxKind.voicePawn ||
        SfxKind.voiceKnight ||
        SfxKind.voiceBishop ||
        SfxKind.voiceRookFemale ||
        SfxKind.voiceQueenFemale ||
        SfxKind.voiceKing =>
          true,
        _ => false,
      };

  static SfxKind fallbackVoiceSfx(dynamic pieceKind) {
    // PieceType ile doğrudan eşleme
    final name = pieceKind.toString().split('.').last;
    return switch (name) {
      'pawn' => SfxKind.voicePawn,
      'knight' => SfxKind.voiceKnight,
      'bishop' => SfxKind.voiceBishop,
      'rook' => SfxKind.voiceRookFemale,
      'queen' => SfxKind.voiceQueenFemale,
      'king' => SfxKind.voiceKing,
      _ => SfxKind.voicePawn,
    };
  }

  static Float64List synthesize(SfxKind kind) {
    const sr = sampleRate;
    final rng = math.Random(kind.index * 977 + 42);
    final dur = switch (kind) {
      SfxKind.stepArmor => 0.14,
      SfxKind.stepStealth => 0.10,
      SfxKind.stepStomp => 0.30,
      SfxKind.wingFlap => 0.26,
      SfxKind.magicGlide => 0.34,
      SfxKind.clashSteel => 0.36,
      SfxKind.slashBlade => 0.28,
      SfxKind.dragonFire => 0.68,
      SfxKind.maulSmash => 0.56,
      SfxKind.bloodDrain => 0.58,
      SfxKind.axeCleave => 0.46,
      SfxKind.voicePawn => 0.52,
      SfxKind.voiceKnight => 0.42,
      SfxKind.voiceBishop => 0.66,
      SfxKind.voiceRookFemale => 0.58,
      SfxKind.voiceQueenFemale => 0.60,
      SfxKind.voiceKing => 0.64,
    };

    final n = (sr * dur).round();
    final pcm = Float64List(n);
    var lp = 0.0;

    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final u = i / n;
      final white = rng.nextDouble() * 2 - 1;
      lp = lp * 0.86 + white * 0.14;
      var s = 0.0;

      switch (kind) {
        case SfxKind.stepArmor:
          final env = math.exp(-t * 28);
          s = (lp * 0.55 +
                  math.sin(t * 2 * math.pi * 115) * 0.45 +
                  math.sin(t * 2 * math.pi * 1480) * 0.18 * math.exp(-t * 45)) *
              env *
              0.55;
        case SfxKind.stepStealth:
          s = lp * math.exp(-t * 36) * 0.38;
        case SfxKind.stepStomp:
          final f = 78 * math.exp(-t * 5.5) + 34;
          s = (math.sin(t * 2 * math.pi * f) * 0.78 + lp * 0.48) * math.exp(-t * 9.5) * 0.85;
        case SfxKind.wingFlap:
          final env = math.sin(math.pi * u) * math.exp(-u * 1.4);
          s = (lp * 0.85 + math.sin(t * 2 * math.pi * 68) * 0.25) * env * 0.65;
        case SfxKind.magicGlide:
          final env = math.sin(math.pi * u);
          s = (math.sin(t * 2 * math.pi * 330) * 0.25 +
                  math.sin(t * 2 * math.pi * 495) * 0.22 +
                  lp * 0.18) *
              env *
              0.42;
        case SfxKind.clashSteel:
          final env = math.exp(-t * 10.5);
          s = (math.sin(t * 2 * math.pi * 1180) * 0.32 +
                  math.sin(t * 2 * math.pi * 1790) * 0.26 +
                  math.sin(t * 2 * math.pi * 2640) * 0.18 +
                  white * math.exp(-t * 45) * 0.55) *
              env *
              0.78;
        case SfxKind.slashBlade:
          final sweep = 420 + 1600 * (1 - u);
          s = (white * 0.35 + math.sin(t * 2 * math.pi * sweep) * 0.28) *
              math.sin(math.pi * u) *
              math.exp(-t * 6.5) *
              0.72;
        case SfxKind.dragonFire:
          final env = math.sin(math.pi * math.min(1.0, u * 1.15));
          final growl = math.sin(t * 2 * math.pi * (82 + 14 * math.sin(t * 26))) * 0.42;
          s = (lp * 0.85 + white * 0.18 + growl) * env * 0.82;
        case SfxKind.maulSmash:
          final boom = math.sin(t * 2 * math.pi * (92 * math.exp(-t * 4.5) + 28));
          final crunch = lp * math.exp(-t * 11) * 0.7;
          final ring = math.sin(t * 2 * math.pi * 620) * math.exp(-t * 14) * 0.22;
          s = (boom * math.exp(-t * 5.8) * 0.85 + crunch + ring) * 0.92;
        case SfxKind.bloodDrain:
          final env = math.sin(math.pi * u);
          final f1 = 260 + 90 * math.sin(t * 11);
          s = (math.sin(t * 2 * math.pi * f1) * 0.34 +
                  math.sin(t * 2 * math.pi * f1 * 1.5) * 0.24 +
                  lp * 0.30) *
              env *
              0.68;
        case SfxKind.axeCleave:
          final whoosh = lp * math.sin(math.pi * math.min(1.0, u * 2.2)) * 0.55;
          final hit = u > 0.32
              ? (math.sin((t - 0.14) * 2 * math.pi * 110) * 0.65 +
                      math.sin((t - 0.14) * 2 * math.pi * 1340) * 0.28) *
                  math.exp(-(t - 0.14) * 11)
              : 0.0;
          s = (whoosh + hit) * 0.85;
        case SfxKind.voicePawn:
          final env = math.sin(math.pi * u) * math.exp(-t * 1.8);
          s = (_brass(t, 196) * 0.5 + _brass(t, 293.6) * 0.4 + lp * 0.12) * env * 0.68;
        case SfxKind.voiceKnight:
          final env = math.exp(-t * 6.5);
          s = (math.sin(t * 2 * math.pi * (1950 - 600 * t)) * 0.32 +
                  math.sin(t * 2 * math.pi * 2880) * 0.18 +
                  lp * 0.42) *
              env *
              0.66;
        case SfxKind.voiceBishop:
          final env = math.sin(math.pi * u);
          final f = 74 - 18 * u + 6 * math.sin(t * 34);
          s = (_brass(t, f) * 0.62 + lp * 0.55) * env * 0.82;
        case SfxKind.voiceRookFemale:
          final env = math.sin(math.pi * u);
          final f = 293.66 + (u < 0.45 ? 46.0 * (u / 0.45) : 46.0);
          s = (_brass(t, f) * 0.42 +
                  _brass(t, f * 1.5) * 0.26 +
                  math.sin(t * 2 * math.pi * 65) * math.exp(-t * 5) * 0.38) *
              env *
              0.72;
        case SfxKind.voiceQueenFemale:
          final env = math.sin(math.pi * u);
          final vib = 1 + 0.012 * math.sin(t * 32);
          s = (math.sin(t * 2 * math.pi * 392 * vib) * 0.32 +
                  math.sin(t * 2 * math.pi * 466.16 * vib) * 0.28 +
                  math.sin(t * 2 * math.pi * 587.33 * vib) * 0.22) *
              env *
              0.58;
        case SfxKind.voiceKing:
          final env = math.sin(math.pi * u);
          final f = 110.0 + 6.0 * math.sin(t * 9);
          s = (_brass(t, f) * 0.58 + _brass(t, f * 1.5) * 0.32 + lp * 0.15) * env * 0.78;
      }
      pcm[i] = s.clamp(-1.0, 1.0);
    }

    return pcm;
  }

  static double _brass(double t, double freq) {
    final w = 2 * math.pi * freq * t;
    return math.sin(w) * 0.55 + math.sin(w * 2) * 0.28 + math.sin(w * 3) * 0.17;
  }

  static Float32List toFloat32(Float64List samples) {
    final out = Float32List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      out[i] = samples[i];
    }
    return out;
  }

  static Uint8List encodeWav(Float64List samples, int sr, {double gain = 1.0}) {
    final dataSize = samples.length * 2;
    final out = ByteData(44 + dataSize);
    void writeAscii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        out.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    out.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little); // PCM
    out.setUint16(22, 1, Endian.little); // Mono
    out.setUint32(24, sr, Endian.little);
    out.setUint32(28, sr * 2, Endian.little);
    out.setUint16(32, 2, Endian.little);
    out.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    out.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i] * gain * 32767.0).round().clamp(-32768, 32767);
      out.setInt16(44 + i * 2, v, Endian.little);
    }
    return out.buffer.asUint8List();
  }
}

