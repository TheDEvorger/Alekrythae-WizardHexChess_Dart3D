import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../renderers/index.dart';
import 'package:three_js_core/others/index.dart';
import 'package:three_js_core/renderers/index.dart';
import 'package:three_js_core/three_js_core.dart' as core;
import 'package:three_js_math/three_js_math.dart';
import 'package:flutter_angle/flutter_angle.dart';

class Settings{
  Settings({
    this.useSourceTexture = false,
    this.enableShadowMap = true,
    this.autoClear = true,
    Map<String,dynamic>? renderOptions,
    this.animate = true,
    this.alpha = false,
    this.autoClearDepth = true,
    this.autoClearStencil = true,
    this.clearAlpha = 1.0,
    this.clearColor = 0x000000,
    this.localClippingEnabled = false,
    this.clippingPlanes = const [],
    this.colorSpace = ColorSpace.srgb,
    this.outputEncoding = sRGBEncoding,
    this.toneMapping = NoToneMapping,
    this.shadowMapType = PCFShadowMap,
    this.toneMappingExposure = 1.0,
    this.logarithmicDepthBuffer = false,
    this.stencil = true,
    this.xr,
    this.antialias = false,

    this.depth = true,
    this.premultipliedAlpha = true,
    this.preserveDrawingBuffer = false,
    this.powerPreference = core.PowerPreference.defaultp,
    this.failIfMajorPerformanceCaveat = false,
    this.reverseDepthBuffer = false,
    this.precision = core.Precision.highp,
    this.screenResolution,
    this.useSurfaceProducer = true,
    this.tearFreeComposite = false,
  }){
    this.renderOptions = renderOptions ?? {
      "format": RGBAFormat,
      "samples": 4
    };
  }
  
  bool premultipliedAlpha;
  bool preserveDrawingBuffer;
  PowerPreference powerPreference;
  bool reverseDepthBuffer;
  bool failIfMajorPerformanceCaveat;
  bool depth = true;
  bool useSurfaceProducer;
  Precision precision;
  bool alpha;
  bool stencil;
  bool logarithmicDepthBuffer;
  int clearColor;
  double clearAlpha;
  bool antialias;
  XRManager Function(AngleRenderer renderer, dynamic gl)? xr;
  double? screenResolution;
  
  bool animate;
  bool useSourceTexture;

  /// [WizardHexChess yaması] Yırtılmasız birleştirme.
  ///
  /// Windows'ta sahne, Flutter'ın da aynı anda okuduğu TEK bir paylaşımlı D3D
  /// dokusuna doğrudan çiziliyordu (çift tampon / senkronizasyon yok). Flutter
  /// kareyi tam o sırada alırsa ekrana yarım çizilmiş bir kare gelir: arka plan
  /// temizlenmiş ama saydam katmanlar (bulut, yağmur, sis) henüz çizilmemiştir.
  /// Bu, katmanların bir görünüp bir kaybolmasına ve görüntünün kaymasına yol açar.
  ///
  /// Açıkken sahne önce ekran dışı bir hedefe eksiksiz çizilir, ardından tek
  /// bir tam ekran çizimle paylaşılan yüzeye kopyalanır (yüzey hiç temizlenmez).
  /// Hedef, ekrana çizimle aynı renk uzayı/ton eşleme/8 bit formatı kullanır;
  /// görüntü birebir aynıdır.
  bool tearFreeComposite;
  bool enableShadowMap;
  bool autoClear;
  bool autoClearDepth;
  bool autoClearStencil;
  bool localClippingEnabled;
  late Map<String,dynamic> renderOptions;
  List<Plane> clippingPlanes;
  int outputEncoding;
  ColorSpace colorSpace;
  int toneMapping;
  int shadowMapType;
  double toneMappingExposure;
}

/// threeJs utility class. If you want to learn how to connect cannon.js with js, please look at the examples/threejs_* instead.
class ThreeJS with WidgetsBindingObserver{
  void Function() onSetupComplete;
  ThreeJS({
    Settings? settings,
    required this.onSetupComplete, 
    required this.setup,
    this.rendererUpdate,
    this.postProcessor,
    this.windowResizeUpdate,
    Size? size,
    AngleRenderer? renderer,
    this.renderNumber = 0,
    this.loadingWidget
  }){
    this.settings = settings ?? Settings();
    _resolution = this.settings.screenResolution;
    _fixedSize = size;
  }

  int renderNumber;

  BuildContext? _context;
  Timer? _debounceTimer;

