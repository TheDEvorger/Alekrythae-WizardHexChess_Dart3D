import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as three;
import 'package:wizard_hex_chess_dart3d/audio/thunder_synth.dart';
import 'package:wizard_hex_chess_dart3d/render/battle_fx.dart';
import 'package:wizard_hex_chess_dart3d/render/lightning_storm.dart';
import 'package:wizard_hex_chess_dart3d/render/storm_vortex.dart';
import 'package:wizard_hex_chess_dart3d/ui/atmosphere_slider.dart';

/// 16 bit PCM mono WAV üretir.
Uint8List _pcm16(List<int> samples) {
  final out = ByteData(44 + samples.length * 2);
  void ascii(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, 1, Endian.little);
  out.setUint32(24, 44100, Endian.little);
  out.setUint32(28, 88200, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  out.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    out.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

int _sample(Uint8List wav, int i) => ByteData.sublistView(wav).getInt16(44 + i * 2, Endian.little);

Iterable<three.Mesh> _visibleBolts(three.Object3D parent) =>
    parent.children.whereType<three.Mesh>().where((m) => m.renderOrder == 5 && m.visible);

void main() {
  group('%100 üstü ses yükseltme (yumuşak sınırlayıcı)', () {
    test('Sessiz kısımlar doğrusal yükselir, tepeler kırpılmadan tam ölçeğe yaklaşır', () {
      final src = _pcm16([0, 3000, -3000, 20000, -32000, 32767]);
      final out = ThunderSynth.boostWav(src, 2.0)!;
      expect(out.length, src.length);
      expect(out.sublist(0, 44), src.sublist(0, 44), reason: 'başlık korunur');
      expect(_sample(out, 0), 0);
      expect(_sample(out, 1), closeTo(6000, 2));
      expect(_sample(out, 2), closeTo(-6000, 2));
      // Eşiği aşan örnekler sıkıştırılır ama sıralama (dinamik) korunur
      expect(_sample(out, 3), greaterThan(23000));
      expect(_sample(out, 3), lessThan(_sample(out, 5)));
      expect(_sample(out, 4), lessThan(-23000));
      for (var i = 0; i < 6; i++) {
        expect(_sample(out, i).abs(), lessThanOrEqualTo(32767));
      }
    });

    test('PCM16 olmayan veya bozuk dosya yükseltilmez', () {
      expect(ThunderSynth.boostWav(Uint8List(10), 2.0), isNull);
      final bad = _pcm16([1, 2, 3]);
      ByteData.sublistView(bad).setUint16(34, 8, Endian.little); // 8 bit
      expect(ThunderSynth.boostWav(bad, 2.0), isNull);
    });
  });

  group('Atmosfer kaydırıcısı: elle giriş + onay', () {
    Future<List<double>> pump(WidgetTester tester, {double value = 1.0}) async {
      final applied = <double>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AtmosphereSlider(
              icon: Icons.cyclone_rounded,
              color: Colors.blue,
              title: 'FIRTINA GÜCÜ',
              value: applied.isEmpty ? value : applied.last,
              sliderMax: 3.0,
              hardMax: 10.0,
              divisions: 60,
              onChanged: (v) => setState(() => applied.add(v)),
            ),
          ),
        ),
      ));
      return applied;
    }

    testWidgets('Kaydırıcı sınırının üstündeki değer onay düğmesiyle uygulanır', (tester) async {
      final applied = await pump(tester);
      await tester.enterText(find.byType(TextField), '450');
      await tester.pump();
      expect(applied, isEmpty, reason: 'onaylanmadan uygulanmaz');

      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(applied.single, closeTo(4.5, 1e-9));
      expect(find.text('SINIR ÜSTÜ'), findsOneWidget);
      expect(find.text('%450'), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 3.0, reason: 'kaydırıcı en uçta durur');
    });

    testWidgets('Sınır verilmişse aşan değer sınıra çekilir, geçersiz giriş uygulanmaz', (tester) async {
      final applied = await pump(tester);
      await tester.enterText(find.byType(TextField), '99999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(applied.single, 10.0);

      await tester.enterText(find.byType(TextField), ',');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(applied.length, 1);
      expect(find.text('Geçerli bir sayı yaz'), findsOneWidget);
    });

    testWidgets('Sınır verilmezse (oyundaki ayarlar) çok büyük değer olduğu gibi uygulanır', (tester) async {
      final applied = <double>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AtmosphereSlider(
            icon: Icons.cloud_rounded,
            color: Colors.blueGrey,
            title: 'FIRTINA SİSİ',
            value: 1.0,
            sliderMax: 3.0,
            onChanged: applied.add,
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), '250000');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      expect(applied.single, closeTo(2500.0, 1e-9), reason: 'yüzde birimi: %250000 = 2500');
    });

    testWidgets('Tur biriminde değer tam sayıya yuvarlanır ve "tur" olarak gösterilir', (tester) async {
      final applied = <double>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AtmosphereSlider(
            icon: Icons.sports_kabaddi_rounded,
            color: Colors.orange,
            title: 'KAPIŞMA TURU',
            value: 4.0,
            sliderMax: 8.0,
            divisions: 8,
            unit: AtmosphereUnit.rounds,
            offLabel: 'Tek çarpışma',
            onChanged: applied.add,
          ),
        ),
      ));
      expect(find.text('4 tur'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '12,6');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      expect(applied.single, 13.0, reason: 'sınır yok, tam sayıya yuvarlanır');
    });

    testWidgets('Seviye biriminde "Sv." gösterilir, 0 sade etiketi çıkar, üst sınır yok', (tester) async {
      final applied = <double>[];
      Widget build(double value) => MaterialApp(
            home: Scaffold(
              body: AtmosphereSlider(
                icon: Icons.auto_awesome_motion_rounded,
                color: Colors.purple,
                title: 'DÜELLO KARMAŞIKLIĞI',
                value: value,
                sliderMax: 4.0,
                divisions: 4,
                unit: AtmosphereUnit.level,
                offLabel: 'Sv. 0 · Sade',
                describe: (v) => v >= 4 ? 'Destansı' : 'Usta',
                onChanged: applied.add,
              ),
            ),
          );
      await tester.pumpWidget(build(2.0));
      expect(find.text('Sv. 2 · Usta'), findsOneWidget);
      await tester.pumpWidget(build(0.0));
      expect(find.text('Sv. 0 · Sade'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '7');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      expect(applied.single, 7.0);
    });

    testWidgets('Saniye biriminde ondalık virgül kabul edilir', (tester) async {
      final applied = <double>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AtmosphereSlider(
            icon: Icons.timelapse_rounded,
            color: Colors.amber,
            title: 'YILDIRIM KALICILIĞI',
            value: 1.2,
            sliderMax: 3.0,
            hardMax: 10.0,
            unit: AtmosphereUnit.seconds,
            onChanged: applied.add,
          ),
        ),
      ));
      expect(find.text('1,2 sn'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '4,5');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      expect(applied.single, closeTo(4.5, 1e-9));
    });
  });

  group('Yıldırım kalıcılığı', () {
    LightningStorm makeStorm(three.Group parent, {required double linger}) {
      final vortex = StormVortex(three.Group(), detail: 0);
      return LightningStorm(
        parent: parent,
        storm: vortex,
        fx: FxSystem(three.Group()),
        skyLight: three.HemisphereLight(0xffffff, 0x000000, 1.0),
        strikeTargets: const [P3(14, 6, 0)],
        onThunder: (_) {},
      )
        ..rate = 0.0 // yalnızca elle çaktırılan yıldırım
        ..linger = linger;
    }

    void run(LightningStorm l, double seconds) {
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        l.update(1 / 60);
      }
    }

    test('Kalıcılık açıkken kanal çaktıktan sonra bir süre havada kalır, sonra söner', () {
      final parent = three.Group();
      final l = makeStorm(parent, linger: 1.2);
      l.triggerNow();
      run(l, 1.0);
      expect(_visibleBolts(parent), isNotEmpty);
      run(l, 2.5);
      expect(_visibleBolts(parent), isEmpty);
    });

    test('Kalıcılık kapalıyken kanal 1 saniye dolmadan söner', () {
      final parent = three.Group();
      final l = makeStorm(parent, linger: 0.0);
      l.triggerNow();
      run(l, 1.0);
      expect(_visibleBolts(parent), isEmpty);
    });

    test('Sahne ışığı çakışta yanıp sönmez: yalnızca yumuşakça söner', () {
      final parent = three.Group();
      final sky = three.HemisphereLight(0xffffff, 0x000000, 1.65);
      final l = LightningStorm(
        parent: parent,
        storm: StormVortex(three.Group(), detail: 0),
        fx: FxSystem(three.Group()),
        skyLight: sky,
        strikeTargets: const [P3(14, 6, 0)],
        onThunder: (_) {},
      )
        ..rate = 0.0
        ..power = 3.0
        ..linger = 1.2;
      l.triggerNow();
      const dt = 1 / 60;
      var prev = sky.intensity;
      var peak = prev;
      for (var i = 0; i < 240; i++) {
        l.update(dt);
        final cur = sky.intensity;
        final prevAdd = prev - 1.65;
        // Bir karede en fazla ~0,24 sn'lik üssel sönüş kadar azalabilir (stroboskop yok);
        // yalnızca gözle görülmeyecek kadar küçük kalıntı en sonda sıfıra oturur.
        if (prevAdd > 0.01) {
          expect(cur - 1.65, greaterThanOrEqualTo(prevAdd * 0.92 - 1e-6), reason: 'kare $i');
        }
        peak = cur > peak ? cur : peak;
        prev = cur;
      }
      expect(peak, greaterThan(1.65 + 0.5), reason: 'çakış sahneyi aydınlatır');
      expect(peak, lessThanOrEqualTo(1.65 + 2.0 + 1e-6), reason: 'tahta beyaza patlamaz');
      expect(sky.intensity, closeTo(1.65, 1e-6), reason: 'sonunda taban ışığına döner');
    });

    test('Aynı anda birden çok yıldırım havada kalabilir', () {
      final parent = three.Group();
      final l = makeStorm(parent, linger: 2.0);
      l.triggerNow();
      run(l, 0.4);
      l.triggerNow();
      run(l, 0.4);
      expect(_visibleBolts(parent).length, 2);
    });
  });

  group('Fırtına ayarları', () {
    void settle(StormVortex v) {
      for (var i = 0; i < 400; i++) {
        v.update(1 / 60);
      }
    }

    test('Üst sınır yok: büyük değerler olduğu gibi kalır, yalnızca negatif/NaN elenir', () {
      final v = StormVortex(three.Group(), detail: 0)
        ..setIntensity(99)
        ..setHaunt(-1)
        ..setFog(50);
      expect(v.intensity, 99.0);
      expect(v.haunt, 0.0);
      expect(v.fog, 50.0);
      v.setFog(double.nan);
      expect(v.fog, 50.0, reason: 'sayı olmayan giriş yok sayılır');
      settle(v);
      v.setDetail(3); // kalite değişince katmanlar yeniden kurulur, çökmez
      v.update(1 / 60);
    });

    test('Sis arttıkça kararmaz: renk her adımda açılır, sahne sisi yaklaşır, yer sisi koyulaşır', () {
      final scene = three.Scene();
      final sceneFog = three.Fog(0x070E1A, 24.0, 110.0);
      scene.fog = sceneFog;
      scene.background = three.Color.fromHex32(0x070E1A);
      final v = StormVortex(three.Group(), detail: 0, fog: 1.0)..bindScene(scene, fog: sceneFog);

      // Varsayılan (1) görünüm aynen korunur.
      expect(sceneFog.near, closeTo(24.0, 1e-9));
      expect(sceneFog.far, closeTo(110.0, 1e-9));
      expect(v.groundMist, 0.0);

      double brightness() => v.fogColor.x + v.fogColor.y + v.fogColor.z;
      var prevBright = brightness();
      var prevFar = sceneFog.far;
      var prevGround = v.groundMist;
      for (final f in [1.5, 2.0, 3.0, 5.0, 10.0, 25.0, 100.0]) {
        v.setFog(f, instant: true);
        expect(brightness(), greaterThan(prevBright), reason: 'sis $f: renk açılmalı (kararmamalı)');
        expect(sceneFog.far, lessThan(prevFar), reason: 'sis $f: görüş mesafesi kısalmalı');
        expect(v.groundMist, greaterThan(prevGround), reason: 'sis $f: yer sisi koyulaşmalı');
        prevBright = brightness();
        prevFar = sceneFog.far;
        prevGround = v.groundMist;
      }
      final bg = scene.background as three.Color;
      expect(bg.red, closeTo(v.fogColor.x, 1e-6), reason: 'arka plan da sise gömülür');

      // Sis 0: hava açılır, sahne sisi uzaklaşır.
      v.setFog(0.0, instant: true);
      expect(sceneFog.far, greaterThan(1000.0));
      expect(v.groundMist, 0.0);
    });

    test('Aynı sis ayarı her pencere boyutunda tahtayı aynı dozda sarar; varsayılan değişmez', () {
      final scene = three.Scene();
      final sceneFog = three.Fog(0x070E1A, 24.0, 110.0);
      scene.fog = sceneFog;
      final v = StormVortex(three.Group(), detail: 0, fog: 1.0)..bindScene(scene, fog: sceneFog);

      // Varsayılan sis: dar pencerede (kamera ~39 birim uzakta) de eskisiyle aynı.
      v.viewDistance = 39.0;
      expect(sceneFog.near, closeTo(24.0, 1e-9));
      expect(sceneFog.far, closeTo(110.0, 1e-9));

      // Yoğun sis: tahtadaki sis oranı kamera uzaklığından bağımsız.
      double boardFog(double camDist) {
        v.viewDistance = camDist;
        return ((camDist - sceneFog.near) / (sceneFog.far - sceneFog.near)).clamp(0.0, 1.0);
      }

      v.setFog(3.0, instant: true);
      expect(boardFog(39.0), closeTo(boardFog(23.0), 0.02));
    });

    test('Güç ve gizem arttıkça parçacık katmanları büyür (doz sürer, dar kapasitede takılmaz)', () {
      final v = StormVortex(three.Group(), detail: 0, intensity: 1.5, haunt: 0.75);
      expect(v.particleScale, 1, reason: 'varsayılan ayarlarda ek maliyet yok');
      v.setIntensity(10.0, instant: true);
      expect(v.particleScale, greaterThanOrEqualTo(4));
      v.setHaunt(6.0, instant: true);
      expect(v.particleScale, StormVortex.maxParticleScale);
      v
        ..setIntensity(1.5, instant: true)
        ..setHaunt(0.75, instant: true);
      expect(v.particleScale, 1, reason: 'değer düşünce katmanlar küçülür');
    });
  });

  group('Yıldırım sıklığı ve kalıcılığı sınırsız', () {
    test('Sıklık arttıkça çakış sayısı artmaya devam eder', () {
      int strikes(double rate) {
        var count = 0;
        final l = LightningStorm(
          parent: three.Group(),
          storm: StormVortex(three.Group(), detail: 0),
          fx: FxSystem(three.Group()),
          skyLight: three.HemisphereLight(0xffffff, 0x000000, 1.0),
          strikeTargets: const [P3(14, 6, 0)],
          onThunder: (_) => count++,
          seed: 7,
        )
          ..rate = rate
          ..linger = 0.0;
        for (var i = 0; i < 60 * 60; i++) {
          l.update(1 / 60);
        }
        return count;
      }

      final at4 = strikes(4.0);
      final at20 = strikes(20.0);
      final at100 = strikes(100.0);
      expect(at20, greaterThan(at4 * 2), reason: 'eskiden ~10 üstünde artış durmuştu');
      expect(at100, greaterThan(at20 * 2));
    });
  });
}
