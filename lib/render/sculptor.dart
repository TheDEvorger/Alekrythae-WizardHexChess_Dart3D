import 'dart:math' as math;

import 'package:three_js/three_js.dart' as three;

import 'battle_fx.dart';

/// Tek bir Mesh içinde 8 farklı fiziksel yüzey (PBR Roughness + Metalness) kanalı.
/// 8x1 ORM DataTexture ile eşleşir:
/// 0=skin, 1=cloth, 2=leather, 3=scale, 4=stone, 5=horn, 6=armor, 7=bladeGold
enum MatSurface {
  skin,
  cloth,
  leather,
  scale,
  stone,
  horn,
  armor,
  bladeGold;

  double get uvX => (index + 0.5) / 8.0;
}

/// 3B eğri boyunca uzanan organik, kumaş veya dövme zırh kesit tanımı.
class Section {
  const Section(
    this.pos,
    this.rx,
    this.rz, {
    required this.color,
    this.surface = MatSurface.armor,
    this.shade = 1.0,
    this.folds = 0,
    this.foldAmp = 0.0,
    this.foldPhase = 0.0,
    this.frontSharp = 0.0,
    this.backSharp = 0.0,
    this.flatBack = 0.0,
    this.twist = 0.0,
  });

  final P3 pos;
  final double rx;
  final double rz;
  final int color;
  final MatSurface surface;
  final double shade;
  final int folds;
  final double foldAmp;
  final double foldPhase;
  final double frontSharp;
  final double backSharp;
  final double flatBack;
  final double twist;
}

P3 _cross(P3 a, P3 b) =>
    P3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

double _dot(P3 a, P3 b) => a.x * b.x + a.y * b.y + a.z * b.z;

P3 _norm(P3 v) {
  final l = v.length;
  return l < 1e-8 ? const P3(0, 1, 0) : P3(v.x / l, v.y / l, v.z / l);
}

P3 _rotAxis(P3 v, P3 axis, double cosA, double sinA) {
  final k = axis * (_dot(axis, v) * (1 - cosA));
  final c = _cross(axis, v) * sinA;
  return P3(v.x * cosA + c.x + k.x, v.y * cosA + c.y + k.y, v.z * cosA + c.z + k.z);
}

/// Deterministik, sıfır-tahsisli 3B mikro doku dalgası (taş gözenekleri, deri/kürk kırçılı).
double _microGrain(P3 p, MatSurface surf) {
  final amp = switch (surf) {
    MatSurface.stone => 0.075,
    MatSurface.cloth => 0.048,
    MatSurface.leather => 0.045,
    MatSurface.scale => 0.055,
    MatSurface.skin => 0.028,
    MatSurface.horn => 0.036,
    MatSurface.armor => 0.022,
    MatSurface.bladeGold => 0.012,
  };
  final h = math.sin(p.x * 37.3 + p.y * 53.7 + p.z * 41.9) * 0.55 +
      math.cos(p.x * 83.1 - p.y * 67.4 + p.z * 79.2) * 0.45;
  return 1.0 + h * amp;
}

/// Tek bir BufferGeometry içinde anatomik uzuvlar, kumaş kıvrımları, boynuzlar,
/// dövme çelik zırh plakaları, gerçekçi bıçak ağızları ve kanat zarları ören heykeltıraş.
/// PBR UV kanalı ve yerleşik ortam kapatma (Ambient Occlusion) ile plastik görünümü yok eder.
class SculptBuilder {
  SculptBuilder({this.groundAo = true});

  final bool groundAo;
  final List<double> _pos = [];
  final List<double> _nrm = [];
  final List<double> _col = [];
  final List<double> _uv = [];
  final List<int> _idx = [];

  int get vertexCount => _pos.length ~/ 3;

