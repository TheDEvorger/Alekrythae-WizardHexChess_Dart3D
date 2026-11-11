import 'dart:math' as math;

import 'package:three_js/three_js.dart' as three;

import '../audio/thunder_synth.dart' show ThunderKind;
import 'battle_fx.dart';
import 'storm_vortex.dart';

/// Fırtınanın gerçekçi yıldırımları ve gök gürültüsü zamanlaması.
///
/// Gerçek bir buluttan yere yıldırımın aşamalarını taklit eder:
/// 1. **Öncü kanal**: Sönük bir kanal ~70 ms içinde buluttan aşağı doğru ilerler.
/// 2. **Dönüş darbeleri**: Kanal göz kamaştırarak çakar, kararır ve 2-4 kez
///    yeniden çakar (gerçek şimşeğin titremesi budur).
/// 3. **Kalıcı kanal (sürekli akım)**: Kanal hemen kaybolmaz; [linger] saniye
///    boyunca soğuyan plazma gibi parlamaya devam eder. Önce dallar söner, ana
///    kanal hafifçe titreşir, ara sıra yeniden parlar, hâlesi genişleyip mora
///    kayar ve en sonunda yumuşakça kaybolur.
///
/// Çakış anında gökyüzü ve bulutlar aydınlanır, yıldırımın düştüğü kule ucunda
/// kıvılcımlar saçılır. Kalıcı kanal çevresini daha sönük aydınlatmaya devam
/// eder (sahne göz kamaştırıcı parlak kalmaz). Ses ışıktan sonra gelir: yakın
/// yıldırımda neredeyse anında sert bir çatırtı + patlama, bulut içindeki uzak
/// şimşeklerde ise 1-2,5 saniye sonra boğuk bir gürleme duyulur.
///
/// Aynı anda [maxBolts]'a kadar yakın yıldırım ekranda kalabilir (havuz
/// gerektikçe büyür); kalıcı bir kanal sönmeden yeni yıldırım düşebilir.
class LightningStorm {
  LightningStorm({
    required three.Object3D parent,
    required this.storm,
    required this.fx,
    required this.skyLight,
    required List<P3> strikeTargets,
    required this.onThunder,
    this.isOnScreen,
    this.groundY = -1.65,
    int seed = 9137,
  })  : _rng = math.Random(seed),
        _targets = List.of(strikeTargets),
        _skyBase = skyLight.intensity,
        _parent = parent {
    for (var i = 0; i < _slotCount; i++) {
      _slots.add(_BoltSlot(parent));
    }
    _boltLight = three.PointLight(0xC4E2FF, 0.0, 52);
    _boltLight.position.setValues(0, -30, 0);
    parent.add(_boltLight);
    // İlk şimşek maç açılır açılmaz değil, birkaç saniye sonra
    _nextEventIn = 3.0 + _rng.nextDouble() * 2.0;
  }

  final StormVortex storm;
  final FxSystem fx;
  final three.Light skyLight;
  final void Function(ThunderKind kind) onThunder;

  /// Dünya noktası kameranın görüş alanında mı? Yıldırımlar oyuncunun gördüğü
  /// yere düşsün diye hedef seçiminde kullanılır (null ise kontrol edilmez).
  final bool Function(P3 p)? isOnScreen;

  /// Yere düşen yıldırımların çarptığı bulut denizi yüksekliği.
  final double groundY;

  final math.Random _rng;
  final List<P3> _targets;
  final double _skyBase;
  late final three.PointLight _boltLight;

  /// Başlangıçta hazır bekleyen yakın yıldırım kanalı sayısı. Sıklık ya da
  /// kalıcılık arttıkça havuz gerektiği kadar büyür ([maxBolts]'a kadar).
  static const int _slotCount = 4;

  /// Aynı anda havada kalabilecek en çok yakın yıldırım kanalı (ekran kartı
  /// güvenliği). Bu da doluyken yeni çakışlar bulut içi şimşek olarak gelir;
  /// yani sıklık arttıkça çakış sayısı artmaya devam eder.
  static const int maxBolts = 32;

  final three.Object3D _parent;
  final List<_BoltSlot> _slots = [];
  final List<_Strike> _strikes = [];

  /// Yıldırım sıklığı çarpanı (0 = kapalı, 1 = normal; üst sınır yok).
  double rate = 1.0;

  /// Fırtına gücü (0..3, elle sınırsız): yakın yıldırım oranı, parlaklık ve
  /// art arda çakışlar.
  double power = 1.0;

  /// Gizemli atmosfer (0..1+): yıldırım hâlesi mora kayar.
  double haunt = 0.0;

