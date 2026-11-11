import 'dart:math' as math;
import 'dart:typed_data';

/// Gök gürültüsü türü: yakın yıldırım (çatırtı + patlama + gürleme) veya
/// bulut içindeki uzak şimşek (yalnızca boğuk, yuvarlanan gürleme).
enum ThunderKind { close, distant }

/// Prosedürel, gerçekçi gök gürültüsü sentezleyicisi.
///
/// Saf Dart'tır (dart:ffi / Flutter bağımlılığı yok); `Isolate.run` içinde
/// arka planda çalıştırılabilir. Gerçek gök gürültüsünün fiziksel katmanlarını
/// ayrı ayrı üretip karıştırır:
///
/// 1. **Çatırtı**: Yıldırım kanalının yakın kısmından gelen, kumaş yırtılması
///    gibi keskin, yoğunluğu hızla azalan geniş bantlı çıtırtılar.
/// 2. **Patlama**: Ana basınç dalgası; düşük frekanslı, perdesi düşen ağır "bum".
/// 3. **Gürleme**: Kanalın uzak kısımlarından farklı zamanlarda gelen sesler;
///    rastgele "yuvarlanmalar", hızlı homurtu modülasyonu ve zamanla boğuklaşan
///    (yüksek frekansları emilen) gürültü.
/// 4. **Yankı**: Vadilerden/dağlardan dönen, her biri daha boğuk gecikmeli kopyalar.
///
/// Çıktı: 44.1 kHz, 16 bit, stereo WAV (sol/sağ gürleme bağımsız → geniş ses).
class ThunderSynth {
  static const int sampleRate = 44100;

  static Uint8List renderWav(ThunderKind kind, int seed) {
    final (l, r) = kind == ThunderKind.close ? _renderClose(seed) : _renderDistant(seed);
    return _encodeStereoWav(l, r, sampleRate);
  }

  /// 16 bit PCM bir WAV dosyasının sesini [gain] kat yükseltir. Kanal sesi
  /// (MCI) %100'ü aşamadığı için %100 üstü ayarlar bu kopyayla çalınır.
  ///
  /// Sert kırpma yerine yumuşak dizli bir sınırlayıcı kullanılır: eşiğin
  /// altındaki örnekler yalnızca yükseltilir, tepeler `tanh` eğrisiyle tam
  /// ölçeğe yaklaşır; cızırtı/çatlama olmaz. Örnek başına (durumsuz) işlendiği
  /// için dikişsiz döngüler dikişsiz kalır. PCM16 değilse null döner.
  static Uint8List? boostWav(Uint8List wav, double gain) {
    if (wav.length < 44) return null;
    final bd = ByteData.sublistView(wav);
    String tag(int o) => String.fromCharCodes(wav.sublist(o, o + 4));
    if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;

    var bits = 0;
    var format = 0;
    var dataStart = -1;
    var dataLen = 0;
    var o = 12;
    while (o + 8 <= wav.length) {
      final id = tag(o);
      final size = bd.getUint32(o + 4, Endian.little);
      final body = o + 8;
      if (id == 'fmt ' && body + 16 <= wav.length) {
        format = bd.getUint16(body, Endian.little);
        bits = bd.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        dataStart = body;
        dataLen = math.min(size, wav.length - body);
        break;
      }
      o = body + size + (size & 1);
    }
    if (format != 1 || bits != 16 || dataStart < 0) return null;

    final out = Uint8List.fromList(wav);
    final ob = ByteData.sublistView(out);
    const knee = 0.72;
    const span = 1.0 - knee;
    final end = dataStart + (dataLen & ~1);
    for (var i = dataStart; i < end; i += 2) {
      final x = ob.getInt16(i, Endian.little) / 32768.0 * gain;
      final a = x.abs();
      final y = a <= knee ? a : knee + span * _tanh((a - knee) / span);
      final s = (y * 32767.0).round().clamp(0, 32767);
      ob.setInt16(i, x < 0 ? -s : s, Endian.little);
    }
    return out;
  }

