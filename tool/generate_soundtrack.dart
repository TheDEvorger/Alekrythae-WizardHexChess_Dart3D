// Fon müziği üretici: `dart run tool/generate_soundtrack.dart`
// Çıktı: assets/audio/dark_fantasy_soundtrack.wav (22.05 kHz, 16 bit, stereo, 64 sn döngü).
//
// Sakin, karanlık fantezi ambiyansı: Re minör akor dizisi (Dm–B♭–F–C–Dm–Gm–B♭–A),
// yumuşak yaylı dokusu, bas, seyrek antik çan ve uzaktan yumuşak davul, hafif yankı.
// Önceki sürümün sorunları giderildi: akor değişiminde ve döngü noktasında tıkırtı yok
// (her ses olayı kendi süresince faz-sürekli üretilir ve döngü uzunluğuna katlanır,
// süzgeç/yankı iki tur çalıştırılıp kalıcı durumdan alınır), hışırtı yok, bas titremiyor,
// ses kırpılmıyor ve fon müziği olarak arka planda kalacak düzeyde.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 22050;
const int chordSec = 8;
const int chordCount = 8;
const int loopSec = chordSec * chordCount; // 64
const int n = sampleRate * loopSec;

/// (bas, [üst sesler]) Hz
const List<(double, List<double>)> chords = [
  (73.42, [146.83, 174.61, 220.00, 293.66]), // Dm
  (58.27, [146.83, 174.61, 233.08, 293.66]), // B♭
  (87.31, [130.81, 174.61, 220.00, 261.63]), // F
  (65.41, [130.81, 164.81, 196.00, 261.63]), // C
  (73.42, [146.83, 174.61, 220.00, 349.23]), // Dm (üstte F4)
  (98.00, [146.83, 196.00, 233.08, 293.66]), // Gm
  (58.27, [146.83, 174.61, 233.08, 349.23]), // B♭ (üstte F4)
  (55.00, [164.81, 220.00, 277.18, 329.63]), // A (Dm'ye çözülür)
];

final Float64List padL = Float64List(n), padR = Float64List(n);
final Float64List dryL = Float64List(n), dryR = Float64List(n);
final math.Random rng = math.Random(20261110);

/// Yükselen kosinüs (0→1) geçişi.
double rise(double x) => x <= 0 ? 0 : (x >= 1 ? 1 : 0.5 - 0.5 * math.cos(math.pi * x));

/// Olay örneğini döngüye katlayarak ekler (sonu başa sarar: kesintisiz döngü).
void add(Float64List buf, int start, int j, double v) {
  buf[(start + j) % n] += v;
}

void renderPadVoice(double f, double startSec, double durSec, double amp,
    {required double attack, required double release, required int maxHarm}) {
  final start = (startSec * sampleRate).round() % n + n;
  final len = (durSec * sampleRate).round();
  // Üç hafif akortsuz kopya: doğal yaylı korosu (±2 sent), farklı sağ/sol konumda
  const detune = [0.9988, 1.0, 1.0013];
  const panL = [0.82, 0.64, 0.46];
  const panR = [0.46, 0.64, 0.82];
  for (var c = 0; c < 3; c++) {
    final fc = f * detune[c];
    final ph0 = rng.nextDouble() * 2 * math.pi;
    final harms = <(double, double)>[];
    for (var h = 1; h <= maxHarm; h++) {
      if (fc * h > 3200) break;
      harms.add((h.toDouble(), (1.0 / h) * math.exp(-0.32 * (h - 1))));
    }
    final w = 2 * math.pi * fc / sampleRate;
    for (var j = 0; j < len; j++) {
      final t = j / sampleRate;
      final env = rise(t / attack) * rise((durSec - t) / release);
      if (env <= 0) continue;
      final ph = ph0 + w * j;
      var s = 0.0;
      for (final (h, a) in harms) {
        s += a * math.sin(ph * h);
      }
      final v = s * env * amp;
      add(padL, start, j, v * panL[c]);
      add(padR, start, j, v * panR[c]);
    }
  }
}

void renderBell(double f, double atSec, double amp, double pan) {
  final start = (atSec * sampleRate).round() % n + n;
  const partials = [(1.0, 1.0, 3.2), (2.0, 0.34, 2.3), (2.76, 0.20, 1.7), (5.40, 0.07, 0.9)];
  final len = (6.0 * sampleRate).round();
  for (var j = 0; j < len; j++) {
    final t = j / sampleRate;
    final atk = rise(t / 0.008);
    var s = 0.0;
    for (final (ratio, a, tau) in partials) {
      s += a * math.exp(-t / tau) * math.sin(2 * math.pi * f * ratio * t);
    }
    final v = s * atk * amp * rise((6.0 - t) / 0.5);
    add(dryL, start, j, v * (1 - pan) * 1.2);
    add(dryR, start, j, v * pan * 1.2);
  }
}

void renderDrum(double atSec, double amp) {
  final start = (atSec * sampleRate).round() % n + n;
  final len = (2.4 * sampleRate).round();
  var phase = 0.0;
  for (var j = 0; j < len; j++) {
    final t = j / sampleRate;
    // Faz integrali: perde 55 Hz'e yumuşakça iner (cıvıltı yok)
    final f = 55.0 * (1 + 0.45 * math.exp(-t / 0.06));
    phase += 2 * math.pi * f / sampleRate;
    final env = rise(t / 0.006) * math.exp(-t / 0.5) * rise((2.4 - t) / 0.3);
    final v = (math.sin(phase) + 0.25 * math.sin(phase * 1.5)) * env * amp;
    add(dryL, start, j, v);
    add(dryR, start, j, v);
  }
}