  /// Kanalın son darbeden sonra havada kalma süresi (saniye). 0: anında söner.
  double linger = 1.2;

  /// Güç doğrudan parlaklığa yansır (doygunluk yok). Tahtayı aydınlatan gök
  /// ışığı yine de en çok taban ışığının ~2 katına çıkar: tahta okunur kalır.
  double get _pw => math.max(0.0, power);
  double get _brightness => 0.75 + 0.3 * _pw;
  double get _hauntK => haunt.clamp(0.0, 1.0);

  double _nextEventIn = 4.0;
  int _lastTarget = -1;
  bool _lit = false;
  final List<_PendingThunder> _pendingThunder = [];

  // Sahne aydınlatması zarfları: çakışta anında yükselir, ardından yumuşakça
  // söner. Böylece bulutlar, yağmur ve tahta her dönüş darbesinde yanıp
  // sönmez (stroboskop etkisi yok); yalnızca yıldırım kanalı keskin kalır.
  double _envFlash = 0.0;
  double _envSky = 0.0;
  double _envSkyLight = 0.0;
  double _envBolt = 0.0;
  _Strike? _lead;
  P3 _flashFrom = const P3(0, -50, 0);
  P3 _flashTo = const P3(0, -50, 0);
  double _flashRadius = 11.0;

  static const double _cloudRelease = 0.16; // bulut / gökyüzü parlaması
  static const double _sceneRelease = 0.24; // tahtayı da aydınlatan gök ışığı
  static const double _boltRelease = 0.08; // kanal yakınındaki nokta ışık

  // ------------------------------------------------------------------ döngü
  void update(double dt) {
    _updateThunderQueue(dt);

    if (rate > 0.001) {
      _nextEventIn -= dt;
      if (_nextEventIn <= 0) _startEvent();
    }

    if (_strikes.isEmpty && !_lit) return;

    final b = _brightness;
    var skyAdd = 0.0;
    var boltLight = 0.0;
    var skyFlash = 0.0;
    _Strike? lead;
    var leadLevel = 0.0;
    _Strike? leadClose;
    var leadCloseLevel = -1.0;

    for (var i = _strikes.length - 1; i >= 0; i--) {
      final s = _strikes[i];
      s.t += dt;
      if (s.t >= s.end) {
        _release(s);
        _strikes.removeAt(i);
        continue;
      }
      final light = s.lightAt(s.t);
      if (s.close) {
        _driveSlot(s);
        if (!s.sparked && s.t >= s.leaderDur) {
          s.sparked = true;
          _impact(s.to, ground: s.ground);
        }
        final l = s.t < s.leaderDur ? 0.08 : light;
        // Gök ışığı tahtayı da aydınlatır: en çok taban ışığının ~2 katına çıkar.
        skyAdd = math.max(skyAdd, math.min(2.0, 1.25 * b * l));
        boltLight = math.max(boltLight, 170.0 * b * l);
        skyFlash = math.max(skyFlash, l * 0.40 * b);
        if (l > leadCloseLevel) {
          leadCloseLevel = l;
          leadClose = s;
        }
        s.flashWeight = l * 1.05 * b;
      } else {
        skyAdd = math.max(skyAdd, 0.6 * b * light);
        skyFlash = math.max(skyFlash, light * 0.16 * b);
        s.flashWeight = light * b;
      }
      if (s.flashWeight > leadLevel) {
        leadLevel = s.flashWeight;
        lead = s;
      }
    }

    // Aydınlatılan bulut bölgesi yıldırımlar arasında sürekli zıplamasın:
    // yeni yıldırım ancak belirgin şekilde daha parlaksa ışığı devralır.
    final cur = _lead;
    if (cur != null && lead != null && lead != cur && _strikes.contains(cur) &&
        lead.flashWeight < cur.flashWeight + 0.35) {
      lead = cur;
      leadLevel = cur.flashWeight;
    }
    if (lead != null) {
      _lead = lead;
      _flashFrom = lead.from;
      _flashTo = lead.to;
      _flashRadius = lead.close ? 11.0 : 24.0;
    } else if (_strikes.isEmpty) {
      _lead = null;
    }

    _envFlash = math.max(leadLevel, _envFlash * math.exp(-dt / _cloudRelease));
    _envSky = math.max(skyFlash, _envSky * math.exp(-dt / _cloudRelease));
    _envSkyLight = math.max(skyAdd, _envSkyLight * math.exp(-dt / _sceneRelease));
    _envBolt = math.max(boltLight, _envBolt * math.exp(-dt / _boltRelease));

    if (_strikes.isEmpty && _envFlash < 0.003 && _envSky < 0.003 && _envSkyLight < 0.003 && _envBolt < 0.05) {
      _resetLights();
      return;
    }
    _lit = true;

    skyLight.intensity = _skyBase + _envSkyLight;
    _boltLight.intensity = _envBolt;
    if (leadClose != null) {
      final lp = leadClose.lightPos;
      _boltLight.position.setValues(lp.x, lp.y, lp.z);
    }
    storm.setLightning(
      level: _envFlash,
      sky: _envSky,
      from: _flashFrom,
      to: _flashTo,
      radius: _flashRadius,
    );
  }