  Widget? loadingWidget;
  Size? _fixedSize;
  late final Settings settings;
  final GlobalKey<core.PeripheralsState> globalKey = GlobalKey<core.PeripheralsState>();
  core.PeripheralsState get domElement => globalKey.currentState!;

  bool visible = true;

  FlutterAngleTexture? texture;
  RenderingContext? gl;

  RenderTarget? renderTarget;
  AngleRenderer? renderer;
  final core.Clock clock = core.Clock();

  late final core.Scene scene;
  late final core.Camera camera;
  Ticker? ticker;

  double get width => screenSize!.width;
  double get height => screenSize!.height;

  Size? screenSize;
  double? _resolution;
  double get dpr => _resolution ?? 1.0;
  void setResolution(double newResolution){
    _resolution = newResolution;
  }

  WebGLTexture? sourceTexture;

  bool pause = false;
  bool _disposed = false;
  bool isVisibleOnScreen = true;
  bool _mounted = false;
  bool get mounted => _mounted;
  bool _updating = false;
  bool get updating => _updating;

  void Function()? rendererUpdate;
  void Function(Size newSize)? windowResizeUpdate;
  void Function([double? dt])? postProcessor;
  Future<void> Function(core.Scene,core.Camera,FlutterAngleTexture,[double? dt])? customRenderer;
  Future<void> Function(BuildContext) onWindowResize = (context) async{};
  FutureOr<void> Function()? setup;
  List<Function(double dt)> events = [];
  List<Function()> disposeEvents = [];

  FlutterAngle? angle = FlutterAngle();

  void addAnimationEvent(Function(double dt) event){
    events.add(event);
  }
  void toDispose(Function() event){
    disposeEvents.add(event);
  }

  @override
  void didChangeMetrics() {
    if (_disposed) return;
    _debounceTimer?.cancel(); // Clear existing timer
    // [WizardHexChess yaması] 300 ms → 150 ms: büyüt/küçült sonrası eski kare daha kısa süre gerilmiş görünür.
    _debounceTimer = Timer(Duration(milliseconds: 150+renderNumber*100), () { // Set a new timer
      if (_context != null && _context!.mounted) {
        _onWindowResize(_context!);
      }
    });
  }

