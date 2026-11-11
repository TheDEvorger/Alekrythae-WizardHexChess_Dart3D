import 'dart:math' as math;

import 'package:three_js/three_js.dart' as three;

import 'battle_fx.dart' show P3;

/// Arenanın etrafında dönen, tamamen GPU'da (shader) üretilen gizemli fırtına girdabı.
///
/// Her bulut katmanı bir fbm gürültü alanıdır ve hareket shader içinde hesaplanır:
///
/// * **Bulut denizi**: Log-polar spiral koordinatlarda akan bulutlar. Bantlar
///   spiral kollar boyunca arenaya doğru akar ve döner; alan sürekli kaynar.
/// * **Göz duvarı**: İç içe iki koni; bulutlar hem döner hem yukarı tırmanır.
/// * **Bulut kuşakları**: Kulelerin arasından geçen, iç içe dönen alçak bulut
///   duvarları; kuleler bulutların içinden yükselir.
/// * **Yırtık bulutlar**: Arenanın çevresinde hızla savrulan bulut parçaları.
/// * **Sağanak**: Girdapla birlikte dönen eğik yağmur çizgileri.
/// * **Kenar sisi**: Platformun dibini yalayan, en hızlı dönen ince sis.
/// * **Rüzgâr şeritleri** ve **ışık izleri**: Girdaba savrulan yumuşak kenarlı
///   izler ve kuyruklu ışık hüzmeleri.
/// * **Gizemli ışık**: Bulutların derinliğinden sızan, nabız gibi atan ışıltı.
/// * **Şimşek**: Çakan şimşek yolu boyunca bulutları ve kuleleri aydınlatır.
/// * **Fırtına sisi**: Gerçek sis. Doz arttıkça renk karanlıktan açık gri-mavi
///   pusa döner, görüş mesafesi kısalır (tahta, taşlar, kuleler ve arka plan
///   da sise gömülür), kenar sisi ve bulut kuşakları kalınlaşır ve tahtanın
///   üstüne alçak kanatlardan başlayarak yer sisi çöker ([bindScene]).
///
/// Ayarların üst sınırı yoktur: her ayar arttıkça kendi etkisinin dozu artar.
///
/// Tahtanın önüne düşen (kameradan bakınca tahtayı ya da taşları örten) bulut,
/// yağmur ve ışık izi parçaları shader içinde otomatik şeffaflaşır; fırtına ne
/// kadar yoğun olursa olsun oyun alanı her kamera açısından açık kalır.
///
/// [setIntensity] fırtınanın gücünü, [setHaunt] gizemli atmosferi, [setFog]
/// sis yoğunluğunu, [setDetail] shader kalitesini canlı olarak değiştirir.
/// Güç, gizem ve sis hedef değere ~0,5 sn'de yumuşakça ulaşır; kaydırıcı
/// sürüklenirken desen zıplamaz, parçacıklar birden belirip kaybolmaz. Dönüş
/// fazları CPU'da biriktirildiği için hız değişince de desen kaymaz.
class StormVortex {
  StormVortex(
    three.Object3D parent, {
    int detail = 1,
    double intensity = 1.0,
    double haunt = 0.0,
    double fog = 1.0,
  }) : _detail = detail.clamp(0, maxDetail) {
    _layers = [
      _Layer(kStormAbyss, _LayerKind.disc),
      _Layer(kStormSea, _LayerKind.disc),
      _Layer(kStormOuterWall, _LayerKind.wall),
      _Layer(kStormInnerWall, _LayerKind.wall),
      _Layer(kStormEdgeMist, _LayerKind.ring),
      _Layer(kStormBelt1, _LayerKind.wall),
      _Layer(kStormBelt2, _LayerKind.wall),
      _Layer(kStormBelt3, _LayerKind.wall),
      _Layer(kStormBelt4, _LayerKind.wall),
    ];
    parent.add(group);
    _build();
    setIntensity(intensity, instant: true);
    setHaunt(haunt, instant: true);
    setFog(fog, instant: true);
  }

  /// 0: Düşük, 1: Orta, 2: Yüksek, 3: Sinematik.
  static const int maxDetail = 3;

  /// Kaydırıcının üst ucu. Ayarların ÜST SINIRI YOKTUR: elle girilen daha
  /// yüksek değerler etkinin dozunu artırmaya devam eder (doygunluk yok).
  static const double maxIntensity = 3.0;

  /// Parçacık katmanları (yağmur, rüzgâr, bulut parçası, ışık izi) en çok bu
  /// kata kadar büyütülür (ekran kartını kilitlememek için). Bunun ötesinde
  /// doz, parçacıkların yoğunluğu/opaklığı artarak sürer.
  static const int maxParticleScale = 8;

  /// Sisin "doz" eğrisi: 1 = varsayılan, üstünde sis rengi açılır, görüş
  /// mesafesi kısalır, tahtaya yer sisi çöker. 0'a yaklaştıkça hava açılır.
  static double hazeOf(double fog) => fog <= 1.0 ? 0.0 : 1.0 - math.exp(-0.35 * (fog - 1.0));

  /// Sahnedeki (tahta, taşlar, kuleler) sis mesafelerinin bölüneceği çarpan.
  static double sceneFogScaleOf(double fog) => math.pow(math.max(fog, 1e-6), 0.8).toDouble();

  /// Ayar değişikliklerinin yumuşatma zaman sabiti (saniye).
  static const double _ease = 0.45;

  final three.Group group = three.Group();
  int _detail;
  late final List<_Layer> _layers;

  // Tüm katmanların paylaştığı uniform nesneleri (tek atama ile hepsi güncellenir).
  final Map<String, dynamic> _uTime = {'value': 0.0};
  final Map<String, dynamic> _uWarp = {'value': 0.0};
  final Map<String, dynamic> _uWindTime = {'value': 0.0};
  final Map<String, dynamic> _uScudTime = {'value': 0.0};
  final Map<String, dynamic> _uRainTime = {'value': 0.0};
  final Map<String, dynamic> _uRainLen = {'value': 1.3};
  final Map<String, dynamic> _uWispTime = {'value': 0.0};
  final Map<String, dynamic> _uStorm = {'value': 1.0};
  final Map<String, dynamic> _uHauntAll = {'value': 0.0};
  final Map<String, dynamic> _uFlash = {'value': 0.0};
  final Map<String, dynamic> _uFlashA = {'value': three.Vector3(0, -50, 0)};
  final Map<String, dynamic> _uFlashB = {'value': three.Vector3(0, -50, 0)};
  final Map<String, dynamic> _uFlashRadius = {'value': 10.0};
  final Map<String, dynamic> _uSkyFlash = {'value': 0.0};
  final Map<String, dynamic> _uFogColor = {'value': _rgb(kStormFogColor)};
  final Map<String, dynamic> _uHauntColor = {'value': _rgb(kStormHauntColor)};
  final Map<String, dynamic> _uWindAlpha = {'value': 0.3};
  final Map<String, dynamic> _uWispAlpha = {'value': 0.0};
  final Map<String, dynamic> _uScudAlpha = {'value': 0.0};
  final Map<String, dynamic> _uRainAlpha = {'value': 0.0};

  /// Sis: x = sis mesafelerinin çarpanı (küçüldükçe sis yaklaşır),
  /// y = en yoğun sis karışımına eklenen pay (0..1).
  final Map<String, dynamic> _uMist = {'value': three.Vector2(1.0, 0.0)};

  /// Tahtaya çöken yer sisinin yoğunluğu (0 = yok; sis dozu arttıkça 1'e yaklaşır).
  final Map<String, dynamic> _uGround = {'value': 0.0};

  /// Tahtayı koruyan iki yatay düzlem: (alt y, alt yarıçap, üst y, üst yarıçap).
  /// Kameradan çıkan ışın bu disklere çarpmadan önce bir parçaya değiyorsa o
  /// parça tahtanın/taşların önündedir ve şeffaflaştırılır.
  final Map<String, dynamic> _uClear = {'value': three.Vector4(0.05, 11.0, 2.6, 10.0)};

  final List<three.Material> _materials = [];
  final List<three.BufferGeometry> _geometries = [];
  final Map<String, three.Material> _towerMaterials = {};

  final Map<String, _Counted> _counted = {};

  double _time = 0.0;
  double _warp = 0.0;
  double _windTime = 0.0;
  double _scudTime = 0.0;
  double _rainTime = 0.0;
  double _wispTime = 0.0;

  // Hedef (ayar) ve ekrandaki (yumuşatılmış) değerler
  double _targetIntensity = 1.0;
  double _intensity = 1.0;
  double _targetHaunt = 0.0;
  double _haunt = 0.0;
  double _targetFog = 1.0;
  double _fog = 1.0;

  double get intensity => _targetIntensity;
  double get haunt => _targetHaunt;
  double get fog => _targetFog;
  int get detail => _detail;

  /// Parçacık katmanlarının şu anki büyütme katı (1, 2, 4, 8).
  int get particleScale => _particleScale;
  int _particleScale = 1;

  /// O an ekrandaki (yumuşatılmış) sis rengi; sahne sisi ve arka plan da bunu izler.
  three.Vector3 get fogColor => _uFogColor['value'] as three.Vector3;

  /// Ekrandaki (yumuşatılmış) sis dozu ve yer sisi yoğunluğu.
  double get currentFog => _fog;
  double get groundMist => _uGround['value'] as double;

  /// Güç doğrudan ekrana yansır: doygunluk yok, değer arttıkça doz artar.
  double get _vis => _intensity;

  // Sahneye bağlanan sis (tahta, taşlar, kuleler) ve ufuk perdesi.
  three.Scene? _scene;
  three.Fog? _sceneFog;
  double _sceneFogNear = 24.0;
  double _sceneFogFar = 110.0;
  three.MeshBasicMaterial? _curtain;
  double _curtainOpacity = 0.88;

  /// Fırtına sisinin tahtayı, taşları, kuleleri, arka planı ve ufuk perdesini
  /// de sarması için sahneyi bağlar. Sis 1'deyken sahne sisi [near]..[far]
  /// aralığındadır; sis arttıkça yaklaşır ve açık griye döner.
  void bindScene(
    three.Scene scene, {
    required three.Fog fog,
    three.MeshBasicMaterial? curtain,
  }) {
    _scene = scene;
    _sceneFog = fog;
    _sceneFogNear = fog.near.toDouble();
    _sceneFogFar = fog.far.toDouble();
    _curtain = curtain;
    _curtainOpacity = curtain?.opacity.toDouble() ?? 0.88;
    _applyFog();
  }

  /// Hız çarpanı: 0 → durgun esinti (0,35), 1 → fırtına (1,25), 3 → yıkım
  /// kasırgası (2,25). 1'in üstünde hız yavaş artar: güçlü fırtına ağır ve
  /// heybetli döner, bulutlar ekranda fırlayıp kaybolmaz.
  double get _speedMul {
    final v = _vis;
    return v <= 1.0 ? 0.35 + 0.9 * v : 1.25 + 0.5 * (v - 1.0);
  }

  /// İç göz duvarının verilen yükseklikteki yarıçapı (şimşek başlangıcı için).
  double innerWallRadiusAt(double y) {
    final c = kStormInnerWall;
    final h = c['height']!.toDouble();
    final y0 = c['y']!.toDouble() - h / 2;
    final t = ((y - y0) / h).clamp(0.0, 1.0);
    final rb = c['radiusBottom']!.toDouble();
    final rt = c['radiusTop']!.toDouble();
    return rb + (rt - rb) * t;
  }

  /// Shader kalitesi; değişirse katmanlar yeniden kurulur (fazlar korunur).
  void setDetail(int detail) {
    final d = detail.clamp(0, maxDetail);
    if (d == _detail) return;
    _detail = d;
    _clear();
    _build();
    _applyCounts();
  }

  /// Negatif ve sayı olmayan girişleri eler; ÜST SINIR YOKTUR.
  static double _dose(double value, double fallback) => value.isFinite ? math.max(0.0, value) : fallback;