  /// Yakın yıldırımın kanal görünümünü (öncü, darbeler, kalıcı kanal) çizer.
  void _driveSlot(_Strike s) {
    final slot = s.slot!;
    if (s.t < s.leaderDur) {
      // Öncü kanal aşamasında yalnızca ana kanalın inmiş kısmı görünür.
      final k = (s.mainSegments * (s.t / s.leaderDur)).floor().clamp(1, s.mainSegments);
      slot.drawCount = k;
      slot.uIntensity['value'] = 0.30;
      slot.uBranch['value'] = 1.0;
      slot.uCool['value'] = 0.0;
    } else {
      slot.drawCount = s.totalSegments;
      slot.uIntensity['value'] = s.channelAt(s.t);
      slot.uBranch['value'] = s.branchAt(s.t);
      slot.uCool['value'] = s.coolAt(s.t);
    }
    final h = _hauntK;
    (slot.uGlowColor['value'] as three.Vector3).setValues(0.42 + 0.22 * h, 0.62 - 0.12 * h, 1.0);
    slot.mesh.visible = true;
  }

  void _resetLights() {
    _lit = false;
    _envFlash = 0.0;
    _envSky = 0.0;
    _envSkyLight = 0.0;
    _envBolt = 0.0;
    skyLight.intensity = _skyBase;
    _boltLight.intensity = 0.0;
    storm.setLightning(level: 0.0, sky: 0.0);
  }

  void _updateThunderQueue(double dt) {
    for (var i = _pendingThunder.length - 1; i >= 0; i--) {
      final p = _pendingThunder[i];
      p.delay -= dt;
      if (p.delay <= 0) {
        _pendingThunder.removeAt(i);
        onThunder(p.kind);
      }
    }
  }

  void _startEvent() {
    // Fırtına güçlendikçe yakın (görünür) yıldırımların oranı artar.
    final closeChance = (0.30 + 0.22 * _pw).clamp(0.2, 0.85);
    final close = _rng.nextDouble() < closeChance;
    final slot = close ? _freeSlot() : null;
    if (slot != null) {
      _strikes.add(_startCloseStrike(slot));
    } else {
      // Kanal havuzu doluysa beklemek yerine bulut içi şimşek çakar:
      // sıklık arttıkça çakışlar sıklaşmaya devam eder.
      if (close) _fadeOldest();
      _strikes.add(_startSheetLightning());
    }
    _scheduleNext(_strikes.last);
  }

  void _scheduleNext(_Strike s) {
    final r = math.max(rate, 0.05);
    // Çakışlar arasındaki en kısa ara da sıklıkla kısalır (üst sınır yok):
    // sıklık 2'ye kadar eski davranış, üstünde ara orantılı olarak daralır.
    final squeeze = math.min(1.0, 2.0 / r);
    // Ara sıra hemen ardından ikinci bir yıldırım (çift çakış)
    final doubleStrike = s.close && _rng.nextDouble() < (0.12 + 0.14 * _pw).clamp(0.0, 0.5);
    _nextEventIn = doubleStrike
        ? (s.strokesEnd + 0.45 + _rng.nextDouble() * 0.6) * squeeze
        : (s.strokesEnd + 0.55) * squeeze + (4.0 + _rng.nextDouble() * 7.0) / r;
  }

  /// Ayarlardaki "Yıldırım Çaktır" düğmesi: hemen yakın bir yıldırım düşürür.
  void triggerNow() {
    var slot = _freeSlot();
    if (slot == null) {
      final oldest = _strikes.firstWhere((s) => s.close);
      _release(oldest);
      _strikes.remove(oldest);
      slot = _freeSlot()!;
    }
    _strikes.add(_startCloseStrike(slot));
  }

  /// Boş kanal; yoksa havuz [maxBolts]'a kadar büyütülür.
  _BoltSlot? _freeSlot() {
    for (final s in _slots) {
      if (!s.busy) return s;
    }
    if (_slots.length < maxBolts) {
      final s = _BoltSlot(_parent);
      _slots.add(s);
      return s;
    }
    return null;
  }