  // ------------------------------------------------------------ yakın yıldırım
  static (Float64List, Float64List) _renderClose(int seed) {
    const sr = sampleRate;
    final rnd = math.Random(seed);
    final dur = 7.5 + rnd.nextDouble() * 2.5;
    final n = (dur * sr).round();

    // 1) Çatırtı (yırtılma)
    final crackDur = 0.28 + rnd.nextDouble() * 0.30;
    final crack = _crackle(
      n,
      math.Random(seed * 31 + 7),
      denseRate: 1500,
      denseTau: 0.05,
      tailRate: 240,
      tailTau: crackDur * 0.6,
      envTau: crackDur * 0.5,
      grainTau: 0.0035,
      hpHz: 350,
      lpHz: 7800,
      clickMs: 8,
    );
    _normalizePeak(crack, 1.0);

    // 2) Patlama
    final boomAt = 0.025 + rnd.nextDouble() * 0.05;
    final boom = _boom(
      n,
      math.Random(seed * 17 + 3),
      at: boomAt,
      decay: 0.55 + rnd.nextDouble() * 0.35,
      lpHz: 140,
      midHz: 230,
      midLevel: 0.9,
      thumpLevel: 0.9,
    );
    _normalizePeak(boom, 1.0);

    // 3) Gürleme: ilk yuvarlanma patlamanın devamıdır, sonrakiler rastgele.
    final rolls = <_Roll>[
      _Roll(at: boomAt + 0.10, amp: 1.0, rise: 0.06, decay: 0.85 + rnd.nextDouble() * 0.4),
    ];
    final rollCount = 4 + rnd.nextInt(4);
    for (var k = 0; k < rollCount; k++) {
      final at = 0.35 + rnd.nextDouble() * dur * 0.60;
      rolls.add(_Roll(
        at: at,
        amp: (0.50 + rnd.nextDouble() * 0.50) * math.exp(-at / 5.5),
        rise: 0.10 + rnd.nextDouble() * 0.35,
        decay: 0.45 + rnd.nextDouble() * 1.10,
      ));
    }
    final (rumL, rumR) = _rumble(
      n,
      seed,
      rolls,
      baseHz: 120,
      extraHz: 380,
      slideTau: 2.6,
      growlHz: 300,
      growlLevel: 0.60,
      growlTau: 4.0,
    );

    // 4) Yankılar (çatırtı + patlamanın boğuk kopyaları)
    final dry = Float64List(n);
    for (var i = 0; i < n; i++) {
      dry[i] = crack[i] * 0.70 + boom[i];
    }
    final echoL = _echoes(dry, const [0.19, 0.41, 0.74, 1.12, 1.61]);
    final echoR = _echoes(dry, const [0.23, 0.47, 0.69, 1.21, 1.55]);

    final pan = rnd.nextDouble() * 2 - 1;
    final l = Float64List(n);
    final r = Float64List(n);
    for (var i = 0; i < n; i++) {
      l[i] = crack[i] * 0.80 * (1 - 0.35 * pan) + boom[i] * 0.90 + rumL[i] * 0.85 + echoL[i] * 0.50;
      r[i] = crack[i] * 0.80 * (1 + 0.35 * pan) + boom[i] * 0.90 + rumR[i] * 0.85 + echoR[i] * 0.50;
    }
    _finish(l, r, drive: 2.1, peak: 0.95, fadeInMs: 0);
    return (l, r);
  }