  /// Fırtına gücü (kaydırıcı 0..3, elle sınırsız). Dönüş hızı, bulut
  /// yoğunluğu, türbülans, rüzgâr, yağmur ve bulut parçaları. [instant]
  /// değilse yumuşak geçer.
  void setIntensity(double value, {bool instant = false}) {
    _targetIntensity = _dose(value, _targetIntensity);
    if (instant) {
      _intensity = _targetIntensity;
      _applyIntensity();
    }
  }

  /// Gizemli atmosfer (kaydırıcı 0..1, elle sınırsız): bulut içi ışıltı ve
  /// girdaba çekilen ışık izleri.
  void setHaunt(double value, {bool instant = false}) {
    _targetHaunt = _dose(value, _targetHaunt);
    if (instant) {
      _haunt = _targetHaunt;
      _applyHaunt();
    }
  }

  /// Fırtına sisi (0 = açık hava, 1 = varsayılan, elle sınırsız). Arttıkça
  /// GERÇEK sis artar: renk açık griye döner, görüş mesafesi kısalır (tahta,
  /// taşlar ve kuleler de sise gömülür) ve tahtaya yer sisi çöker.
  void setFog(double value, {bool instant = false}) {
    _targetFog = _dose(value, _targetFog);
    if (instant) {
      _fog = _targetFog;
      _applyFog();
    }
  }

  void _applyIntensity() {
    final v = _vis;
    _uStorm['value'] = v;
    final base = math.min(v, maxIntensity);
    final over = math.max(0.0, v - maxIntensity);
    _uWindAlpha['value'] = kStormWind['alpha']!.toDouble() * ((0.55 + 0.4 * base).clamp(0.0, 1.6) + 0.2 * over);
    _uRainAlpha['value'] = kStormRain['alpha']!.toDouble() * ((0.4 + 0.3 * base).clamp(0.0, 1.3) + 0.15 * over);
    _applyScudAlpha();
    _applyCounts();
  }

  void _applyHaunt() {
    final h = _haunt;
    _uHauntAll['value'] = h;
    for (final l in _layers) {
      l.uHaunt['value'] = h * l.config['haunt']!.toDouble();
    }
    _uWispAlpha['value'] = kStormWisps['alpha']!.toDouble() * (0.4 + 0.6 * h);
    _applyCounts();
  }

  void _applyFog() {
    final m = _fog;
    final mist = _uMist['value'] as three.Vector2;
    // Sis mesafeleri dozla birlikte sürekli yaklaşır (alt sınır yok).
    mist.x = 1.0 / (0.25 + 0.75 * m);
    mist.y = ((m - 1.0) * 0.5).clamp(0.0, 1.0);
    for (final l in _layers) {
      final gain = (l.config['mist'] ?? 0).toDouble();
      l.uMistAmt['value'] = gain * (m - 1.0);
    }

    // Sis koyulaştıkça KARARMAZ: ışığı saçan, açık gri-mavi bir pusa döner.
    // Karışım ışık gibi doğrusal uzayda yapılıp ekrana (sRGB) çevrilir; ham
    // sRGB değerlerini karıştırmak ara tonları koyu bırakıp sisi karartıyordu.
    final t = hazeOf(m);
    final a = _rgb(kStormFogColor);
    final b = _rgb(kStormHazeColor);
    double mixSrgb(double x, double y) => _toSrgb(_toLinear(x) + (_toLinear(y) - _toLinear(x)) * t);
    final fogCol = _uFogColor['value'] as three.Vector3;
    fogCol.setValues(mixSrgb(a.x, b.x), mixSrgb(a.y, b.y), mixSrgb(a.z, b.z));
    _uGround['value'] = t;
    _syncGroundVisibility();
    _applySceneFog();

    _applyScudAlpha();
    _applyCounts();
  }