  void _fadeOldest() {
    for (final s in _strikes) {
      if (s.close && s.slot != null) {
        s.fadeNow(0.3);
        return;
      }
    }
  }

  void _release(_Strike s) {
    final slot = s.slot;
    if (slot == null) return;
    slot
      ..busy = false
      ..drawCount = 0
      ..mesh.visible = false;
    slot.uIntensity['value'] = 0.0;
    s.slot = null;
  }

  // ------------------------------------------------------- yakın yıldırım
  _Strike _startCloseStrike(_BoltSlot slot) {
    final (to, ground) = _pickTarget();
    final ang = math.atan2(to.z, to.x) + (_rng.nextDouble() - 0.5) * 0.35;
    final y0 = 30.0 + _rng.nextDouble() * 6.0;
    final rWall = storm.innerWallRadiusAt(y0);
    // Gökten neredeyse dikey iner, hafifçe göz duvarına doğru yaslanır.
    final r0 = to.flatLength + (rWall - to.flatLength) * (0.08 + _rng.nextDouble() * 0.22);
    final width = 0.62 * (0.9 + 0.2 * _pw);
    final from = P3(math.cos(ang) * r0, y0, math.sin(ang) * r0);

    final segs = <_Seg>[];
    final main = _fractal(from, to, 6, 0.20);
    for (var i = 0; i < main.length - 1; i++) {
      final b = 0.88 + _rng.nextDouble() * 0.12;
      segs.add(_Seg(main[i], main[i + 1], width, b, b));
    }
    final mainSegments = segs.length;
    _addBranches(segs, main);
    final total = math.min(segs.length, _BoltSlot.maxSegments);
    for (var i = 0; i < total; i++) {
      slot.writeSegment(i, segs[i], branch: i >= mainSegments);
    }
    slot.commit();
    slot.busy = true;

    final s = _Strike(close: true, from: from, to: to, ground: ground)
      ..slot = slot
      ..lightPos = main[(main.length * 0.62).floor()]
      ..mainSegments = mainSegments
      ..totalSegments = total
      ..leaderDur = 0.05 + _rng.nextDouble() * 0.04
      ..tau = 0.032;
    var at = s.leaderDur;
    final strokes = 2 + (_rng.nextDouble() < 0.7 ? 1 : 0) + (_rng.nextDouble() < 0.35 ? 1 : 0);
    var peak = 1.0;
    for (var k = 0; k < strokes; k++) {
      s.pulses.add((at, peak));
      at += 0.045 + _rng.nextDouble() * 0.07;
      peak *= 0.72 + _rng.nextDouble() * 0.12;
    }
    _configureLinger(s, glow: 0.46, lightShare: 0.30);
    s.slot!.drawCount = 1;

    // Yakın yıldırım: ses neredeyse ışıkla birlikte gelir
    _pendingThunder.add(_PendingThunder(ThunderKind.close, s.leaderDur + 0.04 + _rng.nextDouble() * 0.22));
    return s;
  }

  /// Son darbeden sonraki kalıcı kanal evresini kurar: süre, sönüş, titreşim
  /// fazları ve kanalı yeniden aydınlatan zayıf ek darbeler (M-bileşenleri).
  void _configureLinger(_Strike s, {required double glow, required double lightShare}) {
    final last = s.pulses.last.$1;
    s.strokesEnd = last;
    final hold = math.max(0.0, linger) * (s.close ? 1.0 : 0.6);
    if (hold < 0.02) {
      s
        ..glow = 0.0
        ..hold = 0.0
        ..fade = 0.0
        ..end = last + 0.55;
      return;
    }
    s
      ..glow = glow * (0.9 + _rng.nextDouble() * 0.2)
      ..lightShare = lightShare
      ..hold = hold
      ..fade = math.min(0.9, 0.3 + hold * 0.18)
      ..flickA = _rng.nextDouble() * math.pi * 2
      ..flickB = _rng.nextDouble() * math.pi * 2
      ..flickRate = 5.0 + _rng.nextDouble() * 4.0;
    s.end = last + 0.12 + s.hold + s.fade;
    // Kanal havadayken ara sıra yeniden parlar (gerçek yıldırımdaki M-bileşenleri)
    // Kanal ne kadar uzun kalırsa o kadar çok yeniden parlar (üst sınır yok).
    final extra = math.max(0, (hold * (0.6 + 0.3 * _rng.nextDouble())).floor());
    for (var k = 0; k < extra; k++) {
      final at = last + 0.2 + _rng.nextDouble() * hold * 0.85;
      s.echoes.add((at, 0.30 + _rng.nextDouble() * 0.22));
    }
  }