  // ------------------------------------------------------- uzak bulut şimşeği
  static (Float64List, Float64List) _renderDistant(int seed) {
    const sr = sampleRate;
    final rnd = math.Random(seed);
    final dur = 6.5 + rnd.nextDouble() * 3.0;
    final n = (dur * sr).round();

    final rolls = <_Roll>[];
    final first = 0.15 + rnd.nextDouble() * 0.35;
    rolls.add(_Roll(at: first, amp: 1.0, rise: 0.25 + rnd.nextDouble() * 0.30, decay: 1.0 + rnd.nextDouble() * 0.6));
    final rollCount = 3 + rnd.nextInt(4);
    for (var k = 0; k < rollCount; k++) {
      final at = first + 0.4 + rnd.nextDouble() * dur * 0.55;
      rolls.add(_Roll(
        at: at,
        amp: (0.35 + rnd.nextDouble() * 0.65) * math.exp(-at / 5.0),
        rise: 0.20 + rnd.nextDouble() * 0.45,
        decay: 0.7 + rnd.nextDouble() * 1.3,
      ));
    }
    final (rumL, rumR) = _rumble(
      n,
      seed + 1000,
      rolls,
      baseHz: 95,
      extraHz: 170,
      slideTau: 4.0,
      growlHz: 200,
      growlLevel: 0.42,
      growlTau: 5.0,
    );

    // Boğuk, uzaktan gelen patlama
    final boom = _boom(
      n,
      math.Random(seed * 19 + 5),
      at: first + 0.05,
      decay: 0.9,
      lpHz: 75,
      midHz: 150,
      midLevel: 0.35,
      thumpLevel: 0.4,
      attackTau: 0.09,
    );
    _normalizePeak(boom, 1.0);

    // Arada sırada duyulan çok hafif, boğuk çıtırtı dokusu
    final crackle = _crackle(
      n,
      math.Random(seed * 23 + 11),
      denseRate: 0,
      denseTau: 0.05,
      tailRate: 70,
      tailTau: 1.6,
      envTau: 1.4,
      grainTau: 0.006,
      hpHz: 220,
      lpHz: 900,
      clickMs: 0,
      startAt: first,
    );
    _normalizePeak(crackle, 1.0);

    final echoL = _echoes(boom, const [0.33, 0.71, 1.24]);
    final echoR = _echoes(boom, const [0.38, 0.66, 1.31]);

    final l = Float64List(n);
    final r = Float64List(n);
    for (var i = 0; i < n; i++) {
      final common = boom[i] * 0.45 + crackle[i] * 0.10;
      l[i] = rumL[i] * 0.85 + common + echoL[i] * 0.30;
      r[i] = rumR[i] * 0.85 + common + echoR[i] * 0.30;
    }
    _finish(l, r, drive: 1.7, peak: 0.93, fadeInMs: 40);
    return (l, r);
  }

  // ---------------------------------------------------------------- katmanlar

  /// Rastgele zamanlarda tetiklenen, üssel sönen gürültü taneleri (yırtılma sesi).
  static Float64List _crackle(
    int n,
    math.Random nr, {
    required double denseRate,
    required double denseTau,
    required double tailRate,
    required double tailTau,
    required double envTau,
    required double grainTau,
    required double hpHz,
    required double lpHz,
    required double clickMs,
    double startAt = 0.0,
  }) {
    const sr = sampleRate;
    final out = Float64List(n);
    final hp = _Biquad()..highpass(hpHz, 0.7);
    final lp = _Biquad()..lowpass(lpHz, 0.7);
    final grainDecay = math.exp(-1.0 / (grainTau * sr));
    final start = (startAt * sr).round();
    final end = math.min(n, start + ((envTau * 7 + 0.1) * sr).round());
    var grain = 0.0;
    for (var i = start; i < end; i++) {
      final t = (i - start) / sr;
      final rate = denseRate * math.exp(-t / denseTau) + tailRate * math.exp(-t / tailTau);
      final env = math.exp(-t / envTau);
      if (nr.nextDouble() < rate / sr) {
        // Çoğu tane küçük, bazıları çok güçlü: doğal çatırtı dağılımı
        final a = math.pow(nr.nextDouble(), 1.8).toDouble() * env;
        if (a > grain) grain = a;
      }
      grain *= grainDecay;
      var x = (nr.nextDouble() * 2 - 1) * grain;
      if (clickMs > 0 && t < clickMs / 1000) {
        x += (nr.nextDouble() * 2 - 1) * (1 - t / (clickMs / 1000)) * 1.2;
      }
      out[i] = lp.process(hp.process(x));
    }
    return out;
  }

