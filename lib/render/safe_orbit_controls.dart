import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:three_js/three_js.dart' as three;

/// Android ve masaüstünde sıfır boyutlu ilk kare, ekran döndürme ve eksik
/// işaretçi iptali durumlarında kameranın `NaN` konumuna düşmesini önleyen
/// güvenli [three.OrbitControls] alt sınıfı.
///
/// `three_js_core` içindeki `PeripheralsState`, boyutunu yalnızca `initState`
/// sonrasında bir kez önbelleğe alır. Android soğuk açılışında ilk kare
/// `(0, 0)` geldiğinde `clientHeight == 0` kilitlenir ve ilk döndürme
/// sürüklemesinde açı farkı sıfıra bölünerek kamerayı `NaN` yapar. Bu sınıf:
/// 1. Her harekette canlı `RenderBox` boyutunu (yoksa [viewportSize] geri
///    dönüşünü) okur ve pozitif değilse işlemi güvenle atlar.
/// 2. İki parmak yakınlaştırmada sıfır başlangıç mesafesini ve tek parmak
///    kalan `onPointerCancel` durumlarını korur (`RangeError`/`NaN` önlenir).
/// 3. `update()` öncesi/sonrası tüm kamera ve hedef bileşenlerinin sonlu
///    kalmasını zorunlu kılar; bozulma olursa son geçerli pozu geri yükler.
class SafeOrbitControls extends three.OrbitControls {
  SafeOrbitControls(
    super.object,
    super.listenableKey, {
    Size? Function()? viewportSize,
  }) : _viewportSize = viewportSize {
    if (_isFinitePose()) {
      _saveValidPose();
    }
  }

  final Size? Function()? _viewportSize;
  final three.Vector3 _lastValidPos = three.Vector3();
  final three.Vector3 _lastValidTarget = three.Vector3();
  bool _hasValidPose = false;
  bool _listenersAttached = false;

  Size? _liveViewportSize() {
    final ro = listenableKey.currentContext?.findRenderObject();
    if (ro is RenderBox &&
        ro.hasSize &&
        ro.size.width.isFinite &&
        ro.size.height.isFinite &&
        ro.size.width > 0 &&
        ro.size.height > 0) {
      return ro.size;
    }
    final fallback = _viewportSize?.call();
    if (fallback != null &&
        fallback.width.isFinite &&
        fallback.height.isFinite &&
        fallback.width > 0 &&
        fallback.height > 0) {
      return fallback;
    }
    return null;
  }

  double? _finiteCoord(dynamic value) {
    if (value is num) {
      final d = value.toDouble();
      if (d.isFinite) return d;
    }
    return null;
  }

  bool _isVecFinite(three.Vector3 v) => v.x.isFinite && v.y.isFinite && v.z.isFinite;

  bool _isQuatFinite(three.Quaternion q) =>
      q.x.isFinite && q.y.isFinite && q.z.isFinite && q.w.isFinite;

  bool _isFinitePose() => _isVecFinite(object.position) && _isVecFinite(target);

  void _saveValidPose() {
    _lastValidPos.setFrom(object.position);
    _lastValidTarget.setFrom(target);
    _hasValidPose = true;
  }

  three.Vector2? _safeSecondPointerPosition(dynamic event) {
    if (pointers.length < 2) return null;
    final first = pointers[0];
    final second = pointers[1];
    final other = (event.pointerId == first.pointerId) ? second : first;
    return pointerPositions[other.pointerId];
  }

  @override
  void addPointer(dynamic event) {
    removePointer(event);
    pointers.add(event);
  }

  @override
  void onPointerDown(dynamic event) {
    if (enabled == false) return;

    removePointer(event);
    if (!_listenersAttached) {
      domElement.addEventListener(three.PeripheralType.pointermove, onPointerMove);
      domElement.addEventListener(three.PeripheralType.pointerup, onPointerUp);
      _listenersAttached = true;
    }

    pointers.add(event);
    if (event.pointerType == 'touch') {
      onTouchStart(event);
    } else {
      onMouseDown(event);
    }
  }

  @override
  void onPointerUp(dynamic event) {
    _finishPointer(event);
  }

  @override
  void onPointerCancel(dynamic event) {
    _finishPointer(event);
  }

  void _finishPointer(dynamic event) {
    removePointer(event);
    if (pointers.isEmpty && _listenersAttached) {
      final el = listenableKey.currentState;
      el?.removeEventListener(three.PeripheralType.pointermove, onPointerMove);
      el?.removeEventListener(three.PeripheralType.pointerup, onPointerUp);
      _listenersAttached = false;
    }
    dispatchEvent(three.Event(type: 'end'));
    state = three.OrbitState.none;
  }

  @override
  void onTouchMove(dynamic event) {
    if (pointers.isEmpty || state == three.OrbitState.none) return;
    super.onTouchMove(event);
  }

  @override
  void handleTouchMoveRotate(dynamic event) {
    if (pointers.isEmpty) return;
    final size = _liveViewportSize();
    if (size == null) return;

    final px = _finiteCoord(event.pageX);
    final py = _finiteCoord(event.pageY);
    if (px == null || py == null) return;

    if (pointers.length == 1) {
      rotateEnd.setValues(px, py);
    } else {
      final position = _safeSecondPointerPosition(event);
      if (position == null) {
        rotateEnd.setValues(px, py);
      } else {
        rotateEnd.setValues(0.5 * (px + position.x), 0.5 * (py + position.y));
      }
    }

    rotateDelta.sub2(rotateEnd, rotateStart).scale(rotateSpeed);
    if (rotateDelta.x.isFinite && rotateDelta.y.isFinite) {
      rotateLeft(2 * math.pi * rotateDelta.x / size.height);
      rotateUp(2 * math.pi * rotateDelta.y / size.height);
    }
    rotateStart.setFrom(rotateEnd);
  }

