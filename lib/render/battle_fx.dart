import 'dart:async';
import 'dart:math' as math;

import 'package:three_js/three_js.dart' as three;

/// Basit 3B vektör (heap üzerinde Vector3 tahsisi yapmadan hızlı hesap için).
class P3 {
  const P3(this.x, this.y, this.z);
  final double x, y, z;

  P3 operator +(P3 o) => P3(x + o.x, y + o.y, z + o.z);
  P3 operator -(P3 o) => P3(x - o.x, y - o.y, z - o.z);
  P3 operator *(double k) => P3(x * k, y * k, z * k);
  double get length => math.sqrt(x * x + y * y + z * z);
  double get flatLength => math.sqrt(x * x + z * z);
  P3 get flatNormal {
    final l = flatLength;
    return l < 1e-6 ? const P3(0, 0, 1) : P3(x / l, 0, z / l);
  }

  P3 withY(double ny) => P3(x, ny, z);
  static P3 lerp(P3 a, P3 b, double t) =>
      P3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);
  static P3 of(three.Vector3 v) =>
      P3(v.x.toDouble(), v.y.toDouble(), v.z.toDouble());
}

double smooth(double t) => t * t * (3 - 2 * t);
double easeOut(double t) => 1 - (1 - t) * (1 - t);
double easeIn(double t) => t * t;
double easeOutBack(double t) {
  const c1 = 1.70158, c3 = c1 + 1;
  final u = t - 1;
  return 1 + c3 * u * u * u + c1 * u * u;
}