  /// Ana basınç dalgası: alçak geçirgen gürültü + perdesi düşen gövde vuruşu.
  static Float64List _boom(
    int n,
    math.Random nr, {
    required double at,
    required double decay,
    required double lpHz,
    required double midHz,
    required double midLevel,
    required double thumpLevel,
    double attackTau = 0.012,
  }) {
    const sr = sampleRate;
    final out = Float64List(n);
    final lp1 = _Biquad()..lowpass(lpHz, 0.8);
    final lp2 = _Biquad()..lowpass(lpHz, 0.7);
    final mid = _Biquad()..bandpass(midHz, 0.8);
    var phase = 0.0;
    final start = (at * sr).round();
    final end = math.min(n, start + ((decay * 9) * sr).round());
    // Alçak geçirgen gürültünün genliği çok düşük; kabaca dengele.
    final lowGain = 1.0 / math.sqrt(lpHz / (sr * 0.5)) * 0.9;
    for (var i = start; i < end; i++) {
      final tb = (i - start) / sr;
      final env = (1 - math.exp(-tb / attackTau)) * math.exp(-tb / decay);
      final w = nr.nextDouble() * 2 - 1;
      final low = lp2.process(lp1.process(w)) * lowGain;
      final m = mid.process(w) * midLevel * math.exp(-tb / (decay * 0.6)) * 3.0;
      final f = 34 + 46 * math.exp(-tb / 0.10);
      phase += 2 * math.pi * f / sr;
      final thump = math.sin(phase) * math.exp(-tb / (decay * 0.55)) * thumpLevel;
      out[i] = (low + m + thump) * env;
    }
    return out;
  }

  /// Yuvarlanan gürleme. Sol ve sağ kanal bağımsız gürültüden üretilir.
  static (Float64List, Float64List) _rumble(
    int n,
    int seed,
    List<_Roll> rolls, {
    required double baseHz,
    required double extraHz,
    required double slideTau,
    required double growlHz,
    required double growlLevel,
    required double growlTau,
  }) {
    const sr = sampleRate;
    // Ortak yuvarlanma zarfı
    final envelope = Float64List(n);
    var envMax = 1e-9;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      var e = 0.0;
      for (final roll in rolls) {
        e += roll.amp * roll.shape(t);
      }
      envelope[i] = e;
      if (e > envMax) envMax = e;
    }
    final fadeStart = n - (1.4 * sr).round();
    for (var i = 0; i < n; i++) {
      var e = envelope[i] / envMax;
      if (i > fadeStart) {
        final u = (i - fadeStart) / (n - fadeStart);
        e *= 1 - u * u * (3 - 2 * u);
      }
      envelope[i] = e;
    }