  static double _toLinear(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  static double _toSrgb(double c) =>
      c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;

  /// Sahne sisinin ölçüldüğü kamera uzaklığı (geniş pencerede tahtaya uzaklık).
  static const double _refViewDistance = 23.0;
  double _viewScale = 1.0;

  /// Kameranın tahta merkezine uzaklığı (her karede verilir). Dar pencerede
  /// kamera daha uzakta durur; sahne sisi buna göre ölçeklenir ki aynı sis
  /// ayarı her pencere boyutunda tahtayı aynı dozda sarsın.
  set viewDistance(double d) {
    final s = d.isFinite ? math.max(1.0, d / _refViewDistance) : 1.0;
    if ((s - _viewScale).abs() < 0.01) return;
    _viewScale = s;
    _applySceneFog();
  }

  /// Tahta, taşlar, kuleler, arka plan ve ufuk perdesi de aynı sise gömülür.
  void _applySceneFog() {
    final fog = _sceneFog;
    if (fog == null) return;
    final m = _fog;
    final t = hazeOf(m);
    // Bu renderer sisi ton eşleme ve sRGB dönüşümünden SONRA uygular
    // (fog_fragment en sonda): sis rengi ekran değeridir. Bu yüzden fırtına
    // shader'larıyla birebir aynı renk verilir; aksi hâlde tahta ve taşlar
    // pusun içinde koyu siluetler gibi kalıyordu. Sis 1'deyken renk ve
    // mesafeler birebir eskisidir.
    final fc = fogColor;
    fog.color.setValues(fc.x, fc.y, fc.z);
    // Kamera uzaklığına göre ölçek yalnızca sis 1'in üstüne çıkınca devreye
    // girer (varsayılan görünüm her pencerede aynen korunur).
    final view = 1.0 + (_viewScale - 1.0) * (m - 1.0).clamp(0.0, 1.0);
    final s = sceneFogScaleOf(m);
    fog.near = math.min(1e6, _sceneFogNear * view / s);
    fog.far = math.min(1e6, math.max(fog.near + 0.5, _sceneFogFar * view / s));

    final bg = _scene?.background;
    if (bg is three.Color) bg.setValues(fc.x, fc.y, fc.z);

    // Ufuk perdesinin kendi rengi (sisten önce) sRGB'ye çevrilerek çizilir:
    // pusa giderken doğrusal değeri verilir ki ekranda pusla aynı tonda dursun.
    final curtain = _curtain;
    if (curtain != null) {
      final a = _rgb(kStormFogColor);
      curtain.color.setValues(
        a.x + (_toLinear(fc.x) - a.x) * t,
        a.y + (_toLinear(fc.y) - a.y) * t,
        a.z + (_toLinear(fc.z) - a.z) * t,
      );
      curtain.opacity = _curtainOpacity + (1.0 - _curtainOpacity) * t;
    }
  }

  void _applyScudAlpha() {
    final v = _vis;
    final base = math.min(v, maxIntensity);
    final over = math.max(0.0, v - maxIntensity);
    final mistBoost = 1.0 + 0.25 * math.max(0.0, _fog - 1.0);
    _uScudAlpha['value'] =
        kStormScud['alpha']!.toDouble() * ((0.35 + 0.35 * base).clamp(0.0, 1.3) + 0.12 * over) * mistBoost;
  }

  /// Her parçacık katmanında kaç örneğin çizileceği (yoğunluk ayarına göre).
  /// Gereken oran 1'i aşınca katmanlar büyütülür (en çok [maxParticleScale] kat).
  void _applyCounts() {
    final i = _vis;
    final mistExtra = 0.08 * math.max(0.0, _fog - 1.0);
    final fractions = <String, double>{
      'wind': 0.2 + 0.35 * i,
      'wisps': _haunt,
      'scud': i < 0.15 ? 0.0 : 0.12 + 0.32 * i + mistExtra,
      'rain': i < 0.25 ? 0.0 : 0.08 + 0.3 * i,
    };
    _ensureParticleScale(fractions.values.fold(0.0, math.max));
    fractions.forEach((key, f) => _setCount(key, f / _particleScale));
  }

  /// Parçacık katmanlarını gereken kata büyütür/küçültür. Yalnızca geometri
  /// değişir (shader yeniden derlenmez); aynı tohumla üretildiği için mevcut
  /// örnekler yerinde kalır, yeni örnekler sınırdan yumuşakça belirir.
  void _ensureParticleScale(double need) {
    var target = 1;
    while (target < need && target < maxParticleScale) {
      target *= 2;
    }
    final grow = target > _particleScale;
    final shrink = target * 4 <= _particleScale;
    if (!grow && !shrink) return;
    _particleScale = target;
    for (final c in _counted.values) {
      final old = c.geo;
      final geo = c.make(c.base * target);
      c.geo = geo;
      c.max = c.base * target;
      (c.obj as three.Mesh).geometry = geo;
      _geometries
        ..remove(old)
        ..add(geo);
      old.dispose();
    }
  }

  /// Görünen örnek sayısı. Sınırdaki örnekler (en çok %8'lik bir bant) kesilmek
  /// yerine kısmi saydamlıkla yumuşakça belirir/söner; ayar değişirken
  /// yağmur damlaları ve bulut parçaları tek tek "pat" diye çıkıp kaybolmaz.
  void _setCount(String key, double fraction) {
    final c = _counted[key];
    if (c == null) return;
    final shown = c.max * fraction.clamp(0.0, 1.0);
    final band = math.max(1.0, c.max * 0.08);
    final n = math.min(c.max, (shown + band * 0.5).ceil());
    final count = shown <= 0.0 ? 0 : n * c.vertsPer;
    if (c.geo.drawRange['count'] != count) c.geo.drawRange['count'] = count;
    (c.uShow['value'] as three.Vector2).setValues(shown, band);
    c.obj.visible = count > 0;
  }

  /// Hedefe üssel yaklaşma; yeterince yaklaşınca tam hedefe oturur.
  static double _approach(double cur, double target, double k) {
    final d = target - cur;
    if (d.abs() < 1e-4) return target;
    return cur + d * k;
  }

  void update(double dt) {
    // Ayar değişikliklerini yumuşat (yalnızca değer hareket halindeyken iş yapılır).
    final k = 1.0 - math.exp(-dt / _ease);
    if (_intensity != _targetIntensity) {
      _intensity = _approach(_intensity, _targetIntensity, k);
      _applyIntensity();
    }
    if (_haunt != _targetHaunt) {
      _haunt = _approach(_haunt, _targetHaunt, k);
      _applyHaunt();
    }
    if (_fog != _targetFog) {
      _fog = _approach(_fog, _targetFog, k);
      _applyFog();
    }

    final sm = _speedMul;
    _time += dt;
    // Bulut kaynaması (desenin kendi kendine değişmesi) ağır tutulur: bulutlar
    // dönerek akar ama bir saniyede oluşup dağılmaz.
    _warp += dt * (0.40 + 0.20 * sm);
    // Rüzgâr izlerinin ömrü güçle fazla kısalmasın (izler yanıp sönmesin).
    _windTime += dt * (0.5 + 0.5 * sm);
    // Savrulan bulut parçaları da ağır süzülür.
    _scudTime += dt * (0.5 + 0.4 * sm);
    // Yağmurun düşüş hızı fırtınayla az değişir (gerçekte de damla hızı sabittir);
    // şerit boyu düşüş hızıyla uzar: damla kare başına kendi boyundan fazla
    // ilerlemez, yağmur kesintisiz akar (yanıp sönmez).
    final rainRate = 0.7 + 0.3 * sm;
    _rainTime += dt * rainRate;
    _uRainLen['value'] = kStormRain['length']!.toDouble() * rainRate;
    _wispTime += dt * (0.55 + 0.45 * sm);
    _uTime['value'] = _time;
    _uWarp['value'] = _warp;
    _uWindTime['value'] = _windTime;
    _uScudTime['value'] = _scudTime;
    _uRainTime['value'] = _rainTime;
    _uWispTime['value'] = _wispTime;
    for (final l in _layers) {
      // Açısal faz 2π'de sarar (desen açısal yönde periyodik); radyal akış sürekli.
      l.rot = (l.rot + dt * l.spin * sm) % (math.pi * 2);
      l.flow += dt * l.flowRate * sm;
      l.uRot['value'] = l.rot;
      l.uFlow['value'] = l.flow;
    }
  }

  /// Şimşek ışığını bulutlara ve kulelere uygular (her karede [LightningStorm] sürer).
  ///
  /// [level]: kanal boyunca yerel aydınlanma, [sky]: tüm gökyüzünün parlaması,
  /// [radius]: kanaldan ne kadar uzağa ışık yayıldığı (bulut içi şimşekte geniş).
  void setLightning({
    required double level,
    double sky = 0.0,
    P3? from,
    P3? to,
    double radius = 10.0,
  }) {
    if (from != null) (_uFlashA['value'] as three.Vector3).setValues(from.x, from.y, from.z);
    if (to != null) (_uFlashB['value'] as three.Vector3).setValues(to.x, to.y, to.z);
    _uFlash['value'] = level;
    _uSkyFlash['value'] = sky;
    _uFlashRadius['value'] = radius;
  }

  /// Gotik kuleler için fırtınayla bütünleşik koyu taş materyali: kenar ışığı,
  /// şimşek aydınlanması, sis ve gizemli parıltı. Aynı renk için önbelleklenir.
  three.Material towerMaterial(int color, {bool accent = false}) {
    final key = '$color-$accent';
    return _towerMaterials.putIfAbsent(key, () {
      return three.ShaderMaterial.fromMap({
        'uniforms': {
          'uColor': {'value': _rgb(color)},
          'uRimColor': {'value': _rgb(accent ? 0x6FB8FF : 0x3E6A9C)},
          'uTime': _uTime,
          'uHaunt': _uHauntAll,
          'uHauntColor': _uHauntColor,
          'uFlash': _uFlash,
          'uFlashA': _uFlashA,
          'uFlashB': _uFlashB,
          'uFlashRadius': _uFlashRadius,
          'uSkyFlash': _uSkyFlash,
          'uFogColor': _uFogColor,
          'uMist': _uMist,
          'uFog': {'value': three.Vector2(30.0, 120.0)},
        },
        'vertexShader': kStormTowerVertex,
        'fragmentShader': _header(3, false) + kStormNoiseGlsl + kStormFogGlsl + kStormTowerFragment,
      });
    });
  }

  void dispose() {
    _clear();
    for (final m in _towerMaterials.values) {
      m.dispose();
    }
    _towerMaterials.clear();
    group.parent?.remove(group);
  }

  // ------------------------------------------------------------------ kurulum
  static const int _wispSegments = 10;

  void _build() {
    final d = _detail;
    final oct = const [3, 4, 5, 6][d];
    final octLo = d >= 3 ? oct : math.max(2, oct - 1);
    final segs = d >= 3 ? 192 : 128;

    // Dipsiz fırtına tabanı ve ana spiral bulut denizi
    group.add(_discLayer(_layers[0], oct: octLo, lit: d >= 3, order: -40, segments: segs));
    group.add(_discLayer(_layers[1], oct: oct, lit: d >= 1, order: -39, segments: segs));
    // Göz duvarı: dıştaki yavaş, içteki hızlı (paralaks)
    group.add(_wallLayer(_layers[2], oct: octLo, lit: d >= 2, order: -38, segments: segs, side: three.BackSide));
    group.add(_wallLayer(_layers[3], oct: oct, lit: d >= 1, order: -37, segments: segs, side: three.BackSide));
    // Platformu yalayan hızlı kenar sisi
    group.add(_discLayer(_layers[4], oct: octLo, lit: d >= 1, order: -36, segments: segs));

    // Kulelerin arasındaki bulut kuşakları: kaliteye göre 2-4 kabuk.
    // Önce uzak yarılar (dıştan içe), sonra parçacıklar, en son yakın yarılar (içten dışa).
    final belts = [_layers[5], _layers[6], if (d >= 1) _layers[7], if (d >= 3) _layers[8]];
    final beltOct = math.max(2, oct - 1);
    var order = -35;
    for (final b in belts) {
      group.add(_wallLayer(b, oct: beltOct, lit: d >= 2, order: order++, segments: 96, side: three.BackSide));
    }

    // Savrulan bulut parçaları, rüzgâr, sağanak ve ışık izleri
    group.add(_scud(const [40, 90, 150, 240][d], order: order++));
    group.add(_windStreaks(const [200, 420, 700, 1100][d], order: order++));
    group.add(_rain(const [1500, 3000, 5000, 8000][d], order: order++));
    group.add(_wisps(const [20, 45, 70, 120][d], order: order++));

    for (final b in belts.reversed) {
      group.add(_wallLayer(b, oct: beltOct, lit: d >= 2, order: order++, segments: 96, side: three.FrontSide));
    }

    // Tahtaya çöken yer sisi: sis dozu 1'in üstüne çıkınca belirir ve koyulaşır.
    for (final (y, weight, seed) in kGroundMistLayers) {
      final m = _groundMist(y, weight, seed, order: order++);
      _groundMeshes.add(m);
      group.add(m);
    }
    _syncGroundVisibility();
  }

  final List<three.Mesh> _groundMeshes = [];

  /// Yer sisi yokken katmanlar hiç çizilmez (varsayılan sahnede ek maliyet yok).
  void _syncGroundVisibility() {
    final on = (_uGround['value'] as double) > 0.001;
    for (final m in _groundMeshes) {
      m.visible = on;
    }
  }

  /// Tahtanın üstünde ağır ağır sürüklenen yatay sis tabakası. Sütunlar ve
  /// taşlar sisin içinden yükselir (derinlik testi açık); alçak kanatlarda
  /// sis daha erken birikir.
  three.Mesh _groundMist(double y, double weight, double seed, {required int order}) {
    final geo = three.CircleGeometry(radius: 17.0, segments: 72);
    geo.rotateX(-math.pi / 2);
    final mat = _track(
      three.ShaderMaterial.fromMap({
        'uniforms': {
          'uTime': _uTime,
          'uGround': _uGround,
          'uLayer': {'value': weight},
          'uSeed': {'value': seed},
          'uFogColor': _uFogColor,
          'uFlash': _uFlash,
          'uFlashA': _uFlashA,
          'uFlashB': _uFlashB,
          'uFlashRadius': _uFlashRadius,
          'uSkyFlash': _uSkyFlash,
        },
        'vertexShader': kStormVertexShader,
        'fragmentShader': _header(3, false) + kStormNoiseGlsl + kGroundMistFragment,
        'transparent': true,
        'depthWrite': false,
        'side': three.DoubleSide,
      }),
      geo,
    );
    final mesh = three.Mesh(geo, mat);
    mesh.position.y = y;
    mesh.renderOrder = order;
    return mesh;
  }

  void _clear() {
    for (final c in List<three.Object3D>.of(group.children)) {
      group.remove(c);
    }
    for (final g in _geometries) {
      g.dispose();
    }
    for (final m in _materials) {
      m.dispose();
    }
    _geometries.clear();
    _materials.clear();
    _counted.clear();
    _groundMeshes.clear();
  }

  static String _header(int oct, bool lit) =>
      '#define STORM_OCT $oct\n#define STORM_LIT ${lit ? 1 : 0}\n';

  Map<String, dynamic> _layerUniforms(_Layer l) {
    final c = l.config;
    return {
      'uTime': _uTime,
      'uWarp': _uWarp,
      'uStorm': _uStorm,
      'uRot': l.uRot,
      'uFlow': l.uFlow,
      'uHaunt': l.uHaunt,
      'uMistAmt': l.uMistAmt,
      'uHauntColor': _uHauntColor,
      'uFlash': _uFlash,
      'uFlashA': _uFlashA,
      'uFlashB': _uFlashB,
      'uFlashRadius': _uFlashRadius,
      'uSkyFlash': _uSkyFlash,
      'uFogColor': _uFogColor,
      'uMist': _uMist,
      'uClear': _uClear,
      'uFog': {'value': three.Vector2(_d(c, 'fogNear'), _d(c, 'fogFar'))},
      'uDensity': {'value': three.Vector2(_d(c, 'densityBase'), _d(c, 'densitySlope'))},
      'uCells': {'value': _d(c, 'cells')},
      'uCover': {'value': _d(c, 'cover')},
      'uSoft': {'value': _d(c, 'soft')},
      'uAlpha': {'value': _d(c, 'alpha')},
      'uSeed': {'value': _d(c, 'seed')},
      'uDeep': {'value': _rgb(c['deep']!.toInt())},
      'uBody': {'value': _rgb(c['body']!.toInt())},
      'uRim': {'value': _rgb(c['rim']!.toInt())},
      'uGlow': {'value': _rgb(c['glow']!.toInt())},
    };
  }

  T _track<T extends three.Material>(T m, three.BufferGeometry g) {
    _materials.add(m);
    _geometries.add(g);
    return m;
  }

  three.Mesh _discLayer(
    _Layer l, {
    required int oct,
    required bool lit,
    required int order,
    required int segments,
  }) {
    final c = l.config;
    final three.BufferGeometry geo = l.kind == _LayerKind.ring
        ? three.RingGeometry(_d(c, 'r0'), _d(c, 'r3'), segments, 2)
        : three.CircleGeometry(radius: _d(c, 'r3'), segments: segments);
    geo.rotateX(-math.pi / 2);
    final mat = _track(
      three.ShaderMaterial.fromMap({
        'uniforms': {
          ..._layerUniforms(l),
          'uSwirl': {'value': _d(c, 'swirl')},
          'uArms': {'value': _d(c, 'arms')},
          'uArmAmt': {'value': _d(c, 'armAmt')},
          'uStretch': {'value': _d(c, 'stretch')},
          'uGlowReach': {'value': _d(c, 'glowReach')},
          'uRadii': {'value': three.Vector4(_d(c, 'r0'), _d(c, 'r1'), _d(c, 'r2'), _d(c, 'r3'))},
        },
        'vertexShader': kStormVertexShader,
        'fragmentShader': _header(oct, lit) + kStormNoiseGlsl + kStormFogGlsl + kStormSeaFragment,
        'transparent': true,
        'depthWrite': false,
        'side': three.DoubleSide,
      }),
      geo,
    );
    final mesh = three.Mesh(geo, mat);
    mesh.position.y = _d(c, 'y');
    mesh.renderOrder = order;
    return mesh;
  }

  three.Mesh _wallLayer(
    _Layer l, {
    required int oct,
    required bool lit,
    required int order,
    required int segments,
    required int side,
  }) {
    final c = l.config;
    final h = _d(c, 'height');
    final geo = three.CylinderGeometry(_d(c, 'radiusTop'), _d(c, 'radiusBottom'), h, segments, 1, true);
    final mat = _track(
      three.ShaderMaterial.fromMap({
        'uniforms': {
          ..._layerUniforms(l),
          'uTwist': {'value': _d(c, 'twist')},
          'uVCells': {'value': _d(c, 'vcells')},
          'uHeight': {'value': three.Vector2(-h / 2, h / 2)},
          'uVFade': {
            'value': three.Vector4(_d(c, 'fadeIn0'), _d(c, 'fadeIn1'), _d(c, 'fadeOut0'), _d(c, 'fadeOut1')),
          },
        },
        'vertexShader': kStormVertexShader,
        'fragmentShader':
            _header(oct, lit) + kStormNoiseGlsl + kStormClearGlsl + kStormFogGlsl + kStormWallFragment,
        'transparent': true,
        'depthWrite': false,
        // Kamera girdabın gözünde: büyük duvarların iç yüzünü görür. Kuşaklar ise
        // doğru sıralama için uzak (BackSide) ve yakın (FrontSide) yarı olarak çizilir.
        'side': side,
      }),
      geo,
    );
    final mesh = three.Mesh(geo, mat);
    mesh.position.y = _d(c, 'y');
    mesh.renderOrder = order;
    return mesh;
  }

  /// Rüzgâr izleri: her biri kameraya dönük, yumuşak kenarlı ve kuyruğa doğru
  /// incelen bir şerit. (1 piksellik çizgiler gibi tırtıklanıp kırpışmaz.)
  three.Mesh _windStreaks(int count, {required int order}) {
    final c = kStormWind;
    final rMin = _d(c, 'rMin');
    final rMax = _d(c, 'rMax');
    three.BufferGeometry make(int n) {
      final rng = math.Random(4242);
      final pos = <double>[];
      final uv = <double>[];
      for (var i = 0; i < n; i++) {
        final th = rng.nextDouble() * math.pi * 2;
        // İç bölgede daha yoğun: girdabın gözüne yakın rüzgâr daha sert
        final rr = rMin + (rMax - rMin) * math.pow(rng.nextDouble(), 1.6);
        final y = _d(c, 'yMin') + rng.nextDouble() * (_d(c, 'yMax') - _d(c, 'yMin'));
        for (final (a, s) in _quadCorners) {
          pos.addAll([th, y, rr]);
          uv.addAll([a, s]);
        }
      }
      return _instancedGeo(pos, uv, 6);
    }

    final geo = make(count * _particleScale);
    final show = _showUniform();
    final mat = _track(
      three.ShaderMaterial.fromMap({
        'uniforms': {
          'uTime': _uWindTime,
          'uShow': show,
          'uFlash': _uFlash,
          'uFogColor': _uFogColor,
          'uMist': _uMist,
          'uClear': _uClear,
          'uFog': {'value': three.Vector2(_d(c, 'fogNear'), _d(c, 'fogFar'))},
          'uColor': {'value': _rgb(c['color']!.toInt())},
          'uAlpha': _uWindAlpha,
          'uSpeed': {'value': _d(c, 'speed')},
          'uLen': {'value': _d(c, 'length')},
          'uWidth': {'value': _d(c, 'width')},
          'uRInner': {'value': _d(c, 'rInner')},
        },
        'vertexShader': kStormClearGlsl + kStormShowGlsl + kStormWindVertex,
        'fragmentShader': kStormFogGlsl + kStormWindFragment,
        'transparent': true,
        'depthWrite': false,
        'side': three.DoubleSide,
        'blending': three.AdditiveBlending,
      }),
      geo,
    );
    final mesh = three.Mesh(geo, mat)
      // Pozisyonlar shader'da hesaplanıyor; CPU sınır küresi anlamsız.
      ..frustumCulled = false
      ..renderOrder = order;
    _counted['wind'] = _Counted(geo, mesh, count, count * _particleScale, 6, show, make);
    return mesh;
  }

  /// Baş (0) → kuyruk (1) ve kenar (±1) köşeleriyle iki üçgenlik şerit.
  static const List<(double, double)> _quadCorners = [
    (0.0, -1.0),
    (0.0, 1.0),
    (1.0, 1.0),
    (0.0, -1.0),
    (1.0, 1.0),
    (1.0, -1.0),
  ];

  /// Her ışık izi, vertex shader'da kameraya dönük bir şerit (kuyruk) olarak çizilir.
  three.Mesh _wisps(int count, {required int order}) {
    final c = kStormWisps;
    const n = _wispSegments;
    three.BufferGeometry make(int total) {
      final rng = math.Random(6661);
      final pos = <double>[];
      final uv = <double>[];
      for (var k = 0; k < total; k++) {
        final th = rng.nextDouble() * math.pi * 2;
        final y0 = _d(c, 'yMin') + rng.nextDouble() * (_d(c, 'yMax') - _d(c, 'yMin'));
        final r0 = _d(c, 'rMin') + (_d(c, 'rMax') - _d(c, 'rMin')) * math.pow(rng.nextDouble(), 1.3);
        for (var j = 0; j < n; j++) {
          final s0 = j / n;
          final s1 = (j + 1) / n;
          for (final (s, side) in [(s0, -1.0), (s0, 1.0), (s1, 1.0), (s0, -1.0), (s1, 1.0), (s1, -1.0)]) {
            pos.addAll([th, y0, r0]);
            uv.addAll([s, side]);
          }
        }
      }
      return _instancedGeo(pos, uv, n * 6);
    }

    final geo = make(count * _particleScale);
    final show = _showUniform();
    final mat = _track(
      three.ShaderMaterial.fromMap({
        'uniforms': {
          'uWispTime': _uWispTime,
          'uShow': show,
          'uTime': _uTime,
          'uFlash': _uFlash,
          'uClear': _uClear,
          'uMist': _uMist,
          'uColor': _uHauntColor,
          'uAlpha': _uWispAlpha,
          'uFog': {'value': three.Vector2(_d(c, 'fogNear'), _d(c, 'fogFar'))},
          'uRInner': {'value': _d(c, 'rInner')},
          'uWidth': {'value': _d(c, 'width')},
          'uTrail': {'value': _d(c, 'trail')},
        },
        'vertexShader': kStormClearGlsl + kStormShowGlsl + kStormWispVertex,
        'fragmentShader': kStormFogGlsl + kStormWispFragment,
        'transparent': true,
        'depthWrite': false,
        'side': three.DoubleSide,
        'blending': three.AdditiveBlending,
      }),
      geo,
    );
    final mesh = three.Mesh(geo, mat)
      ..frustumCulled = false
      ..renderOrder = order;
    _counted['wisps'] = _Counted(geo, mesh, count, count * _particleScale, n * 6, show, make);
    return mesh;
  }

  /// Arenanın çevresinde savrulan, kameraya dönük yumuşak bulut parçaları.
  three.Mesh _scud(int count, {required int order}) {
    final c = kStormScud;
    three.BufferGeometry make(int n) {
      final rng = math.Random(31337);
      final pos = <double>[];
      final uv = <double>[];
      for (var k = 0; k < n; k++) {
        final th = rng.nextDouble() * math.pi * 2;
        final y0 = _d(c, 'yMin') + math.pow(rng.nextDouble(), 1.4) * (_d(c, 'yMax') - _d(c, 'yMin'));
        final r0 = _d(c, 'rMin') + (_d(c, 'rMax') - _d(c, 'rMin')) * rng.nextDouble();
        for (final (x, y) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]) {
          pos.addAll([th, y0, r0]);
          uv.addAll([x, y]);
        }
      }
      return _instancedGeo(pos, uv, 6);
    }

    final geo = make(count * _particleScale);
    final show = _showUniform();
    final mat = _track(
      three.ShaderMaterial.fromMap({
        'uniforms': {
          'uWindTime': _uScudTime,
          'uShow': show,
          'uTime': _uTime,
          'uStorm': _uStorm,
          'uHaunt': _uHauntAll,
          'uHauntColor': _uHauntColor,
          'uFlash': _uFlash,
          'uFlashA': _uFlashA,
          'uFlashB': _uFlashB,
          'uFlashRadius': _uFlashRadius,
          'uSkyFlash': _uSkyFlash,
          'uFogColor': _uFogColor,
          'uMist': _uMist,
          'uClear': _uClear,
          'uAlpha': _uScudAlpha,
          'uFog': {'value': three.Vector2(_d(c, 'fogNear'), _d(c, 'fogFar'))},
          'uSize': {'value': three.Vector2(_d(c, 'sizeMin'), _d(c, 'sizeMax'))},
          'uSpeed': {'value': _d(c, 'speed')},
          'uDeep': {'value': _rgb(c['deep']!.toInt())},
          'uBody': {'value': _rgb(c['body']!.toInt())},
          'uRim': {'value': _rgb(c['rim']!.toInt())},
        },
        'vertexShader': kStormClearGlsl + kStormShowGlsl + kStormScudVertex,
        'fragmentShader':
            _header(3, false) + kStormNoiseGlsl + kStormClearGlsl + kStormFogGlsl + kStormScudFragment,
        'transparent': true,
        'depthWrite': false,
        'side': three.DoubleSide,
      }),
      geo,
    );
    final mesh = three.Mesh(geo, mat)
      ..frustumCulled = false
      ..renderOrder = order;
    _counted['scud'] = _Counted(geo, mesh, count, count * _particleScale, 6, show, make);
    return mesh;
  }