/// Tek kutuplu alçak geçiren süzgeç (iki tur: kalıcı durum, döngüde sıçrama yok).
Float64List lowPass(Float64List x, double cutoff) {
  final a = 1 - math.exp(-2 * math.pi * cutoff / sampleRate);
  final y = Float64List(n);
  var s = 0.0;
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 0; i < n; i++) {
      s += a * (x[i] - s);
      if (pass == 1) y[i] = s;
    }
  }
  return y;
}

/// Freeverb benzeri yankı (8 tarak + 4 tüm geçiren), iki tur çalıştırılır.
Float64List reverb(Float64List x, int spread) {
  const combs = [558, 594, 639, 678, 711, 746, 779, 809];
  const alls = [278, 220, 170, 112];
  const feedback = 0.80, damp = 0.35;
  final cBuf = [for (final d in combs) Float64List(d + spread)];
  final cIdx = List<int>.filled(combs.length, 0);
  final cLp = List<double>.filled(combs.length, 0);
  final aBuf = [for (final d in alls) Float64List(d + spread)];
  final aIdx = List<int>.filled(alls.length, 0);
  final y = Float64List(n);
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 0; i < n; i++) {
      final input = x[i] * 0.12;
      var out = 0.0;
      for (var c = 0; c < combs.length; c++) {
        final b = cBuf[c];
        final o = b[cIdx[c]];
        cLp[c] = o * (1 - damp) + cLp[c] * damp;
        b[cIdx[c]] = input + cLp[c] * feedback;
        cIdx[c] = (cIdx[c] + 1) % b.length;
        out += o;
      }
      for (var a = 0; a < alls.length; a++) {
        final b = aBuf[a];
        final bo = b[aIdx[a]];
        b[aIdx[a]] = out + bo * 0.5;
        out = bo - out;
        aIdx[a] = (aIdx[a] + 1) % b.length;
      }
      if (pass == 1) y[i] = out;
    }
  }
  return y;
}

void main() {
  // 1. Yaylı dokusu ve bas: her akor 1,5 sn önce yumuşakça girer, sonrakiyle 3,5 sn örtüşür
  for (var c = 0; c < chordCount; c++) {
    final (bass, upper) = chords[c];
    final t0 = c * chordSec - 1.5;
    const dur = chordSec + 3.5;
    for (final f in upper) {
      renderPadVoice(f, t0, dur, 0.050, attack: 3.0, release: 3.5, maxHarm: 7);
    }
    renderPadVoice(bass, t0, dur, 0.150, attack: 3.0, release: 3.5, maxHarm: 3);
  }

  // 2. Seyrek antik çan (akor seslerinden, yumuşak) ve uzaktan davul
  renderBell(440.00, 2.0, 0.050, 0.35); // Dm: La
  renderBell(523.25, 18.0, 0.045, 0.65); // F: Do
  renderBell(587.33, 34.0, 0.050, 0.40); // Dm: Re
  renderBell(466.16, 50.0, 0.045, 0.60); // B♭: Si♭
  renderBell(659.26, 60.0, 0.035, 0.50); // A: Mi (çözülmeyi hazırlar)
  renderDrum(0.0, 0.16);
  renderDrum(16.0, 0.08);
  renderDrum(32.0, 0.16);
  renderDrum(48.0, 0.08);
  renderDrum(56.0, 0.07);
  renderDrum(60.0, 0.10);

  // 3. Yaylıları yumuşat (sert üst harmonik yok), 16 sn'lik çok hafif "nefes" dalgalanması
  final fl = lowPass(padL, 1800), fr = lowPass(padR, 1800);
  for (var i = 0; i < n; i++) {
    final breath = 1 + 0.06 * math.sin(2 * math.pi * 4 * i / n); // döngüde tam 4 tur
    dryL[i] += fl[i] * breath;
    dryR[i] += fr[i] * breath;
  }

  // 4. Yankı (sağ ve sol farklı gecikme: geniş ama sakin bir salon)
  final wetL = reverb(dryL, 0), wetR = reverb(dryR, 23);
  final outL = Float64List(n), outR = Float64List(n);
  var peak = 0.0;
  for (var i = 0; i < n; i++) {
    outL[i] = dryL[i] * 0.80 + wetL[i] * 0.55;
    outR[i] = dryR[i] * 0.80 + wetR[i] * 0.55;
    peak = math.max(peak, math.max(outL[i].abs(), outR[i].abs()));
  }

  // 5. Tepe -5 dBFS'e normalize (kırpılma ve doygunluk yok)
  final g = 0.56 / peak;

  final byteLength = n * 4;
  final bytes = Uint8List(44 + byteLength);
  final bd = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bd.setUint32(4, 36 + byteLength, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little); // PCM
  bd.setUint16(22, 2, Endian.little); // stereo
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 4, Endian.little);
  bd.setUint16(32, 4, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  bd.setUint32(40, byteLength, Endian.little);
  var off = 44;
  for (var i = 0; i < n; i++) {
    bd.setInt16(off, (outL[i] * g * 32767).round().clamp(-32767, 32767), Endian.little);
    bd.setInt16(off + 2, (outR[i] * g * 32767).round().clamp(-32767, 32767), Endian.little);
    off += 4;
  }

  final outFile = File('assets/audio/dark_fantasy_soundtrack.wav');
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(bytes);
  stdout.writeln('Fon müziği oluşturuldu: ${outFile.path} (${bytes.length} bayt, $loopSec sn döngü)');
}