  void _addBranches(List<_Seg> segs, List<P3> main) {
    var branches = 0;
    final maxBranches = 3 + _rng.nextInt(3);
    for (var i = 5; i < main.length - 8 && branches < maxBranches; i++) {
      if (_rng.nextDouble() > 0.075) continue;
      branches++;
      final start = main[i];
      final dir = _norm(main[i + 1] - main[i - 1]);
      final remaining = (main.last - start).length;
      final bDir = _norm(dir * 0.55 + _randPerp(dir) * 0.8 + const P3(0, -0.3, 0));
      final bEnd = start + bDir * (remaining * (0.18 + _rng.nextDouble() * 0.30));
      final path = _fractal(start, bEnd, 4, 0.24);
      _appendFading(segs, path, 0.38, 0.62, 0.06);

      // Dalın dalı
      if (_rng.nextDouble() < 0.5 && path.length > 8) {
        final j = 3 + _rng.nextInt(path.length - 6);
        final sDir = _norm(_norm(path[j + 1] - path[j]) * 0.5 + _randPerp(bDir) * 0.9 + const P3(0, -0.25, 0));
        final sEnd = path[j] + sDir * ((bEnd - path[j]).length * (0.4 + _rng.nextDouble() * 0.4));
        _appendFading(segs, _fractal(path[j], sEnd, 3, 0.26), 0.26, 0.34, 0.03);
      }
    }
  }

  void _appendFading(List<_Seg> segs, List<P3> path, double width, double b0, double b1) {
    final n = path.length - 1;
    for (var i = 0; i < n && segs.length < _BoltSlot.maxSegments; i++) {
      final ba = b0 + (b1 - b0) * (i / n);
      final bb = b0 + (b1 - b0) * ((i + 1) / n);
      segs.add(_Seg(path[i], path[i + 1], width * (1 - 0.5 * i / n), ba, bb));
    }
  }

  void _impact(P3 at, {required bool ground}) {
    // Kanal havada kaldıkça çarpma noktasından duman daha uzun süre tüter.
    final smokeLife = 1.0 + math.min(1.6, linger * 0.5);
    if (ground) {
      // Bulut denizine düşen yıldırım: yayılan şok halkası, yukarı saçılan kıvılcım ve buhar
      fx.shockwave(at, 0xBFE6FF, radius: 3.4 + math.min(_pw, 4.0), life: 0.6, y: at.y + 0.05);
      fx.burst(at, const [0xFFFFFF, 0xCFEAFF, 0x7ED8FF], count: 34, speed: 6.0, size: 0.08, life: 0.7, gravity: 0.0, up: 1.6);
      fx.smoke(at, 0x3A4E6A, count: 12, radius: 0.8, life: smokeLife + 0.4);
    } else {
      fx.burst(at, const [0xFFFFFF, 0xCFEAFF, 0x7ED8FF], count: 30, speed: 5.5, size: 0.075, life: 0.75, gravity: -7.0);
      fx.burst(at, const [0xFFE7B0, 0xFFB868], count: 10, speed: 3.0, size: 0.05, life: 0.55, gravity: -9.0, shards: true);
      fx.smoke(at, 0x34465E, count: 8, radius: 0.35, life: smokeLife);
    }
    // Uzaktaki fırtına yıldırımı tahtayı sarsmaz; yalnızca çok hafif bir titreşim
    // (sık yıldırımda bütün sahnenin sürekli zıplaması istikrarı bozuyordu).
    fx.addShake(ground ? 0.03 : 0.02);
  }

  /// Hedef: bir kule ucu ya da arenanın yanındaki bulut denizi. Önce hedefin ve
  /// üstündeki kanalın ekranda göründüğü adaylar denenir; böylece oyuncu
  /// yalnızca flaşı değil yıldırımın kendisini de görür.
  (P3, bool) _pickTarget() {
    final visible = isOnScreen;
    (P3, bool)? fallback;
    for (var attempt = 0; attempt < 16; attempt++) {
      final useTower = _targets.isNotEmpty && _rng.nextDouble() < 0.55;
      int? idx;
      final P3 cand;
      if (useTower) {
        idx = _rng.nextInt(_targets.length);
        if (idx == _lastTarget && _targets.length > 1) continue;
        cand = _targets[idx];
      } else {
        final a = _rng.nextDouble() * math.pi * 2;
        final r = 13.0 + _rng.nextDouble() * 11.0;
        cand = P3(math.cos(a) * r, groundY, math.sin(a) * r);
      }
      fallback ??= (cand, !useTower);
      if (visible == null || (visible(cand) && visible(cand + const P3(0, 5, 0)))) {
        if (idx != null) _lastTarget = idx;
        return (cand, !useTower);
      }
    }
    return fallback ?? (P3(0, groundY, -16), true);
  }