  /// Girdapla birlikte dönerek düşen sağanak yağmur (kameraya dönük ince şeritler).
  three.Mesh _rain(int count, {required int order}) {
    final c = kStormRain;
    three.BufferGeometry make(int n) {
      final rng = math.Random(9090);
      final pos = <double>[];
      final uv = <double>[];
      for (var k = 0; k < n; k++) {
        final th = rng.nextDouble() * math.pi * 2;
        final rnd = rng.nextDouble();
        final r0 = _d(c, 'rMin') + (_d(c, 'rMax') - _d(c, 'rMin')) * math.pow(rng.nextDouble(), 1.3);
        for (final (a, s) in _quadCorners) {
          pos.addAll([th, rnd, r0]);
          uv.addAll([a, s]);
        }
      }
      return _instancedGeo(pos, uv, 6);
    }

    final geo = make(count * _particleScale);
    final show = _showUniform();
    final mat = _track(
      three.ShaderMaterial.fromMap({
        'uniforms': {
          'uRainTime': _uRainTime,
          'uShow': show,
          'uFlash': _uFlash,
          'uClear': _uClear,
          'uMist': _uMist,
          'uAlpha': _uRainAlpha,
          'uColor': {'value': _rgb(c['color']!.toInt())},
          'uFog': {'value': three.Vector2(_d(c, 'fogNear'), _d(c, 'fogFar'))},
          'uY': {'value': three.Vector2(_d(c, 'yMin'), _d(c, 'yMax'))},
          'uFall': {'value': _d(c, 'fall')},
          'uSwirl': {'value': _d(c, 'swirl')},
          'uLen': _uRainLen,
          'uWidth': {'value': _d(c, 'width')},
        },
        'vertexShader': kStormClearGlsl + kStormShowGlsl + kStormRainVertex,
        'fragmentShader': kStormFogGlsl + kStormRainFragment,
        'transparent': true,
        'depthWrite': false,
        'side': three.DoubleSide,
        'blending': three.AdditiveBlending,
      }),
      geo,
    );
    final mesh = three.Mesh(geo, mat)
      ..frustumCulled = false
      ..renderOrder = order;
    _counted['rain'] = _Counted(geo, mesh, count, count * _particleScale, 6, show, make);
    return mesh;
  }

  /// [vertsPer] köşeli örneklerden oluşan geometri; her köşe 'aIdx' özniteliğinde
  /// ait olduğu örneğin sırasını taşır (yumuşak sayı geçişi için).
  three.BufferGeometry _instancedGeo(List<double> pos, List<double> uv, int vertsPer) {
    final geo = three.BufferGeometry();
    final verts = pos.length ~/ 3;
    final idx = List<double>.generate(verts, (v) => (v ~/ vertsPer).toDouble());
    geo.setAttributeFromString('position', three.Float32BufferAttribute.fromList(pos, 3));
    geo.setAttributeFromString('uv', three.Float32BufferAttribute.fromList(uv, 2));
    geo.setAttributeFromString('aIdx', three.Float32BufferAttribute.fromList(idx, 1));
    geo.drawRange = {'start': 0, 'count': 0};
    return geo;
  }

  static Map<String, dynamic> _showUniform() => {'value': three.Vector2(0.0, 1.0)};

  static double _d(Map<String, num> c, String k) => c[k]!.toDouble();

  static three.Vector3 _rgb(int hex) => three.Vector3(
        ((hex >> 16) & 0xFF) / 255.0,
        ((hex >> 8) & 0xFF) / 255.0,
        (hex & 0xFF) / 255.0,
      );
}

enum _LayerKind { disc, ring, wall }

/// Bir bulut katmanının CPU tarafında biriken dönüş/akış fazı.
class _Layer {
  _Layer(this.config, this.kind)
      : spin = config['spin']!.toDouble(),
        flowRate = (config['inflow'] ?? config['rise'])!.toDouble();
  final Map<String, num> config;
  final _LayerKind kind;
  final double spin;
  final double flowRate;
  double rot = 0.0;
  double flow = 0.0;
  final Map<String, dynamic> uRot = {'value': 0.0};
  final Map<String, dynamic> uFlow = {'value': 0.0};
  final Map<String, dynamic> uHaunt = {'value': 0.0};

