import 'dart:math' as math;

import 'package:three_js/three_js.dart' as three;

import '../game/chess_game.dart';
import '../game/hex_board.dart';
import 'battle_fx.dart';
import 'sculptor.dart';

/// Karanlık-fantezi ordu renk paleti (gerçekçi dövme çelik, deri, kumaş, cilt ve pul tonları).
class Palette {
  const Palette({
    required this.armor,
    required this.armorDark,
    required this.metal,
    required this.steel,
    required this.steelEdge,
    required this.glow,
    required this.cloth,
    required this.clothDark,
    required this.skin,
    required this.dark,
    required this.hair,
    required this.fur,
    required this.leather,
    required this.wood,
    required this.scale,
    required this.belly,
    required this.membrane,
    required this.horn,
    required this.hornBase,
    required this.giantSkin,
    required this.queenSkin,
    required this.dress,
    required this.cape,
    required this.capeLining,
    required this.fire,
    required this.fireCore,
    required this.blood,
    required this.stone,
  });

  final int armor, armorDark, metal, steel, steelEdge, glow;
  final int cloth, clothDark, skin, dark, hair, fur, leather, wood;
  final int scale, belly, membrane, horn, hornBase;
  final int giantSkin, queenSkin, dress, cape, capeLining;
  final int fire, fireCore, blood, stone;

  /// Gümüş Şafak Lejyonu (Beyaz Ordu): fırçalanmış çelik, antik altın, gece safiri, fildişi pullar.
  static const white = Palette(
    armor: 0xC8D0DC,
    armorDark: 0x6E788B,
    metal: 0xCE9B3B,
    steel: 0xBAC4D2,
    steelEdge: 0xEFF5FF,
    glow: 0x4AD8FF,
    cloth: 0x1E3F78,
    clothDark: 0x102447,
    skin: 0xCE9874,
    dark: 0x1E2330,
    hair: 0xB88434,
    fur: 0xBEB5A4,
    leather: 0x5E3B22,
    wood: 0x54361F,
    scale: 0xD5CCBA,
    belly: 0xBA9352,
    membrane: 0x94643A,
    horn: 0xEDE0C4,
    hornBase: 0x75634B,
    giantSkin: 0xB8896C,
    queenSkin: 0xE6D1C8,
    dress: 0xCEC9D8,
    cape: 0xD4CFE0,
    // Vurgu renkleri gece safiri: kırmızı Siyah ordunun (Kızıl Obsidyen) imzasıdır;
    // Beyaz Vezir'in etek/pelerin/yaka kadifesi ve Beyaz saldırı kıvılcımları onunla karışmaz.
    capeLining: 0x22408C,
    fire: 0xFFAE34,
    fireCore: 0xC4F4FF,
    blood: 0x2F6BDF,
    stone: 0x666E7B,
  );

  /// Kızıl Obsidyen Ordusu (Siyah Ordu): karartılmış Şam çeliği, kızıl kadife, kor ve bazalt.
  static const black = Palette(
    armor: 0x313542,
    armorDark: 0x1A1D26,
    metal: 0xA87C46,
    steel: 0x666D7C,
    steelEdge: 0xB8C2D4,
    glow: 0xFF4232,
    cloth: 0x681222,
    clothDark: 0x360711,
    skin: 0xA48472,
    dark: 0x13151D,
    hair: 0x1E1A22,
    fur: 0x3A2921,
    leather: 0x332019,
    wood: 0x2E1C14,
    scale: 0x2B2436,
    belly: 0x6D1E2C,
    membrane: 0x7A1B29,
    horn: 0xC8B79C,
    hornBase: 0x3D322A,
    giantSkin: 0x856A5C,
    queenSkin: 0xD8C9CC,
    dress: 0x1E1526,
    cape: 0x24172E,
    capeLining: 0x8E1024,
    fire: 0xFF5220,
    fireCore: 0xFFE26A,
    blood: 0xAA1226,
    stone: 0x3A363C,
  );

  /// Zümrüt Fırtına Lejyonu (3. Ordu): zümrüt kakmalı antik bronz-çelik, antik altın ve yeşim ateşi.
  static const emerald = Palette(
    armor: 0x265244,
    armorDark: 0x132C24,
    metal: 0xD8A848,
    steel: 0x8CA89E,
    steelEdge: 0xDCF7EC,
    glow: 0x2EE88A,
    cloth: 0x145A46,
    clothDark: 0x0A3025,
    skin: 0xC4906E,
    dark: 0x101E1A,
    hair: 0x8E3C22,
    fur: 0x5A4634,
    leather: 0x4A301E,
    wood: 0x3E2819,
    scale: 0x245846,
    belly: 0xB89448,
    membrane: 0x1D6E52,
    horn: 0xE6D8B8,
    hornBase: 0x584A38,
    giantSkin: 0xAE8266,
    queenSkin: 0xDFD4CE,
    dress: 0x16382E,
    cape: 0x194236,
    capeLining: 0xB88A32,
    fire: 0x2CE878,
    fireCore: 0xE2FF9E,
    blood: 0x22C87A,
    stone: 0x384A44,
  );

  static Palette of(Team t) => switch (t) {
        Team.white => white,
        Team.black => black,
        Team.emerald => emerald,
      };
}

/// Hareketli eklemlere (bacak, gövde, kol, baş, kanat, çene, pelerin…) erişim sağlayan 3B savaşçı iskeleti.
class CreatureRig {
  CreatureRig(this.kind, this.team) {
    root.add(body);
    if (kind == PieceType.rook) {
      body.scale.setValues(2.0, 2.0, 2.0);
    }
  }

  /// Karakter temel ölçeği (Kadın Savaş Devi 2 kat heybetli titan boyutundadır).
  double get baseScale => kind == PieceType.rook ? 2.0 : 1.0;

  final PieceType kind;
  final Team team;

  final three.Group root = three.Group();
  final three.Group body = three.Group();
  final Map<String, three.Object3D> parts = {};
  final Map<String, double> rest = {};
  final Map<String, double> boardRest = {};
  final List<three.Group> orbiters = [];
  final double phase = math.Random().nextDouble() * math.pi * 2;

  double facing = 0;
  bool busy = false;
  bool dying = false;
  bool inPov = false;

  three.Object3D? operator [](String name) => parts[name];

  double get defaultFacing => team == Team.white ? math.pi : 0.0;

  double defaultFacingFor(BoardVariant variant) =>
      team.defaultFacingFor(variant);

  /// Birinci şahıs (POV) kamerası için gövdeye göre gerçek anatomik göz konumu (vizör / göz hizası).
  P3 get povLocalEye => switch (kind) {
        PieceType.pawn => const P3(0, 0.89, 0.105),
        PieceType.knight => const P3(0, 0.82, 0.145),
        PieceType.bishop => const P3(0, 0.86, 0.270),
        PieceType.rook => const P3(0, 2.18, 0.22),
        PieceType.queen => const P3(0, 0.94, 0.105),
        PieceType.king => const P3(0, 1.03, 0.115),
      };

  /// POV yürüyüşünde ufku, düşmanı ve alt kadrajda silah/elleri dengeli gösteren doğal bakış açısı.
  double get povBasePitch => switch (kind) {
        PieceType.pawn => -0.24,
        PieceType.knight => -0.22,
        PieceType.bishop => -0.23,
        PieceType.rook => -0.30,
        PieceType.queen => -0.23,
        PieceType.king => -0.25,
      };

  /// Birinci şahıs (FPS) görünümünde kolların, silahların, kalkanın ve bacakların
  /// ekranı kapatmadan net görünmesini sağlayan kalibre edilmiş eklem duruşları:
  /// `(x, y, z, rx, ry, rz)`.
  Map<String, (double, double, double, double, double, double)> get _povLimbPose =>
      switch (kind) {
        PieceType.pawn => const {
            // Sağ ekran alt köşe: kalkan dışa açılı tutuş (görüşü asla kapatmaz)
            'armL': (-0.27, 0.19, 0.08, -0.12, -0.72, 0.10),
            // Sol ekran alt-orta: çelik teber namlusu ileri uzanmış
            'armR': (0.20, 0.21, 0.10, 0.58, -0.12, 0.20),
            'legL': (-0.095, 0.44, 0.065, 0.0, 0.0, 0.0),
            'legR': (0.095, 0.44, 0.065, 0.0, 0.0, 0.0),
          },
        PieceType.knight => const {
            // Çift kıvrık Şam kukri bıçağı sağ ve sol alt kadrajda ileri hazır
            'armL': (-0.165, 0.27, 0.12, -0.26, 0.16, 0.18),
            'armR': (0.165, 0.27, 0.12, -0.26, -0.16, -0.18),
            'legL': (-0.105, 0.41, 0.065, 0.0, 0.0, 0.0),
            'legR': (0.105, 0.41, 0.065, 0.0, 0.0, 0.0),
          },
        PieceType.bishop => const {
            // Ejderha ön jilet pençeleri önde, kanatlar sağ-sol periferide, ateş ağzı gözün hemen altında
            'armL': (-0.175, 0.36, 0.20, -0.42, 0.18, 0.08),
            'armR': (0.175, 0.36, 0.20, -0.42, -0.18, -0.08),
            'legL': (-0.145, 0.31, 0.02, 0.0, 0.0, 0.0),
            'legR': (0.145, 0.31, 0.02, 0.0, 0.0, 0.0),
            'mouth': (0.0, 0.45, 0.46, 0.0, 0.0, 0.0),
          },
        PieceType.rook => const {
            // Kadın Savaş Devi: sağ altta dikenli kol kalkanı, sol önde altın kuşaklı dev balyoz başı
            'armL': (-0.25, 0.39, 0.11, -0.46, -0.40, -0.12),
            'armR': (0.24, 0.42, 0.10, 0.50, -0.14, 0.24),
            'legL': (-0.132, 0.54, 0.075, 0.0, 0.0, 0.0),
            'legR': (0.132, 0.54, 0.075, 0.0, 0.0, 0.0),
          },
        PieceType.queen => const {
            // Vampir Kraliçe: sağ altta kızıl pençeli el & Kan Küresi, sol önde Kanatlı Yakut Asa
            'armL': (-0.165, 0.35, 0.10, -0.16, 0.14, 0.10),
            'armR': (0.185, 0.33, 0.10, 0.52, -0.10, 0.22),
            'legL': (-0.082, 0.45, 0.065, 0.0, 0.0, 0.0),
            'legR': (0.082, 0.45, 0.065, 0.0, 0.0, 0.0),
          },
        PieceType.king => const {
            // Barbar Kral: sağ altta fildişi savaş borusu, sol önde çift ağızlı hilal savaş baltası
            'armL': (-0.225, 0.37, 0.10, -0.30, 0.14, 0.14),
            'armR': (0.235, 0.36, 0.10, 0.54, -0.16, 0.24),
            'legL': (-0.132, 0.48, 0.070, 0.0, 0.0, 0.0),
            'legR': (0.132, 0.48, 0.070, 0.0, 0.0, 0.0),
          },
      };

  /// Birinci şahıs gözüne geçildiğinde yalnızca kafa, boyun kapağı (`povHide`) ve sırt pelerinini gizler;
  /// ön göğüs zırhı, kemer/etek, eller, silahlar, kanatlar ve yürüyen bacaklar temiz FPS kadrajıyla görünür kalır!
  void setFirstPersonMode(bool active) {
    inPov = active;
    parts['head']?.visible = !active;
    parts['povHide']?.visible = !active;
    parts['cape']?.visible = !active;
    if (kind == PieceType.bishop) {
      parts['neck']?.visible = !active;
    }

    if (active) {
      final map = _povLimbPose;
      for (final entry in map.entries) {
        final name = entry.key;
        final obj = parts[name];
        if (obj == null) continue;
        final (px, py, pz, rx, ry, rz) = entry.value;
        rest['$name.x'] = px;
        rest['$name.y'] = py;
        rest['$name.z'] = pz;
        rest['$name.rx'] = rx;
        rest['$name.ry'] = ry;
        rest['$name.rz'] = rz;
        obj.position.setValues(px, py, pz);
        obj.rotation.x = rx;
        obj.rotation.y = ry;
        obj.rotation.z = rz;
      }
    } else if (boardRest.isNotEmpty) {
      rest
        ..clear()
        ..addAll(boardRest);
      for (final name in const ['armL', 'armR', 'legL', 'legR', 'mouth']) {
        final obj = parts[name];
        if (obj == null || !boardRest.containsKey('$name.x')) continue;
        obj.position.setValues(
          boardRest['$name.x']!,
          boardRest['$name.y']!,
          boardRest['$name.z']!,
        );
        obj.rotation.x = boardRest['$name.rx']!;
        obj.rotation.y = boardRest['$name.ry']!;
        obj.rotation.z = boardRest['$name.rz']!;
      }
    }
  }
}

/// 91 hücreli tahtadaki tüm seçim, hedef, saldırı, son hamle, ipucu ve şah vurgularını
/// YALNIZCA 1 DRAW CALL içinde çizen dinamik altıgen vurgu katmanı.
class HexHighlightLayer {
  HexHighlightLayer(three.Object3D parent) {
    _posAttr = three.Float32BufferAttribute.fromList(
      List<double>.filled(_maxVerts * 3, 0.0),
      3,
    )..setUsage(three.DynamicDrawUsage);
    _colAttr = three.Float32BufferAttribute.fromList(
      List<double>.filled(_maxVerts * 4, 0.0),
      4,
    )..setUsage(three.DynamicDrawUsage);

    _geo = three.BufferGeometry();
    _geo.setAttribute(three.Attribute.position, _posAttr);
    _geo.setAttribute(three.Attribute.color, _colAttr);
    _geo.drawRange = {'start': 0, 'count': 0};

    final mat = three.MeshBasicMaterial.fromMap({
      'vertexColors': true,
      'transparent': true,
      'opacity': 1.0,
      'depthWrite': false,
    });
    mat.side = three.DoubleSide;

    mesh = three.Mesh(_geo, mat)..frustumCulled = false;
    mesh.visible = false;
    parent.add(mesh);
  }