  // -------------------------------------------- bulut içi (uzak) şimşek
  _Strike _startSheetLightning() {
    final ang = _rng.nextDouble() * math.pi * 2;
    final y = 14.0 + _rng.nextDouble() * 14.0;
    final r = storm.innerWallRadiusAt(y) + 4.0 + _rng.nextDouble() * 10.0;
    final from = P3(math.cos(ang) * r, y, math.sin(ang) * r);
    final to = P3(math.cos(ang + 0.25) * r, y - 7.0, math.sin(ang + 0.25) * r);

    final s = _Strike(close: false, from: from, to: to)..tau = 0.075;
    var at = 0.0;
    final pulses = 2 + _rng.nextInt(3);
    for (var k = 0; k < pulses; k++) {
      s.pulses.add((at, 0.45 + _rng.nextDouble() * 0.55));
      at += 0.07 + _rng.nextDouble() * 0.16;
    }
    // Bulutun içi de bir süre hafifçe parlamaya devam eder.
    _configureLinger(s, glow: 0.22, lightShare: 1.0);
    // Uzak şimşek: ses çok sonra ve boğuk gelir
    _pendingThunder.add(_PendingThunder(ThunderKind.distant, 1.0 + _rng.nextDouble() * 1.6));
    return s;
  }

  // ------------------------------------------------------------- geometri
  /// Orta nokta kaydırmalı fraktal yol (gerçek yıldırımın zikzak kanalı).
  List<P3> _fractal(P3 a, P3 b, int levels, double rough) {
    var pts = <P3>[a, b];
    var disp = (b - a).length * rough;
    for (var l = 0; l < levels; l++) {
      final next = <P3>[pts.first];
      for (var i = 0; i < pts.length - 1; i++) {
        final p = pts[i];
        final q = pts[i + 1];
        final mid = (p + q) * 0.5 + _randPerp(q - p) * (disp * (_rng.nextDouble() * 2 - 1));
        next
          ..add(mid)
          ..add(q);
      }
      pts = next;
      disp *= 0.52;
    }
    return pts;
  }

  P3 _randPerp(P3 d) {
    final dn = _norm(d);
    final r = P3(_rng.nextDouble() - 0.5, _rng.nextDouble() - 0.5, _rng.nextDouble() - 0.5);
    final p = r - dn * _dot(r, dn);
    if (p.length < 1e-4) return _norm(_cross(dn, const P3(0, 1, 0.3)));
    return _norm(p);
  }

  static double _dot(P3 a, P3 b) => a.x * b.x + a.y * b.y + a.z * b.z;
  static P3 _cross(P3 a, P3 b) =>
      P3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
  static P3 _norm(P3 a) {
    final l = a.length;
    return l < 1e-9 ? const P3(0, 1, 0) : a * (1 / l);
  }
}

/// Bir yıldırım kanalının GPU tamponu: kendi geometrisi, malzemesi ve
/// uniform'ları vardır; böylece birden çok kanal aynı anda havada kalabilir.
class _BoltSlot {
  _BoltSlot(three.Object3D parent) {
    const maxVerts = maxSegments * vertsPerSegment;
    posAttr = three.Float32BufferAttribute.fromList(List<double>.filled(maxVerts * 3, 0.0), 3)
      ..setUsage(three.DynamicDrawUsage);
    uvAttr = three.Float32BufferAttribute.fromList(List<double>.filled(maxVerts * 2, 0.0), 2)
      ..setUsage(three.DynamicDrawUsage);
    geo = three.BufferGeometry();
    geo.setAttributeFromString('position', posAttr);
    geo.setAttributeFromString('uv', uvAttr);
    geo.drawRange = {'start': 0, 'count': 0};

    final mat = three.ShaderMaterial.fromMap({
      'uniforms': {
        'uIntensity': uIntensity,
        'uGlowColor': uGlowColor,
        'uBranch': uBranch,
        'uCool': uCool,
      },
      'vertexShader': _kBoltVertex,
      'fragmentShader': _kBoltFragment,
      'transparent': true,
      'depthWrite': false,
      'side': three.DoubleSide,
      'blending': three.AdditiveBlending,
    });
    mesh = three.Mesh(geo, mat)
      ..frustumCulled = false
      ..visible = false
      ..renderOrder = 5;
    parent.add(mesh);
  }

  static const int maxSegments = 420;
  static const int vertsPerSegment = 12; // 2 çapraz dörtgen