  int _addVertex(
    P3 p,
    P3 n,
    int hex,
    double shade, {
    MatSurface surface = MatSurface.armor,
  }) {
    final idx = _pos.length ~/ 3;
    _pos
      ..add(p.x)
      ..add(p.y)
      ..add(p.z);
    _nrm
      ..add(n.x)
      ..add(n.y)
      ..add(n.z);
    _uv
      ..add(surface.uvX)
      ..add(0.5);

    // Yer teması gölgesi + mikro yüzey dokusu
    final yAo = groundAo ? (0.82 + 0.18 * (p.y / 0.28).clamp(0.0, 1.0)) : 1.0;
    final grain = _microGrain(p, surface);
    final s = (shade * yAo * grain).clamp(0.10, 1.55);

    var r = ((hex >> 16) & 0xFF) / 255.0 * s;
    var g = ((hex >> 8) & 0xFF) / 255.0 * s;
    var b = (hex & 0xFF) / 255.0 * s;

    // Cilt yüzeylerinde hafif sıcak alt-yüzey (subsurface) tonu
    if (surface == MatSurface.skin && s < 0.95) {
      r += 0.022 * (1.0 - s);
      g += 0.004 * (1.0 - s);
    }

    _col
      ..add(r.clamp(0.0, 1.0))
      ..add(g.clamp(0.0, 1.0))
      ..add(b.clamp(0.0, 1.0));
    return idx;
  }

  void _tri(int a, int b, int c) {
    _idx
      ..add(a)
      ..add(b)
      ..add(c);
  }

  /// Seçilen aralıktaki köşelerin yüzey normallerini pürüzsüz hesaplar ve
  /// alt-yüzey / oyuk (hemisphere cavity) derinliğini köşe renklerine işler.
  void _recomputeSmoothNormals(int vStart, int iStart) {
    for (var v = vStart * 3; v < _nrm.length; v++) {
      _nrm[v] = 0;
    }
    for (var i = iStart; i < _idx.length; i += 3) {
      final ia = _idx[i] * 3, ib = _idx[i + 1] * 3, ic = _idx[i + 2] * 3;
      final ax = _pos[ia], ay = _pos[ia + 1], az = _pos[ia + 2];
      final e1x = _pos[ib] - ax, e1y = _pos[ib + 1] - ay, e1z = _pos[ib + 2] - az;
      final e2x = _pos[ic] - ax, e2y = _pos[ic + 1] - ay, e2z = _pos[ic + 2] - az;
      final nx = e1y * e2z - e1z * e2y;
      final ny = e1z * e2x - e1x * e2z;
      final nz = e1x * e2y - e1y * e2x;
      for (final iv in [ia, ib, ic]) {
        if (iv >= vStart * 3) {
          _nrm[iv] += nx;
          _nrm[iv + 1] += ny;
          _nrm[iv + 2] += nz;
        }
      }
    }
    for (var v = vStart * 3; v < _nrm.length; v += 3) {
      final nx = _nrm[v], ny = _nrm[v + 1], nz = _nrm[v + 2];
      final l = math.sqrt(nx * nx + ny * ny + nz * nz);
      double uNy = 1.0;
      if (l > 1e-9) {
        _nrm[v] = nx / l;
        uNy = ny / l;
        _nrm[v + 1] = uNy;
        _nrm[v + 2] = nz / l;
      } else {
        _nrm[v + 1] = 1;
      }
      // Doğal yarıküre oyuk gölgesi (yukarı bakan yüzeyler aydınlık, çene/koltuk altı koyu)
      final hemi = 0.90 + 0.14 * uNy;
      _col[v] = (_col[v] * hemi).clamp(0.0, 1.0);
      _col[v + 1] = (_col[v + 1] * hemi).clamp(0.0, 1.0);
      _col[v + 2] = (_col[v + 2] * (hemi + (uNy < 0 ? 0.015 * (-uNy) : 0))).clamp(0.0, 1.0);
    }
  }