  /// Sis ayarının bu katmana etkisi: mist kazancı × (sis − 1).
  final Map<String, dynamic> uMistAmt = {'value': 0.0};
}

/// Çizilen örnek sayısı yoğunlukla değişen bir parçacık katmanı.
class _Counted {
  _Counted(this.geo, this.obj, this.base, this.max, this.vertsPer, this.uShow, this.make);
  three.BufferGeometry geo;
  final three.Object3D obj;

  /// Kalite ayarındaki temel örnek sayısı ve şu anki (büyütülmüş) kapasite.
  final int base;
  int max;
  final int vertsPer;

  /// Verilen örnek sayısıyla geometriyi üretir (aynı tohum: ilk örnekler aynı yerde).
  final three.BufferGeometry Function(int count) make;

  /// (görünen örnek sayısı, yumuşak geçiş bandı): shader'da aIdx ile karşılaştırılır.
  final Map<String, dynamic> uShow;
}

// ============================================================================
// KATMAN AYARLARI
// (Değerler önizleme aracında da aynen okunur; yalnızca sayı / hex sabitleri.)
// 'haunt': gizemli ışığın o katmandaki gücü.
// 'mist': fırtına sisi ayarının katmanı ne kadar koyulaştırdığı.
// 'densityBase' + 'densitySlope' × güç: katmanın saydamlık çarpanı.
// ============================================================================

const int kStormFogColor = 0x070E1A;

/// Sis koyulaştıkça her şeyin gömüldüğü, ışığı saçan açık gri-mavi pus.
/// (Gerçek sis ışığı saçar ve açık görünür; koyulaştıkça sahne kararmaz, puslanır.)
const int kStormHazeColor = 0x7A8BA2;

/// Tahtaya çöken yer sisi katmanları: (yükseklik, yoğunluk payı, tohum).
/// Sütun tepeleri 0,17..1,46 arasında: sis önce alçak kanatlarda birikir,
/// dozu arttıkça kral/kraliçe sütunlarına kadar yükselir.
const List<(double, double, double)> kGroundMistLayers = [
  (0.32, 0.80, 3.0),
  (0.85, 0.55, 11.0),
  (1.45, 0.32, 23.0),
];

/// Gizemli ışıltının ve ışık izlerinin rengi (soluk turkuaz-yeşil).
const int kStormHauntColor = 0x62F5C8;

/// En alttaki karanlık, yavaş dönen bulut okyanusu (zemin hissi).
const Map<String, num> kStormAbyss = {
  'y': -5.6,
  'spin': 0.020,
  'inflow': 0.006,
  'swirl': -1.6,
  'cells': 14,
  'arms': 2,
  'armAmt': 0.30,
  'stretch': 0.60,
  'cover': 0.10,
  'soft': 0.55,
  'alpha': 0.97,
  'densityBase': 0.95,
  'densitySlope': 0.03,
  'seed': 3.0,
  'r0': 0.0,
  'r1': 0.5,
  'r2': 80.0,
  'r3': 125.0,
  'deep': 0x03060C,
  'body': 0x0C1628,
  'rim': 0x1B2D48,
  'glow': 0x06131F,
  'glowReach': 16.0,
  'haunt': 1.0,
  'mist': 0.0,
  'fogNear': 30.0,
  'fogFar': 140.0,
};

/// Arenayı saran ana spiral bulut denizi.
const Map<String, num> kStormSea = {
  'y': -1.75,
  'spin': 0.07,
  'inflow': 0.016,
  'swirl': -2.3,
  'cells': 22,
  'arms': 3,
  'armAmt': 0.55,
  'stretch': 0.72,
  'cover': 0.34,
  'soft': 0.32,
  'alpha': 0.92,
  'densityBase': 0.9,
  'densitySlope': 0.08,
  'seed': 11.0,
  'r0': 8.6,
  'r1': 11.0,
  'r2': 70.0,
  'r3': 110.0,
  'deep': 0x0A1220,
  'body': 0x22344F,
  'rim': 0x7F9CC6,
  'glow': 0x164A6C,
  'glowReach': 7.0,
  'haunt': 0.55,
  'mist': 0.15,
  'fogNear': 22.0,
  'fogFar': 95.0,
};

/// Platformun dibinde en hızlı dönen ince sis kuşağı.
const Map<String, num> kStormEdgeMist = {
  'y': -0.42,
  'spin': 0.16,
  'inflow': 0.030,
  'swirl': -1.2,
  'cells': 34,
  'arms': 4,
  'armAmt': 0.45,
  'stretch': 0.30,
  'cover': 0.36,
  'soft': 0.36,
  'alpha': 0.55,
  'densityBase': 0.7,
  'densitySlope': 0.2,
  'seed': 23.0,
  'r0': 9.3,
  'r1': 10.8,
  'r2': 14.0,
  'r3': 21.0,
  'deep': 0x22385A,
  'body': 0x4A6A94,
  'rim': 0xB4D2F2,
  'glow': 0x2E8ABF,
  'glowReach': 3.5,
  'haunt': 0.9,
  'mist': 1.0,
  'fogNear': 26.0,
  'fogFar': 110.0,
};

/// Dış göz duvarı: yavaş, koyu, geniş.
const Map<String, num> kStormOuterWall = {
  'y': 17.0,
  'height': 46.0,
  'radiusBottom': 44.0,
  'radiusTop': 66.0,
  'spin': 0.04,
  'rise': 0.035,
  'twist': 0.06,
  'cells': 18,
  'vcells': 4.5,
  'cover': 0.26,
  'soft': 0.40,
  'alpha': 0.95,
  'densityBase': 0.88,
  'densitySlope': 0.1,
  'seed': 41.0,
  'fadeIn0': 0.0,
  'fadeIn1': 0.16,
  'fadeOut0': 0.78,
  'fadeOut1': 1.0,
  'deep': 0x060C17,
  'body': 0x16243A,
  'rim': 0x4E6C96,
  'glow': 0x0A1C2C,
  'haunt': 0.45,
  'mist': 0.0,
  'fogNear': 40.0,
  'fogFar': 160.0,
};

/// İç göz duvarı: hızlı dönen, yukarı tırmanan, şimşeklerin çıktığı duvar.
const Map<String, num> kStormInnerWall = {
  'y': 17.5,
  'height': 41.0,
  'radiusBottom': 30.0,
  'radiusTop': 50.0,
  'spin': 0.09,
  'rise': 0.060,
  'twist': 0.09,
  'cells': 16,
  'vcells': 5.0,
  'cover': 0.36,
  'soft': 0.34,
  'alpha': 0.90,
  'densityBase': 0.88,
  'densitySlope': 0.1,
  'seed': 57.0,
  'fadeIn0': 0.0,
  'fadeIn1': 0.14,
  'fadeOut0': 0.70,
  'fadeOut1': 0.98,
  'deep': 0x0A1424,
  'body': 0x26395A,
  'rim': 0x9FBDE4,
  'glow': 0x174666,
  'haunt': 0.6,
  'mist': 0.1,
  'fogNear': 40.0,
  'fogFar': 160.0,
};

/// Kuleler arasındaki bulut kuşakları (dıştan içe). Alt kenar bulut denizinden
/// (y ≈ -1.6) yükselir; güç arttıkça hızla koyulaşır.
const Map<String, num> kStormBelt1 = {
  'y': 7.4,
  'height': 18.0,
  'radiusBottom': 27.0,
  'radiusTop': 29.5,
  'spin': 0.06,
  'rise': 0.05,
  'twist': 0.10,
  'cells': 14,
  'vcells': 3.0,
  'cover': 0.34,
  'soft': 0.34,
  'alpha': 0.80,
  'densityBase': 0.10,
  'densitySlope': 0.50,
  'seed': 71.0,
  'fadeIn0': 0.0,
  'fadeIn1': 0.18,
  'fadeOut0': 0.62,
  'fadeOut1': 1.0,
  'deep': 0x0A1424,
  'body': 0x283D5E,
  'rim': 0xA3BFE6,
  'glow': 0x174A6A,
  'haunt': 0.7,
  'mist': 0.45,
  'fogNear': 30.0,
  'fogFar': 140.0,
};

const Map<String, num> kStormBelt2 = {
  'y': 5.9,
  'height': 15.0,
  'radiusBottom': 21.0,
  'radiusTop': 23.0,
  'spin': 0.08,
  'rise': 0.06,
  'twist': 0.12,
  'cells': 12,
  'vcells': 3.0,
  'cover': 0.38,
  'soft': 0.32,
  'alpha': 0.72,
  'densityBase': 0.08,
  'densitySlope': 0.48,
  'seed': 83.0,
  'fadeIn0': 0.0,
  'fadeIn1': 0.18,
  'fadeOut0': 0.60,
  'fadeOut1': 1.0,
  'deep': 0x0B1526,
  'body': 0x2A4062,
  'rim': 0xA9C4E8,
  'glow': 0x1A4E70,
  'haunt': 0.75,
  'mist': 0.45,
  'fogNear': 28.0,
  'fogFar': 130.0,
};

const Map<String, num> kStormBelt3 = {
  'y': 4.4,
  'height': 12.0,
  'radiusBottom': 15.5,
  'radiusTop': 16.8,
  'spin': 0.11,
  'rise': 0.07,
  'twist': 0.14,
  'cells': 10,
  'vcells': 2.6,
  'cover': 0.42,
  'soft': 0.30,
  'alpha': 0.62,
  'densityBase': 0.05,
  'densitySlope': 0.44,
  'seed': 97.0,
  'fadeIn0': 0.0,
  'fadeIn1': 0.20,
  'fadeOut0': 0.55,
  'fadeOut1': 1.0,
  'deep': 0x0C1728,
  'body': 0x2D4466,
  'rim': 0xB0CAEC,
  'glow': 0x1D527A,
  'haunt': 0.8,
  'mist': 0.4,
  'fogNear': 26.0,
  'fogFar': 120.0,
};

const Map<String, num> kStormBelt4 = {
  'y': 2.4,
  'height': 8.0,
  'radiusBottom': 12.2,
  'radiusTop': 12.9,
  'spin': 0.15,
  'rise': 0.08,
  'twist': 0.16,
  'cells': 8,
  'vcells': 2.2,
  'cover': 0.46,
  'soft': 0.30,
  'alpha': 0.52,
  'densityBase': 0.03,
  'densitySlope': 0.40,
  'seed': 109.0,
  'fadeIn0': 0.0,
  'fadeIn1': 0.22,
  'fadeOut0': 0.50,
  'fadeOut1': 1.0,
  'deep': 0x0E1A2C,
  'body': 0x30486A,
  'rim': 0xB8D0F0,
  'glow': 0x22587F,
  'haunt': 0.9,
  'mist': 0.35,
  'fogNear': 24.0,
  'fogFar': 110.0,
};

/// Savrulan yırtık bulut parçaları.
const Map<String, num> kStormScud = {
  'rMin': 11.5,
  'rMax': 34.0,
  'yMin': -1.0,
  'yMax': 11.0,
  'sizeMin': 2.6,
  'sizeMax': 6.5,
  'speed': 7.0,
  'alpha': 0.62,
  'deep': 0x0A1322,
  'body': 0x22344F,
  'rim': 0x9FBDE4,
  'fogNear': 26.0,
  'fogFar': 120.0,
};

/// Sağanak yağmur.
const Map<String, num> kStormRain = {
  'rMin': 11.0,
  'rMax': 42.0,
  'yMin': -1.6,
  'yMax': 20.0,
  'fall': 24.0,
  'swirl': 9.0,
  'length': 1.3,
  'width': 0.035,
  'alpha': 0.40,
  'color': 0xA9C8F0,
  'fogNear': 18.0,
  'fogFar': 80.0,
};