    final outs = <Float64List>[];
    for (var ch = 0; ch < 2; ch++) {
      final nr = math.Random(seed * 13 + ch * 101 + 5);
      final out = Float64List(n);
      final lp1 = _Biquad();
      final lp2 = _Biquad();
      final growl = _Biquad()..bandpass(growlHz, 0.7);
      final mod = _SmoothRandom(nr, lo: 0.22, hi: 1.0, minMs: 22, maxMs: 75);
      final slowMod = _SmoothRandom(nr, lo: 0.55, hi: 1.0, minMs: 180, maxMs: 520);
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        if ((i & 63) == 0) {
          // Zamanla ve sessiz anlarda boğuklaşan gürleme
          final fc = baseHz + extraHz * math.exp(-t / slideTau) * (0.65 + 0.5 * envelope[i]);
          lp1.lowpass(fc, 0.75);
          lp2.lowpass(fc * 1.15, 0.6);
        }
        final w = nr.nextDouble() * 2 - 1;
        final low = lp2.process(lp1.process(w));
        final g = growl.process(w) * growlLevel * math.exp(-t / growlTau);
        out[i] = (low * 6.0 + g) * envelope[i] * mod.next() * slowMod.next();
      }
      outs.add(out);
    }
    // İki kanalı aynı katsayıyla normalize et (stereo dengesi korunur)
    var peak = 1e-9;
    for (final o in outs) {
      for (final v in o) {
        final a = v.abs();
        if (a > peak) peak = a;
      }
    }
    for (final o in outs) {
      for (var i = 0; i < n; i++) {
        o[i] /= peak;
      }
    }
    return (outs[0], outs[1]);
  }

  /// Her biri bir öncekinden daha boğuk ve zayıf gecikmeli kopyalar.
  static Float64List _echoes(Float64List src, List<double> delays) {
    const sr = sampleRate;
    final n = src.length;
    final out = Float64List(n);
    const gains = [0.42, 0.30, 0.22, 0.15, 0.09];
    const cutoffs = [2500.0, 1500.0, 900.0, 600.0, 400.0];
    for (var k = 0; k < delays.length; k++) {
      final d = (delays[k] * sr).round();
      final lp = _OnePole(cutoffs[k]);
      for (var i = d; i < n; i++) {
        out[i] += lp.process(src[i - d]) * gains[k];
      }
    }
    return out;
  }

  /// DC temizliği, yumuşak doyum, normalize ve uçlarda tıkırtısız geçiş.
  static void _finish(Float64List l, Float64List r, {
    required double drive,
    required double peak,
    required double fadeInMs,
  }) {
    final n = l.length;
    for (final ch in [l, r]) {
      final hp = _Biquad()..highpass(28, 0.7);
      final norm = _tanh(drive);
      for (var i = 0; i < n; i++) {
        ch[i] = _tanh(hp.process(ch[i]) * drive) / norm;
      }
    }
    var m = 1e-9;
    for (var i = 0; i < n; i++) {
      m = math.max(m, math.max(l[i].abs(), r[i].abs()));
    }
    final g = peak / m;
    final fadeIn = (fadeInMs / 1000 * sampleRate).round();
    final fadeOut = (0.05 * sampleRate).round();
    for (var i = 0; i < n; i++) {
      var e = g;
      if (i < fadeIn) e *= i / fadeIn;
      if (i > n - fadeOut) e *= (n - i) / fadeOut;
      l[i] *= e;
      r[i] *= e;
    }
  }

  static void _normalizePeak(Float64List x, double peak) {
    var m = 1e-9;
    for (final v in x) {
      final a = v.abs();
      if (a > m) m = a;
    }
    final g = peak / m;
    for (var i = 0; i < x.length; i++) {
      x[i] *= g;
    }
  }

  static double _tanh(double x) {
    if (x > 20) return 1.0;
    if (x < -20) return -1.0;
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  static Uint8List _encodeStereoWav(Float64List l, Float64List r, int sr) {
    final frames = l.length;
    final dataSize = frames * 4;
    final out = ByteData(44 + dataSize);
    void ascii(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        out.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    out.setUint32(4, 36 + dataSize, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little); // PCM
    out.setUint16(22, 2, Endian.little); // Stereo
    out.setUint32(24, sr, Endian.little);
    out.setUint32(28, sr * 4, Endian.little);
    out.setUint16(32, 4, Endian.little);
    out.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    out.setUint32(40, dataSize, Endian.little);
    var o = 44;
    for (var i = 0; i < frames; i++) {
      out.setInt16(o, (l[i] * 32767).round().clamp(-32768, 32767), Endian.little);
      out.setInt16(o + 2, (r[i] * 32767).round().clamp(-32768, 32767), Endian.little);
      o += 4;
    }
    return out.buffer.asUint8List();
  }
}

/// Dikişsiz döngü hâlinde çalan fırtına ambiyansları:
/// * **Rüzgâr**: Ani bastıran rüzgârlarla (gust) şiddetlenen gövde + dar bantlı,
///   perdesi yavaşça kayan ıslık/uluma rezonansları + alçak gürleme.
/// * **Gizemli uğultu**: Formant süzgeçli, titreşimli, perdesi kayan inlemeler ve
///   kısa fısıltılar; uzun, boğuk yankılarla uzaktan geliyormuş gibi.
///
/// Son 3 saniye başa eşit güçte çapraz geçişle karıştırılır, döngü noktası duyulmaz.
class StormAmbience {
  static const double loopSeconds = 24.0;
  static const double _xfade = 3.0;
  static const int _sr = ThunderSynth.sampleRate;

  static Uint8List renderWindLoopWav(int seed) {
    final n = ((loopSeconds + _xfade) * _sr).round();
    final outs = <Float64List>[];
    for (var ch = 0; ch < 2; ch++) {
      final nr = math.Random(seed * 7 + ch * 31);
      final gust = _SmoothRandom(nr, lo: 0.22, hi: 1.0, minMs: 1300, maxMs: 4200);
      final f1 = _SmoothRandom(nr, lo: 210, hi: 480, minMs: 1800, maxMs: 5200);
      final f2 = _SmoothRandom(nr, lo: 420, hi: 900, minMs: 1500, maxMs: 4600);
      final body = Float64List(n);
      final howl = Float64List(n);
      final low = Float64List(n);
      final bodyLp = _Biquad()..lowpass(750, 0.6);
      final bodyHp = _Biquad()..highpass(80, 0.7);
      final bp1 = _Biquad();
      final bp2 = _Biquad();
      final lowLp = _Biquad()..lowpass(95, 0.7);
      for (var i = 0; i < n; i++) {
        final g = gust.next();
        final a = f1.next();
        final b = f2.next();
        if ((i & 63) == 0) {
          bp1.bandpass(a, 14);
          bp2.bandpass(b, 18);
        }
        final w = nr.nextDouble() * 2 - 1;
        body[i] = bodyLp.process(bodyHp.process(w)) * (0.35 + 0.65 * g);
        // Uluma, rüzgâr bastırdığında belirginleşir
        howl[i] = (bp1.process(w) + bp2.process(w) * 0.7) * g * g;
        low[i] = lowLp.process(w) * (0.6 + 0.4 * g);
      }
      ThunderSynth._normalizePeak(body, 1.0);
      ThunderSynth._normalizePeak(howl, 1.0);
      ThunderSynth._normalizePeak(low, 1.0);
      final out = Float64List(n);
      for (var i = 0; i < n; i++) {
        out[i] = body[i] * 0.55 + howl[i] * 0.75 + low[i] * 0.45;
      }
      outs.add(out);
    }
    return _loopStereo(outs[0], outs[1], peak: 0.85);
  }

  static Uint8List renderGhostLoopWav(int seed) {
    final n = ((loopSeconds + _xfade) * _sr).round();
    final rnd = math.Random(seed);
    final l = Float64List(n);
    final r = Float64List(n);

    // "uu", "oo" ve tiz, ürkütücü "ii" ünlülerinin formantları
    const vowels = [(320.0, 800.0), (450.0, 870.0), (300.0, 2250.0)];
    var t0 = 0.6 + rnd.nextDouble() * 1.5;
    var k = 0;
    while (t0 < loopSeconds - 4.5) {
      final dur = 2.6 + rnd.nextDouble() * 2.2;
      final moan = _moan(
        dur,
        150 + rnd.nextDouble() * 120,
        0.72 + rnd.nextDouble() * 0.5,
        vowels[rnd.nextInt(vowels.length)],
        math.Random(seed + 13 * ++k),
      );
      _place(l, r, moan, t0, rnd.nextDouble() * 1.4 - 0.7, 1.0);
      t0 += dur + 1.5 + rnd.nextDouble() * 3.5;
    }
    // Kısa, anlaşılmaz fısıltılar
    for (var w = 0; w < 4; w++) {
      final dur = 0.9 + rnd.nextDouble() * 0.8;
      final at = 1.0 + rnd.nextDouble() * (loopSeconds - 3.5);
      _place(l, r, _whisper(dur, math.Random(seed * 3 + w)), at, rnd.nextDouble() * 1.8 - 0.9, 0.28);
    }

    // Uzaktan, taş duvarlardan dönüyormuş gibi uzun ve boğuk yankılar
    final echoL = ThunderSynth._echoes(l, const [0.29, 0.53, 0.91, 1.37, 1.9]);
    final echoR = ThunderSynth._echoes(r, const [0.33, 0.61, 0.83, 1.29, 2.05]);
    for (var i = 0; i < n; i++) {
      l[i] = l[i] * 0.8 + echoL[i] * 0.95;
      r[i] = r[i] * 0.8 + echoR[i] * 0.95;
    }
    return _loopStereo(l, r, peak: 0.80);
  }

  /// Formant süzgeçli, iki hafif akort dışı sesten oluşan titreşimli inleme.
  static Float64List _moan(double dur, double f0, double glide, (double, double) formants, math.Random nr) {
    final n = (dur * _sr).round();
    final out = Float64List(n);
    final fA = _Biquad()..bandpass(formants.$1, 5);
    final fB = _Biquad()..bandpass(formants.$2, 7);
    final breath = _Biquad()..bandpass(formants.$1 * 1.5, 2);
    var ph1 = 0.0;
    var ph2 = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / _sr;
      final u = t / dur;
      final env = math.pow(math.sin(math.pi * u), 1.6).toDouble();
      final slide = u * u * (3 - 2 * u);
      final f = f0 * (1 + (glide - 1) * slide) * (1 + 0.018 * math.sin(2 * math.pi * 5.2 * t));
      ph1 += 2 * math.pi * f / _sr;
      ph2 += 2 * math.pi * f * 1.0047 / _sr;
      final harmonics = math.min(10, (3500 / f).floor());
      var src = 0.0;
      for (var h = 1; h <= harmonics; h++) {
        src += (math.sin(ph1 * h) + math.sin(ph2 * h)) / h;
      }
      final noise = (nr.nextDouble() * 2 - 1) * 0.25;
      out[i] = (fA.process(src) + fB.process(src) * 0.6 + breath.process(noise) * 0.5) * env;
    }
    ThunderSynth._normalizePeak(out, 1.0);
    return out;
  }

  /// Hece gibi kesik kesik genlik modülasyonlu, tiz bantlı gürültü.
  static Float64List _whisper(double dur, math.Random nr) {
    final n = (dur * _sr).round();
    final out = Float64List(n);
    final bp1 = _Biquad()..bandpass(2400, 3);
    final bp2 = _Biquad()..bandpass(3600, 4);
    final syll = _SmoothRandom(nr, lo: 0.05, hi: 1.0, minMs: 60, maxMs: 140);
    for (var i = 0; i < n; i++) {
      final u = i / n;
      final env = math.sin(math.pi * u);
      final w = nr.nextDouble() * 2 - 1;
      out[i] = (bp1.process(w) + bp2.process(w) * 0.6) * env * syll.next();
    }
    ThunderSynth._normalizePeak(out, 1.0);
    return out;
  }

  static void _place(Float64List l, Float64List r, Float64List src, double at, double pan, double gain) {
    final start = (at * _sr).round();
    final a = (pan + 1) * math.pi / 4;
    final gl = math.cos(a) * gain;
    final gr = math.sin(a) * gain;
    for (var i = 0; i < src.length && start + i < l.length; i++) {
      l[start + i] += src[i] * gl;
      r[start + i] += src[i] * gr;
    }
  }

  /// Son bölümü başa eşit güçte çapraz geçişle bindirip dikişsiz döngü üretir.
  static Uint8List _loopStereo(Float64List l, Float64List r, {required double peak}) {
    final loopN = (loopSeconds * _sr).round();
    final xf = l.length - loopN;
    final ol = Float64List(loopN);
    final or = Float64List(loopN);
    for (var i = 0; i < loopN; i++) {
      if (i < xf) {
        final a = math.sin(math.pi / 2 * i / xf);
        final b = math.cos(math.pi / 2 * i / xf);
        ol[i] = l[i] * a + l[loopN + i] * b;
        or[i] = r[i] * a + r[loopN + i] * b;
      } else {
        ol[i] = l[i];
        or[i] = r[i];
      }
    }
    var m = 1e-9;
    for (var i = 0; i < loopN; i++) {
      m = math.max(m, math.max(ol[i].abs(), or[i].abs()));
    }
    final g = peak / m;
    for (var i = 0; i < loopN; i++) {
      ol[i] *= g;
      or[i] *= g;
    }
    return ThunderSynth._encodeStereoWav(ol, or, _sr);
  }
}