  /// Kesit dizisinden pürüzsüz organik veya dövme zırhlı 3B gövde örer.
  void loft(
    List<Section> sections, {
    int radial = 14,
    bool capStart = true,
    bool capEnd = true,
    bool flat = false,
    double arcStart = 0,
    double arcLen = math.pi * 2,
  }) {
    final m = sections.length;
    if (m < 2) return;
    final closed = (arcLen - math.pi * 2).abs() < 1e-4;
    final cols = closed ? radial : radial + 1;

    final tangents = List<P3>.filled(m, const P3(0, 1, 0));
    for (var i = 0; i < m; i++) {
      P3 d = const P3(0, 0, 0);
      if (i < m - 1) d = d + (sections[i + 1].pos - sections[i].pos);
      if (i > 0) d = d + (sections[i].pos - sections[i - 1].pos);
      if (d.length < 1e-7) {
        for (var k = 1; k < m; k++) {
          final alt = sections[math.min(m - 1, i + k)].pos -
              sections[math.max(0, i - k)].pos;
          if (alt.length > 1e-7) {
            d = alt;
            break;
          }
        }
      }
      tangents[i] = _norm(d.length < 1e-7 ? const P3(0, 1, 0) : d);
    }

    final uFrames = List<P3>.filled(m, const P3(1, 0, 0));
    final vFrames = List<P3>.filled(m, const P3(0, 0, 1));
    final t0 = tangents[0];
    final ref = t0.x.abs() > 0.9 ? const P3(0, 0, -1) : const P3(1, 0, 0);
    uFrames[0] = _norm(ref - t0 * _dot(ref, t0));
    vFrames[0] = _norm(_cross(uFrames[0], t0));

    for (var i = 1; i < m; i++) {
      final prevT = tangents[i - 1], curT = tangents[i];
      var u = uFrames[i - 1];
      final axis = _cross(prevT, curT);
      final sinA = axis.length;
      final cosA = _dot(prevT, curT).clamp(-1.0, 1.0);
      if (sinA > 1e-6) {
        u = _rotAxis(u, axis * (1.0 / sinA), cosA, sinA);
      }
      u = _norm(u - curT * _dot(u, curT));
      uFrames[i] = u;
      vFrames[i] = _norm(_cross(u, curT));
    }

    final grid = List.generate(m, (_) => List<P3>.filled(cols, const P3(0, 0, 0)));
    final shades = List.generate(m, (_) => List<double>.filled(cols, 1.0));

    for (var i = 0; i < m; i++) {
      final s = sections[i];
      final u = uFrames[i], v = vFrames[i];
      for (var j = 0; j < cols; j++) {
        final frac = j / radial;
        final th = arcStart + frac * arcLen + s.twist;
        final ct = math.cos(th), st = math.sin(th);
        var foldMod = 1.0;
        var foldShade = 1.0;
        if (s.folds > 0 && s.foldAmp != 0) {
          final wave = math.cos(s.folds * th + s.foldPhase);
          foldMod += s.foldAmp * wave;
          // Kıvrım çukurlarında derin kumaş/kas gölgesi
          foldShade += wave * s.foldAmp * 1.15;
        }
        var lx = ct * s.rx * foldMod;
        var lz = st * s.rz * foldMod;
        if (s.frontSharp > 0 && st > 0) {
          lx *= 1.0 - s.frontSharp * st * 0.65;
          lz += s.rz * s.frontSharp * st * st * 0.45;
        }
        if (s.backSharp > 0 && st < 0) {
          lx *= 1.0 - s.backSharp * (-st) * 0.65;
          lz -= s.rz * s.backSharp * st * st * 0.45;
        }
        if (s.flatBack > 0 && st < 0) {
          lz *= 1.0 - s.flatBack;
        }
        grid[i][j] = s.pos + u * lx + v * lz;
        shades[i][j] = s.shade * foldShade;
      }
    }

    if (flat) {
      for (var i = 0; i < m - 1; i++) {
        final colA = sections[i].color, colB = sections[i + 1].color;
        final surfA = sections[i].surface, surfB = sections[i + 1].surface;
        for (var j = 0; j < radial; j++) {
          final j1 = closed ? (j + 1) % cols : j + 1;
          final p00 = grid[i][j], p10 = grid[i + 1][j];
          final p11 = grid[i + 1][j1], p01 = grid[i][j1];
          final n = _norm(_cross(p10 - p00, p01 - p00));
          final hemi = 0.90 + 0.14 * n.y;
          final a = _addVertex(p00, n, colA, shades[i][j] * hemi, surface: surfA);
          final b = _addVertex(p10, n, colB, shades[i + 1][j] * hemi, surface: surfB);
          final c = _addVertex(p11, n, colB, shades[i + 1][j1] * hemi, surface: surfB);
          final d = _addVertex(p01, n, colA, shades[i][j1] * hemi, surface: surfA);
          _tri(a, b, c);
          _tri(a, c, d);
        }
      }
      if (closed && capStart && (sections.first.rx > 1e-4 || sections.first.rz > 1e-4)) {
        final s0 = sections.first;
        final n0 = tangents.first * -1;
        final c0 = _addVertex(s0.pos, n0, s0.color, s0.shade * 0.82, surface: s0.surface);
        final ring = [
          for (var j = 0; j < cols; j++)
            _addVertex(grid[0][j], n0, s0.color, shades[0][j] * 0.86, surface: s0.surface),
        ];
        for (var j = 0; j < radial; j++) {
          _tri(c0, ring[j], ring[(j + 1) % cols]);
        }
      }
      if (closed && capEnd && (sections.last.rx > 1e-4 || sections.last.rz > 1e-4)) {
        final sm = sections.last;
        final nm = tangents.last;
        final cm = _addVertex(sm.pos, nm, sm.color, sm.shade * 1.05, surface: sm.surface);
        final ring = [
          for (var j = 0; j < cols; j++)
            _addVertex(grid[m - 1][j], nm, sm.color, shades[m - 1][j], surface: sm.surface),
        ];
        for (var j = 0; j < radial; j++) {
          _tri(cm, ring[(j + 1) % cols], ring[j]);
        }
      }
      return;
    }

    final vStart = vertexCount;
    final iStart = _idx.length;
    final vIdx = List.generate(m, (_) => List<int>.filled(cols, 0));
    for (var i = 0; i < m; i++) {
      final sec = sections[i];
      for (var j = 0; j < cols; j++) {
        vIdx[i][j] = _addVertex(
          grid[i][j],
          const P3(0, 1, 0),
          sec.color,
          shades[i][j],
          surface: sec.surface,
        );
      }
    }
    for (var i = 0; i < m - 1; i++) {
      for (var j = 0; j < radial; j++) {
        final j1 = closed ? (j + 1) % cols : j + 1;
        final a = vIdx[i][j];
        final b = vIdx[i + 1][j];
        final c = vIdx[i + 1][j1];
        final d = vIdx[i][j1];
        _tri(a, b, c);
        _tri(a, c, d);
      }
    }
    _recomputeSmoothNormals(vStart, iStart);

    if (closed && capStart && (sections.first.rx > 1e-4 || sections.first.rz > 1e-4)) {
      final s0 = sections.first;
      final n0 = tangents.first * -1;
      final c0 = _addVertex(s0.pos, n0, s0.color, s0.shade * 0.85, surface: s0.surface);
      final ring = [
        for (var j = 0; j < cols; j++)
          _addVertex(grid[0][j], n0, s0.color, shades[0][j] * 0.9, surface: s0.surface),
      ];
      for (var j = 0; j < radial; j++) {
        _tri(c0, ring[j], ring[(j + 1) % cols]);
      }
    }
    if (closed && capEnd && (sections.last.rx > 1e-4 || sections.last.rz > 1e-4)) {
      final sm = sections.last;
      final nm = tangents.last;
      final cm = _addVertex(sm.pos, nm, sm.color, sm.shade * 1.05, surface: sm.surface);
      final ring = [
        for (var j = 0; j < cols; j++)
          _addVertex(grid[m - 1][j], nm, sm.color, shades[m - 1][j], surface: sm.surface),
      ];
      for (var j = 0; j < radial; j++) {
        _tri(cm, ring[(j + 1) % cols], ring[j]);
      }
    }
  }