/// Girdaba savrulan rüzgâr izleri ('width': şeridin yarı genişliği).
const Map<String, num> kStormWind = {
  'rMin': 11.5,
  'rMax': 42.0,
  'rInner': 10.6,
  'yMin': -1.2,
  'yMax': 7.5,
  'speed': 15.0,
  'length': 2.2,
  'width': 0.022,
  'alpha': 0.30,
  'color': 0x9EC4F0,
  'fogNear': 24.0,
  'fogFar': 95.0,
};

/// Girdaba çekilen kuyruklu ışık izleri.
const Map<String, num> kStormWisps = {
  'rMin': 12.5,
  'rMax': 38.0,
  'rInner': 10.8,
  'yMin': -1.2,
  'yMax': 2.4,
  'width': 0.20,
  'trail': 0.07,
  'alpha': 0.75,
  'fogNear': 30.0,
  'fogFar': 110.0,
};

// ============================================================================
// GLSL
// ============================================================================

const String kStormVertexShader = r'''
varying vec3 vRel;
varying vec3 vWorld;
varying float vFogDepth;
void main() {
  vec4 wp = modelMatrix * vec4(position, 1.0);
  vWorld = wp.xyz;
  vRel = wp.xyz - modelMatrix[3].xyz;
  vec4 mv = viewMatrix * wp;
  vFogDepth = -mv.z;
  gl_Position = projectionMatrix * mv;
}
''';

/// Açısal yönde periyodik (dikişsiz) değer gürültüsü ve fbm.
/// `per` her zaman tam sayı olmalı; x ekseni `per` hücrede bir kendini tekrarlar.
const String kStormNoiseGlsl = r'''
#define TAU 6.28318530718
float stHash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
float stWrap(float x, float per) {
  return x - per * floor((x + 0.5) / per);
}
float stNoise(vec2 p, float per) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float x0 = stWrap(i.x, per);
  float x1 = stWrap(i.x + 1.0, per);
  float a = stHash(vec2(x0, i.y));
  float b = stHash(vec2(x1, i.y));
  float c = stHash(vec2(x0, i.y + 1.0));
  float d = stHash(vec2(x1, i.y + 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float stFbm(vec2 p, float per) {
  float v = 0.0;
  float amp = 0.5;
  for (int i = 0; i < STORM_OCT; i++) {
    v += amp * stNoise(p, per);
    p = p * 2.0 + vec2(3.0, 11.7);
    per *= 2.0;
    amp *= 0.5;
  }
  return v / (1.0 - 2.0 * amp);
}
float stFbm2(vec2 p, float per) {
  return stNoise(p, per) * 0.6667 + stNoise(p * 2.0 + vec2(1.0, 5.3), per * 2.0) * 0.3333;
}
float stSegDist(vec3 p, vec3 a, vec3 b) {
  vec3 ab = b - a;
  float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
  return length(p - a - ab * h);
}
''';

/// Fırtına sisi: katmanın sis aralığı `uMist.x` ile yaklaşır/uzaklaşır, en
/// yoğun karışım `uMist.y` kadar tam sise doğru artar.
const String kStormFogGlsl = r'''
uniform vec2 uMist;
float stFog(vec2 range, float depth, float maxMix) {
  return smoothstep(range.x * uMist.x, range.y * uMist.x, depth) * mix(maxMix, 1.0, uMist.y);
}
''';

/// Parçacık sayısının yumuşak geçişi: örneğin sırası (aIdx) görünen sayının
/// (uShow.x) çevresindeki bantta (uShow.y) ise kısmen saydamdır.
const String kStormShowGlsl = r'''
attribute float aIdx;
uniform vec2 uShow;
float stShow() {
  return clamp((uShow.x - aIdx) / uShow.y + 0.5, 0.0, 1.0);
}
''';

/// Tahta koruması: kameradan bir dünya noktasına giden ışın, nokta geçildikten
/// SONRA tahta disklerinden birine çarpıyorsa nokta tahtanın/taşların önündedir.
/// 1 = serbest, 0 = tahtayı örtüyor (şeffaflaştır).
const String kStormClearGlsl = r'''
uniform vec4 uClear;
float stPlaneCover(vec3 ro, vec3 rd, float dist, float py, float pr) {
  if (abs(rd.y) < 1e-4) return 0.0;
  float t = (py - ro.y) / rd.y;
  if (t <= dist) return 0.0;
  vec3 hit = ro + rd * t;
  // Düzlemin hemen üstünden altına geçerken yumuşak geçiş: yatay kesik çizgi oluşmaz.
  float behind = smoothstep(0.0, 1.5, t - dist);
  return (1.0 - smoothstep(pr, pr + 3.5, length(hit.xz))) * behind;
}
float stBoardClear(vec3 wp) {
  vec3 d = wp - cameraPosition;
  float dist = length(d);
  vec3 rd = d / max(dist, 1e-4);
  float c = max(stPlaneCover(cameraPosition, rd, dist, uClear.x, uClear.y),
                stPlaneCover(cameraPosition, rd, dist, uClear.z, uClear.w));
  return 1.0 - c;
}
''';

/// Yatay bulut katmanı (deniz / dip / kenar sisi): log-polar spiral akış.
///
/// Optimizasyon: Önce ucuz yoğunluk hesaplanır; parça görünmeyecek kadar
/// saydamsa (katkı < %0,2) pahalı hacim ışığı hesaplanmadan atılır. Şimşek
/// ve gizemli ışık hesapları yalnızca etkinken yapılır (uniform dalı, tutarlı).
const String kStormSeaFragment = r'''
uniform float uTime;
uniform float uWarp;
uniform float uStorm;
uniform float uRot;
uniform float uFlow;
uniform float uHaunt;
uniform float uMistAmt;
uniform vec3 uHauntColor;
uniform float uSwirl;
uniform float uCells;
uniform float uArms;
uniform float uArmAmt;
uniform float uStretch;
uniform float uCover;
uniform float uSoft;
uniform float uAlpha;
uniform vec2 uDensity;
uniform float uSeed;
uniform float uGlowReach;
uniform vec4 uRadii;
uniform vec3 uDeep;
uniform vec3 uBody;
uniform vec3 uRim;
uniform vec3 uGlow;
uniform vec3 uFogColor;
uniform vec2 uFog;
uniform float uFlash;
uniform float uFlashRadius;
uniform float uSkyFlash;
uniform vec3 uFlashA;
uniform vec3 uFlashB;
varying vec3 vRel;
varying vec3 vWorld;
varying float vFogDepth;

void main() {
  vec2 d = vRel.xz;
  float r = max(length(d), 1e-3);
  float radial = smoothstep(uRadii.x, uRadii.y, r) * (1.0 - smoothstep(uRadii.z, uRadii.w, r));
  if (radial < 0.003) discard;

  float storm = uStorm;
  // Elle girilen aşırı güçlerde desen biçimi doygunlaşır (sarmal aşırı sıkışıp titreşmez).
  float shape = min(storm, 3.6);
  float lr = log(r);
  // Spiral koordinat: sabit `turns` çizgileri girdap kollarıdır. Güç arttıkça kollar sıkılaşır.
  float swirl = uSwirl * (0.8 + 0.22 * shape);
  float turns = (atan(d.y, d.x) + swirl * lr + uRot) / TAU;
  vec2 sp = vec2(turns * uCells, (lr + uFlow) * uCells * uStretch / TAU + uSeed);

  // Zamanla akan domain warp: bulutlar katı dönmez, kaynar ve dağılır.
  float hp = uCells * 0.5;
  vec2 q = vec2(stFbm2(sp * 0.5 + vec2(0.0, uWarp * 0.06), hp),
                stFbm2(sp * 0.5 + vec2(4.0, 7.9 - uWarp * 0.045), hp));
  vec2 w = sp + (q - 0.5) * vec2(3.2, 2.2) * (0.8 + 0.22 * shape);
  float n = stFbm(w, uCells);

  float armAmt = clamp(uArmAmt + 0.12 * (shape - 1.0), 0.0, 0.9);
  float arm = 0.5 + 0.5 * cos(TAU * (turns * uArms + (q.y - 0.5) * 0.8));
  float dens = n * mix(1.0 - armAmt, 1.0, arm);
  float cover = uCover - 0.07 * clamp(storm - 1.0, -1.0, 1.6) - 0.06 * clamp(uMistAmt, 0.0, 2.5);
  float cov = smoothstep(cover, cover + uSoft, dens);
  float density = clamp((uDensity.x + uDensity.y * storm) * max(0.0, 1.0 + uMistAmt), 0.0, 1.3);

  // Gizemli ışık: bulutların derinliğinden sızan ışıltı. Nabız yavaş ve sığdır;
  // ışıltı bulutun içinde nefes alır, tamamen sönüp yeniden belirmez.
  float haunt = 0.0;
  if (uHaunt > 0.001) {
    float glint = smoothstep(0.56, 0.86, stNoise(sp * 0.5 + vec2(0.0, 17.0 + uWarp * 0.03), hp));
    float pulse = 0.72 + 0.28 * sin(uTime * 0.7 + q.x * 6.0);
    haunt = uHaunt * glint * pulse;
  }

  // Şimşek: kanal boyunca yerel aydınlanma
  float fl = 0.0;
  if (uFlash > 0.0005) {
    float fd = stSegDist(vWorld, uFlashA, uFlashB) / uFlashRadius;
    fl = uFlash * exp(-fd * fd);
  }

  // Işıltı ve şimşek yalnızca var olan bulutu aydınlatır; boşlukta beliren
  // ve kaybolan hayalet bulut lekeleri oluşturmaz.
  float body = smoothstep(0.0, 0.45, cov);
  float alpha = cov * uAlpha * density + haunt * 0.30 * body;
  if (alpha * radial < 0.002) discard;

#if STORM_LIT
  // Göze (merkeze) bakan bulut kenarları aydınlanır: sahte hacim ışığı.
  float n2 = stFbm(w - vec2(0.0, 0.32), uCells);
  float lit = clamp((n - n2) * 2.2 + 0.5, 0.0, 1.0);
#else
  float lit = clamp((n - 0.30) * 1.4, 0.0, 1.0);
#endif

  vec3 col = mix(uDeep, uBody, smoothstep(0.1, 0.9, cov));
  // Gölgede kalan oyuklar kararır, ışığa dönük kabarıklar parlar.
  col *= mix(0.62, 1.15, lit);
  col *= 1.0 - 0.12 * clamp(storm - 1.0, 0.0, 2.0);
  col = mix(col, uRim, lit * lit * smoothstep(0.35, 1.0, cov) * (0.6 + 0.12 * shape));
  float glow = exp(-max(r - uRadii.y, 0.0) / uGlowReach);
  col += uGlow * glow * (0.3 + 0.7 * lit);

  col = mix(col, col * vec3(0.86, 0.82, 1.12), min(uHaunt * 0.6, 0.75));
  col += uHauntColor * haunt * (0.25 + 0.75 * (1.0 - cov * 0.7));

  // Şimşek + tüm gökyüzünün parlaması
  col += vec3(0.60, 0.78, 1.0) * (fl * (0.35 + lit) + uSkyFlash * (0.20 + 0.60 * lit) * cov);

  col = mix(col, uFogColor, stFog(uFog, vFogDepth, 0.92));
  gl_FragColor = vec4(col, clamp(alpha * radial, 0.0, 1.0));
}
''';

