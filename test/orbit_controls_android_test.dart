import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as three;
import 'package:wizard_hex_chess_dart3d/render/safe_orbit_controls.dart';

void _expectFiniteCamera(three.PerspectiveCamera cam) {
  expect(cam.position.x.isFinite, isTrue, reason: 'camera.position.x sonlu olmalı');
  expect(cam.position.y.isFinite, isTrue, reason: 'camera.position.y sonlu olmalı');
  expect(cam.position.z.isFinite, isTrue, reason: 'camera.position.z sonlu olmalı');
  cam.updateMatrixWorld();
  for (var i = 0; i < 16; i++) {
    expect(cam.matrixWorld.storage[i].isFinite, isTrue, reason: 'matrixWorld[$i] sonlu olmalı');
    expect(
      cam.matrixWorldInverse.storage[i].isFinite,
      isTrue,
      reason: 'matrixWorldInverse[$i] sonlu olmalı',
    );
  }
}

void main() {
  group('Android ilk kare (0,0) ve SafeOrbitControls', () {
    testWidgets('ThreeJS.build ilk (0,0) karede Peripherals kurmaz; pozitif boyutta doğru ölçer',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final engine = three.ThreeJS(
        renderNumber: 1, // 100 ms gecikme: test bitiminde dispose ile native GL çağrılmaz
        setup: () {},
        onSetupComplete: () {},
      )
        ..scene = three.Scene()
        ..camera = three.PerspectiveCamera(54, 412 / 915, 0.15, 160);

      Widget wrap(Size size) => MediaQuery(
            data: MediaQueryData(size: size, devicePixelRatio: 2.0),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: engine.build(),
                ),
              ),
            ),
          );

      // 1) Android soğuk açılış ilk karesi: MediaQuery boyutu (0, 0)
      await tester.pumpWidget(wrap(Size.zero));
      expect(find.byType(three.Peripherals), findsNothing);
      expect(engine.globalKey.currentState, isNull);

      // 2) İkinci karede gerçek Android ekran boyutu gelir
      await tester.pumpWidget(wrap(const Size(412, 915)));
      await tester.pump();
      expect(find.byType(three.Peripherals), findsOneWidget);
      final peripherals = engine.globalKey.currentState!;
      expect(peripherals.clientWidth, 412.0);
      expect(peripherals.clientHeight, 915.0);

      engine.angle = null;
      engine.dispose();
      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('Peripherals 0x0 iken bile dokunup sürükleme kamerayı NaN yapmaz', (tester) async {
      final key = GlobalKey<three.PeripheralsState>();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 0,
              height: 0,
              child: three.Peripherals(
                key: key,
                builder: (_) => const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(key.currentState!.clientHeight, 0.0);

      final cam = three.PerspectiveCamera(54, 412 / 915, 0.15, 160)
        ..position.setValues(0, 18, 22);
      final orbit = SafeOrbitControls(cam, key)
        ..minPolarAngle = 0.18
        ..maxPolarAngle = 1.35
        ..minDistance = 6.5
        ..maxDistance = 48.0;
      addTearDown(orbit.dispose);

      // Dokunup sürükleme: eski OrbitControls burada clientHeight=0 ile NaN üretiyordu
      key.currentState!.overrideEmit(
        three.PeripheralType.pointerdown,
        three.WebPointerEvent()
          ..pointerId = 1
          ..pointerType = 'touch'
          ..pageX = 120
          ..pageY = 300,
      );
      key.currentState!.overrideEmit(
        three.PeripheralType.pointermove,
        three.WebPointerEvent()
          ..pointerId = 1
          ..pointerType = 'touch'
          ..pageX = 190
          ..pageY = 360,
      );
      key.currentState!.overrideEmit(
        three.PeripheralType.pointerup,
        three.WebPointerEvent()
          ..pointerId = 1
          ..pointerType = 'touch'
          ..pageX = 190
          ..pageY = 360,
      );

      _expectFiniteCamera(cam);
      expect(cam.position.x, closeTo(0.0, 1e-6));
      expect(cam.position.y, closeTo(18.0, 1e-6));
      expect(cam.position.z, closeTo(22.0, 1e-6));
    });

    testWidgets('Dokunup döndürme ve ekran yönü değişiminde canlı yükseklik kullanılır',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final key = GlobalKey<three.PeripheralsState>();
      Widget buildAt(Size size) => Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: three.Peripherals(
                  key: key,
                  builder: (_) => const ColoredBox(color: Color(0xFF000000)),
                ),
              ),
            ),
          );

      // Başlangıç: dikey ekran 412x915
      await tester.pumpWidget(buildAt(const Size(412, 915)));
      await tester.pump();

      final cam = three.PerspectiveCamera(54, 412 / 915, 0.15, 160)
        ..position.setValues(0, 18, 22);
      final orbit = SafeOrbitControls(cam, key)
        ..rotateSpeed = 1.0
        ..minPolarAngle = 0.18
        ..maxPolarAngle = 1.35
        ..minDistance = 6.5
        ..maxDistance = 48.0;
      addTearDown(orbit.dispose);

      // Gerçek dokunma sürüklemesi
      final gesture = await tester.startGesture(
        const Offset(200, 400),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveBy(const Offset(80, 40));
      await gesture.up();
      await tester.pump();

      _expectFiniteCamera(cam);
      expect(cam.position.x.abs(), greaterThan(0.5), reason: 'yatay dönüş kamerayı kaydırmalı');

      // Ekranı yataya döndür: 915x412 (PeripheralsState.clientHeight hâlâ 915 kalır)
      await tester.pumpWidget(buildAt(const Size(915, 412)));
      await tester.pump();
      expect(key.currentState!.clientHeight, 915.0);

      // Kamerayı başlangıca alıp yatay yükseklikle (412) açı farkını doğrula
      cam.position.setValues(0, 18, 22);
      orbit.update();
      final thetaBefore = orbit.getAzimuthalAngle.toDouble();

      final g2 = await tester.startGesture(
        const Offset(300, 200),
        kind: PointerDeviceKind.touch,
      );
      await g2.moveBy(const Offset(103, 0));
      await g2.up();
      await tester.pump();

      _expectFiniteCamera(cam);
      final deltaTheta = (orbit.getAzimuthalAngle.toDouble() - thetaBefore).abs();
      expect(deltaTheta, closeTo(2 * math.pi * 103 / 412, 1e-4));
    });

    testWidgets('İki parmak çimdikleme sıfır mesafede ve iptalde (onPointerCancel) çökmez',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final key = GlobalKey<three.PeripheralsState>();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 800,
              child: three.Peripherals(
                key: key,
                builder: (_) => const ColoredBox(color: Color(0xFF000000)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final cam = three.PerspectiveCamera(54, 400 / 800, 0.15, 160)
        ..position.setValues(0, 18, 22);
      final orbit = SafeOrbitControls(cam, key)
        ..minPolarAngle = 0.18
        ..maxPolarAngle = 1.35
        ..minDistance = 6.5
        ..maxDistance = 48.0;
      addTearDown(orbit.dispose);

      // İki parmak tam aynı noktada başlar (dollyStart.y == 0) sonra ayrılır
      final p1 = three.WebPointerEvent()
        ..pointerId = 10
        ..pointerType = 'touch'
        ..pageX = 200
        ..pageY = 400;
      final p2 = three.WebPointerEvent()
        ..pointerId = 11
        ..pointerType = 'touch'
        ..pageX = 200
        ..pageY = 400;
      key.currentState!.overrideEmit(three.PeripheralType.pointerdown, p1);
      key.currentState!.overrideEmit(three.PeripheralType.pointerdown, p2);
      key.currentState!.overrideEmit(
        three.PeripheralType.pointermove,
        three.WebPointerEvent()
          ..pointerId = 11
          ..pointerType = 'touch'
          ..pageX = 240
          ..pageY = 400,
      );
      _expectFiniteCamera(cam);

      // Parmaklardan biri sistem tarafından iptal edilir; ardından diğer parmak hareket eder
      key.currentState!.overrideEmit(three.PeripheralType.pointercancel, p2);
      key.currentState!.overrideEmit(
        three.PeripheralType.pointermove,
        three.WebPointerEvent()
          ..pointerId = 10
          ..pointerType = 'touch'
          ..pageX = 220
          ..pageY = 420,
      );
      key.currentState!.overrideEmit(three.PeripheralType.pointercancel, p1);
      _expectFiniteCamera(cam);
      expect(orbit.state, three.OrbitState.none);
      expect(orbit.pointers, isEmpty);

      // Tekrarlı cancel sonrasında tek sürükleme 2x/3x hızlanmaz (çift dinleyici yok)
      cam.position.setValues(0, 18, 22);
      orbit.update();
      final thetaBefore = orbit.getAzimuthalAngle.toDouble();
      final g = await tester.startGesture(
        const Offset(200, 400),
        kind: PointerDeviceKind.touch,
      );
      await g.moveBy(const Offset(100, 0));
      await g.up();
      await tester.pump();
      expect(
        (orbit.getAzimuthalAngle.toDouble() - thetaBefore).abs(),
        closeTo(2 * math.pi * 100 / 800, 1e-4),
      );
    });
  });
}