  /// Anatomik kas şişkinliğine sahip bükümlü uzuv (bacak, kol, kuyruk).
  void limb(
    List<(P3 pos, double rx, double rz, int color, double shade)> nodes, {
    MatSurface surface = MatSurface.armor,
    int radial = 10,
    double muscleSwelling = 0.14,
    bool capStart = true,
    bool capEnd = true,
  }) {
    final sections = <Section>[];
    for (var i = 0; i < nodes.length; i++) {
      final (p, rx, rz, col, sh) = nodes[i];
      sections.add(Section(p, rx, rz, color: col, shade: sh, surface: surface));
      if (i < nodes.length - 1) {
        final (np, nrx, nrz, ncol, nsh) = nodes[i + 1];
        final mid = P3.lerp(p, np, 0.46);
        final swell = 1.0 + muscleSwelling;
        sections.add(Section(
          mid,
          (rx * 0.54 + nrx * 0.46) * swell,
          (rz * 0.54 + nrz * 0.46) * swell,
          color: mixColor(col, ncol, 0.45),
          shade: (sh + nsh) * 0.52,
          surface: surface,
        ));
      }
    }
    loft(sections, radial: radial, capStart: capStart, capEnd: capEnd);
  }

  /// Kıvrımlı gerçekçi boynuz, pençe, diş veya kemik dikeni.
  void curvedHorn(
    P3 start,
    P3 ctrl,
    P3 tip, {
    required double rBase,
    required int baseColor,
    required int tipColor,
    MatSurface surface = MatSurface.horn,
    int steps = 7,
    int radial = 9,
    bool ribbed = true,
  }) {
    final secs = <Section>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final u = 1 - t;
      final p = start * (u * u) + ctrl * (2 * u * t) + tip * (t * t);
      final rib = ribbed && i < steps ? (1.0 + 0.065 * math.sin(t * math.pi * 9)) : 1.0;
      final r = rBase * math.pow(1 - t * 0.94, 0.85) * rib;
      secs.add(Section(
        p,
        r,
        r,
        color: mixColor(baseColor, tipColor, t),
        surface: surface,
        shade: 0.76 + 0.34 * t,
      ));
    }
    loft(secs, radial: radial, capStart: true, capEnd: true);
  }

  /// Elmas kesitli, keskin ağızlı dövme çelik kılıç / hançer / balta / mızrak namlusu.
  void blade(
    List<(P3 pos, double halfWidth, double halfThick)> profile, {
    required int steelColor,
    required int edgeColor,
    MatSurface surface = MatSurface.bladeGold,
  }) {
    if (profile.length < 2) return;
    final secs = <Section>[];
    for (var i = 0; i < profile.length; i++) {
      final (p, hw, ht) = profile[i];
      secs.add(Section(
        p,
        ht,
        hw,
        color: i == 0 ? steelColor : mixColor(steelColor, edgeColor, 0.52),
        surface: surface,
        shade: 0.96 + 0.22 * (i / profile.length),
      ));
    }
    loft(secs, radial: 4, flat: true, capStart: true, capEnd: false);
  }

  /// Ejderha / yarasa kanat parmakları arasına gerilmiş gerçekçi deri zar.
  void wingWeb(
    List<P3> boneA,
    List<P3> boneB, {
    required int boneSideColor,
    required int midWebColor,
    double sag = 0.025,
  }) {
    final n = math.min(boneA.length, boneB.length);
    if (n < 2) return;
    const cols = 5;
    for (final side in const [1.0, -1.0]) {
      final vStart = vertexCount;
      final iStart = _idx.length;
      final grid = List.generate(n, (_) => List<int>.filled(cols, 0));
      for (var i = 0; i < n; i++) {
        final ti = i / (n - 1);
        for (var j = 0; j < cols; j++) {
          final tj = j / (cols - 1);
          var p = P3.lerp(boneA[i], boneB[i], tj);
          final arch = math.sin(tj * math.pi);
          if (i == n - 1) {
            final prevMid = P3.lerp(boneA[n - 2], boneB[n - 2], tj);
            p = P3.lerp(p, prevMid, arch * 0.28);
          }
          p = p + P3(0, -arch * sag + side * 0.0025, -arch * sag * 0.5);
          final col = mixColor(boneSideColor, midWebColor, arch);
          final sh = 0.72 + 0.34 * arch * (1 - ti * 0.25);
          grid[i][j] = _addVertex(
            p,
            P3(0, side, 0),
            col,
            sh,
            surface: MatSurface.leather,
          );
        }
      }
      for (var i = 0; i < n - 1; i++) {
        for (var j = 0; j < cols - 1; j++) {
          final a = grid[i][j], b = grid[i + 1][j];
          final c = grid[i + 1][j + 1], d = grid[i][j + 1];
          if (side > 0) {
            _tri(a, b, c);
            _tri(a, c, d);
          } else {
            _tri(a, c, b);
            _tri(a, d, c);
          }
        }
      }
      _recomputeSmoothNormals(vStart, iStart);
    }
  }

  /// Elipsoid / anatomik küremsi parça (omuzluk, kas kütlesi, kalkan göbeği, kaya).
  void ellipsoid(
    P3 center,
    double rx,
    double ry,
    double rz, {
    required int color,
    MatSurface surface = MatSurface.armor,
    double shade = 1.0,
    int stacks = 8,
    int slices = 12,
    bool flat = false,
    double hemi = 1.0,
    double jitter = 0.0,
    int seed = 1,
  }) {
    final rng = math.Random(seed);
    final secs = <Section>[];
    for (var i = 0; i <= stacks; i++) {
      final v = i / stacks;
      final phi = (hemi < 1.0)
          ? (1 - v) * (math.pi * hemi)
          : (1 - v) * math.pi;
      final y = math.cos(phi) * ry;
      final sinP = math.sin(phi);
      final jit = jitter > 0 && i > 0 && i < stacks
          ? 1.0 + (rng.nextDouble() * 2 - 1) * jitter
          : 1.0;
      secs.add(Section(
        center + P3(0, y, 0),
        math.max(0.0005, rx * sinP * jit),
        math.max(0.0005, rz * sinP * jit),
        color: color,
        surface: surface,
        shade: shade * (0.78 + 0.26 * v),
        folds: jitter > 0 ? 5 : 0,
        foldAmp: jitter * 0.5,
        foldPhase: i * 1.1,
      ));
    }
    loft(secs, radial: slices, flat: flat, capStart: hemi < 1.0, capEnd: false);
  }

  /// Pahlı (beveled) dövme prizma / zırh plakası / çekiç başı.
  void beveledBox(
    P3 center,
    double w,
    double h,
    double d, {
    required int color,
    MatSurface surface = MatSurface.armor,
    double bevel = 0.14,
    double shade = 1.0,
    double taperTop = 1.0,
    double rotY = math.pi / 4,
  }) {
    final rx = w * 0.707, rz = d * 0.707;
    final bh = h * bevel.clamp(0.04, 0.4);
    final hh = h * 0.5;
    loft(
      [
        Section(center + P3(0, -hh, 0), rx * (1 - bevel), rz * (1 - bevel),
            color: color, surface: surface, shade: shade * 0.72, twist: rotY),
        Section(center + P3(0, -hh + bh, 0), rx, rz,
            color: color, surface: surface, shade: shade * 0.9, twist: rotY),
        Section(center + P3(0, hh - bh, 0), rx * taperTop, rz * taperTop,
            color: color, surface: surface, shade: shade * 1.05, twist: rotY),
        Section(center + P3(0, hh, 0), rx * taperTop * (1 - bevel),
            rz * taperTop * (1 - bevel),
            color: color, surface: surface, shade: shade * 1.14, twist: rotY),
      ],
      radial: 4,
      flat: true,
    );
  }

  /// Savaşçının ayakları altına satranç kaidesi KOYMADAN doğal zemin gölgesi ve ince ordu halkası çizer.
  void groundAura({
    required int shadowColor,
    required int ringColor,
    double radius = 0.33,
  }) {
    const n = 18;
    const y = 0.008;
    final c = _addVertex(
      const P3(0, y, 0),
      const P3(0, 1, 0),
      shadowColor,
      0.42,
      surface: MatSurface.stone,
    );
    final inner = <int>[];
    final rimIn = <int>[];
    final rimOut = <int>[];
    for (var i = 0; i < n; i++) {
      final a = i * math.pi * 2 / n;
      final ca = math.cos(a), sa = math.sin(a);
      inner.add(_addVertex(
        P3(ca * radius * 0.88, y, sa * radius * 0.88),
        const P3(0, 1, 0),
        shadowColor,
        0.72,
        surface: MatSurface.stone,
      ));
      rimIn.add(_addVertex(
        P3(ca * radius * 0.90, y + 0.003, sa * radius * 0.90),
        const P3(0, 1, 0),
        ringColor,
        1.05,
        surface: MatSurface.bladeGold,
      ));
      rimOut.add(_addVertex(
        P3(ca * radius, y + 0.002, sa * radius),
        const P3(0, 1, 0),
        ringColor,
        0.75,
        surface: MatSurface.bladeGold,
      ));
    }
    for (var i = 0; i < n; i++) {
      final i1 = (i + 1) % n;
      _tri(c, inner[i1], inner[i]);
      _tri(rimIn[i], rimIn[i1], rimOut[i1]);
      _tri(rimIn[i], rimOut[i1], rimOut[i]);
    }
  }

  three.BufferGeometry build() {
    final g = three.BufferGeometry();
    g.setIndex(_idx);
    g.setAttribute(
      three.Attribute.position,
      three.Float32BufferAttribute.fromList(_pos, 3),
    );
    g.setAttribute(
      three.Attribute.normal,
      three.Float32BufferAttribute.fromList(_nrm, 3),
    );
    g.setAttribute(
      three.Attribute.color,
      three.Float32BufferAttribute.fromList(_col, 3),
    );
    g.setAttribute(
      three.Attribute.uv,
      three.Float32BufferAttribute.fromList(_uv, 2),
    );
    g.computeBoundingSphere();
    return g;
  }
}