/// Göz duvarı ve bulut kuşakları: dönen + yukarı tırmanan helezonik bulut duvarı.
const String kStormWallFragment = r'''
uniform float uTime;
uniform float uWarp;
uniform float uStorm;
uniform float uRot;
uniform float uFlow;
uniform float uHaunt;
uniform float uMistAmt;
uniform vec3 uHauntColor;
uniform float uTwist;
uniform float uCells;
uniform float uVCells;
uniform float uCover;
uniform float uSoft;
uniform float uAlpha;
uniform vec2 uDensity;
uniform float uSeed;
uniform vec2 uHeight;
uniform vec4 uVFade;
uniform vec3 uDeep;
uniform vec3 uBody;
uniform vec3 uRim;
uniform vec3 uGlow;
uniform vec3 uFogColor;
uniform vec2 uFog;
uniform float uFlash;
uniform float uFlashRadius;
uniform float uSkyFlash;
uniform vec3 uFlashA;
uniform vec3 uFlashB;
varying vec3 vRel;
varying vec3 vWorld;
varying float vFogDepth;

void main() {
  float hn = clamp((vRel.y - uHeight.x) / (uHeight.y - uHeight.x), 0.0, 1.0);
  float vf = smoothstep(uVFade.x, uVFade.y, hn) * (1.0 - smoothstep(uVFade.z, uVFade.w, hn));
  float density = clamp((uDensity.x + uDensity.y * uStorm) * max(0.0, 1.0 + uMistAmt), 0.0, 1.3);
  float clearMask = stBoardClear(vWorld);
  if (vf * density * clearMask < 0.003) discard;

  float storm = uStorm;
  float shape = min(storm, 3.6);
  float turns = (atan(vRel.z, vRel.x) + uRot) / TAU + hn * uTwist * (0.7 + 0.35 * shape);
  vec2 sp = vec2(turns * uCells, hn * uVCells - uFlow + uSeed);

  float hp = uCells * 0.5;
  vec2 q = vec2(stFbm2(sp * 0.5 + vec2(0.0, -uWarp * 0.05), hp),
                stFbm2(sp * 0.5 + vec2(6.0, 3.7 + uWarp * 0.04), hp));
  vec2 w = sp + (q - 0.5) * vec2(2.6, 2.4) * (0.8 + 0.22 * shape);
  float n = stFbm(w, uCells);

  float billow = 0.80 + 0.30 * sin(hn * 3.14159);
  float dens = n * billow;
  float cover = uCover - 0.06 * clamp(storm - 1.0, -1.0, 1.6) - 0.06 * clamp(uMistAmt, 0.0, 2.5);
  float cov = smoothstep(cover, cover + uSoft, dens);

  // Gizemli ışık: duvarın içinde yükselen, yavaşça nefes alan ışıltılar
  float haunt = 0.0;
  if (uHaunt > 0.001) {
    float glint = smoothstep(0.58, 0.86, stNoise(sp * 0.5 + vec2(0.0, 9.0 + uWarp * 0.04), hp));
    float pulse = 0.72 + 0.28 * sin(uTime * 0.6 + q.y * 6.0);
    haunt = uHaunt * glint * pulse;
  }

  float fl = 0.0;
  if (uFlash > 0.0005) {
    float fd = stSegDist(vWorld, uFlashA, uFlashB) / (uFlashRadius * 1.3);
    fl = uFlash * exp(-fd * fd);
  }

  // Işıltı ve şimşek yalnızca var olan bulutu aydınlatır (boşlukta bulut belirmez).
  float alpha = cov * uAlpha * density + haunt * 0.22 * density * smoothstep(0.0, 0.45, cov);
  float mask = vf * clearMask;
  if (alpha * mask < 0.002) discard;

#if STORM_LIT
  // Işık yukarıdan (gözün açıklığından) gelir.
  float n2 = stFbm(w + vec2(0.0, 0.30), uCells);
  float lit = clamp((n - n2) * 2.4 + 0.5, 0.0, 1.0);
#else
  float lit = clamp((n - 0.30) * 1.4, 0.0, 1.0);
#endif
  lit *= mix(0.55, 1.0, hn);

  vec3 col = mix(uDeep, uBody, smoothstep(0.1, 0.9, cov) * mix(0.6, 1.0, hn));
  col *= mix(0.62, 1.15, lit);
  col *= 1.0 - 0.12 * clamp(storm - 1.0, 0.0, 2.0);
  col = mix(col, uRim, lit * lit * smoothstep(0.35, 1.0, cov) * (0.65 + 0.12 * shape));
  col += uGlow * (1.0 - smoothstep(0.0, 0.35, hn)) * (0.3 + 0.7 * lit);

  col = mix(col, col * vec3(0.86, 0.82, 1.12), min(uHaunt * 0.6, 0.75));
  col += uHauntColor * haunt * (0.3 + 0.7 * (1.0 - cov * 0.6));

  col += vec3(0.60, 0.78, 1.0) * (fl * (0.35 + lit) + uSkyFlash * (0.20 + 0.60 * lit) * cov);

  col = mix(col, uFogColor, stFog(uFog, vFogDepth, 0.85));
  gl_FragColor = vec4(col, clamp(alpha * mask, 0.0, 1.0));
}
''';

/// Rüzgâr izleri: her şerit kendi spiral yörüngesinde içe savrulur ve yeniden
/// doğar. Baş ve kuyruk noktası hesaplanıp aradaki şerit kameraya döndürülür.
/// position = (başlangıç açısı, yükseklik, yarıçap), uv = (0 baş / 1 kuyruk, kenar ±1)
const String kStormWindVertex = r'''
uniform float uTime;
uniform float uSpeed;
uniform float uLen;
uniform float uWidth;
uniform float uRInner;
varying vec2 vUv;
varying float vFade;
varying float vFogDepth;

float wnHash(vec3 p) {
  return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void main() {
  float th0 = position.x;
  float y0 = position.y;
  float r0 = position.z;
  float along = uv.x;
  float rnd = wnHash(position);

  float life = 3.0 + rnd * 3.5;
  float ph = fract(uTime / life + rnd * 17.0);
  float rIn = max(r0 * 0.62, uRInner);
  float r = mix(r0, rIn, ph * ph);
  float speed = uSpeed * (0.75 + rnd * 0.6);
  float th = th0 - speed / mix(r0, rIn, 0.5) * ph * life;
  float y = y0 + ph * (1.0 + rnd * 2.5) + sin(uTime * 1.3 + rnd * 40.0) * 0.35;

  // Kuyruk, hareket yönünün gerisinde kalır.
  float thT = th + uLen * (0.6 + rnd * 0.8) / r;
  vec3 head = vec3(cos(th) * r, y, sin(th) * r);
  vec3 tail = vec3(cos(thT) * r, y + 0.12, sin(thT) * r);

  vec4 mvH = modelViewMatrix * vec4(head, 1.0);
  vec4 mvT = modelViewMatrix * vec4(tail, 1.0);
  vec2 dir = mvH.xy - mvT.xy;
  float dl = length(dir);
  dir = dl > 1e-5 ? dir / dl : vec2(1.0, 0.0);
  vec2 perp = vec2(-dir.y, dir.x);
  vec4 mv = mix(mvH, mvT, along);
  mv.xy += perp * uv.y * uWidth * (1.0 - along * 0.6);

  vFogDepth = -mv.z;
  vFade = sin(ph * 3.14159) * stBoardClear((modelMatrix * vec4(mix(head, tail, along), 1.0)).xyz) * stShow();
  vUv = uv;
  gl_Position = projectionMatrix * mv;
}
''';

const String kStormWindFragment = r'''
uniform vec3 uColor;
uniform float uAlpha;
uniform float uFlash;
uniform vec3 uFogColor;
uniform vec2 uFog;
varying vec2 vUv;
varying float vFade;
varying float vFogDepth;
void main() {
  float across = 1.0 - abs(vUv.y);
  float soft = across * across * (3.0 - 2.0 * across);
  float along = 1.0 - vUv.x;
  float f = 1.0 - stFog(uFog, vFogDepth, 1.0);
  // Şimşek izleri yalnızca hafifçe parlatır (izler flaşla belirip kaybolmaz).
  vec3 c = uColor + vec3(0.5, 0.65, 0.8) * min(uFlash, 1.5) * 0.2;
  gl_FragColor = vec4(c * vFade * along * soft * uAlpha * f * 0.9, 1.0);
}
''';

/// Işık izleri: spiral çizerek içe ve yukarı çekilen, kameraya dönük kuyruklu şeritler.
/// position = (başlangıç açısı, yükseklik, yarıçap), uv = (kuyruk boyunca 0..1, kenar ±1)
const String kStormWispVertex = r'''
uniform float uWispTime;
uniform float uTime;
uniform float uRInner;
uniform float uWidth;
uniform float uTrail;
varying vec2 vUv;
varying float vFade;
varying float vFogDepth;

float wpHash(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 wispAt(float ph, float th0, float y0, float r0, float rnd) {
  float rEnd = max(r0 * 0.5, uRInner);
  float e = ph * ph * (3.0 - 2.0 * ph);
  float r = mix(r0, rEnd, e);
  float th = th0 - (0.9 + rnd * 0.8) * 6.28318 * ph;
  float y = y0 + ph * (1.0 + rnd * 1.8) + sin(ph * 12.566 + rnd * 6.283) * (0.3 + rnd * 0.4);
  return vec3(cos(th) * r, y, sin(th) * r);
}

void main() {
  float th0 = position.x;
  float y0 = position.y;
  float r0 = position.z;
  float rnd = wpHash(position.xz);
  float s = uv.x;
  float side = uv.y;

  float life = 10.0 + rnd * 8.0;
  float ph = fract(uWispTime / life + rnd * 7.31);
  float phs = max(ph - s * uTrail, 0.0);
  vec3 p = wispAt(phs, th0, y0, r0, rnd);
  vec3 p2 = wispAt(phs + 0.004, th0, y0, r0, rnd);

  vec4 mv = modelViewMatrix * vec4(p, 1.0);
  vec4 mv2 = modelViewMatrix * vec4(p2, 1.0);
  vec2 dir = mv2.xy - mv.xy;
  float dl = length(dir);
  dir = dl > 1e-5 ? dir / dl : vec2(1.0, 0.0);
  vec2 perp = vec2(-dir.y, dir.x);
  float w = uWidth * (1.0 - s * 0.75) * (0.7 + rnd * 0.6);
  mv.xy += perp * side * w;

  vFogDepth = -mv.z;
  // Yavaş ve yumuşak nabız (hızlı kırpışma yerine): izler düzensiz yanıp sönmez.
  float flick = 0.86 + 0.14 * sin(uTime * (1.6 + rnd * 1.2) + rnd * 40.0);
  vFade = smoothstep(0.0, 0.08, ph) * (1.0 - smoothstep(0.86, 1.0, ph)) * flick
        * step(0.0, ph - s * uTrail) * stBoardClear((modelMatrix * vec4(p, 1.0)).xyz) * stShow();
  vUv = vec2(s, side);
  gl_Position = projectionMatrix * mv;
}
''';

const String kStormWispFragment = r'''
uniform vec3 uColor;
uniform float uAlpha;
uniform float uFlash;
uniform vec2 uFog;
varying vec2 vUv;
varying float vFade;
varying float vFogDepth;
void main() {
  float across = 1.0 - abs(vUv.y);
  float soft = across * across * (3.0 - 2.0 * across);
  float along = 1.0 - vUv.x;
  float head = smoothstep(0.82, 1.0, along);
  float a = soft * (along * along * 0.7 + head * 0.95) * vFade * uAlpha;
  float f = 1.0 - stFog(uFog, vFogDepth, 0.8);
  vec3 c = mix(uColor, vec3(0.92, 1.0, 1.0), head * soft * 0.5) + vec3(0.4, 0.5, 0.7) * min(uFlash, 1.5) * 0.12;
  gl_FragColor = vec4(c * a * f, 1.0);
}
''';