  /// Hücre başına 54 köşe: Dev tahtada açık meydandaki bir Vampir Kraliçe'nin
  /// 70+ hedefi ve seçim/son hamle/şah vurguları birlikte sığar.
  static const int _maxVerts = 7200;
  late final three.Float32BufferAttribute _posAttr;
  late final three.Float32BufferAttribute _colAttr;
  late final three.BufferGeometry _geo;
  late final three.Mesh mesh;
  int _cursor = 0;

  void begin() {
    _cursor = 0;
  }

  void addHex(
    HexCell cell, {
    required int color,
    double? topY,
    double ringInner = 0.62,
    double ringOuter = 0.77,
    double ringAlpha = 0.90,
    double fillAlpha = 0.18,
    bool fangs = false,
  }) {
    final (cx, cz) = HexBoard.worldXZ(cell);
    final y = (topY ?? 0.20) + 0.008;
    final r = ((color >> 16) & 0xFF) / 255.0;
    final g = ((color >> 8) & 0xFF) / 255.0;
    final b = (color & 0xFF) / 255.0;

    // İç yarı-saydam altıgen dolgu
    if (fillAlpha > 0.005 && _cursor + 18 < _maxVerts) {
      for (var i = 0; i < 6; i++) {
        final a0 = i * math.pi / 3;
        final a1 = (i + 1) * math.pi / 3;
        _vtx(cx, y, cz, r, g, b, fillAlpha * 0.55);
        _vtx(cx + math.cos(a1) * ringInner, y, cz + math.sin(a1) * ringInner, r, g, b, fillAlpha);
        _vtx(cx + math.cos(a0) * ringInner, y, cz + math.sin(a0) * ringInner, r, g, b, fillAlpha);
      }
    }

    // Keskin altıgen çerçeve halkası
    if (_cursor + 36 < _maxVerts) {
      for (var i = 0; i < 6; i++) {
        final a0 = i * math.pi / 3;
        final a1 = (i + 1) * math.pi / 3;
        final ix0 = cx + math.cos(a0) * ringInner, iz0 = cz + math.sin(a0) * ringInner;
        final ix1 = cx + math.cos(a1) * ringInner, iz1 = cz + math.sin(a1) * ringInner;
        final ox0 = cx + math.cos(a0) * ringOuter, oz0 = cz + math.sin(a0) * ringOuter;
        final ox1 = cx + math.cos(a1) * ringOuter, oz1 = cz + math.sin(a1) * ringOuter;

        _vtx(ix0, y + 0.002, iz0, r, g, b, ringAlpha);
        _vtx(ix1, y + 0.002, iz1, r, g, b, ringAlpha);
        _vtx(ox1, y + 0.002, oz1, r, g, b, ringAlpha * 0.78);

        _vtx(ix0, y + 0.002, iz0, r, g, b, ringAlpha);
        _vtx(ox1, y + 0.002, oz1, r, g, b, ringAlpha * 0.78);
        _vtx(ox0, y + 0.002, oz0, r, g, b, ringAlpha * 0.78);
      }
    }

    // Saldırı karesi için merkeze bakan 6 keskin ok dişi
    if (fangs && _cursor + 18 < _maxVerts) {
      for (var i = 0; i < 6; i++) {
        final am = (i + 0.5) * math.pi / 3;
        final al = am - 0.14, ar = am + 0.14;
        _vtx(cx + math.cos(al) * ringInner, y + 0.004, cz + math.sin(al) * ringInner, r, g, b, 0.95);
        _vtx(cx + math.cos(ar) * ringInner, y + 0.004, cz + math.sin(ar) * ringInner, r, g, b, 0.95);
        _vtx(cx + math.cos(am) * (ringInner * 0.66), y + 0.005, cz + math.sin(am) * (ringInner * 0.66), 1.0, 0.92, 0.92, 1.0);
      }
    }
  }

  void _vtx(double x, double y, double z, double r, double g, double b, double a) {
    if (_cursor >= _maxVerts) return;
    final pa = _posAttr.array;
    final ca = _colAttr.array;
    final pi = _cursor * 3;
    pa[pi] = x;
    pa[pi + 1] = y;
    pa[pi + 2] = z;
    final ci = _cursor * 4;
    ca[ci] = r;
    ca[ci + 1] = g;
    ca[ci + 2] = b;
    ca[ci + 3] = a;
    _cursor++;
  }

  void commit() {
    mesh.visible = _cursor > 0;
    _geo.drawRange['count'] = _cursor;
    _posAttr.needsUpdate = true;
    _colAttr.needsUpdate = true;
  }
}

/// Tüm karakterleri ve altıgen savaş arenasını PBR (MeshStandardMaterial + ORM doku)
/// ve anatomik SculptBuilder ağları olarak üretir, önbelleğe alır.
class CreatureFactory {
  final Map<String, three.BufferGeometry> _geoCache = {};

  /// 8 yüzey sınıfı için birleşik PBR Roughness (G) + Metalness (B) palet dokusu.
  late final three.DataTexture _ormTex = () {
    // 0=skin, 1=cloth, 2=leather, 3=scale, 4=stone, 5=horn, 6=armor, 7=bladeGold
    const pairs = <(int rough, int metal)>[
      (184, 8),
      (224, 5),
      (142, 20),
      (96, 46),
      (194, 15),
      (108, 26),
      (68, 118),
      (38, 148),
    ];
    final bytes = <int>[];
    for (final (rgh, mtl) in pairs) {
      bytes
        ..add(255)
        ..add(rgh)
        ..add(mtl)
        ..add(255);
    }
    final tex = three.DataTexture(
      three.Uint8BufferAttribute.fromList(bytes, 4).array,
      8,
      1,
      three.RGBAFormat,
      three.UnsignedByteType,
      null,
      three.ClampToEdgeWrapping,
      three.ClampToEdgeWrapping,
      three.NearestFilter,
      three.NearestFilter,
    );
    tex.needsUpdate = true;
    return tex;
  }();

  late final three.MeshStandardMaterial _pbrMat = () {
    final m = three.MeshStandardMaterial.fromMap({
      'color': 0xFFFFFF,
      'vertexColors': true,
      'roughness': 1.0,
      'metalness': 1.0,
    });
    m.roughnessMap = _ormTex;
    m.metalnessMap = _ormTex;
    return m;
  }();

  late final three.MeshStandardMaterial _doublePbrMat = () {
    final m = three.MeshStandardMaterial.fromMap({
      'color': 0xFFFFFF,
      'vertexColors': true,
      'roughness': 1.0,
      'metalness': 1.0,
    });
    m.roughnessMap = _ormTex;
    m.metalnessMap = _ormTex;
    m.side = three.DoubleSide;
    return m;
  }();

  late final three.MeshBasicMaterial _glowSculptMat = () {
    return three.MeshBasicMaterial.fromMap({
      'color': 0xFFFFFF,
      'vertexColors': true,
    });
  }();

  three.BufferGeometry _sculpt(
    String key,
    void Function(SculptBuilder s) fn, {
    bool groundAo = true,
  }) =>
      _geoCache.putIfAbsent(key, () {
        final s = SculptBuilder(groundAo: groundAo);
        fn(s);
        return s.build();
      });

  three.Mesh _addSculpt(
    three.Object3D parent,
    String key,
    void Function(SculptBuilder s) fn, {
    bool doubleSide = false,
    bool glow = false,
    bool groundAo = true,
  }) {
    final geo = _sculpt(key, fn, groundAo: groundAo);
    final mat = glow
        ? _glowSculptMat
        : (doubleSide ? _doublePbrMat : _pbrMat);
    final mesh = three.Mesh(geo, mat);
    mesh.userData['glow'] = glow;
    parent.add(mesh);
    return mesh;
  }

  /// Ölüm animasyonu için karakterin tüm PBR parçalarını tek bir şeffaf/parlayabilir PBR malzemeye bağlar.
  three.MeshStandardMaterial isolateForDeath(CreatureRig rig) {
    final mat = three.MeshStandardMaterial.fromMap({
      'color': 0xFFFFFF,
      'vertexColors': true,
      'transparent': true,
      'opacity': 1.0,
      'roughness': 1.0,
      'metalness': 1.0,
      'emissive': 0x000000,
    });
    mat.roughnessMap = _ormTex;
    mat.metalnessMap = _ormTex;
    mat.side = three.DoubleSide;
    rig.root.traverse((n) {
      if (n is three.Mesh) {
        n.material = mat;
      }
    });
    return mat;
  }

  /// Açılış ekranı sırasında 2 ve 3 kişilik arena ile temel savaşçı geometrilerini önbelleğe alır;
  /// oyuna girişte ilk kare takılmasını (jank) tamamen önler.
  void prewarmCoreGeometries(List<int> tileColors) {
    buildArena(tileColors, variant: BoardVariant.twoPlayer);
    buildArena(tileColors, variant: BoardVariant.threePlayer);
    for (final team in Team.values) {
      for (final kind in PieceType.values) {
        build(ChessPiece(team, kind));
      }
    }
  }

  void dispose() {
    for (final geo in _geoCache.values) {
      geo.dispose();
    }
    _geoCache.clear();
    _pbrMat.dispose();
    _doublePbrMat.dispose();
    _glowSculptMat.dispose();
    _ormTex.dispose();
  }

  // ================================================================ AMFİ SÜTUNLU ARENA (2 DRAW CALL)
  /// 91..217 oyma taş altıgen amfi sütununu, bronz çerçeveli bazalt savaş platformunu ve 6 meşale kazanını
  /// yalnızca 2 statik Mesh içinde birleştirir. Her altıgen hücrenin kendine ait 3B sütun yüksekliği vardır!
  /// Büyük tahtada platform ve kazanlar tahta genişliğiyle büyür; sahnede oyun alanı
  /// [BoardShape.playScale] ile Klasik arenanın alanına sığdırılır.
  (three.Mesh solid, three.Mesh flames) buildArena(
    List<int> tileColors, {
    BoardVariant variant = BoardVariant.twoPlayer,
    BoardSize size = BoardSize.classic,
  }) {
    final shape = BoardShape.of(variant, size);
    final cacheTag = shape.size == BoardSize.classic
        ? variant.name
        : '${variant.name}_${shape.size.name}';
    // Klasik'te 1.0: platform ve kazanlar tahtanın dış kenarıyla birlikte genişler.
    final k = shape.extent / BoardShape.of(variant).extent;
    final braz = 9.12 * k;
    final solidGeo = _sculpt('arena_solid_amfi_$cacheTag', (s) {
      // Kademeli koyu bazalt ve dövme bronz amfi temel platformu
      s.loft(
        [
          Section(P3(0, -1.05, 0), 9.35 * k, 9.35 * k,
              color: 0x060910, surface: MatSurface.stone, shade: 0.64),
          Section(P3(0, -0.38, 0), 9.95 * k, 9.95 * k,
              color: 0x121824, surface: MatSurface.stone, shade: 0.86),
          Section(P3(0, -0.04, 0), 9.64 * k, 9.64 * k,
              color: 0x1B2333, surface: MatSurface.stone, shade: 0.96),
          Section(P3(0, 0.02, 0), 9.48 * k, 9.48 * k,
              color: 0xA88242, surface: MatSurface.bladeGold, shade: 1.12),
          Section(P3(0, 0.04, 0), 9.20 * k, 9.20 * k,
              color: 0x0C111B, surface: MatSurface.stone, shade: 0.78),
        ],
        radial: 24,
        flat: true,
      );

      // Bireysel altıgen amfi sütunları: her hücre kendi yüksekliğine (`topY`) yükselir!
      for (final cell in shape.cells) {
        final (wx, wz) = HexBoard.worldXZ(cell);
        final topY = shape.columnHeight(cell);
        final ci = HexBoard.colorIndex(cell);
        final baseCol = tileColors[ci];
        final deepShaftCol = mixColor(baseCol, 0x090D16, 0.66);
        final midShaftCol = mixColor(baseCol, 0x141B29, 0.42);
        final bevelCol = mixColor(baseCol, 0xEAE3D6, 0.12);

        final stoneVar = ((cell.q * 19 + cell.r * 31) & 7) - 3.5;
        final variedTop = stoneVar >= 0
            ? mixColor(baseCol, 0xF0E8DA, stoneVar * 0.014)
            : mixColor(baseCol, 0x141824, (-stoneVar) * 0.016);

        const rBase = HexBoard.tileRadius * 0.992;
        const rShaft = HexBoard.tileRadius * 0.968;
        const rOuter = HexBoard.tileRadius * 0.946;
        const rInner = HexBoard.tileRadius * 0.884;

        final isRoyalThrone = topY >= 1.40;
        final isHighTerrace = topY >= 0.88;

        if (isRoyalThrone) {
          // Şah ve Vezir sütunları: antik altın bilezikli anıtsal kraliyet sütunu
          s.loft(
            [
              Section(P3(wx, -0.06, wz), rBase, rBase,
                  color: deepShaftCol, surface: MatSurface.stone, shade: 0.62),
              Section(P3(wx, topY * 0.55, wz), rShaft, rShaft,
                  color: midShaftCol, surface: MatSurface.stone, shade: 0.86),
              Section(P3(wx, topY - 0.20, wz), rShaft * 1.01, rShaft * 1.01,
                  color: 0xB88E46, surface: MatSurface.bladeGold, shade: 1.15),
              Section(P3(wx, topY - 0.13, wz), rShaft, rShaft,
                  color: 0xCFA454, surface: MatSurface.bladeGold, shade: 1.22),
              Section(P3(wx, topY - 0.032, wz), rOuter, rOuter,
                  color: bevelCol, surface: MatSurface.stone, shade: 0.98),
              Section(P3(wx, topY, wz), rInner, rInner,
                  color: mixColor(variedTop, 0xFFE6A8, 0.12),
                  surface: MatSurface.stone,
                  shade: 1.08),
            ],
            radial: 6,
            capStart: false,
            flat: true,
          );
        } else if (isHighTerrace) {
          // Üst amfi kademeleri: bronz kuşaklı yüksek taş sütunlar
          s.loft(
            [
              Section(P3(wx, -0.06, wz), rBase, rBase,
                  color: deepShaftCol, surface: MatSurface.stone, shade: 0.64),
              Section(P3(wx, topY - 0.18, wz), rShaft, rShaft,
                  color: midShaftCol, surface: MatSurface.stone, shade: 0.86),
              Section(P3(wx, topY - 0.12, wz), rShaft, rShaft,
                  color: 0x8B6B38, surface: MatSurface.bladeGold, shade: 1.02),
              Section(P3(wx, topY - 0.030, wz), rOuter, rOuter,
                  color: bevelCol, surface: MatSurface.stone, shade: 0.96),
              Section(P3(wx, topY, wz), rInner, rInner,
                  color: variedTop, surface: MatSurface.stone, shade: 1.05),
            ],
            radial: 6,
            capStart: false,
            flat: true,
          );
        } else {
          // Orta ve alt amfi basamak sütunları
          s.loft(
            [
              Section(P3(wx, -0.06, wz), rBase, rBase,
                  color: deepShaftCol, surface: MatSurface.stone, shade: 0.65),
              Section(P3(wx, topY - 0.030, wz), rOuter, rOuter,
                  color: bevelCol, surface: MatSurface.stone, shade: 0.95),
              Section(P3(wx, topY, wz), rInner, rInner,
                  color: variedTop, surface: MatSurface.stone, shade: 1.04),
            ],
            radial: 6,
            capStart: false,
            flat: true,
          );
        }
      }

      // 6 köşe dövme demir ve bronz ateş kazanı sütunu (amfi yüksekliğiyle uyumlu)
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3 + math.pi / 6;
        final bx = math.cos(a) * braz, bz = math.sin(a) * braz;
        s.loft(
          [
            Section(P3(bx, -0.08, bz), 0.38, 0.38,
                color: 0x171B24, surface: MatSurface.stone, shade: 0.75),
            Section(P3(bx, 0.88, bz), 0.22, 0.22,
                color: 0x2A303E, surface: MatSurface.armor, shade: 0.92),
            Section(P3(bx, 1.18, bz), 0.45, 0.45,
                color: 0x9E7A3E, surface: MatSurface.bladeGold, shade: 1.12),
            Section(P3(bx, 1.36, bz), 0.37, 0.37,
                color: 0x241B18, surface: MatSurface.armor, shade: 0.82),
          ],
          radial: 8,
          flat: true,
        );
      }
    }, groundAo: false);