  @override
  void handleMouseMoveRotate(dynamic event) {
    final size = _liveViewportSize();
    if (size == null) return;

    final cx = _finiteCoord(event.clientX);
    final cy = _finiteCoord(event.clientY);
    if (cx == null || cy == null) return;

    rotateEnd.setValues(cx, cy);
    rotateDelta.sub2(rotateEnd, rotateStart).scale(rotateSpeed);
    if (rotateDelta.x.isFinite && rotateDelta.y.isFinite) {
      rotateLeft(2 * math.pi * rotateDelta.x / size.height);
      rotateUp(2 * math.pi * rotateDelta.y / size.height);
    }
    rotateStart.setFrom(rotateEnd);
    update();
  }

  @override
  void handleTouchMovePan(dynamic event) {
    if (pointers.isEmpty) return;
    final px = _finiteCoord(event.pageX);
    final py = _finiteCoord(event.pageY);
    if (px == null || py == null) return;

    if (pointers.length == 1) {
      panEnd.setValues(px, py);
    } else {
      final position = _safeSecondPointerPosition(event);
      if (position == null) return;
      panEnd.setValues(0.5 * (px + position.x), 0.5 * (py + position.y));
    }

    panDelta.sub2(panEnd, panStart).scale(panSpeed);
    pan(panDelta.x, panDelta.y);
    panStart.setFrom(panEnd);
  }

  @override
  void handleTouchMoveDolly(dynamic event) {
    if (pointers.length < 2) return;
    final position = _safeSecondPointerPosition(event);
    if (position == null) return;

    final px = _finiteCoord(event.pageX);
    final py = _finiteCoord(event.pageY);
    if (px == null || py == null) return;

    final dx = px - position.x;
    final dy = py - position.y;
    final distance = math.sqrt(dx * dx + dy * dy);
    dollyEnd.setValues(0, distance);

    if (!dollyStart.y.isFinite || dollyStart.y <= 1e-3 || distance <= 1e-3) {
      dollyStart.setFrom(dollyEnd);
      return;
    }

    final ratio = (dollyEnd.y / dollyStart.y).clamp(0.1, 10.0);
    final dollyScale = math.pow(ratio, zoomSpeed).toDouble();
    if (dollyScale.isFinite && dollyScale > 0) {
      dollyDelta.setValues(0, dollyScale);
      dollyOut(dollyDelta.y);
    }
    dollyStart.setFrom(dollyEnd);
  }

  @override
  void pan(double deltaX, double deltaY) {
    if (!deltaX.isFinite || !deltaY.isFinite) return;
    final size = _liveViewportSize();
    if (size == null) return;

    final cam = object;
    if (cam is three.PerspectiveCamera) {
      offset.setFrom(cam.position).sub(target);
      var targetDistance = offset.length;
      targetDistance *= math.tan((cam.fov / 2) * math.pi / 180.0);
      panLeft(2 * deltaX * targetDistance / size.height, cam.matrix);
      panUp(2 * deltaY * targetDistance / size.height, cam.matrix);
    } else if (cam is three.OrthographicCamera) {
      panLeft(
        deltaX * (cam.right - cam.left) / cam.zoom / size.width,
        cam.matrix,
      );
      panUp(
        deltaY * (cam.top - cam.bottom) / cam.zoom / size.height,
        cam.matrix,
      );
    } else {
      enablePan = false;
    }
  }

  @override
  bool update() {
    if (!_isFinitePose()) {
      if (_hasValidPose) {
        object.position.setFrom(_lastValidPos);
        target.setFrom(_lastValidTarget);
      } else {
        return false;
      }
    } else {
      _saveValidPose();
    }

    if (!sphericalDelta.theta.isFinite || !sphericalDelta.phi.isFinite) {
      sphericalDelta.set(0, 0, 0);
    }
    if (!_isVecFinite(panOffset)) {
      panOffset.setValues(0, 0, 0);
    }
    if (!scale.isFinite || scale <= 0) {
      scale = 1;
    }

    final changed = super.update();
    if (!_isFinitePose() || !_isQuatFinite(object.quaternion)) {
      if (_hasValidPose) {
        object.position.setFrom(_lastValidPos);
        target.setFrom(_lastValidTarget);
        object.lookAt(target);
      }
      sphericalDelta.set(0, 0, 0);
      panOffset.setValues(0, 0, 0);
      scale = 1;
      return false;
    }

    _saveValidPose();
    return changed;
  }

  @override
  void deactivate() {
    final el = listenableKey.currentState;
    if (el == null) return;
    el.removeEventListener(three.PeripheralType.contextmenu, onContextMenu);
    el.removeEventListener(three.PeripheralType.pointerdown, onPointerDown);
    el.removeEventListener(three.PeripheralType.pointercancel, onPointerCancel);
    el.removeEventListener(three.PeripheralType.wheel, onMouseWheel);
    el.removeEventListener(three.PeripheralType.keydown, onKeyDown);
    el.removeEventListener(three.PeripheralType.keyup, onKeyUp);
    if (_listenersAttached) {
      el.removeEventListener(three.PeripheralType.pointermove, onPointerMove);
      el.removeEventListener(three.PeripheralType.pointerup, onPointerUp);
      _listenersAttached = false;
    }
  }

  @override
  void dispose() {
    deactivate();
    super.dispose();
  }
}