/// İki 0xRRGGBB rengini doğrusal karıştırır.
int mixColor(int a, int b, double t) {
  t = t.clamp(0.0, 1.0);
  int ch(int s) {
    final ca = (a >> s) & 0xFF, cb = (b >> s) & 0xFF;
    return (ca + (cb - ca) * t).round() & 0xFF;
  }

  return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

/// Three.js Color nesnesine doğrudan 0xRRGGBB yazar (alfa belirsizliği olmadan).
void setHexRgb(three.Color c, int hex) {
  c.red = ((hex >> 16) & 0xFF) / 255.0;
  c.green = ((hex >> 8) & 0xFF) / 255.0;
  c.blue = (hex & 0xFF) / 255.0;
}

class _Job {
  _Job(this.start, this.duration, this.step);
  final double start;
  final double duration;
  final void Function(double t) step;
  final Completer<void> done = Completer<void>();
}

enum AnimKind { move, combat, fixed }

/// Zaman çizelgesi: hareket (`moveSpeed`) ve dövüş (`combatSpeed`) hızlarını
/// bağımsız slider'lar üzerinden ayrı ayrı ölçekler; `fixed` ise sabit gerçek süredir.
class Animator {
  final List<_Job> _jobs = [];
  final List<_Job> _doneScratch = [];
  double now = 0;
  double moveSpeed = 0.80;
  double combatSpeed = 0.70;

  double _factorOf(AnimKind kind) => switch (kind) {
        AnimKind.move => moveSpeed.clamp(0.30, 3.0),
        AnimKind.combat => combatSpeed.clamp(0.25, 3.0),
        AnimKind.fixed => 1.0,
      };

  Future<void> play(
    double seconds,
    void Function(double t) step, {
    AnimKind kind = AnimKind.move,
  }) {
    final scaled = seconds / _factorOf(kind);
    final job = _Job(now, math.max(0.001, scaled), step);
    _jobs.add(job);
    return job.done.future;
  }

  Future<void> wait(double seconds, {AnimKind kind = AnimKind.move}) =>
      play(seconds, (_) {}, kind: kind);

  void tick(double time) {
    now = time;
    if (_jobs.isEmpty) return;
    _doneScratch.clear();
    final len = _jobs.length;
    for (var i = 0; i < len; i++) {
      final job = _jobs[i];
      final t = ((now - job.start) / job.duration).clamp(0.0, 1.0);
      job.step(t);
      if (t >= 1.0) {
        _doneScratch.add(job);
      }
    }
    if (_doneScratch.isNotEmpty) {
      for (final job in _doneScratch) {
        _jobs.remove(job);
        if (!job.done.isCompleted) job.done.complete();
      }
      _doneScratch.clear();
    }
  }

  void clear() => _jobs.clear();
}

class _PData {
  double x = 0, y = 0, z = 0;
  double vx = 0, vy = 0, vz = 0;
  double r = 1, g = 1, b = 1;
  double life = 0.5;
  double age = 0;
  double gravity = 0;
  double drag = 0;
  double s0 = 0.05, s1 = 0;
  double angle = 0;
  double spin = 0;
  bool shard = false;
}

/// Tek bir dinamik BufferGeometry içinde yüzlerce parçacığı 1 draw call ile çizer.
class _ParticleBatch {
  _ParticleBatch(three.Object3D parent, {required this.maxCount, required bool additive}) {
    const vertsPerParticle = 12; // 2 çapraz 3B dörtgen = 4 üçgen = 12 köşe
    final maxVerts = maxCount * vertsPerParticle;
    _posAttr = three.Float32BufferAttribute.fromList(
      List<double>.filled(maxVerts * 3, 0.0),
      3,
    )..setUsage(three.DynamicDrawUsage);
    _colAttr = three.Float32BufferAttribute.fromList(
      List<double>.filled(maxVerts * 4, 0.0),
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
    if (additive) mat.blending = three.AdditiveBlending;

    mesh = three.Mesh(_geo, mat)..frustumCulled = false;
    mesh.visible = false;
    parent.add(mesh);
  }

  final int maxCount;
  late final three.Float32BufferAttribute _posAttr;
  late final three.Float32BufferAttribute _colAttr;
  late final three.BufferGeometry _geo;
  late final three.Mesh mesh;
  final List<_PData> _active = [];
  final List<_PData> _free = [];

  void add({
    required P3 at,
    required int color,
    required P3 velocity,
    required double life,
    required double s0,
    required double s1,
    required double gravity,
    required double drag,
    required double angle,
    required double spin,
    required bool shard,
  }) {
    if (_active.length >= maxCount) return;
    final p = _free.isNotEmpty ? _free.removeLast() : _PData();
    p
      ..x = at.x
      ..y = at.y
      ..z = at.z
      ..vx = velocity.x
      ..vy = velocity.y
      ..vz = velocity.z
      ..r = ((color >> 16) & 0xFF) / 255.0
      ..g = ((color >> 8) & 0xFF) / 255.0
      ..b = (color & 0xFF) / 255.0
      ..life = math.max(0.05, life)
      ..age = 0
      ..gravity = gravity
      ..drag = drag
      ..s0 = s0
      ..s1 = s1
      ..angle = angle
      ..spin = spin
      ..shard = shard;
    _active.add(p);
  }

  void update(double dt) {
    if (_active.isEmpty) {
      if (mesh.visible) {
        mesh.visible = false;
        _geo.drawRange['count'] = 0;
      }
      return;
    }

    final pa = _posAttr.array;
    final ca = _colAttr.array;
    var vCursor = 0;

    for (var i = _active.length - 1; i >= 0; i--) {
      final p = _active[i];
      p.age += dt;
      final t = p.age / p.life;
      if (t >= 1.0) {
        _free.add(_active.removeAt(i));
        continue;
      }
      if (p.drag > 0) {
        final k = math.max(0.0, 1.0 - p.drag * dt);
        p.vx *= k;
        p.vy *= k;
        p.vz *= k;
      }
      p.vy += p.gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.z += p.vz * dt;
      if (p.gravity < 0 && p.y < 0.21) {
        p.y = 0.21;
        p.vy = -p.vy * 0.28;
        p.vx *= 0.62;
        p.vz *= 0.62;
      }
      p.angle += p.spin * dt;

      final size = math.max(0.002, p.s0 + (p.s1 - p.s0) * t);
      final alpha = p.shard
          ? (t > 0.7 ? 1.0 - (t - 0.7) / 0.3 : 1.0)
          : (1.0 - t * t) * 0.92;

      final ca1 = math.cos(p.angle) * size;
      final sa1 = math.sin(p.angle) * size;
      final h = p.shard ? size * 0.65 : size;

      // Dörtgen 1: dikey çapraz kanat
      _writeQuad(
        pa, ca, vCursor,
        p.x - ca1, p.y - h, p.z - sa1,
        p.x + ca1, p.y - h * 0.2, p.z + sa1,
        p.x + ca1 * 0.8, p.y + h, p.z + sa1 * 0.8,
        p.x - ca1 * 0.8, p.y + h * 0.2, p.z - sa1 * 0.8,
        p.r, p.g, p.b, alpha,
      );
      vCursor += 6;

      // Dörtgen 2: dik açılı ikinci kanat (her kamera açısından hacimli görünüm)
      _writeQuad(
        pa, ca, vCursor,
        p.x + sa1, p.y - h * 0.6, p.z - ca1,
        p.x - sa1, p.y - h * 0.6, p.z + ca1,
        p.x - sa1 * 0.7, p.y + h * 0.6, p.z + ca1 * 0.7,
        p.x + sa1 * 0.7, p.y + h * 0.6, p.z - ca1 * 0.7,
        p.r, p.g, p.b, alpha,
      );
      vCursor += 6;
    }

    mesh.visible = vCursor > 0;
    _geo.drawRange['count'] = vCursor;
    _posAttr.needsUpdate = true;
    _colAttr.needsUpdate = true;
  }

  void _writeQuad(
    dynamic pa,
    dynamic ca,
    int v0,
    double x0, double y0, double z0,
    double x1, double y1, double z1,
    double x2, double y2, double z2,
    double x3, double y3, double z3,
    double r, double g, double b, double a,
  ) {
    void vtx(int k, double x, double y, double z) {
      final pi = (v0 + k) * 3;
      pa[pi] = x;
      pa[pi + 1] = y;
      pa[pi + 2] = z;
      final ci = (v0 + k) * 4;
      ca[ci] = r;
      ca[ci + 1] = g;
      ca[ci + 2] = b;
      ca[ci + 3] = a;
    }

    vtx(0, x0, y0, z0);
    vtx(1, x1, y1, z1);
    vtx(2, x2, y2, z2);
    vtx(3, x0, y0, z0);
    vtx(4, x2, y2, z2);
    vtx(5, x3, y3, z3);
  }

  void clear() {
    _free.addAll(_active);
    _active.clear();
    mesh.visible = false;
    _geo.drawRange['count'] = 0;
  }
}

class _PooledFx {
  _PooledFx(this.mesh, this.mat);
  final three.Mesh mesh;
  final three.MeshBasicMaterial mat;
  bool active = false;
  double age = 0;
  double life = 0.4;
  double s0 = 0.1;
  double s1 = 1.0;
  double spin = 0;
  double maxOpacity = 0.9;
}

/// Sıfır sahne ekleme/çıkarma ve sıfır shader yeniden derlemesiyle çalışan
/// ultra-hızlı savaş efektleri sistemi.
class FxSystem {
  FxSystem(this.layer) {
    _glowBatch = _ParticleBatch(layer, maxCount: 280, additive: true);
    _smokeBatch = _ParticleBatch(layer, maxCount: 160, additive: false);

    // Sahneye yalnızca 1 kez eklenen kalıcı savaş ışığı (shader derlemesini önler)
    _combatLight = three.PointLight(0xFFAA55, 0.0, 7.5);
    _combatLight.position.setValues(0, -10, 0);
    layer.add(_combatLight);

    final ringGeo = three.RingGeometry(0.76, 1.0, 28);
    for (var i = 0; i < 5; i++) {
      final mat = _makeFxMat();
      final m = three.Mesh(ringGeo, mat)
        ..rotation.x = -math.pi / 2
        ..visible = false;
      layer.add(m);
      _rings.add(_PooledFx(m, mat));
    }

    final slashGeo = three.TorusGeometry(1, 0.042, 4, 20, math.pi * 0.95);
    for (var i = 0; i < 6; i++) {
      final mat = _makeFxMat();
      final m = three.Mesh(slashGeo, mat)..visible = false;
      layer.add(m);
      _slashes.add(_PooledFx(m, mat));
    }

    final pillarGeo = three.CylinderGeometry(0.34, 0.46, 1.0, 16, 1, true);
    for (var i = 0; i < 2; i++) {
      final mat = _makeFxMat();
      final m = three.Mesh(pillarGeo, mat)..visible = false;
      layer.add(m);
      _pillars.add(_PooledFx(m, mat));
    }
  }

  final three.Object3D layer;
  final math.Random rng = math.Random();
  late final _ParticleBatch _glowBatch;
  late final _ParticleBatch _smokeBatch;
  late final three.PointLight _combatLight;
  final List<_PooledFx> _rings = [];
  final List<_PooledFx> _slashes = [];
  final List<_PooledFx> _pillars = [];

  double _lightPeak = 0;
  double _lightLife = 0.4;
  double _lightAge = 1.0;
  double shake = 0;

  three.MeshBasicMaterial _makeFxMat() {
    final m = three.MeshBasicMaterial.fromMap({
      'color': 0xFFFFFF,
      'transparent': true,
      'opacity': 0.9,
      'depthWrite': false,
    });
    m.blending = three.AdditiveBlending;
    m.side = three.DoubleSide;
    return m;
  }

  _PooledFx _acquire(List<_PooledFx> pool) {
    for (final fx in pool) {
      if (!fx.active) return fx;
    }
    return pool.first;
  }

  double r([double a = 1]) => (rng.nextDouble() * 2 - 1) * a;
  double particleScale = 1.0;

  void spawn(
    P3 at, {
    required int color,
    P3 velocity = const P3(0, 0, 0),
    double life = 0.6,
    double size = 0.06,
    double endSize = 0.0,
    double gravity = 0,
    double drag = 0.0,
    bool glow = true,
    bool shard = false,
    double spin = 0,
  }) {
    final batch = glow ? _glowBatch : _smokeBatch;
    batch.add(
      at: at,
      color: color,
      velocity: velocity,
      life: life,
      s0: size,
      s1: endSize,
      gravity: gravity,
      drag: drag,
      angle: rng.nextDouble() * math.pi * 2,
      spin: spin != 0 ? spin : r(3.0),
      shard: shard,
    );
  }

  void burst(
    P3 at,
    List<int> colors, {
    int count = 22,
    double speed = 2.0,
    double size = 0.06,
    double life = 0.65,
    double gravity = -3.5,
    bool glow = true,
    bool shards = false,
    double up = 1.0,
  }) {
    final n = math.max(1, (count * particleScale).round());
    for (var i = 0; i < n; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final e = rng.nextDouble() * 0.9 + 0.1;
      final s = speed * (0.4 + rng.nextDouble() * 0.8);
      spawn(
        at,
        color: colors[i % colors.length],
        velocity: P3(
          math.cos(a) * s * (1 - e * 0.4),
          s * e * up,
          math.sin(a) * s * (1 - e * 0.4),
        ),
        life: life * (0.6 + rng.nextDouble() * 0.55),
        size: size * (0.65 + rng.nextDouble() * 0.75),
        endSize: shards ? size * 0.35 : 0.0,
        gravity: gravity,
        drag: 1.2,
        glow: glow,
        shard: shards,
        spin: shards ? r(11) : r(3),
      );
    }
  }

  void smoke(P3 at, int color, {int count = 12, double radius = 0.3, double life = 0.75}) {
    final n = math.max(1, (count * particleScale).round());
    for (var i = 0; i < n; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final s = 0.35 + rng.nextDouble() * 0.55;
      spawn(
        at + P3(math.cos(a) * radius * 0.3, rng.nextDouble() * 0.45, math.sin(a) * radius * 0.3),
        color: color,
        velocity: P3(math.cos(a) * s, 0.38 + rng.nextDouble() * 0.55, math.sin(a) * s),
        life: life * (0.7 + rng.nextDouble() * 0.45),
        size: 0.075,
        endSize: 0.20,
        drag: 2.4,
        glow: false,
      );
    }
  }

  void shockwave(P3 at, int color, {double radius = 1.4, double life = 0.48, double y = 0.22}) {
    final fx = _acquire(_rings);
    setHexRgb(fx.mat.color, color);
    fx.mat.opacity = 0.9;
    fx.mesh.position.setValues(at.x, y, at.z);
    fx.mesh.scale.setValues(0.12, 0.12, 0.12);
    fx.mesh.visible = true;
    fx
      ..active = true
      ..age = 0
      ..life = life
      ..s0 = 0.12
      ..s1 = radius
      ..spin = 0
      ..maxOpacity = 0.9;
  }

  void slash(P3 at, int color, double yaw,
      {double tilt = 0, double size = 0.58, double life = 0.32}) {
    final fx = _acquire(_slashes);
    setHexRgb(fx.mat.color, color);
    fx.mat.opacity = 1.0;
    fx.mesh.position.setValues(at.x, at.y, at.z);
    fx.mesh.rotation.set(0, yaw, tilt);
    fx.mesh.scale.setValues(size * 0.7, size * 0.7, size * 0.7);
    fx.mesh.visible = true;
    fx
      ..active = true
      ..age = 0
      ..life = life
      ..s0 = size * 0.7
      ..s1 = size * 1.18
      ..spin = 7.5
      ..maxOpacity = 1.0;
  }

  void pillar(P3 at, int color, {double life = 0.85, double height = 2.8}) {
    final fx = _acquire(_pillars);
    setHexRgb(fx.mat.color, color);
    fx.mat.opacity = 0.78;
    fx.mesh.position.setValues(at.x, at.y + height * 0.5, at.z);
    fx.mesh.scale.setValues(1.0, height, 1.0);
    fx.mesh.visible = true;
    fx
      ..active = true
      ..age = 0
      ..life = life
      ..s0 = 1.0
      ..s1 = 0.18
      ..spin = 2.5
      ..maxOpacity = 0.78;
  }

  void flash(P3 at, int color, {double intensity = 14, double life = 0.4, double distance = 7.5}) {
    if (_combatLight.color != null) {
      setHexRgb(_combatLight.color!, color);
    }
    _combatLight.position.setValues(at.x, at.y, at.z);
    _combatLight.distance = distance;
    _combatLight.intensity = intensity;
    _lightPeak = intensity;
    _lightLife = math.max(0.05, life);
    _lightAge = 0;
  }

  void addShake(double amount) => shake = math.max(shake, amount);

  void update(double dt) {
    _glowBatch.update(dt);
    _smokeBatch.update(dt);

    for (final fx in _rings) {
      if (!fx.active) continue;
      fx.age += dt;
      final t = fx.age / fx.life;
      if (t >= 1.0) {
        fx.active = false;
        fx.mesh.visible = false;
      } else {
        final s = fx.s0 + (fx.s1 - fx.s0) * easeOut(t);
        fx.mesh.scale.setValues(s, s, 1);
        fx.mat.opacity = (1 - t) * fx.maxOpacity;
      }
    }

    for (final fx in _slashes) {
      if (!fx.active) continue;
      fx.age += dt;
      final t = fx.age / fx.life;
      if (t >= 1.0) {
        fx.active = false;
        fx.mesh.visible = false;
      } else {
        final s = fx.s0 + (fx.s1 - fx.s0) * easeOut(t);
        fx.mesh.scale.setValues(s, s, s);
        fx.mesh.rotation.x += fx.spin * dt * 0.3;
        fx.mesh.rotation.z += fx.spin * dt;
        fx.mat.opacity = (1 - t) * fx.maxOpacity;
      }
    }

    for (final fx in _pillars) {
      if (!fx.active) continue;
      fx.age += dt;
      final t = fx.age / fx.life;
      if (t >= 1.0) {
        fx.active = false;
        fx.mesh.visible = false;
      } else {
        final s = fx.s0 + (fx.s1 - fx.s0) * easeOut(t);
        fx.mesh.scale.x = s;
        fx.mesh.scale.z = s;
        fx.mesh.rotation.y += fx.spin * dt;
        fx.mat.opacity = (1 - t) * fx.maxOpacity;
      }
    }

    if (_lightAge < _lightLife) {
      _lightAge += dt;
      final t = (_lightAge / _lightLife).clamp(0.0, 1.0);
      _combatLight.intensity = _lightPeak * (1 - t) * (1 - t);
    } else if (_combatLight.intensity != 0) {
      _combatLight.intensity = 0;
    }

    shake = math.max(0.0, shake - dt * 0.75);
  }

  void clear() {
    _glowBatch.clear();
    _smokeBatch.clear();
    for (final pool in [_rings, _slashes, _pillars]) {
      for (final fx in pool) {
        fx.active = false;
        fx.mesh.visible = false;
      }
    }
    _combatLight.intensity = 0;
    _lightAge = _lightLife;
    shake = 0;
  }
}