  late final three.Float32BufferAttribute posAttr;
  late final three.Float32BufferAttribute uvAttr;
  late final three.BufferGeometry geo;
  late final three.Mesh mesh;
  final Map<String, dynamic> uIntensity = {'value': 0.0};
  final Map<String, dynamic> uGlowColor = {'value': three.Vector3(0.42, 0.62, 1.0)};
  final Map<String, dynamic> uBranch = {'value': 1.0};
  final Map<String, dynamic> uCool = {'value': 0.0};
  bool busy = false;

  set drawCount(int segments) => geo.drawRange['count'] = segments * vertsPerSegment;

  void commit() {
    posAttr.needsUpdate = true;
    uvAttr.needsUpdate = true;
  }

  /// Bir kanal parçasını birbirine dik iki dörtgen olarak yazar.
  /// uv.x: kanal eksenine uzaklık (-1..1), uv.y: parlaklık (dallarda negatif
  /// işaretli; dallar kalıcı evrede ana kanaldan önce söner).
  void writeSegment(int index, _Seg s, {required bool branch}) {
    final d = LightningStorm._norm(s.b - s.a);
    var u = LightningStorm._cross(d, const P3(0, 1, 0));
    if (u.length < 0.2) u = LightningStorm._cross(d, const P3(1, 0, 0));
    u = LightningStorm._norm(u) * s.halfWidth;
    final v = LightningStorm._norm(LightningStorm._cross(d, u)) * s.halfWidth;
    final pa = posAttr.array;
    final ua = uvAttr.array;
    final sign = branch ? -1.0 : 1.0;
    var vi = index * vertsPerSegment;

    void vtx(P3 p, double across, double bright) {
      pa[vi * 3] = p.x;
      pa[vi * 3 + 1] = p.y;
      pa[vi * 3 + 2] = p.z;
      ua[vi * 2] = across;
      ua[vi * 2 + 1] = bright * sign;
      vi++;
    }

    for (var k = 0; k < 2; k++) {
      final side = k == 0 ? u : v;
      final a0 = s.a - side, a1 = s.a + side, b1 = s.b + side, b0 = s.b - side;
      vtx(a0, -1, s.brightA);
      vtx(a1, 1, s.brightA);
      vtx(b1, 1, s.brightB);
      vtx(a0, -1, s.brightA);
      vtx(b1, 1, s.brightB);
      vtx(b0, -1, s.brightB);
    }
  }
}

class _Seg {
  _Seg(this.a, this.b, this.halfWidth, this.brightA, this.brightB);
  final P3 a, b;
  final double halfWidth, brightA, brightB;
}

class _PendingThunder {
  _PendingThunder(this.kind, this.delay);
  final ThunderKind kind;
  double delay;
}

class _Strike {
  _Strike({required this.close, required this.from, required this.to, this.ground = false});
  final bool close;
  final bool ground;
  final P3 from, to;
  final List<(double, double)> pulses = [];

  /// Kanal havadayken gelen zayıf yeniden parlamalar (M-bileşenleri). Kanalı
  /// tam, sahneyi yalnızca hafifçe aydınlatır (gökyüzü tekrar tekrar çakmaz).
  final List<(double, double)> echoes = [];
  _BoltSlot? slot;

  /// Bu karedeki bulut aydınlatma ağırlığı (hangi yıldırımın bulutları aydınlattığı).
  double flashWeight = 0;
  P3 lightPos = const P3(0, -30, 0);
  double t = 0;
  double leaderDur = 0;
  double tau = 0.03;
  double end = 1.0;
  double strokesEnd = 0;
  int mainSegments = 0;
  int totalSegments = 0;
  bool sparked = false;

  // Kalıcı kanal evresi
  double glow = 0;
  double lightShare = 0.3;
  double hold = 0;
  double fade = 0;
  double flickA = 0, flickB = 0, flickRate = 6;

  /// Erken söndürme (yeni yıldırıma yer açmak için): bu andan itibaren
  /// [_forcedFade] saniyede yumuşakça biter.
  double _forcedAt = -1;
  double _forcedFade = 0.3;

  void fadeNow(double seconds) {
    if (_forcedAt >= 0) return;
    _forcedAt = t;
    _forcedFade = seconds;
    end = math.min(end, t + seconds);
  }

  double get _forced => _forcedAt < 0 ? 1.0 : (1.0 - (t - _forcedAt) / _forcedFade).clamp(0.0, 1.0);

  /// Darbe dizisinin t anındaki parlaklığı (hızlı yükseliş, üssel sönüş).
  double _pulsesAt(double t) => _sum(pulses, t, tau);

  /// Kalıcı kanaldaki yeniden parlamalar: biraz daha yavaş ve yumuşak.
  double _echoesAt(double t) => _sum(echoes, t, tau * 2.5);