    final flameGeo = _sculpt('arena_flames_amfi_$cacheTag', (s) {
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3 + math.pi / 6;
        final bx = math.cos(a) * braz, bz = math.sin(a) * braz;
        final isEmeraldCorner = variant == BoardVariant.threePlayer && i == 3;
        final c0 = isEmeraldCorner ? 0x22D678 : 0xFF5518;
        final c1 = isEmeraldCorner ? 0x74F5A8 : 0xFFAA32;
        final c2 = isEmeraldCorner ? 0xE6FFCC : 0xFFF4B2;
        s.loft(
          [
            Section(P3(bx, 1.31, bz), 0.26, 0.26, color: c0, shade: 1.0),
            Section(P3(bx, 1.56, bz), 0.18, 0.18,
                color: c1, shade: 1.18, folds: 5, foldAmp: 0.20),
            Section(P3(bx, 1.84, bz), 0.026, 0.026, color: c2, shade: 1.35),
          ],
          radial: 8,
        );
      }
    }, groundAo: false);

    return (
      three.Mesh(solidGeo, _pbrMat),
      three.Mesh(flameGeo, _glowSculptMat),
    );
  }

  // ================================================================ SAVAŞÇI ÜRETİMİ
  CreatureRig build(ChessPiece piece) {
    final rig = CreatureRig(piece.kind, piece.team);
    final p = Palette.of(piece.team);
    final tag = piece.team.name;
    switch (piece.kind) {
      case PieceType.pawn:
        _vanguard(rig, p, tag);
      case PieceType.knight:
        _assassin(rig, p, tag);
      case PieceType.bishop:
        _dragon(rig, p, tag);
      case PieceType.rook:
        _warTitan(rig, p, tag);
      case PieceType.queen:
        _vampireQueen(rig, p, tag);
      case PieceType.king:
        _barbarianKing(rig, p, tag);
    }
    rig.parts.forEach((name, obj) {
      rig.rest['$name.rx'] = obj.rotation.x.toDouble();
      rig.rest['$name.ry'] = obj.rotation.y.toDouble();
      rig.rest['$name.rz'] = obj.rotation.z.toDouble();
      rig.rest['$name.x'] = obj.position.x.toDouble();
      rig.rest['$name.y'] = obj.position.y.toDouble();
      rig.rest['$name.z'] = obj.position.z.toDouble();
    });
    rig.boardRest.addAll(rig.rest);
    return rig;
  }

  three.Group _pivot(
    CreatureRig r,
    String name,
    three.Object3D parent,
    double x,
    double y,
    double z,
  ) {
    final g = three.Group();
    g.position.setValues(x, y, z);
    parent.add(g);
    r.parts[name] = g;
    return g;
  }

  /// Plastik satranç taşı tabanı OLMADAN doğal temas gölgesi ve ince ordu halkası ekler.
  void _addGroundContact(CreatureRig r, Palette p, String tag, double radius) {
    _addSculpt(r.root, 'aura_${r.kind.name}_$tag', (s) {
      s.groundAura(
        shadowColor: 0x07090F,
        ringColor: mixColor(p.metal, p.glow, 0.35),
        radius: radius,
      );
    }, groundAo: false);
  }

  // ===================================================== 1. KALKAN MUHAFIZI (Zırhlı Öncü Şövalye)
  void _vanguard(CreatureRig r, Palette p, String tag) {
    _addGroundContact(r, p, tag, 0.30);

    // Eklemli zırhlı bacaklar (kalçadan yürüyen gerçek şövalye tozlukları, dizlik ve demir çizmeler)
    for (final (name, sx, fz) in [('legL', -1.0, 0.025), ('legR', 1.0, -0.025)]) {
      final leg = _pivot(r, name, r.body, sx * 0.095, 0.44, 0.0);
      _addSculpt(leg, 'vanguard_${name}_$tag', (s) {
        // Demir sabaton çizme burnu
        s.loft([
          Section(P3(0, -0.435, fz + 0.075), 0.036, 0.024,
              color: p.armorDark, surface: MatSurface.armor, shade: 0.86),
          Section(P3(0, -0.415, fz + 0.02), 0.048, 0.072,
              color: p.armor, surface: MatSurface.armor, shade: 0.96),
          Section(P3(0, -0.37, fz), 0.044, 0.048,
              color: p.armorDark, surface: MatSurface.armor, shade: 0.92),
        ], radial: 10);
        // Kaval zırhı (greave) + diz kapağı (poleyn) + uyluk zırhı (cuisse)
        s.limb([
          (P3(0, -0.38, fz), 0.042, 0.046, p.armor, 0.96),
          (P3(0, -0.21, fz + 0.02), 0.050, 0.055, p.armor, 1.04),
          (const P3(0, 0.0, 0), 0.058, 0.062, p.clothDark, 0.90),
        ], surface: MatSurface.armor, muscleSwelling: 0.12);
        // Kanatlı çelik dizlik (poleyn)
        s.ellipsoid(P3(0, -0.20, fz + 0.052), 0.048, 0.044, 0.028,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.12);
      });
    }

    // Kıvrımlı arma eteği (surcoat) + kaburga sırtlı göğüs zırhı (cuirass)
    final torso = _pivot(r, 'torso', r.body, 0, 0.44, 0);
    _addSculpt(torso, 'vanguard_torso_$tag', (s) {
      s.loft([
        Section(const P3(0, -0.14, 0), 0.168, 0.138,
            color: p.clothDark, surface: MatSurface.cloth, shade: 0.84, folds: 8, foldAmp: 0.09),
        Section(const P3(0, -0.01, 0), 0.136, 0.114,
            color: p.cloth, surface: MatSurface.cloth, shade: 0.98, folds: 8, foldAmp: 0.05),
        Section(const P3(0, 0.025, 0), 0.145, 0.124,
            color: p.leather, surface: MatSurface.leather, shade: 0.95),
        Section(const P3(0, 0.048, 0.005), 0.142, 0.120,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.10),
        Section(const P3(0, 0.12, 0.012), 0.134, 0.110,
            color: p.armor, surface: MatSurface.armor, shade: 0.98, frontSharp: 0.34),
        Section(const P3(0, 0.23, 0.016), 0.162, 0.122,
            color: p.armor, surface: MatSurface.armor, shade: 1.08, frontSharp: 0.36),
        Section(const P3(0, 0.255, 0.008), 0.124, 0.092,
            color: p.armorDark, surface: MatSurface.armor, shade: 0.94),
      ]);
      // Kalça zırh plakaları (tassets) ve kemer tokası
      s.beveledBox(const P3(0, 0.036, 0.122), 0.048, 0.042, 0.022,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.18, rotY: 0);
      for (final sx in const [-1.0, 1.0]) {
        s.beveledBox(P3(sx * 0.115, -0.035, 0.065), 0.075, 0.105, 0.022,
            color: p.armor, surface: MatSurface.armor, shade: 1.02, rotY: sx * 0.35);
      }
    });

    // Üst boyun zırhı ve omuz kubbeleri (3. şahısta tam görünür, POV'da kamerayı kapatmaması için gizlenir)
    final povHide = _pivot(r, 'povHide', torso, 0, 0, 0);
    _addSculpt(povHide, 'vanguard_neck_$tag', (s) {
      s.loft([
        Section(const P3(0, 0.23, 0.016), 0.162, 0.122,
            color: p.armor, surface: MatSurface.armor, shade: 1.08, frontSharp: 0.36),
        Section(const P3(0, 0.31, 0.004), 0.126, 0.098,
            color: p.armorDark, surface: MatSurface.armor, shade: 0.94),
        Section(const P3(0, 0.345, 0), 0.068, 0.068,
            color: p.armorDark, surface: MatSurface.armor, shade: 0.88),
      ]);
      for (final sx in const [-1.0, 1.0]) {
        s.ellipsoid(P3(sx * 0.178, 0.255, 0.01), 0.078, 0.064, 0.084,
            color: p.armor, surface: MatSurface.armor, shade: 1.06, hemi: 0.65);
        s.ellipsoid(P3(sx * 0.188, 0.228, 0.01), 0.080, 0.024, 0.086,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.14);
      }
    });

    // Gerçekçi Barbute/Sallet Şövalye Miğferi (gölgeli T-vizör yarığı + at kılı sorguç)
    final head = _pivot(r, 'head', torso, 0, 0.35, 0.01);
    _addSculpt(head, 'vanguard_head_$tag', (s) {
      // İç karanlık vizör boşluğu
      s.ellipsoid(const P3(0, 0.072, 0.022), 0.066, 0.072, 0.072,
          color: 0x090B10, surface: MatSurface.cloth, shade: 0.55);
      // Dövme çelik miğfer kubbesi ve yanak plakaları
      s.loft([
        Section(const P3(0, -0.01, 0), 0.070, 0.076,
            color: p.armorDark, surface: MatSurface.armor, shade: 0.88),
        Section(const P3(0, 0.055, 0.012), 0.086, 0.096,
            color: p.armor, surface: MatSurface.armor, shade: 1.02, frontSharp: 0.32),
        Section(const P3(0, 0.125, 0.008), 0.084, 0.095,
            color: p.armor, surface: MatSurface.armor, shade: 1.08, frontSharp: 0.26),
        Section(const P3(0, 0.178, -0.004), 0.040, 0.058,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.15),
      ], radial: 14);
      // Kabartmalı altın burun/alın haçı (T-vizör çerçevesi) ve derin göz yarığı
      s.beveledBox(const P3(0, 0.095, 0.090), 0.105, 0.016, 0.018,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.16, rotY: 0);
      s.beveledBox(const P3(0, 0.082, 0.086), 0.086, 0.012, 0.018,
          color: 0x07090E, surface: MatSurface.cloth, shade: 0.4, rotY: 0);
      for (final sx in const [-1.0, 1.0]) {
        s.ellipsoid(P3(sx * 0.024, 0.082, 0.091), 0.010, 0.004, 0.006,
            color: p.glow, surface: MatSurface.bladeGold, shade: 1.35);
      }
      // İp dokulu at kılı miğfer sorgucu
      s.curvedHorn(
        const P3(0, 0.172, 0.03),
        const P3(0, 0.265, -0.05),
        const P3(0, 0.095, -0.18),
        rBase: 0.036,
        baseColor: p.cloth,
        tipColor: mixColor(p.cloth, p.metal, 0.35),
        surface: MatSurface.cloth,
        ribbed: true,
      );
    });

    // Sol kol: Perçinli Şövalye Kalkanı (Heater Shield)
    final armL = _pivot(r, 'armL', torso, -0.178, 0.24, 0.02);
    _addSculpt(armL, 'vanguard_armL_$tag', (s) {
      s.limb([
        (const P3(0, 0, 0), 0.044, 0.044, p.armorDark, 0.92),
        (const P3(-0.04, -0.11, 0.08), 0.042, 0.042, p.armor, 1.02),
        (const P3(-0.02, -0.14, 0.17), 0.038, 0.038, p.metal, 1.08),
      ], surface: MatSurface.armor);
      s.loft([
        Section(const P3(-0.02, -0.35, 0.21), 0.020, 0.018,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.08),
        Section(const P3(-0.02, -0.22, 0.225), 0.118, 0.032,
            color: p.cloth, surface: MatSurface.leather, shade: 0.96, frontSharp: 0.36),
        Section(const P3(-0.02, -0.05, 0.232), 0.158, 0.036,
            color: p.armor, surface: MatSurface.armor, shade: 1.06, frontSharp: 0.30),
        Section(const P3(-0.02, 0.10, 0.222), 0.150, 0.032,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.14, frontSharp: 0.22),
      ], radial: 10, flat: true);
      s.ellipsoid(const P3(-0.02, -0.06, 0.264), 0.048, 0.048, 0.025,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.22);
    });

    // Sağ kol: Dövme Çelik Teber (Halberd) + Savaş Flama Şeridi
    final armR = _pivot(r, 'armR', torso, 0.178, 0.24, 0.01);
    _addSculpt(armR, 'vanguard_armR_$tag', (s) {
      s.limb([
        (const P3(0, 0, 0), 0.044, 0.044, p.armorDark, 0.92),
        (const P3(0.035, -0.12, 0.07), 0.042, 0.042, p.armor, 1.02),
        (const P3(0.03, -0.15, 0.16), 0.038, 0.038, p.armorDark, 0.98),
      ], surface: MatSurface.armor);
      // Dişbudak teber sapı
      s.loft([
        Section(const P3(0.03, -0.44, 0.13), 0.018, 0.018,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.08),
        Section(const P3(0.03, -0.38, 0.135), 0.015, 0.015,
            color: p.wood, surface: MatSurface.horn, shade: 0.94),
        Section(const P3(0.03, 0.36, 0.19), 0.015, 0.015,
            color: p.wood, surface: MatSurface.horn, shade: 0.98),
        Section(const P3(0.03, 0.40, 0.194), 0.025, 0.025,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.15),
      ], radial: 8);
      // Üst mızrak namlusu + ön hilal teber ağzı + arka zırh gagası
      s.blade([
        (const P3(0.03, 0.40, 0.194), 0.036, 0.014),
        (const P3(0.03, 0.53, 0.204), 0.026, 0.010),
        (const P3(0.03, 0.67, 0.215), 0.002, 0.002),
      ], steelColor: p.steel, edgeColor: p.steelEdge);
      s.blade([
        (const P3(0.03, 0.36, 0.20), 0.016, 0.010),
        (const P3(0.03, 0.42, 0.295), 0.072, 0.005),
        (const P3(0.03, 0.48, 0.225), 0.012, 0.005),
      ], steelColor: p.steel, edgeColor: p.steelEdge);
      s.curvedHorn(
        const P3(0.03, 0.41, 0.185),
        const P3(0.03, 0.42, 0.135),
        const P3(0.03, 0.38, 0.105),
        rBase: 0.014,
        baseColor: p.steel,
        tipColor: p.steelEdge,
        surface: MatSurface.bladeGold,
        steps: 4,
        ribbed: false,
      );
    });
    armR.rotation.x = 0.20;
  }

  // ===================================================== 2. SUİKASTÇİ (Gölge Avcısı)
  void _assassin(CreatureRig r, Palette p, String tag) {
    _addGroundContact(r, p, tag, 0.31);

    // Çevik bükülü avcı bacakları (kalçadan hareketli deri çizmeler ve dizlikler)
    for (final (name, sx, fz) in [('legL', -1.0, 0.06), ('legR', 1.0, -0.05)]) {
      final leg = _pivot(r, name, r.body, sx * 0.105, 0.41, 0.0);
      _addSculpt(leg, 'assassin_${name}_$tag', (s) {
        s.loft([
          Section(P3(sx * 0.015, -0.405, fz + 0.075), 0.032, 0.020,
              color: p.dark, surface: MatSurface.leather, shade: 0.85),
          Section(P3(sx * 0.015, -0.385, fz + 0.02), 0.044, 0.066,
              color: p.leather, surface: MatSurface.leather, shade: 0.94),
          Section(P3(sx * 0.02, -0.32, fz), 0.040, 0.044,
              color: p.dark, surface: MatSurface.cloth, shade: 0.88),
        ], radial: 9);
        s.limb([
          (P3(sx * 0.02, -0.33, fz), 0.038, 0.042, p.leather, 0.94),
          (P3(sx * 0.03, -0.17, fz + 0.04), 0.048, 0.052, p.armorDark, 0.98),
          (const P3(0, 0, 0), 0.056, 0.060, p.clothDark, 0.92),
        ], surface: MatSurface.leather, muscleSwelling: 0.16);
      });
    }

    // Öne eğimli çivili deri brigandine gövde + fırlatma bıçağı kemeri
    final torso = _pivot(r, 'torso', r.body, 0, 0.40, 0.01);
    _addSculpt(torso, 'assassin_torso_$tag', (s) {
      s.loft([
        Section(const P3(0, -0.06, 0.0), 0.128, 0.102,
            color: p.cloth, surface: MatSurface.cloth, shade: 0.94, folds: 6, foldAmp: 0.07),
        Section(const P3(0, 0.03, 0.015), 0.110, 0.088,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.10),
        Section(const P3(0, 0.14, 0.036), 0.128, 0.094,
            color: p.leather, surface: MatSurface.leather, shade: 0.98, frontSharp: 0.22),
        Section(const P3(0, 0.22, 0.048), 0.136, 0.096,
            color: p.armor, surface: MatSurface.armor, shade: 1.04, frontSharp: 0.22),
      ]);
      // Çapraz göğüs kayışı ve 3 fırlatma hançeri kını
      s.limb([
        (const P3(-0.12, 0.22, 0.105), 0.018, 0.014, p.leather, 1.02),
        (const P3(0.0, 0.14, 0.138), 0.022, 0.016, p.metal, 1.16),
        (const P3(0.12, 0.04, 0.10), 0.018, 0.014, p.leather, 0.98),
      ], surface: MatSurface.leather, radial: 6, muscleSwelling: 0);
    });

    final povHide = _pivot(r, 'povHide', torso, 0, 0, 0);
    _addSculpt(povHide, 'assassin_neck_$tag', (s) {
      s.loft([
        Section(const P3(0, 0.22, 0.048), 0.136, 0.096,
            color: p.armor, surface: MatSurface.armor, shade: 1.04, frontSharp: 0.22),
        Section(const P3(0, 0.26, 0.07), 0.156, 0.108,
            color: p.armor, surface: MatSurface.armor, shade: 1.04, frontSharp: 0.24),
        Section(const P3(0, 0.33, 0.08), 0.074, 0.070,
            color: p.clothDark, surface: MatSurface.cloth, shade: 0.86),
      ]);
      for (final sx in const [-1.0, 1.0]) {
        s.ellipsoid(P3(sx * 0.16, 0.26, 0.065), 0.064, 0.046, 0.072,
            color: p.armorDark, surface: MatSurface.armor, shade: 1.04, hemi: 0.62);
      }
    });

    // Rüzgârda savrulan yırtmaçlı gölge pelerini
    final cape = _pivot(r, 'cape', torso, 0, 0.30, 0.02);
    _addSculpt(cape, 'assassin_cape_$tag', (s) {
      s.loft([
        Section(const P3(0, 0, 0), 0.15, 0.04,
            color: p.clothDark, surface: MatSurface.cloth, shade: 0.90),
        Section(const P3(0, -0.18, -0.10), 0.20, 0.045,
            color: p.armorDark, surface: MatSurface.cloth, shade: 0.92, folds: 7, foldAmp: 0.13),
        Section(const P3(0, -0.38, -0.22), 0.25, 0.04,
            color: p.cloth, surface: MatSurface.cloth, shade: 0.95, folds: 7, foldAmp: 0.17),
        Section(const P3(0, -0.54, -0.30), 0.22, 0.02,
            color: p.clothDark, surface: MatSurface.cloth, shade: 0.80, folds: 7, foldAmp: 0.24),
      ], radial: 12);
    }, doubleSide: true);

    // Derin gölgeli kukuleta + burun köprülü deri maske + kısık avcı gözleri
    final head = _pivot(r, 'head', torso, 0, 0.34, 0.085);
    _addSculpt(head, 'assassin_head_$tag', (s) {
      // Kukuleta içi koyu gölge ve alt yüz deri maskesi
      s.ellipsoid(const P3(0, 0.068, 0.015), 0.062, 0.074, 0.068,
          color: 0x090A10, surface: MatSurface.cloth, shade: 0.55);
      s.loft([
        Section(const P3(0, 0.005, 0.02), 0.052, 0.058,
            color: p.leather, surface: MatSurface.leather, shade: 0.92, frontSharp: 0.38),
        Section(const P3(0, 0.058, 0.028), 0.058, 0.068,
            color: p.dark, surface: MatSurface.leather, shade: 0.96, frontSharp: 0.42),
      ], radial: 10);
      // Üstten sarkan keskin katmanlı kukuleta kumaşı
      s.loft([
        Section(const P3(0, -0.01, -0.015), 0.094, 0.098,
            color: p.clothDark, surface: MatSurface.cloth, shade: 0.86, folds: 6, foldAmp: 0.05),
        Section(const P3(0, 0.075, 0.008), 0.088, 0.102,
            color: p.armor, surface: MatSurface.cloth, shade: 0.98, frontSharp: 0.36),
        Section(const P3(0, 0.145, -0.022), 0.060, 0.088,
            color: p.armor, surface: MatSurface.cloth, shade: 1.04, frontSharp: 0.45),
        Section(const P3(0, 0.172, -0.10), 0.012, 0.020,
            color: p.cloth, surface: MatSurface.cloth, shade: 0.94),
      ], radial: 12, arcStart: math.pi * 0.58, arcLen: math.pi * 1.84);
      // Gölge içinden parlayan ince badem gözler
      for (final sx in const [-1.0, 1.0]) {
        s.ellipsoid(P3(sx * 0.024, 0.074, 0.072), 0.011, 0.0045, 0.007,
            color: p.glow, surface: MatSurface.bladeGold, shade: 1.35);
      }
    }, doubleSide: true);

    // İkiz kıvrık Şam çeliği Kukri / Hançer kolları
    for (final (name, sx) in [('armL', -1.0), ('armR', 1.0)]) {
      final arm = _pivot(r, name, torso, sx * 0.162, 0.25, 0.065);
      _addSculpt(arm, 'assassin_${name}_$tag', (s) {
        s.limb([
          (const P3(0, 0, 0), 0.042, 0.042, p.armor, 0.96),
          (P3(sx * 0.048, -0.10, 0.08), 0.038, 0.040, p.leather, 0.98),
          (P3(sx * 0.03, -0.14, 0.18), 0.034, 0.036, p.armorDark, 0.94),
        ], surface: MatSurface.leather, muscleSwelling: 0.14);
        s.beveledBox(P3(sx * 0.03, -0.14, 0.21), 0.024, 0.078, 0.026,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.18, rotY: 0);
        s.blade([
          (P3(sx * 0.03, -0.14, 0.22), 0.026, 0.008),
          (P3(sx * 0.042, -0.16, 0.34), 0.040, 0.009),
          (P3(sx * 0.036, -0.13, 0.46), 0.028, 0.007),
          (P3(sx * 0.024, -0.08, 0.56), 0.003, 0.002),
        ], steelColor: p.steel, edgeColor: p.steelEdge);
      });
      arm.rotation.x = -0.25;
      arm.rotation.z = sx * 0.22;
    }
  }

  // ===================================================== 3. EJDERHA (Antik Sürüngen Ejder)
  void _dragon(CreatureRig r, Palette p, String tag) {
    _addGroundContact(r, p, tag, 0.37);

    // Kırıklı bazalt tüneme kayası (r.root üzerinde sabit kalır)
    _addSculpt(r.root, 'dragon_crag_$tag', (s) {
      s.ellipsoid(const P3(0, 0.045, -0.02), 0.30, 0.065, 0.28,
          color: p.stone, surface: MatSurface.stone, shade: 0.88, stacks: 5, slices: 9, flat: true, jitter: 0.14, seed: 11);
    });

    // Eklemli pençeli arka bacaklar (POV ve uçuşta hareketli digitigrade sürüngen anatomisi)
    for (final (name, sx) in [('legL', -1.0), ('legR', 1.0)]) {
      final leg = _pivot(r, name, r.body, sx * 0.145, 0.31, -0.05);
      _addSculpt(leg, 'dragon_${name}_$tag', (s) {
        s.limb([
          (const P3(0, 0, 0), 0.084, 0.098, p.scale, 0.98),
          (P3(sx * 0.035, -0.13, 0.11), 0.056, 0.066, p.scale, 0.94),
          (P3(sx * 0.010, -0.235, 0.07), 0.046, 0.056, p.armorDark, 0.88),
        ], surface: MatSurface.scale, muscleSwelling: 0.20);
        for (final ca in const [-0.30, 0.0, 0.30]) {
          final cx = sx * 0.010 + math.sin(ca) * 0.042;
          s.curvedHorn(
            P3(cx, -0.235, 0.10),
            P3(cx + math.sin(ca) * 0.04, -0.222, 0.17),
            P3(cx + math.sin(ca) * 0.06, -0.268, 0.228),
            rBase: 0.018,
            baseColor: p.hornBase,
            tipColor: p.horn,
            steps: 5,
            ribbed: false,
          );
        }
      });
    }

    // Yırtıcı öne eğimli ejderha göğüs kafesi ve altın karın plakaları (ventral scutes)
    final torso = _pivot(r, 'torso', r.body, 0, 0.29, -0.03);
    _addSculpt(torso, 'dragon_torso_$tag', (s) {
      s.loft([
        Section(const P3(0, -0.04, -0.15), 0.135, 0.135,
            color: p.scale, surface: MatSurface.scale, shade: 0.90),
        Section(const P3(0, 0.08, -0.03), 0.180, 0.168,
            color: p.scale, surface: MatSurface.scale, shade: 0.98, folds: 6, foldAmp: 0.045),
        Section(const P3(0, 0.22, 0.09), 0.192, 0.172,
            color: p.belly, surface: MatSurface.scale, shade: 1.04, frontSharp: 0.24, folds: 7, foldAmp: 0.045),
      ], radial: 14);
      // Ön göğüs zırh plakaları (ventral scutes)
      s.loft([
        Section(const P3(0, 0.05, 0.10), 0.095, 0.045,
            color: p.belly, surface: MatSurface.horn, shade: 1.05, folds: 5, foldAmp: 0.08),
        Section(const P3(0, 0.21, 0.22), 0.108, 0.048,
            color: p.belly, surface: MatSurface.horn, shade: 1.10, folds: 5, foldAmp: 0.08),
      ], radial: 8);
    });

    final povHide = _pivot(r, 'povHide', torso, 0, 0, 0);
    _addSculpt(povHide, 'dragon_neckjoin_$tag', (s) {
      s.loft([
        Section(const P3(0, 0.22, 0.09), 0.192, 0.172,
            color: p.belly, surface: MatSurface.scale, shade: 1.04, frontSharp: 0.24),
        Section(const P3(0, 0.35, 0.16), 0.145, 0.136,
            color: p.scale, surface: MatSurface.scale, shade: 1.02),
      ], radial: 14);
      s.loft([
        Section(const P3(0, 0.21, 0.22), 0.108, 0.048,
            color: p.belly, surface: MatSurface.horn, shade: 1.10),
        Section(const P3(0, 0.34, 0.25), 0.082, 0.040,
            color: p.belly, surface: MatSurface.horn, shade: 1.06),
      ], radial: 8);
      for (var i = 0; i < 4; i++) {
        final t = i / 3.0;
        final base = P3(0, 0.03 + t * 0.29, -0.15 + t * 0.19);
        s.curvedHorn(
          base,
          base + const P3(0, 0.065, -0.07),
          base + const P3(0, 0.115, -0.13),
          rBase: 0.024,
          baseColor: p.hornBase,
          tipColor: p.horn,
          steps: 5,
          ribbed: false,
        );
      }
    });

    // Eklemli jilet pençeli ön kollar (POV modunda önde net görünür!)
    for (final (name, sx) in [('armL', -1.0), ('armR', 1.0)]) {
      final arm = _pivot(r, name, torso, sx * 0.15, 0.23, 0.12);
      _addSculpt(arm, 'dragon_${name}_$tag', (s) {
        s.limb([
          (const P3(0, 0, 0), 0.054, 0.056, p.scale, 0.98),
          (P3(sx * 0.02, -0.12, 0.10), 0.038, 0.042, p.scale, 0.95),
          (P3(0, -0.18, 0.17), 0.034, 0.036, p.hornBase, 0.92),
        ], surface: MatSurface.scale, muscleSwelling: 0.16);
        for (final ca in const [-0.26, 0.0, 0.26]) {
          final cx = math.sin(ca) * 0.028;
          s.curvedHorn(
            P3(cx, -0.18, 0.18),
            P3(cx + math.sin(ca) * 0.02, -0.19, 0.24),
            P3(cx + math.sin(ca) * 0.03, -0.23, 0.28),
            rBase: 0.013,
            baseColor: p.hornBase,
            tipColor: p.horn,
            steps: 4,
            ribbed: false,
          );
        }
      });
    }

    // Kaslı kıvrımlı kuyruk + keskin mahmuz yaprağı
    final tail = _pivot(r, 'tail', torso, 0, -0.02, -0.15);
    _addSculpt(tail, 'dragon_tail_$tag', (s) {
      s.limb([
        (const P3(0, 0, 0), 0.105, 0.105, p.scale, 0.94),
        (const P3(0, -0.08, -0.22), 0.075, 0.078, p.scale, 0.92),
        (const P3(0.05, -0.11, -0.44), 0.050, 0.052, p.scale, 0.90),
        (const P3(-0.03, -0.05, -0.64), 0.028, 0.030, p.metal, 1.04),
      ], surface: MatSurface.scale, muscleSwelling: 0.06);
      s.blade([
        (const P3(-0.03, -0.05, -0.62), 0.048, 0.014),
        (const P3(-0.04, -0.02, -0.74), 0.068, 0.010),
        (const P3(-0.04, 0.01, -0.86), 0.003, 0.002),
      ], steelColor: p.metal, edgeColor: p.horn);
    });

    // S-kıvrımlı zırhlı boyun
    final neck = _pivot(r, 'neck', torso, 0, 0.34, 0.15);
    _addSculpt(neck, 'dragon_neck_$tag', (s) {
      s.loft([
        Section(const P3(0, -0.02, -0.02), 0.116, 0.116,
            color: p.scale, surface: MatSurface.scale, shade: 0.98, folds: 5, foldAmp: 0.04),
        Section(const P3(0, 0.12, 0.05), 0.092, 0.098,
            color: p.belly, surface: MatSurface.scale, shade: 1.02, frontSharp: 0.25),
        Section(const P3(0, 0.24, 0.10), 0.078, 0.086,
            color: p.scale, surface: MatSurface.scale, shade: 1.04),
      ], radial: 12);
      for (var i = 0; i < 3; i++) {
        final y = 0.04 + i * 0.082;
        final z = -0.05 + i * 0.04;
        s.curvedHorn(
          P3(0, y, z),
          P3(0, y + 0.05, z - 0.07),
          P3(0, y + 0.09, z - 0.12),
          rBase: 0.019,
          baseColor: p.hornBase,
          tipColor: p.horn,
          steps: 4,
          ribbed: false,
        );
      }
    });

    // Gerçekçi boynuzlu sürüngen kafatası + kaş kemeri + fildişi dişler
    final head = _pivot(r, 'head', neck, 0, 0.24, 0.10);
    _addSculpt(head, 'dragon_head_$tag', (s) {
      s.loft([
        Section(const P3(0, 0.01, -0.05), 0.094, 0.084,
            color: p.scale, surface: MatSurface.scale, shade: 0.98),
        Section(const P3(0, 0.038, 0.05), 0.090, 0.080,
            color: p.scale, surface: MatSurface.scale, shade: 1.04, folds: 4, foldAmp: 0.06),
        Section(const P3(0, 0.022, 0.165), 0.062, 0.055,
            color: p.scale, surface: MatSurface.scale, shade: 1.06, frontSharp: 0.26),
        Section(const P3(0, 0.018, 0.26), 0.038, 0.036,
            color: p.hornBase, surface: MatSurface.horn, shade: 1.0),
      ], radial: 12);
      for (final sx in const [-1.0, 1.0]) {
        s.curvedHorn(
          P3(sx * 0.056, 0.065, -0.01),
          P3(sx * 0.135, 0.165, -0.14),
          P3(sx * 0.175, 0.245, -0.31),
          rBase: 0.031,
          baseColor: p.hornBase,
          tipColor: p.horn,
          steps: 7,
          ribbed: true,
        );
        s.curvedHorn(
          P3(sx * 0.074, 0.025, -0.02),
          P3(sx * 0.14, 0.04, -0.11),
          P3(sx * 0.17, 0.06, -0.21),
          rBase: 0.018,
          baseColor: p.hornBase,
          tipColor: p.horn,
          steps: 5,
          ribbed: true,
        );
        // Zırhlı kaş kemeri ve gömülü kor göz yarığı
        s.curvedHorn(
          P3(sx * 0.045, 0.062, 0.04),
          P3(sx * 0.072, 0.060, 0.075),
          P3(sx * 0.055, 0.048, 0.115),
          rBase: 0.014,
          baseColor: p.scale,
          tipColor: p.hornBase,
          steps: 4,
          ribbed: false,
        );
        s.ellipsoid(P3(sx * 0.060, 0.042, 0.072), 0.012, 0.008, 0.018,
            color: p.fire, surface: MatSurface.bladeGold, shade: 1.4);
        for (final fz in const [0.11, 0.17, 0.225]) {
          s.curvedHorn(
            P3(sx * 0.042, -0.008, fz),
            P3(sx * 0.040, -0.028, fz + 0.005),
            P3(sx * 0.036, -0.048, fz),
            rBase: 0.009,
            baseColor: p.horn,
            tipColor: 0xFFFFFF,
            steps: 3,
            ribbed: false,
          );
        }
      }
    });

    // Hareketli alt çene
    final jaw = _pivot(r, 'jaw', head, 0, -0.015, 0.03);
    _addSculpt(jaw, 'dragon_jaw_$tag', (s) {
      s.loft([
        Section(const P3(0, 0, -0.02), 0.068, 0.036,
            color: p.belly, surface: MatSurface.scale, shade: 0.92),
        Section(const P3(0, -0.012, 0.10), 0.052, 0.028,
            color: p.scale, surface: MatSurface.scale, shade: 0.96),
        Section(const P3(0, -0.008, 0.205), 0.028, 0.020,
            color: p.hornBase, surface: MatSurface.horn, shade: 1.0),
      ], radial: 10);
      for (final sx in const [-1.0, 1.0]) {
        s.curvedHorn(
          P3(sx * 0.032, 0.002, 0.175),
          P3(sx * 0.032, 0.020, 0.18),
          P3(sx * 0.030, 0.035, 0.175),
          rBase: 0.008,
          baseColor: p.horn,
          tipColor: 0xFFFFFF,
          steps: 3,
          ribbed: false,
        );
      }
    });
    jaw.rotation.x = 0.14;

    // Ateş püskürtme çekirdeği doğrudan torso'ya bağlıdır ki POV modunda kafa gizliyken de parlasın!
    final mouth = _pivot(r, 'mouth', torso, 0, 0.57, 0.49);
    final mouthGlow = _addSculpt(mouth, 'dragon_firecore_$tag', (s) {
      s.ellipsoid(const P3(0, 0, -0.04), 0.034, 0.028, 0.048,
          color: p.fireCore, shade: 1.35);
    }, glow: true);
    mouthGlow.visible = false;
    r.parts['mouthGlow'] = mouthGlow;

    // 4-parmaklı deri zarlı devasa ejderha kanatları
    for (final (name, sx) in [('wingL', -1.0), ('wingR', 1.0)]) {
      final wing = _pivot(r, name, torso, sx * 0.135, 0.28, 0.06);
      _addSculpt(wing, 'dragon_${name}_$tag', (s) {
        const root = P3(0, 0, 0);
        final elbow = P3(sx * 0.23, 0.13, -0.05);
        final wrist = P3(sx * 0.44, 0.29, 0.04);
        s.limb([
          (root, 0.044, 0.044, p.scale, 1.0),
          (elbow, 0.034, 0.034, p.scale, 0.98),
          (wrist, 0.026, 0.026, p.metal, 1.08),
        ], surface: MatSurface.scale, muscleSwelling: 0.14);
        s.curvedHorn(
          wrist,
          wrist + P3(sx * 0.04, 0.06, 0.05),
          wrist + P3(sx * 0.06, 0.10, 0.09),
          rBase: 0.016,
          baseColor: p.hornBase,
          tipColor: p.horn,
          steps: 4,
          ribbed: false,
        );

        List<P3> fingerCurve(P3 ctrl, P3 tip) => [
              for (var i = 0; i <= 5; i++)
                () {
                  final t = i / 5.0, u = 1 - t;
                  return wrist * (u * u) + ctrl * (2 * u * t) + tip * (t * t);
                }(),
            ];

        final f1 = fingerCurve(P3(sx * 0.64, 0.31, 0.02), P3(sx * 0.84, 0.18, -0.10));
        final f2 = fingerCurve(P3(sx * 0.60, 0.18, -0.10), P3(sx * 0.74, -0.04, -0.24));
        final f3 = fingerCurve(P3(sx * 0.48, 0.08, -0.14), P3(sx * 0.54, -0.20, -0.28));
        final f4 = [
          elbow,
          P3.lerp(elbow, P3(sx * 0.25, -0.22, -0.22), 0.33),
          P3.lerp(elbow, P3(sx * 0.25, -0.22, -0.22), 0.66),
          P3.lerp(elbow, P3(sx * 0.20, -0.24, -0.22), 0.85),
          P3(sx * 0.16, -0.25, -0.20),
          P3(sx * 0.10, -0.22, -0.16),
        ];

        for (final pts in [f1, f2, f3]) {
          s.curvedHorn(
            pts.first,
            pts[2],
            pts.last,
            rBase: 0.016,
            baseColor: p.scale,
            tipColor: p.horn,
            steps: 5,
            ribbed: false,
          );
        }
        s.wingWeb(f1, f2, boneSideColor: p.scale, midWebColor: p.membrane, sag: 0.025);
        s.wingWeb(f2, f3, boneSideColor: p.scale, midWebColor: p.membrane, sag: 0.028);
        s.wingWeb(f3, f4, boneSideColor: p.scale, midWebColor: p.membrane, sag: 0.022);
      }, doubleSide: true);
      wing.rotation.y = sx * 0.28;
      wing.rotation.z = sx * -0.14;
    }
  }

  // ===================================================== 4. KADIN SAVAŞ DEVİ / VALKÜR TİTAN (Sıfır Kale Şekli!)
  void _warTitan(CreatureRig r, Palette p, String tag) {
    _addGroundContact(r, p, tag, 0.70);

    // Eklemli uzun, atletik Valkür/Amazon dev kadın bacakları (kürklü savaş çizmeleri + altın dizlik + uyluk kayışları)
    for (final (name, sx, fz) in [('legL', -1.0, 0.025), ('legR', 1.0, -0.025)]) {
      final leg = _pivot(r, name, r.body, sx * 0.132, 0.54, 0.0);
      _addSculpt(leg, 'valkyrie_titan_${name}_$tag', (s) {
        // Demir burunlu yüksek bağcıklı Valkür savaş çizmesi
        s.loft([
          Section(P3(0, -0.535, fz + 0.088), 0.052, 0.032,
              color: p.armorDark, surface: MatSurface.armor, shade: 0.88),
          Section(P3(0, -0.495, fz + 0.022), 0.070, 0.104,
              color: p.leather, surface: MatSurface.leather, shade: 0.96),
          Section(P3(0, -0.36, fz), 0.068, 0.074,
              color: p.leather, surface: MatSurface.leather, shade: 0.98, folds: 6, foldAmp: 0.05),
          Section(P3(0, -0.31, fz), 0.074, 0.080,
              color: p.fur, surface: MatSurface.cloth, shade: 1.0, folds: 7, foldAmp: 0.08),
        ], radial: 12);
        // Kaval zırhı + atletik-kadınsı uyluk anatomisi
        s.limb([
          (P3(0, -0.32, fz), 0.066, 0.072, p.armor, 1.02),
          (P3(0, -0.20, fz + 0.028), 0.074, 0.080, p.giantSkin, 1.02),
          (const P3(0, 0, 0), 0.092, 0.098, p.giantSkin, 1.04),
        ], surface: MatSurface.skin, muscleSwelling: 0.16);
        // Kanat kabartmalı altın dizlik ve deri uyluk kemeri
        s.ellipsoid(P3(0, -0.21, fz + 0.074), 0.052, 0.056, 0.032,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.18);
        s.ellipsoid(P3(0, -0.09, fz + 0.005), 0.090, 0.018, 0.094,
            color: p.leather, surface: MatSurface.leather, shade: 0.95);
      });
    }

    // Kadınsı kum saati bel, pileli savaş eteği, konturlu Valkür göğüs zırhı ve açık Amazon omuzları
    final torso = _pivot(r, 'torso', r.body, 0, 0.54, 0);
    _addSculpt(torso, 'valkyrie_titan_torso_$tag', (s) {
      // Pileli deri ve altın perçinli Valkür savaş eteği + bel kemeri
      s.loft([
        Section(const P3(0, -0.15, 0), 0.238, 0.192,
            color: p.leather, surface: MatSurface.leather, shade: 0.90, folds: 10, foldAmp: 0.11),
        Section(const P3(0, -0.02, 0), 0.198, 0.162,
            color: p.cloth, surface: MatSurface.cloth, shade: 0.98, folds: 8, foldAmp: 0.06),
        Section(const P3(0, 0.045, 0.008), 0.176, 0.140,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.16),
      ], radial: 16);
      // Ön kumaş savaş kuşağı (loin-banner) ve altın kemer tokası
      s.beveledBox(const P3(0, 0.035, 0.148), 0.078, 0.068, 0.032,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.22, rotY: 0);
      s.loft([
        Section(const P3(0, 0.01, 0.142), 0.062, 0.016,
            color: p.cloth, surface: MatSurface.cloth, shade: 1.02),
        Section(const P3(0, -0.13, 0.162), 0.072, 0.016,
            color: p.cloth, surface: MatSurface.cloth, shade: 0.98),
        Section(const P3(0, -0.24, 0.172), 0.045, 0.012,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.14),
      ], radial: 8);

      // Atletik-kadınsı ince bel ve konturlu Valkür göğüs zırhı
      s.loft([
        Section(const P3(0, 0.04, 0), 0.168, 0.132,
            color: p.giantSkin, surface: MatSurface.skin, shade: 0.96),
        Section(const P3(0, 0.13, 0.01), 0.148, 0.116,
            color: p.giantSkin, surface: MatSurface.skin, shade: 1.02, folds: 4, foldAmp: 0.03),
        Section(const P3(0, 0.23, 0.022), 0.192, 0.148,
            color: p.armor, surface: MatSurface.armor, shade: 1.06, frontSharp: 0.16),
        Section(const P3(0, 0.325, 0.024), 0.205, 0.152,
            color: p.armor, surface: MatSurface.armor, shade: 1.10, frontSharp: 0.18),
      ], radial: 16);

      // Kadınsı anatomik Valkür göğüs zırhı kubbeleri ve altın işlemeler
      for (final sx in const [-1.0, 1.0]) {
        s.ellipsoid(P3(sx * 0.082, 0.300, 0.140), 0.082, 0.072, 0.068,
            color: p.armor, surface: MatSurface.armor, shade: 1.10);
        s.ellipsoid(P3(sx * 0.082, 0.292, 0.148), 0.076, 0.022, 0.064,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.20);
      }
      // Göğüs ortası mücevherli altın broş
      s.ellipsoid(const P3(0, 0.310, 0.182), 0.028, 0.036, 0.020,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.22);
      s.ellipsoid(const P3(0, 0.310, 0.192), 0.016, 0.022, 0.014,
          color: p.glow, surface: MatSurface.bladeGold, shade: 1.38);
    });

    // Üst köprücük/boyun bloğu ve devasa boynuzlu omuzluklar (POV'da beyaz duvar oluşturmaması için gizlenir)
    final povHide = _pivot(r, 'povHide', torso, 0, 0, 0);
    _addSculpt(povHide, 'valkyrie_titan_neck_$tag', (s) {
      s.loft([
        Section(const P3(0, 0.325, 0.024), 0.205, 0.152,
            color: p.armor, surface: MatSurface.armor, shade: 1.10, frontSharp: 0.18),
        Section(const P3(0, 0.40, 0.010), 0.212, 0.132,
            color: p.giantSkin, surface: MatSurface.skin, shade: 1.05),
        Section(const P3(0, 0.465, -0.005), 0.082, 0.082,
            color: p.giantSkin, surface: MatSurface.skin, shade: 0.98),
      ], radial: 16);
      for (final sx in const [-1.0, 1.0]) {
        s.ellipsoid(P3(sx * 0.245, 0.385, 0.01), 0.095, 0.072, 0.102,
            color: p.armor, surface: MatSurface.armor, shade: 1.08, hemi: 0.62);
        s.ellipsoid(P3(sx * 0.252, 0.358, 0.01), 0.098, 0.022, 0.105,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.18);
        s.curvedHorn(
          P3(sx * 0.265, 0.41, 0.0),
          P3(sx * 0.355, 0.48, -0.03),
          P3(sx * 0.395, 0.57, -0.06),
          rBase: 0.026,
          baseColor: p.metal,
          tipColor: p.steelEdge,
          surface: MatSurface.bladeGold,
          steps: 5,
          ribbed: false,
        );
      }
    });

    // Gerçekçi Kadınsı Savaşçı Yüzü + Uzun Örgülü/Dalgalı Saçlar + Kanatlı Valkür Tacı (Sakal veya Kale YOK!)
    final head = _pivot(r, 'head', torso, 0, 0.47, 0.01);
    _addSculpt(head, 'valkyrie_titan_head_$tag', (s) {
      // Zarif ama güçlü kadınsı çene hattı, elmacık kemikleri ve alın
      s.loft([
        Section(const P3(0, 0.0, 0.012), 0.052, 0.060,
            color: p.giantSkin, surface: MatSurface.skin, shade: 0.96, frontSharp: 0.36),
        Section(const P3(0, 0.062, 0.018), 0.084, 0.094,
            color: p.giantSkin, surface: MatSurface.skin, shade: 1.04, frontSharp: 0.24),
        Section(const P3(0, 0.125, 0.010), 0.088, 0.098,
            color: p.giantSkin, surface: MatSurface.skin, shade: 1.06),
        Section(const P3(0, 0.185, -0.006), 0.072, 0.084,
            color: p.hair, surface: MatSurface.cloth, shade: 0.96),
      ], radial: 16);
      // İnce burun sırtı ve dolgun dudaklar
      s.curvedHorn(
        const P3(0, 0.112, 0.088),
        const P3(0, 0.086, 0.108),
        const P3(0, 0.068, 0.098),
        rBase: 0.011,
        baseColor: p.giantSkin,
        tipColor: p.giantSkin,
        surface: MatSurface.skin,
        steps: 3,
        ribbed: false,
      );
      s.ellipsoid(const P3(0, 0.045, 0.090), 0.019, 0.0065, 0.010,
          color: mixColor(p.giantSkin, p.blood, 0.52), surface: MatSurface.skin, shade: 1.08);

      // Kirpik gölgeli keskin badem gözler
      for (final sx in const [-1.0, 1.0]) {
        s.ellipsoid(P3(sx * 0.032, 0.104, 0.084), 0.016, 0.0065, 0.008,
            color: 0x181018, surface: MatSurface.cloth, shade: 0.68);
        s.ellipsoid(P3(sx * 0.032, 0.103, 0.088), 0.0105, 0.0055, 0.006,
            color: p.glow, surface: MatSurface.bladeGold, shade: 1.38);
      }

      // Sırtına ve omuzlarına dökülen gür dalgalı & örgülü savaşçı kadın saçları
      s.loft([
        Section(const P3(0, 0.175, -0.015), 0.098, 0.102,
            color: p.hair, surface: MatSurface.cloth, shade: 0.98),
        Section(const P3(0, 0.04, -0.065), 0.124, 0.088,
            color: p.hair, surface: MatSurface.cloth, shade: 0.94, folds: 10, foldAmp: 0.11),
        Section(const P3(0, -0.16, -0.115), 0.132, 0.072,
            color: p.hair, surface: MatSurface.cloth, shade: 0.90, folds: 10, foldAmp: 0.14),
        Section(const P3(0, -0.34, -0.145), 0.095, 0.045,
            color: p.hair, surface: MatSurface.cloth, shade: 0.84, folds: 8, foldAmp: 0.16),
      ], radial: 14, arcStart: math.pi * 0.72, arcLen: math.pi * 1.56);
      // Ön omuzlara düşen ikiz savaş örgüleri
      for (final sx in const [-1.0, 1.0]) {
        s.limb([
          (P3(sx * 0.078, 0.08, 0.01), 0.024, 0.024, p.hair, 0.98),
          (P3(sx * 0.092, -0.06, 0.045), 0.020, 0.020, p.hair, 0.94),
          (P3(sx * 0.086, -0.18, 0.065), 0.014, 0.014, p.metal, 1.18),
        ], surface: MatSurface.cloth, radial: 7, muscleSwelling: 0.08);
      }

      // Kanatlı ve Boynuzlu Altın Valkür Savaş Diademi (Sıfır kale burcu!)
      s.ellipsoid(const P3(0, 0.142, 0.012), 0.092, 0.018, 0.100,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.20);
      s.curvedHorn(
        const P3(0, 0.145, 0.102),
        const P3(0, 0.195, 0.112),
        const P3(0, 0.235, 0.102),
        rBase: 0.016,
        baseColor: p.metal,
        tipColor: p.glow,
        surface: MatSurface.bladeGold,
        steps: 4,
        ribbed: false,
      );
      for (final sx in const [-1.0, 1.0]) {
        s.curvedHorn(
          P3(sx * 0.086, 0.150, 0.01),
          P3(sx * 0.168, 0.215, -0.04),
          P3(sx * 0.195, 0.315, -0.08),
          rBase: 0.025,
          baseColor: p.metal,
          tipColor: p.horn,
          surface: MatSurface.bladeGold,
          steps: 6,
          ribbed: true,
        );
      }
    }, doubleSide: true);

    // Sol kol: Atletik kadın kolu + altın pazubent + deri kolluk + el + Dikenli Valkür Kol Kalkanı
    final armL = _pivot(r, 'armL', torso, -0.262, 0.37, 0.02);
    _addSculpt(armL, 'valkyrie_titan_armL_$tag', (s) {
      s.limb([
        (const P3(0, 0, 0), 0.066, 0.066, p.giantSkin, 1.02),
        (const P3(-0.045, -0.16, 0.08), 0.058, 0.060, p.giantSkin, 1.0),
        (const P3(-0.035, -0.28, 0.19), 0.052, 0.054, p.leather, 0.98),
        (const P3(-0.028, -0.33, 0.24), 0.048, 0.052, p.giantSkin, 1.02),
      ], surface: MatSurface.skin, muscleSwelling: 0.16);
      s.ellipsoid(const P3(-0.025, -0.09, 0.04), 0.064, 0.014, 0.064,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.20);
      // Yuvarlak dövme çelik ve altın Valkür kol kalkanı
      s.ellipsoid(const P3(-0.082, -0.23, 0.17), 0.028, 0.132, 0.132,
          color: p.armor, surface: MatSurface.armor, shade: 1.10);
      s.ellipsoid(const P3(-0.104, -0.23, 0.17), 0.020, 0.054, 0.054,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.22);
    });
    armL.rotation.x = -0.22;

    // Sağ kol: Atletik kadın kolu + eldivenli yumruk + Devasa Dövme Çelik Savaş Balyozu (War-Maul)
    final armR = _pivot(r, 'armR', torso, 0.262, 0.37, 0.02);
    _addSculpt(armR, 'valkyrie_titan_armR_$tag', (s) {
      s.limb([
        (const P3(0, 0, 0), 0.068, 0.068, p.giantSkin, 1.02),
        (const P3(0.045, -0.16, 0.09), 0.058, 0.060, p.giantSkin, 1.0),
        (const P3(0.03, -0.27, 0.20), 0.052, 0.054, p.leather, 0.98),
        (const P3(0.03, -0.31, 0.23), 0.050, 0.054, p.giantSkin, 1.04),
      ], surface: MatSurface.skin, muscleSwelling: 0.16);
      s.ellipsoid(const P3(0.025, -0.09, 0.045), 0.064, 0.014, 0.064,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.20);
      s.loft([
        Section(const P3(0.03, -0.52, 0.15), 0.032, 0.032,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.14),
        Section(const P3(0.03, -0.46, 0.16), 0.024, 0.024,
            color: p.wood, surface: MatSurface.horn, shade: 0.95),
        Section(const P3(0.03, 0.24, 0.28), 0.028, 0.028,
            color: p.wood, surface: MatSurface.horn, shade: 0.98),
        Section(const P3(0.03, 0.32, 0.295), 0.042, 0.042,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.18),
      ], radial: 8);
      // Pahlı dövme çelik savaş balyozu başı + altın kuşaklar + arka delici gaga
      s.ellipsoid(const P3(0.03, 0.33, 0.31), 0.132, 0.122, 0.232,
          color: p.armor, surface: MatSurface.armor, shade: 1.08, stacks: 6, slices: 8, flat: true);
      s.beveledBox(const P3(0.03, 0.33, 0.31), 0.280, 0.260, 0.082,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.20, rotY: 0);
      s.ellipsoid(const P3(0.03, 0.33, 0.542), 0.090, 0.090, 0.038,
          color: p.steel, surface: MatSurface.bladeGold, shade: 1.20, flat: true, slices: 8);
      s.curvedHorn(
        const P3(0.03, 0.33, 0.09),
        const P3(0.03, 0.34, -0.02),
        const P3(0.03, 0.28, -0.14),
        rBase: 0.044,
        baseColor: p.steel,
        tipColor: p.steelEdge,
        surface: MatSurface.bladeGold,
        steps: 4,
        ribbed: false,
      );
    });
    armR.rotation.x = -0.34;
  }

  // ===================================================== 5. VAMPİR KRALİÇE (Kan Kontesi - Eklemli Bacak & Gövde!)
  void _vampireQueen(CreatureRig r, Palette p, String tag) {
    _addGroundContact(r, p, tag, 0.34);

    // Ön yırtmaçlı gotik elbisenin içinden görünen eklemli topuklu çizmeli bacaklar (POV ve yürüyüş için!)
    for (final (name, sx, fz) in [('legL', -1.0, 0.02), ('legR', 1.0, -0.02)]) {
      final leg = _pivot(r, name, r.body, sx * 0.082, 0.45, 0.0);
      _addSculpt(leg, 'queen_${name}_$tag', (s) {
        s.loft([
          Section(P3(0, -0.445, fz + 0.078), 0.028, 0.018,
              color: p.dark, surface: MatSurface.leather, shade: 0.90),
          Section(P3(0, -0.415, fz + 0.022), 0.038, 0.064,
              color: p.capeLining, surface: MatSurface.leather, shade: 0.98),
          Section(P3(0, -0.30, fz), 0.036, 0.040,
              color: p.dark, surface: MatSurface.leather, shade: 0.95),
        ], radial: 10);
        s.limb([
          (P3(0, -0.31, fz), 0.035, 0.038, p.dark, 0.96),
          (P3(0, -0.16, fz + 0.022), 0.044, 0.048, p.queenSkin, 1.02),
          (const P3(0, 0, 0), 0.055, 0.058, p.dress, 0.96),
        ], surface: MatSurface.leather, muscleSwelling: 0.14);
        s.ellipsoid(P3(0, -0.18, fz + 0.046), 0.032, 0.036, 0.020,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.18);
      });
    }

    // Ön yırtmaçlı 12-pileli gotik kadife etek + altın kemerli korse + yakut gerdanlıklı üst gövde
    final torso = _pivot(r, 'torso', r.body, 0, 0.45, 0);
    _addSculpt(torso, 'queen_torso_$tag', (s) {
      // Arkadan ve yanlardan yere uzanan, önü bacak hareketine açık yırtmaçlı kadife kuyruk etek
      s.loft([
        Section(const P3(0, -0.435, -0.05), 0.295, 0.335,
            color: p.capeLining, surface: MatSurface.cloth, shade: 0.88, folds: 12, foldAmp: 0.09),
        Section(const P3(0, -0.34, -0.03), 0.258, 0.288,
            color: p.dress, surface: MatSurface.cloth, shade: 0.94, folds: 12, foldAmp: 0.10),
        Section(const P3(0, -0.12, -0.01), 0.168, 0.175,
            color: p.dress, surface: MatSurface.cloth, shade: 0.98, folds: 10, foldAmp: 0.07),
        Section(const P3(0, 0.03, 0.0), 0.142, 0.122,
            color: p.cloth, surface: MatSurface.cloth, shade: 1.02),
      ], radial: 14, arcStart: math.pi * 0.26, arcLen: math.pi * 1.48);

      // Kadife korse, ince bel ve göğüs
      s.loft([
        Section(const P3(0, 0.01, 0.0), 0.136, 0.114,
            color: p.cloth, surface: MatSurface.cloth, shade: 1.00, folds: 8, foldAmp: 0.04),
        Section(const P3(0, 0.15, 0.005), 0.094, 0.078,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.16),
        Section(const P3(0, 0.275, 0.018), 0.132, 0.104,
            color: p.dress, surface: MatSurface.cloth, shade: 1.06, frontSharp: 0.18),
      ], radial: 16);
    }, doubleSide: true);

    final povHide = _pivot(r, 'povHide', torso, 0, 0, 0);
    _addSculpt(povHide, 'queen_neck_$tag', (s) {
      s.loft([
        Section(const P3(0, 0.275, 0.018), 0.132, 0.104,
            color: p.dress, surface: MatSurface.cloth, shade: 1.06, frontSharp: 0.18),
        Section(const P3(0, 0.35, 0.010), 0.132, 0.082,
            color: p.queenSkin, surface: MatSurface.skin, shade: 1.05),
        Section(const P3(0, 0.405, 0.005), 0.044, 0.044,
            color: p.queenSkin, surface: MatSurface.skin, shade: 1.0),
      ], radial: 16);
      s.ellipsoid(const P3(0, 0.325, 0.094), 0.024, 0.032, 0.016,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.20);
      s.ellipsoid(const P3(0, 0.325, 0.100), 0.016, 0.022, 0.014,
          color: p.blood, surface: MatSurface.bladeGold, shade: 1.35);
    });

    // Kraliyet kadife pelerini
    final cape = _pivot(r, 'cape', torso, 0, 0.34, -0.04);
    _addSculpt(cape, 'queen_cape_$tag', (s) {
      s.loft([
        Section(const P3(0, 0, 0), 0.14, 0.035,
            color: p.cape, surface: MatSurface.cloth, shade: 0.98),
        Section(const P3(0, -0.24, -0.08), 0.22, 0.045,
            color: p.cape, surface: MatSurface.cloth, shade: 0.96, folds: 9, foldAmp: 0.11),
        Section(const P3(0, -0.50, -0.17), 0.29, 0.045,
            color: p.capeLining, surface: MatSurface.cloth, shade: 0.98, folds: 9, foldAmp: 0.15),
        Section(const P3(0, -0.72, -0.25), 0.33, 0.025,
            color: p.blood, surface: MatSurface.cloth, shade: 0.92, folds: 9, foldAmp: 0.18),
      ], radial: 14);
    }, doubleSide: true);

    // Gerçekçi yüz hatları + Aristokrat gotik yaka (head altında olduğundan POV'da görüşü kapatmaz!)
    final head = _pivot(r, 'head', torso, 0, 0.41, 0.01);
    _addSculpt(head, 'queen_head_$tag', (s) {
      // Aristokrat gotik kadife arka yaka
      s.loft([
        Section(const P3(0, -0.07, -0.03), 0.11, 0.09,
            color: p.capeLining, surface: MatSurface.cloth, shade: 0.95),
        Section(const P3(0, 0.06, -0.06), 0.182, 0.118,
            color: p.capeLining, surface: MatSurface.cloth, shade: 1.06, folds: 5, foldAmp: 0.14),
        Section(const P3(0, 0.15, -0.09), 0.210, 0.108,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.16, folds: 5, foldAmp: 0.18),
      ], radial: 10, arcStart: math.pi * 1.08, arcLen: math.pi * 0.84);

      s.loft([
        Section(const P3(0, 0.0, 0.012), 0.036, 0.045,
            color: p.queenSkin, surface: MatSurface.skin, shade: 0.96, frontSharp: 0.38),
        Section(const P3(0, 0.046, 0.014), 0.062, 0.072,
            color: p.queenSkin, surface: MatSurface.skin, shade: 1.03, frontSharp: 0.24),
        Section(const P3(0, 0.095, 0.006), 0.066, 0.075,
            color: p.queenSkin, surface: MatSurface.skin, shade: 1.06),
        Section(const P3(0, 0.145, -0.005), 0.052, 0.062,
            color: p.hair, surface: MatSurface.cloth, shade: 0.95),
      ], radial: 16);
      // İnce zarif burun sırtı ve dudak
      s.curvedHorn(
        const P3(0, 0.082, 0.066),
        const P3(0, 0.062, 0.082),
        const P3(0, 0.048, 0.074),
        rBase: 0.0085,
        baseColor: p.queenSkin,
        tipColor: p.queenSkin,
        surface: MatSurface.skin,
        steps: 3,
        ribbed: false,
      );
      s.ellipsoid(const P3(0, 0.032, 0.068), 0.013, 0.0045, 0.007,
          color: p.blood, surface: MatSurface.skin, shade: 1.12);
      for (final sx in const [-1.0, 1.0]) {
        s.ellipsoid(P3(sx * 0.023, 0.076, 0.064), 0.012, 0.005, 0.006,
            color: 0x160E18, surface: MatSurface.cloth, shade: 0.7);
        s.ellipsoid(P3(sx * 0.023, 0.075, 0.067), 0.0075, 0.004, 0.005,
            color: p.blood, surface: MatSurface.bladeGold, shade: 1.35);
      }
      // Omuzlara dökülen dolgun dalgalı saçlar
      s.loft([
        Section(const P3(0, 0.135, -0.012), 0.075, 0.078,
            color: p.hair, surface: MatSurface.cloth, shade: 0.96),
        Section(const P3(0, 0.02, -0.052), 0.090, 0.065,
            color: p.hair, surface: MatSurface.cloth, shade: 0.92, folds: 8, foldAmp: 0.10),
        Section(const P3(0, -0.15, -0.085), 0.082, 0.048,
            color: p.hair, surface: MatSurface.cloth, shade: 0.86, folds: 8, foldAmp: 0.14),
      ], radial: 12, arcStart: math.pi * 0.78, arcLen: math.pi * 1.44);
      // İnce telkâri gotik taç (Filigree Tiara)
      for (final a in const [-0.68, -0.34, 0.0, 0.34, 0.68]) {
        final h = a == 0.0 ? 0.088 : (a.abs() < 0.5 ? 0.058 : 0.038);
        final bx = math.sin(a) * 0.062, bz = math.cos(a) * 0.062;
        s.curvedHorn(
          P3(bx, 0.132, bz),
          P3(bx * 1.10, 0.132 + h * 0.6, bz * 1.06),
          P3(bx * 1.15, 0.132 + h, bz * 1.10),
          rBase: a == 0.0 ? 0.013 : 0.009,
          baseColor: p.metal,
          tipColor: a == 0.0 ? p.blood : p.metal,
          surface: MatSurface.bladeGold,
          steps: 4,
          ribbed: false,
        );
      }
    }, doubleSide: true);

    // Sol kol + Kızıl pençeli zarif el + Havada süzülen Kan Küresi
    final armL = _pivot(r, 'armL', torso, -0.138, 0.32, 0.02);
    _addSculpt(armL, 'queen_armL_$tag', (s) {
      s.limb([
        (const P3(0, 0, 0), 0.036, 0.036, p.dress, 1.0),
        (const P3(-0.06, -0.10, 0.08), 0.030, 0.030, p.dress, 0.98),
        (const P3(-0.05, -0.05, 0.20), 0.025, 0.025, p.queenSkin, 1.04),
      ], surface: MatSurface.cloth);
      for (final fx in const [-0.016, 0.0, 0.016]) {
        s.curvedHorn(
          P3(-0.05 + fx, -0.05, 0.215),
          P3(-0.05 + fx * 1.2, -0.03, 0.245),
          P3(-0.05 + fx, -0.01, 0.258),
          rBase: 0.0055,
          baseColor: p.queenSkin,
          tipColor: p.blood,
          surface: MatSurface.skin,
          steps: 3,
          ribbed: false,
        );
      }
    });
    final orb = _addSculpt(armL, 'queen_orb_$tag', (s) {
      s.ellipsoid(const P3(0, 0, 0), 1.0, 1.0, 1.0, color: p.blood, shade: 1.35);
    }, glow: true, groundAo: false);
    orb.position.setValues(-0.05, 0.05, 0.25);
    orb.scale.setValues(0.044, 0.044, 0.044);
    r.parts['orb'] = orb;

    // Sağ kol: Kanatlı Kan Kadehi Asası
    final armR = _pivot(r, 'armR', torso, 0.138, 0.32, 0.02);
    _addSculpt(armR, 'queen_armR_$tag', (s) {
      s.limb([
        (const P3(0, 0, 0), 0.036, 0.036, p.dress, 1.0),
        (const P3(0.06, -0.11, 0.08), 0.030, 0.030, p.dress, 0.98),
        (const P3(0.05, -0.12, 0.18), 0.025, 0.025, p.queenSkin, 1.04),
      ], surface: MatSurface.cloth);
      s.loft([
        Section(const P3(0.05, -0.62, 0.15), 0.012, 0.012,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.12),
        Section(const P3(0.05, 0.22, 0.20), 0.013, 0.013,
            color: p.dark, surface: MatSurface.armor, shade: 0.96),
        Section(const P3(0.05, 0.28, 0.205), 0.032, 0.032,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.18),
      ], radial: 8);
      s.ellipsoid(const P3(0.05, 0.34, 0.208), 0.034, 0.056, 0.034,
          color: p.blood, surface: MatSurface.bladeGold, shade: 1.35, flat: true, slices: 6);
      for (final sx in const [-1.0, 1.0]) {
        s.curvedHorn(
          const P3(0.05, 0.29, 0.205),
          P3(0.05 + sx * 0.075, 0.34, 0.205),
          P3(0.05 + sx * 0.055, 0.42, 0.205),
          rBase: 0.012,
          baseColor: p.metal,
          tipColor: p.steelEdge,
          surface: MatSurface.bladeGold,
          steps: 5,
          ribbed: false,
        );
      }
    });

    for (var i = 0; i < 2; i++) {
      final bat = makeBat(p);
      bat.userData['angle'] = i * math.pi;
      r.body.add(bat);
      r.orbiters.add(bat);
    }
  }

  /// Vampir Kraliçe'nin zar kanatlı yarasaları.
  three.Group makeBat(Palette p, {double size = 1.0}) {
    final g = three.Group();
    final key = p == Palette.white ? 'w' : 'b';
    _addSculpt(g, 'bat_body_$key', (s) {
      s.ellipsoid(const P3(0, 0, 0), 0.022, 0.018, 0.034,
          color: p.dark, surface: MatSurface.leather, shade: 0.95);
      for (final sx in const [-1.0, 1.0]) {
        s.curvedHorn(
          P3(sx * 0.010, 0.012, 0.018),
          P3(sx * 0.016, 0.028, 0.020),
          P3(sx * 0.018, 0.038, 0.016),
          rBase: 0.006,
          baseColor: p.dark,
          tipColor: p.capeLining,
          steps: 3,
          ribbed: false,
        );
      }
    }, groundAo: false);
    for (final sx in const [-1.0, 1.0]) {
      final w = three.Group();
      w.userData['side'] = sx;
      _addSculpt(w, 'bat_wing_${sx > 0 ? "R" : "L"}_$key', (s) {
        final a = [
          const P3(0, 0, 0.01),
          P3(sx * 0.045, 0.012, 0.015),
          P3(sx * 0.095, 0.005, -0.005),
        ];
        final b = [
          const P3(0, 0, -0.015),
          P3(sx * 0.038, -0.005, -0.030),
          P3(sx * 0.075, -0.012, -0.042),
        ];
        s.wingWeb(a, b, boneSideColor: p.dark, midWebColor: p.blood, sag: 0.006);
      }, doubleSide: true, groundAo: false);
      g.add(w);
    }
    g.scale.setValues(size, size, size);
    return g;
  }

  // ===================================================== 6. BARBAR KRAL (Kuzey Hükümdarı)
  void _barbarianKing(CreatureRig r, Palette p, String tag) {
    _addGroundContact(r, p, tag, 0.38);

    // Eklemli kürklü ve zırhlı hükümdar bacakları
    for (final (name, sx, fz) in [('legL', -1.0, 0.025), ('legR', 1.0, -0.025)]) {
      final leg = _pivot(r, name, r.body, sx * 0.132, 0.48, 0.0);
      _addSculpt(leg, 'king_${name}_$tag', (s) {
        s.loft([
          Section(P3(0, -0.475, fz + 0.08), 0.048, 0.030,
              color: p.leather, surface: MatSurface.leather, shade: 0.86),
          Section(P3(0, -0.445, fz + 0.02), 0.064, 0.090,
              color: p.leather, surface: MatSurface.leather, shade: 0.95),
          Section(P3(0, -0.34, fz), 0.062, 0.068,
              color: p.fur, surface: MatSurface.cloth, shade: 0.98, folds: 7, foldAmp: 0.08),
        ], radial: 10);
        s.limb([
          (P3(0, -0.35, fz), 0.060, 0.066, p.armor, 1.0),
          (P3(0, -0.17, fz + 0.025), 0.068, 0.074, p.metal, 1.10),
          (const P3(0, 0, 0), 0.078, 0.082, p.armor, 0.98),
        ], surface: MatSurface.armor, muscleSwelling: 0.18);
        s.ellipsoid(P3(0, -0.17, fz + 0.068), 0.052, 0.048, 0.032,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.18);
      });
    }

    // Geniş hükümdar gövdesi + zırh eteği
    final torso = _pivot(r, 'torso', r.body, 0, 0.48, 0);
    _addSculpt(torso, 'king_torso_$tag', (s) {
      s.loft([
        Section(const P3(0, -0.12, 0), 0.215, 0.175,
            color: p.cloth, surface: MatSurface.cloth, shade: 0.92, folds: 8, foldAmp: 0.08),
        Section(const P3(0, 0.02, 0), 0.184, 0.150,
            color: p.leather, surface: MatSurface.leather, shade: 0.96),
        Section(const P3(0, 0.07, 0.01), 0.198, 0.162,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.15),
        Section(const P3(0, 0.20, 0.015), 0.208, 0.162,
            color: p.armor, surface: MatSurface.armor, shade: 1.04, frontSharp: 0.22),
        Section(const P3(0, 0.32, 0.018), 0.228, 0.168,
            color: p.armor, surface: MatSurface.armor, shade: 1.08, frontSharp: 0.24),
      ], radial: 14);
    });

    // Kalın kurt postu omuz mantosu ve boyun kapağı (POV'da görüşü kapatmaması için gizlenir)
    final povHide = _pivot(r, 'povHide', torso, 0, 0, 0);
    _addSculpt(povHide, 'king_neck_$tag', (s) {
      s.loft([
        Section(const P3(0, 0.32, 0.018), 0.228, 0.168,
            color: p.armor, surface: MatSurface.armor, shade: 1.08, frontSharp: 0.24),
        Section(const P3(0, 0.42, 0.0), 0.185, 0.145,
            color: p.fur, surface: MatSurface.cloth, shade: 1.0),
        Section(const P3(0, 0.46, 0.0), 0.085, 0.085,
            color: p.skin, surface: MatSurface.skin, shade: 0.98),
      ], radial: 14);
      s.loft([
        Section(const P3(0, 0.36, -0.02), 0.288, 0.218,
            color: p.fur, surface: MatSurface.cloth, shade: 0.98, folds: 9, foldAmp: 0.08),
        Section(const P3(0, 0.44, -0.03), 0.268, 0.198,
            color: p.fur, surface: MatSurface.cloth, shade: 1.06, folds: 9, foldAmp: 0.09),
      ], radial: 12, arcStart: math.pi * 0.72, arcLen: math.pi * 1.56);
      for (final sx in const [-1.0, 1.0]) {
        s.ellipsoid(P3(sx * 0.14, 0.37, 0.148), 0.038, 0.038, 0.024,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.22);
      }
    });

    // Kürklü kraliyet savaş pelerini
    final cape = _pivot(r, 'cape', torso, 0, 0.40, -0.10);
    _addSculpt(cape, 'king_cape_$tag', (s) {
      s.loft([
        Section(const P3(0, 0, 0), 0.21, 0.05,
            color: p.fur, surface: MatSurface.cloth, shade: 1.0),
        Section(const P3(0, -0.24, -0.07), 0.26, 0.055,
            color: p.cloth, surface: MatSurface.cloth, shade: 0.96, folds: 8, foldAmp: 0.11),
        Section(const P3(0, -0.52, -0.14), 0.31, 0.05,
            color: p.clothDark, surface: MatSurface.cloth, shade: 0.90, folds: 8, foldAmp: 0.15),
        Section(const P3(0, -0.78, -0.20), 0.34, 0.03,
            color: p.fur, surface: MatSurface.cloth, shade: 0.94, folds: 8, foldAmp: 0.16),
      ], radial: 12);
    }, doubleSide: true);

    // Örgülü gür sakallı yüz + Boynuzlu Kuzey Hükümdar Miğfer-Tacı
    final head = _pivot(r, 'head', torso, 0, 0.46, 0.01);
    _addSculpt(head, 'king_head_$tag', (s) {
      s.loft([
        Section(const P3(0, 0.0, 0.01), 0.062, 0.068,
            color: p.skin, surface: MatSurface.skin, shade: 0.95),
        Section(const P3(0, 0.065, 0.015), 0.078, 0.085,
            color: p.skin, surface: MatSurface.skin, shade: 1.04, frontSharp: 0.22),
        Section(const P3(0, 0.13, 0.005), 0.084, 0.092,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.16),
        Section(const P3(0, 0.19, -0.005), 0.068, 0.074,
            color: p.armor, surface: MatSurface.armor, shade: 1.08),
      ], radial: 14);
      // Gür örgülü kral sakalı ve altın sakal halkası
      s.loft([
        Section(const P3(0, 0.055, 0.055), 0.068, 0.050,
            color: p.hair, surface: MatSurface.cloth, shade: 0.98, folds: 6, foldAmp: 0.10),
        Section(const P3(0, -0.035, 0.075), 0.056, 0.044,
            color: p.hair, surface: MatSurface.cloth, shade: 0.94, folds: 6, foldAmp: 0.12),
        Section(const P3(0, -0.135, 0.085), 0.026, 0.024,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.18),
      ], radial: 10);
      // Burun siperi + taç sivrilikleri + gömülü gözler + fildişi boynuzlar
      s.beveledBox(const P3(0, 0.095, 0.092), 0.018, 0.062, 0.020,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.18, rotY: 0);
      for (final a in const [-0.45, 0.0, 0.45]) {
        final h = a == 0.0 ? 0.068 : 0.045;
        s.curvedHorn(
          P3(math.sin(a) * 0.080, 0.145, math.cos(a) * 0.082),
          P3(math.sin(a) * 0.085, 0.145 + h * 0.6, math.cos(a) * 0.086),
          P3(math.sin(a) * 0.088, 0.145 + h, math.cos(a) * 0.088),
          rBase: 0.014,
          baseColor: p.metal,
          tipColor: p.steelEdge,
          surface: MatSurface.bladeGold,
          steps: 3,
          ribbed: false,
        );
      }
      for (final sx in const [-1.0, 1.0]) {
        s.ellipsoid(P3(sx * 0.028, 0.086, 0.078), 0.011, 0.006, 0.008,
            color: p.glow, surface: MatSurface.bladeGold, shade: 1.38);
        s.curvedHorn(
          P3(sx * 0.078, 0.148, 0.0),
          P3(sx * 0.188, 0.205, -0.02),
          P3(sx * 0.158, 0.345, 0.065),
          rBase: 0.028,
          baseColor: p.hornBase,
          tipColor: p.horn,
          steps: 7,
          ribbed: true,
        );
      }
    });

    // Sol kol: Kaslı kol, dövme zırh eldiveni ve fildişi Kuzey Savaş Borusu (War-Horn)
    final armL = _pivot(r, 'armL', torso, -0.23, 0.34, 0.02);
    _addSculpt(armL, 'king_armL_$tag', (s) {
      s.limb([
        (const P3(0, 0, 0), 0.064, 0.064, p.skin, 1.02),
        (const P3(-0.05, -0.14, 0.07), 0.058, 0.060, p.skin, 1.0),
        (const P3(-0.04, -0.24, 0.17), 0.054, 0.056, p.metal, 1.14),
      ], surface: MatSurface.skin, muscleSwelling: 0.20);
      // Altın çemberli kıvrık fildişi savaş borusu
      s.curvedHorn(
        const P3(-0.04, -0.26, 0.14),
        const P3(-0.06, -0.20, 0.26),
        const P3(-0.02, -0.07, 0.34),
        rBase: 0.042,
        baseColor: p.metal,
        tipColor: p.horn,
        surface: MatSurface.horn,
        steps: 6,
        ribbed: true,
      );
    });
    armL.rotation.x = -0.18;
    armL.rotation.z = 0.14;

    // Sağ kol: Çift Ağızlı Hilal Savaş Baltası (Double-Bitted Great-Axe)
    final armR = _pivot(r, 'armR', torso, 0.23, 0.34, 0.02);
    _addSculpt(armR, 'king_armR_$tag', (s) {
      s.limb([
        (const P3(0, 0, 0), 0.066, 0.066, p.skin, 1.02),
        (const P3(0.05, -0.14, 0.08), 0.060, 0.062, p.skin, 1.0),
        (const P3(0.035, -0.24, 0.18), 0.054, 0.056, p.metal, 1.14),
      ], surface: MatSurface.skin, muscleSwelling: 0.20);
      s.loft([
        Section(const P3(0.035, -0.52, 0.14), 0.028, 0.028,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.16),
        Section(const P3(0.035, -0.46, 0.15), 0.020, 0.020,
            color: p.wood, surface: MatSurface.horn, shade: 0.94),
        Section(const P3(0.035, 0.34, 0.25), 0.022, 0.022,
            color: p.wood, surface: MatSurface.horn, shade: 0.98),
        Section(const P3(0.035, 0.42, 0.26), 0.034, 0.034,
            color: p.metal, surface: MatSurface.bladeGold, shade: 1.18),
      ], radial: 8);
      s.blade([
        (const P3(0.035, 0.42, 0.26), 0.030, 0.014),
        (const P3(0.035, 0.57, 0.278), 0.002, 0.002),
      ], steelColor: p.steel, edgeColor: p.steelEdge);
      for (final dirZ in const [1.0, -1.0]) {
        s.blade([
          (P3(0.035, 0.33, 0.25 + dirZ * 0.02), 0.018, 0.014),
          (P3(0.035, 0.34, 0.25 + dirZ * 0.12), 0.088, 0.010),
          (P3(0.035, 0.35, 0.25 + dirZ * 0.21), 0.158, 0.005),
          (P3(0.035, 0.36, 0.25 + dirZ * 0.25), 0.178, 0.0015),
        ], steelColor: p.steel, edgeColor: p.steelEdge);
      }
      s.ellipsoid(const P3(0.035, 0.34, 0.25), 0.026, 0.042, 0.042,
          color: p.metal, surface: MatSurface.bladeGold, shade: 1.24);
    });
    armR.rotation.x = -0.28;
    armR.rotation.z = -0.12;
  }
}