/// Tek bir "yuvarlanma": yumuşak yükseliş, üssel sönüm.
class _Roll {
  _Roll({required this.at, required this.amp, required this.rise, required this.decay});
  final double at, amp, rise, decay;

  double shape(double t) {
    final x = t - at;
    if (x < 0) {
      final q = x / rise;
      return q < -4 ? 0.0 : math.exp(-q * q);
    }
    return math.exp(-x / decay);
  }
}

/// RBJ biquad filtresi (Transposed Direct Form II).
class _Biquad {
  double _b0 = 1, _b1 = 0, _b2 = 0, _a1 = 0, _a2 = 0;
  double _z1 = 0, _z2 = 0;

  void lowpass(double fc, double q) {
    final (cs, alpha) = _pre(fc, q);
    final a0 = 1 + alpha;
    _b0 = (1 - cs) / 2 / a0;
    _b1 = (1 - cs) / a0;
    _b2 = _b0;
    _a1 = -2 * cs / a0;
    _a2 = (1 - alpha) / a0;
  }

  void highpass(double fc, double q) {
    final (cs, alpha) = _pre(fc, q);
    final a0 = 1 + alpha;
    _b0 = (1 + cs) / 2 / a0;
    _b1 = -(1 + cs) / a0;
    _b2 = _b0;
    _a1 = -2 * cs / a0;
    _a2 = (1 - alpha) / a0;
  }