  static double _sum(List<(double, double)> list, double t, double tau) {
    var v = 0.0;
    for (final (at, peak) in list) {
      final x = t - at;
      if (x < 0) continue;
      final p = peak * (x < 0.006 ? x / 0.006 : math.exp(-(x - 0.006) / tau));
      if (p > v) v = p;
    }
    return v;
  }

  /// Kalıcı kanalın zarfı: son darbeden sonra yavaşça zayıflar, titrer ve
  /// [fade] süresinde yumuşakça kaybolur. 0..1 (glow ile çarpılır).
  double _afterglowAt(double t) {
    if (pulses.isEmpty || t < pulses.first.$1) return 0.0;
    final since = t - strokesEnd;
    // Dönüş darbeleri arasında kanal kararır (gerçek şimşeğin titremesi korunur).
    if (since < 0) return 0.07;
    if (glow <= 0) {
      // Kalıcılık kapalı: kısa kalıntı parıltısı
      return 0.07 * math.exp(-since / 0.18);
    }
    // Son darbe sönerken kanal kalıcı parıltıya devredilir.
    var env = glow * math.min(1.0, since / 0.004) *
        (1.0 - 0.45 * (since / math.max(hold, 1e-3)).clamp(0.0, 1.0));
    final tail = since - hold - 0.12;
    if (tail > 0) {
      final k = (tail / math.max(fade, 1e-3)).clamp(0.0, 1.0);
      env *= 1.0 - k * k * (3.0 - 2.0 * k);
    }
    // Plazma titreşimi: iki yavaş, bir hızlı bileşen (yumuşak, kırpışmayan)
    final flick = 0.86 +
        0.08 * math.sin(t * 2.3 + flickA) +
        0.06 * math.sin(t * flickRate + flickB);
    return env * flick;
  }

  /// Kanal parlaklığı (yıldırım ağının görünürlüğü).
  double channelAt(double t) =>
      math.max(math.max(_pulsesAt(t), _echoesAt(t)), _afterglowAt(t)) * _forced;

  /// Sahne aydınlatması: dönüş darbeleri tam; kalıcı kanal ve yeniden
  /// parlamalar yalnızca [lightShare] kadar (sahne sürekli çakıp sönmez).
  double lightAt(double t) {
    if (pulses.isEmpty || t < pulses.first.$1) return 0.0;
    final steady = math.max(_afterglowAt(t), _echoesAt(t) * 0.6) * lightShare;
    return math.max(_pulsesAt(t), steady) * _forced;
  }

  /// Dallar kalıcı evrede ana kanaldan önce söner.
  double branchAt(double t) {
    final since = t - strokesEnd;
    if (since <= 0) return 1.0;
    return math.max(math.exp(-since / 0.35), _echoesAt(t) * 1.2).clamp(0.0, 1.0);
  }

  /// Soğuma: 0 = akkor beyaz çekirdek, 1 = genişleyen mor-mavi hâle.
  double coolAt(double t) {
    final since = t - strokesEnd;
    if (since <= 0 || hold <= 0) return 0.0;
    final c = (since / (hold + fade)).clamp(0.0, 1.0);
    return math.max(0.0, math.sqrt(c) - _echoesAt(t) * 0.8);
  }
}

const String _kBoltVertex = r'''
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
''';

/// Merkezde göz kamaştırıcı beyaz çekirdek, dışa doğru yumuşak mavi hâle.
/// Kanal soğudukça (uCool) çekirdek incelir ve kızıllaşmadan mora kayar, hâle
/// genişler; dallar (negatif parlaklık) uBranch ile ana kanaldan önce söner.
const String _kBoltFragment = r'''
uniform float uIntensity;
uniform vec3 uGlowColor;
uniform float uBranch;
uniform float uCool;
varying vec2 vUv;
void main() {
  float bright = abs(vUv.y);
  float branch = step(vUv.y, 0.0);
  float a = abs(vUv.x);
  float core = exp(-a * a * mix(90.0, 70.0, uCool));
  float glow = exp(-a * a * mix(5.0, 3.0, uCool)) * (1.0 - a);
  vec3 coreCol = mix(vec3(1.0), vec3(0.78, 0.84, 1.0), uCool);
  vec3 glowCol = mix(uGlowColor, uGlowColor * vec3(1.15, 0.85, 1.05), uCool);
  vec3 c = coreCol * core * mix(1.7, 1.2, uCool) + glowCol * glow * mix(0.6, 0.85, uCool);
  float k = bright * uIntensity * mix(1.0, uBranch, branch);
  gl_FragColor = vec4(c * k, 1.0);
}
''';