/// Yırtık bulut parçaları: arenanın çevresinde savrulan kameraya dönük kümeler.
/// position = (başlangıç açısı, yükseklik, yarıçap), uv = köşe (-1..1)
const String kStormScudVertex = r'''
uniform float uWindTime;
uniform float uSpeed;
uniform vec2 uSize;
varying vec2 vUv;
varying float vRnd;
varying float vShow;
varying vec3 vWorld;
varying float vFogDepth;

float scHash(vec2 p) {
  return fract(sin(dot(p, vec2(41.31, 289.17))) * 15731.743);
}

void main() {
  float th0 = position.x;
  float y0 = position.y;
  float r0 = position.z;
  float rnd = scHash(position.xz + position.y);
  float r = r0 + sin(uWindTime * 0.13 + rnd * 40.0) * 2.0;
  float th = th0 - uWindTime * uSpeed * (0.7 + rnd * 0.6) / r;
  float y = y0 + sin(uWindTime * 0.21 + rnd * 17.0) * 0.8;
  vec3 center = (modelMatrix * vec4(cos(th) * r, y, sin(th) * r, 1.0)).xyz;

  // Kameraya dönük, hareket yönünde biraz uzatılmış bulut kümesi
  vec3 right = vec3(viewMatrix[0][0], viewMatrix[1][0], viewMatrix[2][0]);
  vec3 up = vec3(viewMatrix[0][1], viewMatrix[1][1], viewMatrix[2][1]);
  float size = mix(uSize.x, uSize.y, rnd);
  vec3 wp = center + right * uv.x * size * 1.5 + up * uv.y * size * 0.8;

  vUv = uv;
  vRnd = rnd;
  vShow = stShow();
  vWorld = wp;
  vec4 mv = viewMatrix * vec4(wp, 1.0);
  vFogDepth = -mv.z;
  gl_Position = projectionMatrix * mv;
}
''';

const String kStormScudFragment = r'''
uniform float uWindTime;
uniform float uTime;
uniform float uStorm;
uniform float uAlpha;
uniform float uHaunt;
uniform vec3 uHauntColor;
uniform vec3 uDeep;
uniform vec3 uBody;
uniform vec3 uRim;
uniform float uFlash;
uniform float uFlashRadius;
uniform float uSkyFlash;
uniform vec3 uFlashA;
uniform vec3 uFlashB;
uniform vec3 uFogColor;
uniform vec2 uFog;
varying vec2 vUv;
varying float vRnd;
varying float vShow;
varying vec3 vWorld;
varying float vFogDepth;

void main() {
  float edge = 1.0 - smoothstep(0.72, 1.0, max(abs(vUv.x), abs(vUv.y)));
  // Tahta koruması parça başına: bulut tahtanın önünden geçerken yalnızca
  // tahtayla örtüşen kısmı yumuşakça saydamlaşır (bulut topluca kaybolmaz).
  float mask = stBoardClear(vWorld) * vShow;
  if (edge * mask < 0.01) discard;
  vec2 p = vUv;
  vec2 o = vec2(vRnd * 91.0, vRnd * 37.0) + vec2(uWindTime * 0.08, 0.0);
  float n = stNoise(p * 2.2 + o, 997.0) * 0.6 + stNoise(p * 4.7 + o * 1.7, 997.0) * 0.3
          + stNoise(p * 9.3 + o * 2.3, 997.0) * 0.1;
  float d = length(p) + (n - 0.5) * 0.75;
  float shape = (1.0 - smoothstep(0.30, 0.90, d)) * edge;
  if (shape * mask < 0.01) discard;

  float lit = clamp(0.5 + vUv.y * 0.45 + (n - 0.5) * 0.8, 0.0, 1.0);
  vec3 col = mix(uDeep, uBody, shape);
  col *= mix(0.6, 1.15, lit);
  col = mix(col, uRim, lit * lit * shape * 0.45);
  col += uHauntColor * uHaunt * smoothstep(0.55, 0.8, n) * 0.25 * (0.78 + 0.22 * sin(uTime * 0.8 + vRnd * 30.0));

  float fl = 0.0;
  if (uFlash > 0.0005) {
    float fd = stSegDist(vWorld, uFlashA, uFlashB) / (uFlashRadius * 1.2);
    fl = uFlash * exp(-fd * fd);
  }
  col += vec3(0.60, 0.78, 1.0) * (fl * (0.4 + lit) + uSkyFlash * (0.25 + 0.6 * lit));

  col = mix(col, uFogColor, stFog(uFog, vFogDepth, 0.85));
  gl_FragColor = vec4(col, clamp(shape * uAlpha * mask, 0.0, 1.0));
}
''';

/// Sağanak: her damla girdapla birlikte döner ve düşer; hız yönünde kameraya
/// dönük ince bir şerit olarak çizilir. position = (açı, rastgele, yarıçap),
/// uv = (0 baş / 1 kuyruk, kenar ±1)
const String kStormRainVertex = r'''
uniform float uRainTime;
uniform vec2 uY;
uniform float uFall;
uniform float uSwirl;
uniform float uLen;
uniform float uWidth;
varying float vA;
varying float vSide;
varying float vFogDepth;

void main() {
  float th0 = position.x;
  float rnd = position.y;
  float r0 = position.z;
  float along = uv.x;
  float span = uY.y - uY.x;

  float y = uY.y - mod(uRainTime * uFall * (0.8 + rnd * 0.4) + rnd * span * 7.0, span);
  float th = th0 - uRainTime * uSwirl * (0.7 + rnd * 0.6) / r0;
  vec3 head = vec3(cos(th) * r0, y, sin(th) * r0);
  vec3 tang = vec3(sin(th), 0.0, -cos(th));
  vec3 vel = normalize(vec3(0.0, -uFall, 0.0) + tang * uSwirl * 1.6);
  vec3 tail = head - vel * uLen * (0.7 + rnd * 0.6);

  vec4 mvHead = modelViewMatrix * vec4(head, 1.0);
  vec4 mvTail = modelViewMatrix * vec4(tail, 1.0);
  vec2 dir = mvHead.xy - mvTail.xy;
  float dl = length(dir);
  dir = dl > 1e-5 ? dir / dl : vec2(0.0, 1.0);
  vec2 perp = vec2(-dir.y, dir.x);
  vec4 mv = mix(mvHead, mvTail, along);
  mv.xy += perp * uv.y * uWidth;

  float edge = smoothstep(uY.x, uY.x + 1.5, y) * (1.0 - smoothstep(uY.y - 3.0, uY.y, y));
  vA = edge * (1.0 - along * 0.75) * stBoardClear((modelMatrix * vec4(mix(head, tail, along), 1.0)).xyz) * stShow();
  vSide = uv.y;
  vFogDepth = -mv.z;
  gl_Position = projectionMatrix * mv;
}
''';

const String kStormRainFragment = r'''
uniform vec3 uColor;
uniform float uAlpha;
uniform float uFlash;
uniform vec2 uFog;
varying float vA;
varying float vSide;
varying float vFogDepth;
void main() {
  float soft = 1.0 - abs(vSide);
  float f = 1.0 - stFog(uFog, vFogDepth, 1.0);
  // Yağmur her zaman görünür; şimşek onu yalnızca biraz parlatır
  // (eskiden 2,5 kat parlayıp sönmesi yağmuru "bir var bir yok" gösteriyordu).
  vec3 c = uColor * (1.0 + min(uFlash, 1.5) * 0.45);
  gl_FragColor = vec4(c * vA * soft * uAlpha * f, 1.0);
}
''';

/// Gotik kuleler: koyu fırtına taşı, göze bakan yüzlerde yumuşak ışık, kenar
/// ışığı, şimşekte parlama, sis ve gizemli kenar parıltısı.
const String kStormTowerVertex = r'''
varying vec3 vN;
varying vec3 vWorld;
varying float vFogDepth;
void main() {
  vec4 wp = modelMatrix * vec4(position, 1.0);
  vWorld = wp.xyz;
  vN = normalize(mat3(modelMatrix) * normal);
  vec4 mv = viewMatrix * wp;
  vFogDepth = -mv.z;
  gl_Position = projectionMatrix * mv;
}
''';

const String kStormTowerFragment = r'''
uniform vec3 uColor;
uniform vec3 uRimColor;
uniform float uTime;
uniform float uHaunt;
uniform vec3 uHauntColor;
uniform float uFlash;
uniform float uFlashRadius;
uniform float uSkyFlash;
uniform vec3 uFlashA;
uniform vec3 uFlashB;
uniform vec3 uFogColor;
uniform vec2 uFog;
varying vec3 vN;
varying vec3 vWorld;
varying float vFogDepth;
void main() {
  vec3 n = normalize(vN);
  vec3 v = normalize(cameraPosition - vWorld);
  float rim = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.5);
  vec3 toEye = normalize(vec3(-vWorld.x, 2.0, -vWorld.z));
  float eye = clamp(dot(n, toEye), 0.0, 1.0);
  float up = n.y * 0.5 + 0.5;
  float h = clamp((vWorld.y + 1.5) / 22.0, 0.0, 1.0);
  float grain = stNoise(vWorld.xz * 1.7 + vec2(vWorld.y * 2.3, 0.0), 997.0);
  vec3 col = uColor * (0.5 + 0.7 * eye + 0.25 * up) * mix(0.8, 1.25, h) * (0.85 + 0.3 * grain);
  col += uRimColor * rim * (0.22 + 0.25 * h);

  if (uFlash > 0.0005 || uSkyFlash > 0.0005) {
    float fd = stSegDist(vWorld, uFlashA, uFlashB) / (uFlashRadius * 1.6);
    float fl = uFlash * exp(-fd * fd);
    col += vec3(0.70, 0.85, 1.0) * (fl * (0.3 + 0.9 * eye + rim) + uSkyFlash * (0.2 + 0.5 * eye + 0.5 * rim));
  }
  col += uHauntColor * uHaunt * rim * (0.25 + 0.2 * sin(uTime * 1.4 + vWorld.y * 0.4));

  col = mix(col, uFogColor, stFog(uFog, vFogDepth, 0.8));
  gl_FragColor = vec4(col, 1.0);
}
''';

/// Yer sisi: tahtanın üstünde ağır ağır sürüklenen, kendi içinde kabaran
/// yatay sis tabakası. Rengi sahnenin sis rengidir (açık gri-mavi pus);
/// şimşek çaktığında sis içten aydınlanır.
const String kGroundMistFragment = r'''
uniform float uTime;
uniform float uGround;
uniform float uLayer;
uniform float uSeed;
uniform vec3 uFogColor;
uniform float uFlash;
uniform float uFlashRadius;
uniform float uSkyFlash;
uniform vec3 uFlashA;
uniform vec3 uFlashB;
varying vec3 vRel;
varying vec3 vWorld;
varying float vFogDepth;

void main() {
  float amt = uGround * uLayer;
  if (amt < 0.002) discard;
  float r = length(vRel.xz);
  // Platformun dışına doğru incelir; girdabın kenar sisiyle birleşir.
  float edge = 1.0 - smoothstep(12.0, 17.0, r);
  if (edge < 0.002) discard;

  // Girdapla birlikte çok yavaş dönen ve sürüklenen iki ölçekli sis kümeleri
  float a = uTime * 0.02 + uSeed;
  mat2 rot = mat2(cos(a), -sin(a), sin(a), cos(a));
  vec2 p = rot * vRel.xz * 0.24 + vec2(uSeed * 1.7, uSeed * 0.9) + vec2(uTime * 0.045, -uTime * 0.03);
  float n = stFbm(p, 512.0);
  float n2 = stFbm(p * 0.42 + vec2(7.0, 2.0) - vec2(uTime * 0.018), 512.0);
  float cloud = smoothstep(0.22, 0.82, n * 0.6 + n2 * 0.55);

  float alpha = amt * edge * mix(0.40, 1.0, cloud);
  vec3 col = uFogColor * (1.06 + 0.10 * cloud) + vec3(0.015, 0.02, 0.03);

  // Şimşek sisin içinden parlar
  if (uFlash > 0.0005 || uSkyFlash > 0.0005) {
    float fd = stSegDist(vWorld, uFlashA, uFlashB) / (uFlashRadius * 1.6);
    float fl = uFlash * exp(-fd * fd);
    col += vec3(0.55, 0.72, 1.0) * (fl * 0.35 + uSkyFlash * 0.45);
  }
  gl_FragColor = vec4(col, clamp(alpha, 0.0, 1.0));
}
''';