  void bandpass(double fc, double q) {
    final (cs, alpha) = _pre(fc, q);
    final a0 = 1 + alpha;
    _b0 = alpha / a0;
    _b1 = 0;
    _b2 = -alpha / a0;
    _a1 = -2 * cs / a0;
    _a2 = (1 - alpha) / a0;
  }

  (double, double) _pre(double fc, double q) {
    final w = 2 * math.pi * fc.clamp(10.0, ThunderSynth.sampleRate * 0.45) / ThunderSynth.sampleRate;
    return (math.cos(w), math.sin(w) / (2 * q));
  }

  double process(double x) {
    final y = _b0 * x + _z1;
    _z1 = _b1 * x - _a1 * y + _z2;
    _z2 = _b2 * x - _a2 * y;
    return y;
  }
}

class _OnePole {
  _OnePole(double fc) : _a = 1 - math.exp(-2 * math.pi * fc / ThunderSynth.sampleRate);
  final double _a;
  double _y = 0;
  double process(double x) => _y += _a * (x - _y);
}

/// Rastgele hedeflere yumuşakça kayan modülasyon (homurtu dokusu).
class _SmoothRandom {
  _SmoothRandom(this._r, {required this.lo, required this.hi, required this.minMs, required this.maxMs})
      : _cur = hi,
        _target = hi;
  final math.Random _r;
  final double lo, hi, minMs, maxMs;
  double _cur, _target;
  double _step = 0;
  int _left = 0;

  double next() {
    if (_left <= 0) {
      _target = lo + _r.nextDouble() * (hi - lo);
      _left = ((minMs + _r.nextDouble() * (maxMs - minMs)) / 1000 * ThunderSynth.sampleRate).round();
      _step = (_target - _cur) / _left;
    }
    _left--;
    _cur += _step;
    return _cur;
  }
}