  void dispose(){
    if(_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel(); // Cancel timer if active
    _debounceTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    ticker?.dispose();
    ticker = null;
    _disposeComposite();
    renderer?.dispose();
    renderer = null;
    renderTarget?.dispose();
    renderTarget = null;
    scene.dispose();
    for(final event in disposeEvents){
      event.call();
    }
    
    camera.dispose();
    events.clear();
    disposeEvents.clear();

    //allNativeData.dispose();

    angle?.dispose([texture]);
    loadingWidget = null;
    _fixedSize = null;
    screenSize = null;

    rendererUpdate = null;
    windowResizeUpdate = null;
    postProcessor = null;
    setup = null;
  }

  bool _initStarted = false;

  void initSize(BuildContext context){
    if (_initStarted || _disposed) {
      return;
    }
    final mqd = MediaQuery.of(context);
    final candidateSize = _fixedSize ?? mqd.size;
    final res = _resolution ?? mqd.devicePixelRatio;
    // [WizardHexChess yaması] Android ilk karede MediaQuery boyutu (0, 0) dönebilir;
    // pozitif doku boyutu gelene kadar GL/doku kurulumunu ertele.
    if (candidateSize.width.toInt() <= 0 ||
        candidateSize.height.toInt() <= 0 ||
        (candidateSize.width * res).toInt() <= 0 ||
        (candidateSize.height * res).toInt() <= 0) {
      screenSize = candidateSize;
      return;
    }

    _initStarted = true;
    _context = context;
    WidgetsBinding.instance.addObserver(this);

    screenSize = candidateSize;
    _resolution ??= res;

    Future.delayed(Duration(milliseconds: renderNumber*100), () async{
      if (!_disposed) {
        await initPlatformState();
      }
    });
  }
  
  Future<void> animate(Duration duration) async {
    if (!mounted || _disposed || updating || _resizing || !isVisibleOnScreen || !visible) {
      return;
    }
    _updating = true;
    double dt = clock.getDelta();
    
    if(settings.animate){
      await (customRenderer?.call(scene,camera,texture!,dt) ?? render(scene,camera,texture!,dt));
      if(!pause){
        for(int i = 0; i < events.length;i++){
          events[i].call(dt);
        }
      }
    }
    _updating = false;
  }

  Future<void> render([core.Scene? scene, core.Camera? camera, FlutterAngleTexture? texture, double? dt]) async{
    scene ??= this.scene;
    camera ??= this.camera;
    texture ??= this.texture!;
    
    if(sourceTexture == null){
      angle?.activateTexture(texture);
    }
    rendererUpdate?.call();
    if(postProcessor == null){
      if (settings.tearFreeComposite && sourceTexture == null) {
        _renderComposite(scene, camera, texture);
      }
      else {
        renderer!.clear();
        renderer!.setViewport(0,0,width,height);
        renderer!.render(scene, camera);
      }
    }
    else{
      postProcessor?.call(dt);
    }

    if(sourceTexture != null){
      angle?.activateTexture(texture);
    }
    await angle?.updateTexture(texture,sourceTexture);
  }

  // ------------------------------------------------ [WizardHexChess yaması]
  /// Son karenin ölçümleri (tanılama): sahne çiziminin CPU süresi (ms),
  /// çizim çağrısı ve üçgen sayısı.
  double lastRenderMs = 0;
  int lastDrawCalls = 0;
  int lastTriangles = 0;
  final Stopwatch _renderWatch = Stopwatch();

  // Yırtılmasız birleştirme (bkz. Settings.tearFreeComposite).
  RenderTarget? _compositeTarget;
  core.Scene? _compositeScene;
  core.Camera? _compositeCamera;
  core.ShaderMaterial? _compositeMaterial;
  core.BufferGeometry? _compositeGeometry;

  /// Sahneyi ekran dışı hedefe eksiksiz çizer, sonra tek bir tam ekran üçgenle
  /// paylaşılan yüzeye kopyalar. Paylaşılan yüzey hiçbir an temizlenmez; Flutter
  /// hangi anda okursa okusun ya önceki ya yeni TAM kareyi görür.
  void _renderComposite(core.Scene scene, core.Camera camera, FlutterAngleTexture texture) {
    final r = renderer!;
    final target = _ensureCompositeTarget(r);

    r.setRenderTarget(target);
    _renderWatch
      ..reset()
      ..start();
    r.render(scene, camera); // autoClear hedefi temizler
    _renderWatch.stop();
    lastRenderMs = _renderWatch.elapsedMicroseconds / 1000.0;
    lastDrawCalls = (r.info.render['calls'] ?? 0).toInt();
    lastTriangles = (r.info.render['triangles'] ?? 0).toInt();

    // flutter_angle'ın masaüstü sarmalayıcısında bindFramebuffer(hedef, null)
    // hiçbir şey yapmaz; three.js ekrana döndüğünü sanır ama ekran dışı hedef
    // bağlı kalır. Paylaşılan yüzeyi kütüphanenin kendi yoluyla yeniden bağla
    // (three.js'in durum önbelleği zaten "null" bekliyor; tutarlı kalır).
    angle?.activateTexture(texture);
    r.setRenderTarget(null);
    r.setViewport(0, 0, width, height);
    final autoClear = r.autoClear;
    r.autoClear = false;
    r.render(_compositeScene!, _compositeCamera!);
    r.autoClear = autoClear;
    // Komutları hemen GPU'ya gönder (kare hazır bildirimi bekletilmeden).
    gl?.flush();
  }

  RenderTarget _ensureCompositeTarget(AngleRenderer r) {
    final w = math.max(1, (width * dpr).floor());
    final h = math.max(1, (height * dpr).floor());
    var target = _compositeTarget;
    if (target == null) {
      target = RenderTarget(
        w,
        h,
        RenderTargetOptions({
          'format': RGBAFormat,
          // Ekrandaki gibi düz 8 bit RGBA saklanır (donanımsal sRGB dönüşümü yok).
          'internalFormat': WebGL.RGBA8,
          'minFilter': NearestFilter,
          'magFilter': NearestFilter,
          'generateMipmaps': false,
          'depthBuffer': true,
          'stencilBuffer': settings.stencil,
          'samples': 0,
        }),
      );
      // Hedef "ekran yerine geçer": malzemeler ekrana çizer gibi aynı renk
      // uzayına kodlar ve aynı ton eşlemeyi uygular (three.js'in XR hedefleri
      // için kullandığı yol). Böylece görüntü birebir aynı kalır.
      target.isXRRenderTarget = true;
      target.texture.colorSpace = r.outputColorSpace;
      _compositeTarget = target;
      _buildCompositePass(target);
    }
    else if (target.width != w || target.height != h) {
      // [WizardHexChess yaması] target.setSize KULLANILMAZ: three_js_core'da
      // setSize GPU dokusunu dispose() ile serbest bırakıp yeni boyutta yeniden
      // ayırtır, ama RenderTarget.dispose() yalnızca İLK çağrıda çalışır
      // (_didDispose). İkinci yeniden boyutlandırmadan itibaren GPU dokusu eski
      // boyutta kalır, three.js ise yeni görüş alanıyla çizer: ekranda sahnenin
      // bir köşesi pikselli ve yakınlaşmış görünür. Hedef baştan kurulur.
      _disposeComposite();
      return _ensureCompositeTarget(r);
    }
    return target;
  }

  void _buildCompositePass(RenderTarget target) {
    // Ekranı tamamen kaplayan tek üçgen (köşegen dikişi olmaz).
    final geo = core.BufferGeometry();
    geo.setAttributeFromString(
      'position',
      Float32BufferAttribute.fromList([-1.0, -1.0, 0.0, 3.0, -1.0, 0.0, -1.0, 3.0, 0.0], 3),
    );
    final mat = core.ShaderMaterial.fromMap({
      'uniforms': {
        'tScene': {'value': target.texture},
      },
      'vertexShader': '''
        varying vec2 vUv;
        void main() {
          vUv = position.xy * 0.5 + 0.5;
          gl_Position = vec4(position.xy, 0.0, 1.0);
        }
      ''',
      'fragmentShader': '''
        uniform sampler2D tScene;
        varying vec2 vUv;
        void main() {
          gl_FragColor = texture2D(tScene, vUv);
        }
      ''',
      'depthTest': false,
      'depthWrite': false,
      'transparent': false,
      'blending': NoBlending,
      'toneMapped': false,
    });
    final mesh = core.Mesh(geo, mat)..frustumCulled = false;
    _compositeScene = core.Scene()..add(mesh);
    _compositeCamera = core.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    _compositeMaterial = mat;
    _compositeGeometry = geo;
  }

  void _disposeComposite() {
    _compositeTarget?.dispose();
    _compositeTarget = null;
    _compositeMaterial?.dispose();
    _compositeMaterial = null;
    _compositeGeometry?.dispose();
    _compositeGeometry = null;
    _compositeScene = null;
    _compositeCamera = null;
  }
  
  void initRenderer() {
    AngleRendererParameters options = AngleRendererParameters(
      width: width,
      height: height,
      gl: gl!,
      stencil: settings.stencil,
      antialias: settings.antialias,
      alpha: settings.alpha,
      clearColor: settings.clearColor,
      clearAlpha: settings.clearAlpha,
      logarithmicDepthBuffer: settings.logarithmicDepthBuffer,
      xr: settings.xr,
      depth: settings.depth,
      premultipliedAlpha: settings.premultipliedAlpha,
      preserveDrawingBuffer: settings.preserveDrawingBuffer,
      powerPreference: settings.powerPreference,
      failIfMajorPerformanceCaveat: settings.failIfMajorPerformanceCaveat,
      reverseDepthBuffer: settings.reverseDepthBuffer,
      precision: settings.precision,
    );
    
    renderer = AngleRenderer(options);
    renderer!.setPixelRatio(_resolution!);
    renderer!.setSize(width, height, false);
    renderer!.alpha = settings.alpha;
    renderer!.shadowMap.enabled = settings.enableShadowMap;
    renderer!.shadowMap.type = settings.shadowMapType;
    renderer!.autoClear = settings.autoClear;
    renderer!.setClearColor(
      Color.fromHex32(settings.clearColor), 
      settings.clearAlpha
    );
    renderer!.autoClearDepth = settings.autoClearDepth;
    renderer!.autoClearStencil = settings.autoClearStencil;
    renderer!.outputEncoding = settings.outputEncoding;
    renderer!.outputColorSpace = settings.colorSpace.toString();
    renderer!.localClippingEnabled = settings.localClippingEnabled;
    renderer!.clippingPlanes = settings.clippingPlanes;
    renderer!.toneMapping = settings.toneMapping;
    renderer!.toneMappingExposure = settings.toneMappingExposure;

    if(settings.useSourceTexture){
      final RenderTargetOptions pars = RenderTargetOptions(settings.renderOptions);
      renderTarget = RenderTarget((width * _resolution!).toInt(), (height * _resolution!).toInt(), pars);
      renderer!.setRenderTarget(renderTarget);
      sourceTexture = renderer!.getRenderTargetGLTexture(renderTarget!);
    }
  }
  
  // [WizardHexChess yaması] Yeniden boyutlandırma sırasında kare çizilmez.
  // angle.resize() paylaşılan D3D yüzeyini `await` içinde değiştirir; bu arada
  // Ticker'ın çizdiği kare eski/yarı kurulmuş yüzeye ve yeni boyuta karışık
  // çizim yapıyordu. Üst üste gelen yeniden boyutlandırmalar sıraya alınır.
  bool _resizing = false;
  bool _resizePending = false;

  Future<void> _onWindowResize(BuildContext context) async{
    if (_disposed) return;
    if (_resizing) {
      _resizePending = true;
      return;
    }
    final mqd = MediaQuery.maybeOf(context);
    if (mqd == null) return;
    if(_fixedSize == null && screenSize != mqd.size && texture != null && mqd.size.width.toInt() > 0 && mqd.size.height.toInt() > 0){
      _resizing = true;
      try {
        // Yarıda kalan karenin bitmesini bekle.
        while (_updating) {
          await Future<void>.delayed(const Duration(milliseconds: 4));
          if (_disposed) return;
        }
        double dt = clock.getDelta();
        screenSize = mqd.size;

        if(settings.screenResolution == null){
          _resolution = mqd.devicePixelRatio;
        }

        final options = AngleOptions(
          width: width.toInt(),
          height: height.toInt(),
          dpr: _resolution!,
        );

        await angle?.resize(texture!, options);
        if (_disposed) return;

        camera.aspect = width/height;
        camera.updateProjectionMatrix();

        windowResizeUpdate?.call(screenSize!);
        renderer!.setSize(width, height);

        if(postProcessor != null){
          postProcessor?.call(dt);
        }
        await render(scene,camera,texture!,dt);
      }
      finally {
        _resizing = false;
      }
    }
    if (_resizePending && !_disposed && context.mounted) {
      _resizePending = false;
      await _onWindowResize(context);
    }
  }

  Future<void> initScene() async{
    if (renderer == null) {
      initRenderer();
    }
    await setup?.call();
    _mounted = true;
    ticker = Ticker(animate);
    ticker?.start();
    onSetupComplete();
  }

  Future<void> initPlatformState() async {
    if (_disposed) return;
    if(texture == null){
      await angle?.init();
      if (_disposed) return;
      
      texture = await angle?.createTexture(      
        AngleOptions(
          width: width.toInt(), 
          height: height.toInt(), 
          dpr: _resolution!,
          alpha: settings.alpha,
          antialias: settings.antialias,
          customRenderer: !settings.useSourceTexture,
          useSurfaceProducer: settings.useSurfaceProducer
        )
      );
      if (_disposed) return;
    }

    console.info(texture?.toMap());
    if (gl == null) {
      gl = texture!.getContext();
    }
    await initScene();
  }

  Widget build() {
    return  Builder(builder: (BuildContext context) {
      initSize(context);
      // [WizardHexChess yaması] Android ilk karede MediaQuery (0, 0) iken
      // Peripherals bağlanırsa clientWidth/clientHeight kalıcı olarak 0'a
      // kilitlenir; OrbitControls döndürmede 0'a bölüp kamerayı NaN yapar ve
      // ekran tek renge düşer. Pozitif boyut gelene kadar Peripherals kurulmaz.
      if (!_initStarted ||
          screenSize == null ||
          screenSize!.width.toInt() <= 0 ||
          screenSize!.height.toInt() <= 0) {
        return loadingWidget ?? const SizedBox.shrink();
      }
      return core.Peripherals(
        key: globalKey,
        builder: (BuildContext context) {
          return Container(
            width: !visible?0:width,
            height: !visible?0:height,
            child: SizeChangedLayoutNotifier(
              child: Builder(builder: (BuildContext context) {
                if (kIsWeb) {
                  return texture != null && mounted? HtmlElementView(viewType:texture!.textureId.toString()):loadingWidget ?? Container(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    color: Theme.of(context).canvasColor,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator()
                  );
                } 
                else {
                  return texture != null && mounted?
                    Transform.scale(
                      scaleY: sourceTexture != null || Platform.isAndroid?1:-1,
                      child:Texture(textureId: texture!.textureId)
                    ):loadingWidget ?? Container(
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height,
                      color: Theme.of(context).canvasColor,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator()
                    );
                }
              })
            )
          );
        }
      );
    });
  }
}