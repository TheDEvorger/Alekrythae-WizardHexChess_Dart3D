import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:three_js/three_js.dart' as three;

import 'audio/battle_audio.dart';
import 'data/game_database.dart';
import 'game/ai.dart';
import 'game/chess_game.dart';
import 'game/hex_board.dart';
import 'game/three_player_ai.dart';
import 'render/battle_fx.dart';
import 'render/creatures.dart';
import 'render/lightning_storm.dart';
import 'render/safe_orbit_controls.dart';
import 'render/storm_vortex.dart';
import 'ui/atmosphere_slider.dart';
import 'ui/creature_badge.dart';
import 'ui/launch_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WizardHexChessApp());
}

class WizardHexChessApp extends StatelessWidget {
  const WizardHexChessApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Wizard Hex Chess 3D',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF070B14),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFC89B48),
            brightness: Brightness.dark,
          ),
        ),
        home: const WizardArena(),
      );
}

enum GameMode {
  humanVsAi('İnsan vs Yapay Zekâ'),
  humanVsHuman('2 Oyuncu (Aynı Cihaz)'),
  aiVsAi('YZ vs YZ (Canlı İzle)');

  const GameMode(this.label);
  final String label;

  String labelFor(BoardVariant v) {
    if (v == BoardVariant.twoPlayer) return label;
    return switch (this) {
      GameMode.humanVsAi => 'İnsan vs 2 YZ',
      GameMode.humanVsHuman => '3 Oyuncu (Aynı Cihaz)',
      GameMode.aiVsAi => '3 YZ (Canlı Savaş)',
    };
  }
}

enum CamPreset {
  white('Beyaz Cephesi'),
  black('Siyah Cephesi'),
  emerald('Zümrüt Cephesi'),
  top('Tepeden Taktik');

  const CamPreset(this.label);
  final String label;
}

enum DeathMode { topple, slash, burn, crush, drain, launch }

class WizardArena extends StatefulWidget {
  const WizardArena({super.key});

  @override
  State<WizardArena> createState() => _WizardArenaState();
}

class _WizardArenaState extends State<WizardArena> with WidgetsBindingObserver {
  final ChessGame game = ChessGame();
  final CreatureFactory _factory = CreatureFactory();
  final Animator _anim = Animator()
    ..moveSpeed = 0.80
    ..combatSpeed = 0.70;
  final BattleAudio _audio = BattleAudio();
  final FocusNode _keyFocus = FocusNode();

  late final three.ThreeJS _engine;
  late FxSystem _fx;
  late HexHighlightLayer _hl;

  final Map<HexCell, CreatureRig> _rigs = {};

  late three.Group _world;

  /// Tahta, taşlar, vurgular ve savaş efektleri: büyük 3 kişilik tahtalarda
  /// [BoardShape.playScale] ile Klasik arenanın alanına sığdırılır (fırtına,
  /// kuleler, sis ve kamera düzeni her boyutta aynı kalır).
  late three.Group _playLayer;
  double _playScale = 1.0;
  late three.Group _arenaLayer;
  late three.Group _pieceLayer;
  late three.PointLight _fireLight;
  late three.Group _stormLayer;
  late three.Group _horizonGroup;
  StormVortex? _storm;
  LightningStorm? _lightning;
  late three.HemisphereLight _skyLight;
  final List<P3> _spireTips = [];
  final math.Random _rng = math.Random(777);
  three.OrbitControls? _orbit;
  three.Raycaster? _raycaster;

  HexCell? _selected;
  List<HexCell> _targets = [];
  (HexCell from, HexCell to)? _hint;

  bool _ready = false;
  bool _busy = false;
  bool _thinking = false;
  bool _hintBusy = false;
  int _generation = 0;

  // SQLite kalıcılık, açılış ekranı ve profil durumu
  int _currentMatchId = -1;
  int _matchStartTimestamp = 0;
  PlayerProfileStats _profile = const PlayerProfileStats();
  SavedMatchSummary? _activeSavedMatch;
  SqliteDiagnostics? _dbDiagnostics;
  bool _showLaunchScreen = true;
  bool _bootReady = false;
  String _bootStatus = 'Antik rünler ve savaş arenası sislerden uyanıyor…';
  double _bootProgress = 0.15;
  GraphicsQuality _graphicsQuality = GraphicsQuality.balanced;
  double _stormIntensity = 1.5;
  double _hauntLevel = 0.75;
  double _lightningRate = 1.5;
  double _thunderVolume = 1.0;
  double _ambienceVolume = 0.7;
  double _stormFog = 1.0;
  double _lightningLinger = 1.2;
  StormQuality _stormQuality = StormQuality.auto;

  GameMode _mode = GameMode.humanVsAi;
  Team _humanTeam = Team.white;
  AiLevel _level = AiLevel.wizard;
  CamPreset _camPreset = CamPreset.white;

  // Ayrı hareket ve dövüş hızı slider değerleri
  double _moveSpeed = 0.80;
  double _combatSpeed = 0.70;

  /// Bitirici darbeden önce savaşçıların karşılıklı kapıştığı tur sayısı.
  double _duelRounds = 4.0;

  /// Düellonun sade/kısa ↔ uzun/karmaşık seviyesi (bkz. [_duelExchanges]).
  double _duelComplexity = 2.0;

  /// Düello sürerken ekrana dokunulursa kalan turlar atlanıp son darbeye geçilir.
  bool _duelActive = false;
  bool _duelSkip = false;

  // Tahtayı taşıma (Pan) ve Birinci Şahıs (POV) modları
  bool _panBoardMode = false;
  bool _boardPanned = false;
  bool _povEnabled = true;

  // Aktif POV kamera durumu (POV açıkken insan ve YZ hamlelerinin hepsinde devreye girer)
  CreatureRig? _povRig;
  String _povWho = '';
  bool _inPovSequence = false;
  double _povCountdown = 0.0;
  double _povLookYaw = 0.0;
  double _povLookPitch = 0.0;
  double _povReadyExtraPitch = 0.0;
  double _povRoll = 0.0;
  P3? _povFocusWorld;
  double _povFocusWeight = 0.0;
  P3? _povSavedCamPos;
  P3? _povSavedTarget;
  double _povSavedFov = 45.0;

  // Sesli komut / savaş narası alt yazı bildirimi
  VoiceLine? _activeVoice;
  Team _activeVoiceTeam = Team.white;
  Timer? _voiceBannerTimer;

  String _message = 'Beyaz ordu başlar. Bir savaşçıya dokun.';
  String _battleText = '';

  // Dokunma, tahtayı taşıma ve kamera döndürmeyi ayıran hassas işaretçi takibi
  int? _activePointer;
  Offset? _downPos;
  Offset? _lastDragPos;
  int _downMs = 0;
  int _pointerCount = 0;

  final Stopwatch _clock = Stopwatch()..start();
  double _last = 0;

  // Doğal arduvaz bazalt, traverten mermer ve sıcak kumtaşı renkleri
  static const tileColors = [0x38455A, 0xACA493, 0x6E5847];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio.init();
    _bootstrapApp();
    _engine = three.ThreeJS(
      settings: three.Settings(
        enableShadowMap: false,
        antialias: true,
        stencil: false,
        alpha: false,
        clearColor: 0x0A1322,
        screenResolution: 1.2,
        toneMapping: three.ACESFilmicToneMapping,
        toneMappingExposure: 1.14,
        // Sahne önce ekran dışında eksiksiz çizilir, sonra tek seferde ekrana
        // kopyalanır: yarım çizilmiş kareler (bulut/yağmur katmanlarının bir
        // görünüp bir kaybolması, görüntü kayması) ekrana gelmez.
        // Android kendi çift tamponlu yüzeyini kullanır; orada gerekmez.
        tearFreeComposite: !kIsWeb && defaultTargetPlatform != TargetPlatform.android,
      ),
      setup: _setup3d,
      windowResizeUpdate: (_) {
        if (!_inPovSequence) {
          _refitCameraAfterResize();
        } else {
          final cam = _engine.camera;
          if (cam is three.PerspectiveCamera) {
            final aspect = (_engine.width / math.max(1.0, _engine.height)).clamp(0.42, 2.6);
            cam.aspect = aspect;
            cam.fov = aspect < 0.85 ? 84.0 : 76.0;
            cam.updateProjectionMatrix();
          }
        }
      },
      onSetupComplete: () {
        _ready = true;
        _bootReady = true;
        _bootStatus = 'Savaş Arenası Hazır!';
        _bootProgress = 1.0;
        if (mounted) setState(() {});
        if (!_showLaunchScreen) _maybeAi();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(GameDatabase.instance.onAppBackgrounded());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _voiceBannerTimer?.cancel();
    _anim.clear();
    _orbit?.dispose();
    _audio.dispose();
    _keyFocus.dispose();
    _engine.dispose();
    unawaited(GameDatabase.instance.close());
    super.dispose();
  }

  // ================================================================ SQLITE & BAŞLANGIÇ LOJİĞİ
  Future<void> _bootstrapApp() async {
    setState(() {
      _bootStatus = 'SQLite WAL veritabanı bağlanıyor…';
      _bootProgress = 0.25;
    });

    try {
      final boot = await GameDatabase.instance.init();
      _profile = boot.profile;
      _activeSavedMatch = boot.activeMatch;
      _dbDiagnostics = boot.diagnostics;

      final s = boot.settings;
      if (game.variant != s.variant || game.boardSize3P != s.boardSize3P) {
        game.setVariant(s.variant, size: s.boardSize3P);
        // 3B sahne ayarlardan önce kurulduysa arena yeni boyuta göre yenilenir.
        if (_ready) {
          _rebuildArenaMesh();
          _rebuildAllRigsFromBoard();
          _refreshHighlights();
        }
      }
      _mode = GameMode.values.firstWhere(
        (m) => m.name == s.modeName,
        orElse: () => GameMode.humanVsAi,
      );
      _level = AiLevel.fromKey(s.aiLevelName);
      _humanTeam = s.humanTeam;
      _povEnabled = s.povEnabled;
      _moveSpeed = s.moveSpeed;
      _combatSpeed = s.combatSpeed;
      _duelRounds = s.duelRounds;
      _duelComplexity = s.duelComplexity;
      _audio.voiceEnabled = s.voiceEnabled;
      _audio.sfxEnabled = s.sfxEnabled;
      _audio.setVoiceVolume(s.voiceVolume);
      _audio.setSfxVolume(s.sfxVolume);
      _audio.setBgmVolume(s.bgmVolume);
      _audio.setBgmEnabled(s.bgmEnabled);
      _graphicsQuality = s.graphicsQuality;
      _stormIntensity = s.stormIntensity;
      _hauntLevel = s.hauntLevel;
      _lightningRate = s.lightningRate;
      _thunderVolume = s.thunderVolume;
      _ambienceVolume = s.ambienceVolume;
      _stormFog = s.stormFog;
      _lightningLinger = s.lightningLinger;
      _stormQuality = s.stormQuality;

      _anim.moveSpeed = _moveSpeed;
      _anim.combatSpeed = _combatSpeed;
      // 3B sahne bu noktada henüz kurulmamış olabilir (ayar yükleme ile _setup3d
      // yarışır). Kurulmadıysa _setup3d bu kaliteyi zaten kendisi uygular.
      if (_ready) {
        _fx.particleScale = _graphicsQuality.particleScale;
        _applyStormVisuals();
      }
    } catch (e) {
      debugPrint('Savaş motoru bootstrap hatası: $e');
    }
    // Rüzgâr/gizemli uğultu ve gök gürültüsü sesi (kayıtlı ya da varsayılan ayarlarla)
    _applyStormAudio();

    if (mounted) {
      setState(() {
        _bootStatus = 'Antik amfi ve savaşçı modelleri sislerden çağrılıyor…';
        _bootProgress = 0.70;
      });
    }
  }

  PersistedSettings _currentSettings() => PersistedSettings(
        variant: game.variant,
        boardSize3P: game.boardSize3P,
        modeName: _mode.name,
        aiLevelName: _level.name,
        humanTeam: _humanTeam,
        povEnabled: _povEnabled,
        moveSpeed: _moveSpeed,
        combatSpeed: _combatSpeed,
        duelRounds: _duelRounds,
        duelComplexity: _duelComplexity,
        voiceEnabled: _audio.voiceEnabled,
        sfxEnabled: _audio.sfxEnabled,
        bgmEnabled: _audio.bgmEnabled,
        bgmVolume: _audio.bgmVolume,
        voiceVolume: _audio.voiceVolume,
        sfxVolume: _audio.sfxVolume,
        graphicsQuality: _graphicsQuality,
        stormIntensity: _stormIntensity,
        hauntLevel: _hauntLevel,
        lightningRate: _lightningRate,
        thunderVolume: _thunderVolume,
        ambienceVolume: _ambienceVolume,
        stormFog: _stormFog,
        lightningLinger: _lightningLinger,
        stormQuality: _stormQuality,
      );

  void _persistSettings() {
    GameDatabase.instance.scheduleSaveSettings(_currentSettings());
  }

  Future<void> _startNewMatchSession(BoardVariant v) async {
    _matchStartTimestamp = DateTime.now().millisecondsSinceEpoch;
    _currentMatchId = await GameDatabase.instance.startNewMatch(
      variant: v,
      boardSize: game.boardSize,
      modeName: _mode.name,
      aiLevelName: _level.name,
      humanTeam: _humanTeam,
    );
    _activeSavedMatch = null;
  }

  void _resumeSavedMatch() {
    final saved = _activeSavedMatch;
    if (saved == null || !saved.isActive) return;
    _generation++;
    _anim.clear();
    _fx.clear();
    _exitPovImmediate();

    final ok = game.restoreFromEncodedMoves(
      saved.variant,
      saved.encodedMoves,
      size: saved.boardSize,
    );
    if (!ok) {
      _startMatchFromLaunch(saved.variant, saved.boardSize);
      return;
    }
    _currentMatchId = saved.id;
    _matchStartTimestamp = saved.startedAtMs;
    _humanTeam = saved.humanTeam;
    _camPreset = switch (_humanTeam) {
      Team.white => CamPreset.white,
      Team.black => CamPreset.black,
      Team.emerald => CamPreset.emerald,
    };
    _mode = GameMode.values.firstWhere(
      (m) => m.name == saved.modeName,
      orElse: () => GameMode.humanVsAi,
    );
    _level = AiLevel.fromKey(saved.aiLevelName);

    _rebuildArenaMesh();
    _rebuildAllRigsFromBoard();
    _refreshHighlights();
    _applyCameraFraming(snapPosition: true);
    _message = 'Kayıtlı savaş yüklendi! Sıra ${game.turn.title} orduda.';
    _setLaunchScreenVisible(false);
    _maybeAi();
  }

  Future<void> _startMatchFromLaunch(BoardVariant v, [BoardSize? size]) async {
    final sizeChanges = v == BoardVariant.threePlayer &&
        size != null &&
        size != game.boardSize3P;
    if (game.variant != v || sizeChanges) {
      _switchVariant(v, size: size, skipMatchSession: true);
    } else {
      _generation++;
      _anim.clear();
      _fx.clear();
      _exitPovImmediate();
      game.reset();
      _busy = false;
      _thinking = false;
      _hintBusy = false;
      _selected = null;
      _targets = [];
      _hint = null;
      _battleText = '';
      _message = v == BoardVariant.threePlayer
          ? '3 Kişilik Amfi Masası (${game.boardSize3P.label} tahta) hazır! Beyaz, Siyah ve Zümrüt ordular savaşa hazır.'
          : '2 Kişilik Amfi Düellosu hazır! Beyaz ordu başlar.';
      _rebuildAllRigsFromBoard();
      _refreshHighlights();
    }
    _setLaunchScreenVisible(false, refreshUi: false);
    await _startNewMatchSession(v);
    _applyCameraFraming(snapPosition: true);
    if (mounted) setState(() {});
    _maybeAi();
  }

  // ================================================================ 3B SAHNE & SİSLİ ATMOSFER
  Future<void> _setup3d() async {
    _engine.scene = three.Scene();
    // Karanlık fantezi gizemli amfi atmosferi: derin sis ve fırtına mavisi (Görsel 2)
    _engine.scene.background = three.Color.fromHex32(0xFF070E1A);
    // Tahta alanı tertemiz kalır; sis daire çevresinde ve ufukta derinleşir
    _engine.scene.fog = three.Fog(0xFF070E1A, 24.0, 110.0);

    final aspect = (_engine.width / math.max(1.0, _engine.height)).clamp(0.42, 2.6);
    _engine.camera = three.PerspectiveCamera(aspect < 0.85 ? 54 : 45, aspect, 0.15, 160);

    // Buzul gök kubbe ve dağ sisi yansımalı gölge ışığı
    _skyLight = three.HemisphereLight(0xD6EEFF, 0x142844, 1.65);
    _engine.scene.add(_skyLight);

    final keyLight = three.DirectionalLight(0xFFF4DE, 2.65);
    keyLight.position.setValues(-7, 18, 12);
    _engine.scene.add(keyLight);

    // Sisten süzülen soğuk gümüş-mavi silüet ve kenar ışığı (rim-light - Görsel 2)
    final rimLight = three.DirectionalLight(0x60E5FF, 2.10);
    rimLight.position.setValues(7, 14, -15);
    _engine.scene.add(rimLight);

    _fireLight = three.PointLight(0xFFA24C, 16.0, 32);
    _fireLight.position.setValues(8, 9, 2);
    _engine.scene.add(_fireLight);

    _world = three.Group();
    _engine.scene.add(_world);

    // Amfitiyatro çevresinde dönen hacimli fırtına bulutları ve sis girdabı
    _buildAtmosphericStorm();

    _playLayer = three.Group();
    _world.add(_playLayer);

    _arenaLayer = three.Group();
    _playLayer.add(_arenaLayer);
    _factory.prewarmCoreGeometries(tileColors);
    _rebuildArenaMesh();

    _hl = HexHighlightLayer(_playLayer);

    _pieceLayer = three.Group();
    _playLayer.add(_pieceLayer);

    final fxLayer = three.Group();
    _playLayer.add(fxLayer);
    _fx = FxSystem(fxLayer);
    _fx.particleScale = _graphicsQuality.particleScale;

    // Gerçekçi yıldırımlar: kule uçlarına düşer, gök gürültüsü mesafeye göre gecikir.
    _lightning = LightningStorm(
      parent: _stormLayer,
      storm: _storm!,
      fx: _fx,
      skyLight: _skyLight,
      strikeTargets: _spireTips,
      onThunder: _handleLightningThunder,
      isOnScreen: _isOnScreen,
      groundY: kStormSea['y']!.toDouble() + 0.1,
    )
      ..rate = _lightningRate
      ..power = _stormIntensity
      ..haunt = _hauntLevel
      ..linger = _lightningLinger;

    _makeAllPieces();
    _refreshHighlights();

    _orbit = SafeOrbitControls(
      _engine.camera,
      _engine.globalKey,
      viewportSize: () => _engine.screenSize,
    )
      ..enablePan = true
      ..enableDamping = false
      ..rotateSpeed = 0.85
      ..zoomSpeed = 0.95
      ..panSpeed = 0.90
      ..minPolarAngle = 0.18
      ..maxPolarAngle = 1.35
      ..minDistance = _orbitMinDistance
      ..maxDistance = 48.0;

    _applyCameraFraming(snapPosition: true);
    _raycaster = three.Raycaster();

    _engine.addAnimationEvent((_) => _tick());
    _ready = true;
  }

  void _syncOrbitInteraction() {
    final orbit = _orbit;
    if (orbit == null) return;
    if (_inPovSequence) {
      orbit.enabled = false;
      return;
    }
    orbit.enabled = true;
    if (_panBoardMode) {
      orbit.enableRotate = false;
      orbit.enablePan = false;
      orbit.enableZoom = true;
    } else {
      orbit.enableRotate = true;
      orbit.enablePan = true;
      orbit.enableZoom = true;
    }
  }

  void _buildAtmosphericStorm() {
    _stormLayer = three.Group();
    _world.add(_stormLayer);

    // 1. UZAK UFUK SİS PERDESİ: fırtınanın arkasındaki karanlık; her şeyden önce çizilir.
    final curtainMat = three.MeshBasicMaterial.fromMap({
      'color': 0x070E1A,
      'transparent': true,
      'opacity': 0.88,
      'side': three.DoubleSide,
      'depthWrite': false,
    });
    final curtainGeo = three.CylinderGeometry(78, 62, 38, 36, 1, true);
    final fogCurtain = three.Mesh(curtainGeo, curtainMat);
    fogCurtain.position.y = 6.0;
    fogCurtain.renderOrder = -40;
    _stormLayer.add(fogCurtain);

    // 2. GERÇEK FIRTINA GİRDABI (shader tabanlı, bkz. render/storm_vortex.dart)
    // Spiral bulut denizi + helezonik göz duvarı + kenar sisi + rüzgâr izleri.
    _storm = StormVortex(
      _stormLayer,
      detail: _stormDetail(),
      intensity: _stormIntensity,
      haunt: _hauntLevel,
      fog: _stormFog,
    );
    // Fırtına sisi yalnızca bulutları değil tahtayı, taşları, kuleleri, arka
    // planı ve ufuk perdesini de sarar (sis arttıkça kararmaz, puslanır).
    final sceneFog = _engine.scene.fog;
    if (sceneFog is three.Fog) {
      _storm!.bindScene(_engine.scene, fog: sceneFog, curtain: curtainMat);
    }

    // 3. DAİRENİN ETRAFINDAKİ GOTİK HİSAR & KATEDRAL KULELERİ
    // Savaş arenası dairesinin çevresini (radius 12.0 - 28.0) saran gotik kuleler ve sivri iğneler
    _horizonGroup = three.Group();
    _stormLayer.add(_horizonGroup);
    _buildGothicCitadelRing();

    // Şimşekler _setup3d içinde FxSystem kurulduktan sonra eklenir (LightningStorm).
  }

  static int _stormDetailFor(GraphicsQuality q) => switch (q) {
        GraphicsQuality.performance => 0,
        GraphicsQuality.balanced => 1,
        GraphicsQuality.ultra => 2,
      };

  /// Dünya noktası kameranın görüş alanında mı (kenarlardan biraz içeride)?
  bool _isOnScreen(P3 p) {
    final v = three.Vector3(p.x, p.y, p.z)..project(_engine.camera);
    return v.z > -1 && v.z < 1 && v.x.abs() < 0.88 && v.y.abs() < 0.86;
  }

  /// Fırtına kalitesi "Otomatik" ise grafik kalitesini izler.
  int _stormDetail() => switch (_stormQuality) {
        StormQuality.auto => _stormDetailFor(_graphicsQuality),
        StormQuality.low => 0,
        StormQuality.medium => 1,
        StormQuality.high => 2,
        StormQuality.cinematic => 3,
      };

  void _applyStormVisuals() {
    // Güç, gizem ve sis StormVortex içinde ~0,5 sn'de yumuşakça hedefe ulaşır;
    // kaydırıcı sürüklenirken bulut deseni zıplamaz.
    _storm
      ?..setDetail(_stormDetail())
      ..setIntensity(_stormIntensity)
      ..setHaunt(_hauntLevel)
      ..setFog(_stormFog);
    final l = _lightning;
    if (l != null) {
      l
        ..rate = _lightningRate
        ..power = _stormIntensity
        ..haunt = _hauntLevel
        ..linger = _lightningLinger;
    }
  }

  /// Açılış ekranında fırtına ambiyansı, yıldırım, savaş efekti ve replikleri
  /// susturur (yalnızca fon müziği çalar); maça girildiğinde atmosferi başlatır.
  void _setLaunchScreenVisible(bool show, {bool refreshUi = true}) {
    _showLaunchScreen = show;
    _applyStormAudio();
    if (refreshUi && mounted) setState(() {});
  }

  void _handleLightningThunder(ThunderKind kind) {
    if (_showLaunchScreen) return;
    _audio.playThunder(kind);
  }

  void _playSfx(SfxKind kind) {
    if (_showLaunchScreen) return;
    _audio.playSfx(kind);
  }

  void _applyStormAudio() {
    _audio.thunderVolume = _thunderVolume;
    if (_showLaunchScreen) {
      // Oyun başlamadan yalnızca fon müziği duyulsun; rüzgâr/uğultu maça girince başlar.
      _audio.setStormAmbience(wind: 0, ghost: 0);
      return;
    }
    _audio.setStormAmbience(
      // Rüzgâr fırtına gücüyle, uğultu gizemli atmosferle şiddetlenir; ikisinin
      // de üst sınırı yoktur (doz arttıkça ses de artar).
      wind: _ambienceVolume * (0.25 + 0.3 * _stormIntensity),
      ghost: _ambienceVolume * _hauntLevel * 0.7,
    );
  }

  static String _stormPowerLabel(double v) {
    if (v <= 0.01) return 'Durgun';
    if (v < 0.5) return 'Esinti';
    if (v < 1.0) return 'Fırtına';
    if (v < 1.5) return 'Kasırga';
    if (v < 2.2) return 'Felaket Girdabı';
    if (v <= 3.0) return 'Yıkım Kasırgası';
    return 'Titan Tayfunu';
  }

  static String? _fogLabel(double v) {
    if (v <= 0.01) return null; // "Kapalı" gösterilir
    if (v < 0.6) return 'Açık';
    if (v < 1.4) return 'Pus';
    if (v < 2.4) return 'Sisli';
    if (v <= 3.0) return 'Yoğun Sis';
    if (v <= 6.0) return 'Kesif Sis';
    return 'Göz Gözü Görmüyor';
  }

  Widget _buildStormSettingsSection(void Function(void Function()) setSheet) {
    // Fırtına değerleri arena arayüzünde gösterilmez: yalnızca ayar sayfası
    // yeniden çizilir (her kaydırıcı adımında koca arena ağacı yeniden kurulmaz,
    // sürükleme sırasında kare atlaması olmaz).
    void changed(void Function() fn, {bool visuals = true, bool audio = false}) {
      fn();
      if (visuals) _applyStormVisuals();
      if (audio) _applyStormAudio();
      _persistSettings();
      setSheet(() {});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('FIRTINA, YILDIRIM & GİZEMLİ ATMOSFER',
            style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Color(0xFFC8A464))),
        const SizedBox(height: 2),
        const Text(
          'Üst sınır yok: kaydırıcı yetmezse yanındaki kutuya istediğin değeri yazıp ✓ ile onayla.',
          style: TextStyle(fontSize: 10.5, color: Color(0xFF98A8C2)),
        ),
        const SizedBox(height: 8),
        AtmosphereSlider(
          icon: Icons.cyclone_rounded,
          color: const Color(0xFF7FB2FF),
          title: 'FIRTINA GÜCÜ',
          value: _stormIntensity,
          sliderMax: AtmosphereLimits.stormSlider,
          divisions: 60,
          offLabel: null,
          describe: _stormPowerLabel,
          onChanged: (v) => changed(() => _stormIntensity = v, audio: true),
        ),
        AtmosphereSlider(
          icon: Icons.cloud_rounded,
          color: const Color(0xFFA9C4E8),
          title: 'FIRTINA SİSİ',
          value: _stormFog,
          sliderMax: AtmosphereLimits.fogSlider,
          divisions: 60,
          describe: _fogLabel,
          onChanged: (v) => changed(() => _stormFog = v),
        ),
        AtmosphereSlider(
          icon: Icons.blur_on_rounded,
          color: const Color(0xFF62F5C8),
          title: 'GİZEMLİ ATMOSFER',
          value: _hauntLevel,
          sliderMax: AtmosphereLimits.mysticSlider,
          divisions: 20,
          onChanged: (v) => changed(() => _hauntLevel = v, audio: true),
        ),
        AtmosphereSlider(
          icon: Icons.flash_on_rounded,
          color: const Color(0xFFFFE27A),
          title: 'YILDIRIM SIKLIĞI',
          value: _lightningRate,
          sliderMax: AtmosphereLimits.lightningRateSlider,
          divisions: 40,
          onChanged: (v) => changed(() => _lightningRate = v),
        ),
        AtmosphereSlider(
          icon: Icons.timelapse_rounded,
          color: const Color(0xFFFFC56B),
          title: 'YILDIRIM KALICILIĞI',
          value: _lightningLinger,
          sliderMax: AtmosphereLimits.lingerSlider,
          divisions: 30,
          unit: AtmosphereUnit.seconds,
          offLabel: 'Anında söner',
          onChanged: (v) => changed(() => _lightningLinger = v),
        ),
        const Text(
          'Rüzgâr, uğultu ve gök gürültüsü ses düzeyleri yukarıdaki SES KARIŞIMI bölümünde.',
          style: TextStyle(fontSize: 10.5, color: Color(0xFF98A8C2)),
        ),
        const SizedBox(height: 8),
        const Text('FIRTINA KALİTESİ',
            style: TextStyle(fontSize: 11, letterSpacing: 1.1, color: Color(0xFFC8A464))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in StormQuality.values)
              ChoiceChip(
                label: Text(q.label, style: const TextStyle(fontSize: 12)),
                selected: _stormQuality == q,
                selectedColor: q == StormQuality.cinematic ? const Color(0xFF4A2B68) : const Color(0xFF2B4268),
                onSelected: (_) => changed(() => _stormQuality = q),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          switch (_stormQuality) {
            StormQuality.auto => 'Grafik kalitesine göre otomatik seçilir.',
            StormQuality.low => 'Düşük: 3 katman gürültü, hacim ışığı yok. Zayıf cihazlar için.',
            StormQuality.medium => 'Orta: 4 katman gürültü, ana bulutlarda hacim ışığı.',
            StormQuality.high => 'Yüksek: 5 katman gürültü, daha çok rüzgâr ve ışık izi.',
            StormQuality.cinematic =>
              'Sinematik: 6 katman gürültü, tüm bulutlarda hacim ışığı, en yoğun rüzgâr ve ışık izi sürüsü. Güçlü ekran kartı ister.',
          },
          style: const TextStyle(fontSize: 11, color: Color(0xFF98A8C2)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFFE27A),
            side: const BorderSide(color: Color(0xFF6B5A22)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          onPressed: () => _lightning?.triggerNow(),
          icon: const Icon(Icons.flash_on_rounded, size: 18),
          label: const Text('Yıldırım Çaktır (Dene)'),
        ),
      ],
    );
  }

  void _buildGothicCitadelRing() {
    const towerCount = 28;
    final stoneColors = [
      0x0A121D, // Derin gotik bazalt
      0x0F1A28, // Obsidyen duman
      0x142234, // Gece fırtına taşı
      0x192B40, // Buzul arduvaz
    ];

    for (var i = 0; i < towerCount; i++) {
      final baseAng = (i / towerCount) * math.pi * 2;
      final ang = baseAng + (_rng.nextDouble() * 0.10 - 0.05);
      final rad = 12.5 + (i % 6) * 2.6 + _rng.nextDouble() * 1.6;

      final isForeground = math.sin(ang) > 0.40; // Beyaz ordu tarafı (kamera önü)
      final isBackdrop = math.sin(ang) < -0.15;  // Siyah ordu arkası (Görsel 2 arka planı)

      final double height;
      final double widthScale;
      if (isForeground) {
        // Ön planda taş harabeler ve alçak siperler: Tahta görüşünü ASLA engellemez!
        height = 1.6 + _rng.nextDouble() * 1.8;
        widthScale = 0.75 + _rng.nextDouble() * 0.35;
      } else if (isBackdrop) {
        // Arka planda Görsel 2'deki gibi göğe yükselen devasa katedral kuleleri!
        height = 12.0 + _rng.nextDouble() * 12.0;
        widthScale = 1.0 + _rng.nextDouble() * 0.6;
      } else {
        // Yan kanatlarda orta-yüksek gotik burçlar
        height = 6.0 + _rng.nextDouble() * 7.5;
        widthScale = 0.85 + _rng.nextDouble() * 0.45;
      }

      // Fırtınayla bütünleşik koyu taş: kenar ışığı, şimşekte parlama, sis.
      // Opaktır ve derinlik yazar; arkasındaki bulutlar doğru kesilir.
      final col = stoneColors[i % stoneColors.length];
      final towerMat = _storm!.towerMaterial(col);

      final accentCol = mixColor(col, 0x56A8F5, 0.22);
      final accentMat = _storm!.towerMaterial(accentCol, accent: true);

      final tower = three.Group();
      tower.position.setValues(
        math.cos(ang) * rad,
        isForeground ? -0.8 : -1.2,
        math.sin(ang) * rad,
      );
      tower.rotation.y = ang + math.pi / 4;

      if (isForeground) {
        // Alçak gotik siper / payanda sütunu
        final shaftGeo = three.CylinderGeometry(0.35 * widthScale, 0.55 * widthScale, height, 5);
        final capGeo = three.ConeGeometry(0.58 * widthScale, height * 0.45, 5);
        final shaft = three.Mesh(shaftGeo, towerMat);
        shaft.position.y = height * 0.5;
        final cap = three.Mesh(capGeo, accentMat);
        cap.position.y = height + height * 0.22;
        tower.add(shaft);
        tower.add(cap);
      } else {
        // Görsel 2: Çok kademeli, sivri iğneli ve yan kulecikli anıtsal gotik kule
        final shaftH = height * 0.55;
        final spireH = height * 0.45;
        final rTop = 0.45 * widthScale;
        final rBottom = 1.05 * widthScale;

        // Ana gövde sütunu
        final shaftGeo = three.CylinderGeometry(rTop, rBottom, shaftH, 6);
        final shaft = three.Mesh(shaftGeo, towerMat);
        shaft.position.y = shaftH * 0.5;
        tower.add(shaft);

        // Katedral galerisi / korniş bileziği
        final corniceGeo = three.CylinderGeometry(rTop * 1.35, rTop * 1.05, shaftH * 0.08, 6);
        final cornice = three.Mesh(corniceGeo, accentMat);
        cornice.position.y = shaftH;
        tower.add(cornice);

        // Ana iğne sivri kubbe (Görsel 2'deki gibi jilet gibi sivri gotik iğne)
        final spireGeo = three.ConeGeometry(rTop * 1.25, spireH, 6);
        final spire = three.Mesh(spireGeo, accentMat);
        spire.position.y = shaftH + spireH * 0.5;
        tower.add(spire);

        // Görsel 2 imzası: Ana iğnenin etrafında 3-4 adet minyatür sivri yan kulecik
        final subCount = isBackdrop ? 4 : 2;
        final subGeo = three.ConeGeometry(rTop * 0.35, spireH * 0.35, 4);
        for (var s = 0; s < subCount; s++) {
          final sAng = s * (math.pi * 2 / subCount);
          final sub = three.Mesh(subGeo, accentMat);
          sub.position.setValues(
            math.cos(sAng) * (rTop * 1.15),
            shaftH + spireH * 0.16,
            math.sin(sAng) * (rTop * 1.15),
          );
          tower.add(sub);
        }

        // Dışa doğru açılan gotik uçan payanda kanatları (Görsel 2)
        if (isBackdrop && height > 16.0) {
          final buttressGeo = three.BoxGeometry(0.22, height * 0.32, rBottom * 1.8);
          final buttress = three.Mesh(buttressGeo, towerMat);
          buttress.position.setValues(0, height * 0.25, rBottom * 0.7);
          buttress.rotation.x = -0.35;
          tower.add(buttress);
        }
      }

      // Yıldırımın düşebileceği kule uçları (ön siperlerde külah ucu ~1.45 × yükseklik)
      final tipHeight = isForeground ? height * 1.445 : height;
      _spireTips.add(P3(tower.position.x, tower.position.y + tipHeight, tower.position.z));
      _horizonGroup.add(tower);
    }
  }

  void _rebuildArenaMesh() {
    for (final child in List<three.Object3D>.of(_arenaLayer.children)) {
      _arenaLayer.remove(child);
    }
    final (arenaSolid, arenaFlames) = _factory.buildArena(
      tileColors,
      variant: game.variant,
      size: game.boardSize,
    );
    _arenaLayer.add(arenaSolid);
    _arenaLayer.add(arenaFlames);
    _applyPlayScale();
  }

  /// Etkin tahta boyutunun oyun alanı ölçeğini uygular; yakınlaştırma sınırı
  /// da küçülen taşlara aynı yakınlıktan bakılabilsin diye ölçeklenir.
  void _applyPlayScale() {
    _playScale = game.shape.playScale;
    _playLayer.scale.setValues(_playScale, _playScale, _playScale);
    _orbit?.minDistance = _orbitMinDistance;
  }

  double get _orbitMinDistance => 6.5 * _playScale;

  /// Oyun alanı (yerel) konumunu sahne konumuna çevirir.
  P3 _playToWorld(P3 p) => P3(p.x * _playScale, p.y * _playScale, p.z * _playScale);

  /// Sahne (dünya) konumunu oyun alanı yerel konumuna çevirir (sarsıntı ofseti dâhil).
  P3 _worldToPlay(P3 w) {
    final o = _world.position;
    return P3(
      (w.x - o.x) / _playScale,
      (w.y - o.y) / _playScale,
      (w.z - o.z) / _playScale,
    );
  }

  P3 _camGoalForPreset(CamPreset preset, double fitDist) {
    final r = fitDist * 0.80;
    final y = fitDist * 0.72;
    return switch (preset) {
      CamPreset.white => P3(0, y, r),
      CamPreset.black => game.isThreePlayer
          ? P3(r * 0.8660254, y, -r * 0.5)
          : P3(0, y, -r),
      CamPreset.emerald => P3(-r * 0.8660254, y, -r * 0.5),
      CamPreset.top => P3(
          0,
          fitDist * 1.06,
          (_humanTeam == Team.black &&
                      !game.isThreePlayer &&
                      _mode == GameMode.humanVsAi
                  ? -1.0
                  : 1.0) *
              fitDist *
              0.22,
        ),
    };
  }

  /// Tahtanın verilen görüş açısı ve ekran oranında tamamen sığdığı kamera uzaklığı.
  static double _fitDistFor(double fovDeg, double aspect) {
    final tanH = math.tan(fovDeg * math.pi / 360.0) * aspect;
    return math.max(23.0, 10.65 / tanH);
  }

  /// Son kamera sığdırmasında kullanılan ekran oranı ve görüş açısı.
  double _framedAspect = 1.0;
  double _framedFov = 45.0;

  /// Telefon (dikey) ve masaüstü (yatay) ekran oranlarına göre kamerayı sığdırır.
  void _applyCameraFraming({required bool snapPosition}) {
    final cam = _engine.camera;
    if (cam is! three.PerspectiveCamera) return;
    final aspect = (_engine.width / math.max(1.0, _engine.height)).clamp(0.42, 2.6);
    cam.fov = aspect < 0.85 ? 54.0 : 45.0;
    cam.aspect = aspect;
    cam.near = 0.15;
    cam.updateProjectionMatrix();
    _framedAspect = aspect;
    _framedFov = cam.fov.toDouble();

    if (!snapPosition) return;
    final fitDist = _fitDistFor(cam.fov.toDouble(), aspect);
    final targetY = aspect < 0.85 ? 0.10 : 0.36;

    _boardPanned = false;
    _orbit?.target.setValues(0, targetY, 0);
    final goal = _camGoalForPreset(_camPreset, fitDist);
    cam.position.setValues(goal.x, goal.y, goal.z);
    cam.lookAt(three.Vector3(0, targetY, 0));
    _orbit?.update();
  }

  /// Pencere büyütülüp küçültülünce kullanıcının döndürdüğü bakış açısı korunur;
  /// yalnızca kamera uzaklığı yeni ekran oranına göre ölçeklenir. Böylece dar
  /// pencerede tahta kesilmez, geniş pencerede de gereksiz uzakta kalmaz.
  void _refitCameraAfterResize() {
    final cam = _engine.camera;
    if (cam is! three.PerspectiveCamera) return;
    final oldFit = _fitDistFor(_framedFov, _framedAspect);
    _applyCameraFraming(snapPosition: false);
    final newFit = _fitDistFor(cam.fov.toDouble(), cam.aspect.toDouble());
    final orbit = _orbit;
    if (orbit == null || (newFit - oldFit).abs() < 1e-3) return;

    final t = orbit.target;
    final dx = cam.position.x - t.x;
    final dy = cam.position.y - t.y;
    final dz = cam.position.z - t.z;
    final dist = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (dist < 1e-3) return;
    final newDist = (dist * newFit / oldFit).clamp(orbit.minDistance, orbit.maxDistance);
    final k = newDist / dist;
    cam.position.setValues(t.x + dx * k, t.y + dy * k, t.z + dz * k);
    orbit.update();
  }

  /// Tahtayı ekrana paralel olarak (X, Z) düzleminde kaydırır (Move Board).
  void _panBoardByPixels(Offset delta, Size viewSize) {
    if (!_ready || _inPovSequence || _orbit == null) return;
    final cam = _engine.camera;
    if (cam is! three.PerspectiveCamera) return;

    final tgt = _orbit!.target;
    final dxCam = cam.position.x - tgt.x;
    final dyCam = cam.position.y - tgt.y;
    final dzCam = cam.position.z - tgt.z;
    final dist = math.sqrt(dxCam * dxCam + dyCam * dyCam + dzCam * dzCam).clamp(6.0, 48.0);

    // Kameranın yatay ileri ve sağ vektörleri
    var fwdX = -dxCam.toDouble();
    var fwdZ = -dzCam.toDouble();
    final fLen = math.sqrt(fwdX * fwdX + fwdZ * fwdZ);
    if (fLen < 1e-4) {
      fwdX = 0;
      fwdZ = -1;
    } else {
      fwdX /= fLen;
      fwdZ /= fLen;
    }
    final rightX = -fwdZ;
    final rightZ = fwdX;

    final worldPerPixel = (2.0 * dist * math.tan(cam.fov * math.pi / 360.0)) /
        math.max(240.0, viewSize.height);

    final moveRight = -delta.dx * worldPerPixel;
    final moveFwd = delta.dy * worldPerPixel;
    final wx = rightX * moveRight + fwdX * moveFwd;
    final wz = rightZ * moveRight + fwdZ * moveFwd;

    final nextTx = (tgt.x + wx).clamp(-10.5, 10.5);
    final nextTz = (tgt.z + wz).clamp(-10.5, 10.5);
    final actualDx = nextTx - tgt.x;
    final actualDz = nextTz - tgt.z;

    tgt.x = nextTx;
    tgt.z = nextTz;
    cam.position.x += actualDx;
    cam.position.z += actualDz;
    _orbit!.update();

    if (!_boardPanned && (nextTx.abs() > 0.25 || nextTz.abs() > 0.25)) {
      setState(() => _boardPanned = true);
    }
  }

  Future<void> _recenterBoard() async {
    if (!_ready || _inPovSequence || _orbit == null) return;
    final cam = _engine.camera;
    final aspect = (_engine.width / math.max(1.0, _engine.height)).clamp(0.42, 2.6);
    final targetY = aspect < 0.85 ? -0.35 : 0.0;
    final startTarget = P3.of(_orbit!.target);
    final goalTarget = P3(0, targetY, 0);
    final startCam = P3.of(cam.position);
    final goalCam = startCam + (goalTarget - startTarget);

    setState(() {
      _boardPanned = false;
      _message = 'Savaş tahtası merkeze hizalandı.';
    });
    await _anim.play(
      0.32,
      (t) {
        final k = smooth(t);
        final ct = P3.lerp(startTarget, goalTarget, k);
        final cp = P3.lerp(startCam, goalCam, k);
        _orbit!.target.setValues(ct.x, ct.y, ct.z);
        cam.position.setValues(cp.x, cp.y, cp.z);
        _orbit!.update();
      },
      kind: AnimKind.fixed,
    );
  }

  Future<void> _animateCameraToPreset(CamPreset preset) async {
    _camPreset = preset;
    if (!_ready || _inPovSequence) return;
    final cam = _engine.camera;
    if (cam is! three.PerspectiveCamera) return;
    final aspect = (_engine.width / math.max(1.0, _engine.height)).clamp(0.42, 2.6);
    final tanH = math.tan(cam.fov * math.pi / 360.0) * aspect;
    final fitDist = math.max(23.0, 10.65 / tanH);
    final targetY = aspect < 0.85 ? 0.10 : 0.36;

    final start = P3.of(cam.position);
    final startTgt = P3.of(_orbit!.target);
    final goalTgt = P3(0, targetY, 0);
    final goal = _camGoalForPreset(preset, fitDist);
    _boardPanned = false;
    if (mounted) setState(() {});
    await _anim.play(
      0.40,
      (t) {
        final k = smooth(t);
        final p = P3.lerp(start, goal, k);
        final tg = P3.lerp(startTgt, goalTgt, k);
        _orbit?.target.setValues(tg.x, tg.y, tg.z);
        cam.position.setValues(p.x, p.y, p.z);
        cam.lookAt(three.Vector3(tg.x, tg.y, tg.z));
        _orbit?.update();
      },
      kind: AnimKind.fixed,
    );
  }

  // ================================================================ BİRİNCİ ŞAHIS (POV 2.0) KAMERA SİSTEMİ
  (P3 eye, P3 lookTarget, double finalYaw) _computePovCameraPose(CreatureRig rig) {
    final localEye = rig.povLocalEye;
    final yaw = rig.root.rotation.y.toDouble();
    final sinY = math.sin(yaw), cosY = math.cos(yaw);

    // 1:1 tam gövde senkronizasyonu: sıçrama, uçuş ve atılmalarda kamera ASLA gövde içine gömülmez!
    final bx = rig.body.position.x.toDouble();
    final by = rig.body.position.y.toDouble();
    final bz = rig.body.position.z.toDouble();

    final torso = rig.parts['torso'];
    final torsoLeanZ =
        torso != null ? (torso.rotation.x.toDouble() * 0.12).clamp(-0.06, 0.10) : 0.0;
    final torsoTurnY =
        torso != null ? (torso.rotation.y.toDouble() * 0.22).clamp(-0.18, 0.18) : 0.0;

    final lx = localEye.x + bx;
    final ly = localEye.y + by;
    final lz = localEye.z + bz + torsoLeanZ;

    final wx = rig.root.position.x.toDouble() + lx * cosY + lz * sinY;
    final wy = rig.root.position.y.toDouble() + ly;
    final wz = rig.root.position.z.toDouble() - lx * sinY + lz * cosY;
    final eye = P3(wx, wy, wz);

    var baseYaw = yaw + torsoTurnY;
    var basePitch = rig.povBasePitch + _povReadyExtraPitch;

    // Uçuş inişlerinde veya dövüş düellolarında hedefe/rakibe otomatik sinematik kilitlenme
    final focus = _povFocusWorld;
    if (focus != null && _povFocusWeight > 1e-3) {
      final d = focus - eye;
      final flat = d.flatLength;
      if (flat > 0.08) {
        final targetYaw = math.atan2(d.x, d.z);
        var dyaw = (targetYaw - baseYaw) % (math.pi * 2);
        if (dyaw > math.pi) dyaw -= math.pi * 2;
        final targetPitch = math.atan2(d.y, flat).clamp(-0.62, 0.26);
        baseYaw += dyaw * _povFocusWeight;
        basePitch += (targetPitch - basePitch) * _povFocusWeight;
      }
    }

    final finalYaw = baseYaw + _povLookYaw;
    final finalPitch = (basePitch + _povLookPitch).clamp(-1.15, 0.42);
    final cosP = math.cos(finalPitch);
    final dirX = math.sin(finalYaw) * cosP;
    final dirY = math.sin(finalPitch);
    final dirZ = math.cos(finalYaw) * cosP;

    final look = P3(wx + dirX * 4.0, wy + dirY * 4.0, wz + dirZ * 4.0);
    // Göz ve bakış noktası oyun alanında hesaplandı; kamera sahne biriminde durur.
    return (_playToWorld(eye), _playToWorld(look), finalYaw);
  }

  /// POV yakın kırpma düzlemi: küçültülmüş oyun alanında karakterin kendi
  /// silahı/kolu aynı oranda görünür kalsın diye alanla birlikte ölçeklenir.
  double get _povNear => 0.035 * _playScale;

  void _updateActivePovCamera() {
    final rig = _povRig;
    if (rig == null) return;
    final cam = _engine.camera;
    if (cam is! three.PerspectiveCamera) return;

    final (eye, look, finalYaw) = _computePovCameraPose(rig);
    final s = _fx.shake * 0.16;
    cam.position.setValues(
      eye.x + (s > 1e-4 ? _fx.r(s) : 0),
      eye.y + (s > 1e-4 ? _fx.r(s) * 0.5 : 0),
      eye.z + (s > 1e-4 ? _fx.r(s) : 0),
    );
    // Doğal adım ve darbe ağırlığı veren hafif birinci şahıs baş yatışı (camera roll)
    final sinR = math.sin(_povRoll);
    final cosR = math.cos(_povRoll);
    cam.up.setValues(-math.cos(finalYaw) * sinR, cosR, math.sin(finalYaw) * sinR);
    cam.lookAt(three.Vector3(look.x, look.y, look.z));
  }

  void _exitPovImmediate() {
    if (_povRig != null) {
      _povRig!.setFirstPersonMode(false);
      _povRig = null;
    }
    for (final r in _rigs.values) {
      if (r.inPov) r.setFirstPersonMode(false);
    }
    _inPovSequence = false;
    _povCountdown = 0.0;
    _povLookYaw = 0.0;
    _povLookPitch = 0.0;
    _povReadyExtraPitch = 0.0;
    _povRoll = 0.0;
    _povFocusWorld = null;
    _povFocusWeight = 0.0;
    final cam = _engine.camera;
    if (cam is three.PerspectiveCamera) {
      cam.up.setValues(0, 1, 0);
      cam.near = 0.15;
      if (_povSavedCamPos != null && _povSavedTarget != null) {
        cam.fov = _povSavedFov;
        cam.updateProjectionMatrix();
        _orbit?.target.setValues(
          _povSavedTarget!.x,
          _povSavedTarget!.y,
          _povSavedTarget!.z,
        );
        cam.position.setValues(
          _povSavedCamPos!.x,
          _povSavedCamPos!.y,
          _povSavedCamPos!.z,
        );
        cam.lookAt(three.Vector3(
          _povSavedTarget!.x,
          _povSavedTarget!.y,
          _povSavedTarget!.z,
        ));
      } else {
        _applyCameraFraming(snapPosition: false);
      }
    }
    _povSavedCamPos = null;
    _povSavedTarget = null;
    _syncOrbitInteraction();
    _orbit?.update();
  }

  void _skipCurrentPovToBoard() {
    if (!_inPovSequence) return;
    _exitPovImmediate();
    if (mounted) setState(() {});
  }

  // ================================================================ SESLENDİRME & SAVAŞ NARASI BİLDİRİMİ
  void _triggerVoice(PieceType kind, VoiceEvent event, Team team) {
    if (_showLaunchScreen) return;
    final line = _audio.speak(kind, event);
    _voiceBannerTimer?.cancel();
    if (mounted) {
      setState(() {
        _activeVoice = line;
        _activeVoiceTeam = team;
      });
    }
    final bannerDurationMs = math.max(3800, line.durationMs + 350);
    _voiceBannerTimer = Timer(Duration(milliseconds: bannerDurationMs), () {
      if (mounted) {
        setState(() => _activeVoice = null);
      }
    });
  }

  /// Hücrenin sütun tepesi (oyun alanı yerel biriminde).
  P3 _cellPos(HexCell c) {
    final (x, z) = HexBoard.worldXZ(c);
    return P3(x, game.shape.columnHeight(c), z);
  }

  double _groundAt(double x, double z) =>
      game.shape.surfaceHeightAtWorld(x, z);

  P3 _stepPathPos(P3 a, P3 b, double u) {
    final x = a.x + (b.x - a.x) * u;
    final z = a.z + (b.z - a.z) * u;
    return P3(x, _groundAt(x, z), z);
  }

  void _place(CreatureRig r, P3 p) => r.root.position.setValues(p.x, p.y, p.z);
  P3 _posOf(CreatureRig r) => P3.of(r.root.position);

  CreatureRig _spawnRig(ChessPiece piece, HexCell cell) {
    final rig = _factory.build(piece);
    _place(rig, _cellPos(cell));
    final f = rig.defaultFacingFor(game.variant);
    rig.facing = f;
    rig.root.rotation.y = f;
    _pieceLayer.add(rig.root);
    _rigs[cell] = rig;
    return rig;
  }

  /// Masa düzenini ve/veya 3 kişilik tahta boyutunu değiştirip yeni savaş kurar.
  void _switchVariant(
    BoardVariant next, {
    BoardSize? size,
    bool skipMatchSession = false,
  }) {
    final sizeChanges = size != null && size != game.boardSize3P;
    if (!_ready) return;
    if (game.variant == next && !(next == BoardVariant.threePlayer && sizeChanges)) {
      // 2 kişilik oyun sürerken yalnızca 3'lü boyut tercihi değiştiyse oyunu bozmadan hatırla
      if (sizeChanges) {
        game.rememberBoardSize3P(size);
        _persistSettings();
      }
      return;
    }
    _generation++;
    _anim.clear();
    _fx.clear();
    _exitPovImmediate();
    if (next == BoardVariant.twoPlayer && _humanTeam == Team.emerald) {
      _humanTeam = Team.white;
    }
    if (next == BoardVariant.twoPlayer && _camPreset == CamPreset.emerald) {
      _camPreset = CamPreset.white;
    }
    game.setVariant(next, size: size);
    _busy = false;
    _thinking = false;
    _hintBusy = false;
    _selected = null;
    _targets = [];
    _hint = null;
    _battleText = '';
    _message = next == BoardVariant.threePlayer
        ? '3 Kişilik Amfi Masası (${game.boardSize3P.label} tahta, ${game.boardSize3P.cellCount} hücre) kuruldu! Beyaz, Siyah ve Zümrüt ordular karşı karşıya.'
        : '2 Kişilik Amfi Düellosu kuruldu! Beyaz ordu başlar.';
    _rebuildArenaMesh();
    _rebuildAllRigsFromBoard();
    _refreshHighlights();
    _applyCameraFraming(snapPosition: true);
    if (!skipMatchSession) {
      unawaited(_startNewMatchSession(next));
    }
    _persistSettings();
    setState(() {});
    _maybeAi();
  }

  void _makeAllPieces() {
    for (final entry in game.pieces.entries) {
      _spawnRig(entry.value, entry.key);
    }
  }

  void _rebuildAllRigsFromBoard() {
    for (final child in List<three.Object3D>.of(_pieceLayer.children)) {
      _pieceLayer.remove(child);
    }
    _rigs.clear();
    _makeAllPieces();
  }

  // ================================================================ ANİMASYON DÖNGÜSÜ
  /// Kare süresi ölçümü (yalnızca `--dart-define=WHC_FRAME_STATS=true` ile).
  static const bool _kFrameStats = bool.fromEnvironment('WHC_FRAME_STATS');
  double _statSince = 0;
  int _statFrames = 0;
  double _statWorst = 0;
  int _statSlow = 0;
  double _statRenderMs = 0;
  double _statTickMs = 0;

  void _recordFrame(double now, double raw, double tickMs) {
    _statFrames++;
    if (raw > _statWorst) _statWorst = raw;
    if (raw > 1 / 30) _statSlow++;
    _statRenderMs += _engine.lastRenderMs;
    _statTickMs += tickMs;
    final span = now - _statSince;
    if (span >= 5.0) {
      final n = math.max(1, _statFrames);
      final r = _engine.renderer;
      final lookups = r?.programLookups ?? 0;
      r?.programLookups = 0;
      debugPrint('[kare] faz $_diagPhase · ${(_statFrames / span).toStringAsFixed(1)} fps · '
          'en uzun ${(_statWorst * 1000).toStringAsFixed(1)} ms · '
          '33 ms üstü: $_statSlow/$_statFrames · '
          'sahne CPU ${(_statRenderMs / n).toStringAsFixed(1)} ms · '
          'tick ${(_statTickMs / n).toStringAsFixed(1)} ms · '
          'çizim ${_engine.lastDrawCalls} · üçgen ${_engine.lastTriangles} · '
          'program arama/kare ${(lookups / n).toStringAsFixed(1)}');
      if (r != null) {
        String ms(Stopwatch w) => (w.elapsedMicroseconds / 1000.0 / n).toStringAsFixed(1);
        debugPrint('[profil] güncelle ${ms(r.profUpdate)} · listele ${ms(r.profProject)} · '
            'setProgram ${ms(r.profSetProgram)} · VAO ${ms(r.profBinding)} · çiz ${ms(r.profDraw)} ms/kare');
        for (final w in [r.profUpdate, r.profProject, r.profSetProgram, r.profBinding, r.profDraw]) {
          w.reset();
        }
      }
      _statSince = now;
      _statFrames = 0;
      _statWorst = 0;
      _statSlow = 0;
      _statRenderMs = 0;
      _statTickMs = 0;
    }
  }

  void _tick() {
    final now = _clock.elapsedMicroseconds / 1e6;
    final raw = now - _last;
    final dt = raw.clamp(0.0, 0.05);
    _last = now;
    _tickBody(now, dt);
    if (_kFrameStats) {
      _recordFrame(now, raw, (_clock.elapsedMicroseconds / 1e6 - now) * 1000.0);
      _diagCycle(now);
    }
  }

  // GEÇİCİ TANI: her 10 sn'de bir fırtınayı / karakterleri gizleyip maliyeti ölçer.
  int _diagPhase = 0;
  void _diagCycle(double now) {
    final phase = (now / 10).floor() % 4;
    if (phase == _diagPhase) return;
    _diagPhase = phase;
    _storm?.group.visible = phase == 0 || phase == 2;
    _pieceLayer.visible = phase == 0 || phase == 1;
    _statSince = now;
    _statFrames = 0;
    _statWorst = 0;
    _statSlow = 0;
    _statRenderMs = 0;
    _statTickMs = 0;
  }

  void _tickBody(double now, double dt) {
    _anim.tick(now);
    _fx.update(dt);
    _idle(now);

    // Fırtına girdabı: bulut akışı tamamen shader'da, burada yalnızca zaman ilerler.
    if (_ready) {
      // Sis dozu pencere boyutundan bağımsız olsun: dar pencerede kamera tahtadan
      // daha uzakta durduğu için sahne sisi kameranın uzaklığına göre ölçeklenir.
      final cp = _engine.camera.position;
      _storm?.viewDistance = math.sqrt(cp.x * cp.x + cp.y * cp.y + cp.z * cp.z);
      _storm?.update(dt);

      // Yıldırım + gök gürültüsü zamanlaması
      _lightning?.update(dt);
    }

    if (_povRig != null) {
      _world.position.setValues(0, 0, 0);
      _updateActivePovCamera();
    } else {
      final s = _fx.shake * 0.5;
      if (s > 1e-4) {
        _world.position.setValues(_fx.r(s), _fx.r(s) * 0.4, _fx.r(s));
      } else if (_world.position.x != 0 || _world.position.y != 0 || _world.position.z != 0) {
        _world.position.setValues(0, 0, 0);
      }
    }
    _fireLight.intensity = 14.5 + math.sin(now * 8.5) * 1.4 + math.sin(now * 21) * 0.9;
  }

  /// '$part.$axis' anahtarları önbelleklenir: boşta animasyonu her karede
  /// onlarca karakter × birkaç parça için yeni String üretmez (GC takılması olmaz).
  static final Map<String, Map<String, String>> _restKeys = {};
  static String _restKey(String part, String axis) =>
      (_restKeys[part] ??= <String, String>{})[axis] ??= '$part.$axis';

  double _rest(CreatureRig r, String part, String axis) => r.rest[_restKey(part, axis)] ?? 0;

  void _setRot(CreatureRig r, String part, {double? x, double? y, double? z}) {
    final p = r.parts[part];
    if (p == null) return;
    if (x != null) p.rotation.x = x;
    if (y != null) p.rotation.y = y;
    if (z != null) p.rotation.z = z;
  }

  void _idleOffset(CreatureRig r, String part, {double x = 0, double y = 0, double z = 0}) {
    _setRot(r, part,
        x: _rest(r, part, 'rx') + x,
        y: _rest(r, part, 'ry') + y,
        z: _rest(r, part, 'rz') + z);
  }

  void _animateBats(CreatureRig rig, double t) {
    final radius = rig.inPov ? 0.68 : 0.42;
    final baseY = rig.inPov ? 1.36 : 1.16;
    for (var i = 0; i < rig.orbiters.length; i++) {
      final bat = rig.orbiters[i];
      final a = t * 1.7 + i * math.pi + rig.phase;
      bat.position.setValues(
          math.cos(a) * radius, baseY + 0.07 * math.sin(t * 3 + i), math.sin(a) * radius);
      bat.rotation.y = -a;
      for (final w in bat.children) {
        final side = w.userData['side'];
        if (side is double) w.rotation.z = side * 0.7 * math.sin(t * 24 + i);
      }
    }
  }

  void _idle(double t) {
    for (final entry in _rigs.entries) {
      final rig = entry.value;
      _animateBats(rig, t);
      if (rig.busy) continue;
      final ph = rig.phase;
      final sel = entry.key == _selected;
      final w = math.sin(t * 2.1 + ph);
      rig.body.position.y = sel ? 0.07 + 0.025 * math.sin(t * 5) : 0.0;
      switch (rig.kind) {
        case PieceType.bishop:
          final flap = math.sin(t * 2.3 + ph) * 0.16;
          _idleOffset(rig, 'wingL', z: flap);
          _idleOffset(rig, 'wingR', z: -flap);
          _idleOffset(rig, 'tail', y: math.sin(t * 1.4 + ph) * 0.26);
          _idleOffset(rig, 'head',
              x: math.sin(t * 1.1 + ph) * 0.06, y: math.sin(t * 0.6 + ph) * 0.16);
        case PieceType.knight:
          _idleOffset(rig, 'torso', x: 0.02 * w);
          _idleOffset(rig, 'head', y: math.sin(t * 0.7 + ph) * 0.25);
          _idleOffset(rig, 'cape', x: -0.04 + w * 0.04);
        case PieceType.rook:
          _idleOffset(rig, 'torso', x: w * 0.02, y: w * 0.03);
          _idleOffset(rig, 'head', y: math.sin(t * 0.5 + ph) * 0.16);
          _idleOffset(rig, 'armR', x: w * 0.04);
        case PieceType.queen:
          _idleOffset(rig, 'cape', x: -0.03 + math.sin(t * 1.7 + ph) * 0.04);
          final orb = rig.parts['orb'];
          final s = 0.044 * (1 + 0.18 * math.sin(t * 4 + ph));
          orb?.scale.setValues(s, s, s);
        case PieceType.king:
          _idleOffset(rig, 'torso', x: w * 0.02);
          _idleOffset(rig, 'armR', x: w * 0.045);
          _idleOffset(rig, 'cape', x: -0.03 + w * 0.03);
          _idleOffset(rig, 'head', y: math.sin(t * 0.5 + ph) * 0.12);
        case PieceType.pawn:
          _idleOffset(rig, 'torso', x: w * 0.018);
          _idleOffset(rig, 'armR', x: w * 0.035);
      }
    }
  }

  // ================================================================ ANALİTİK DOKUNMA & TAHTA TAŞIMA
  bool get _isHumanTurn => switch (_mode) {
        GameMode.humanVsHuman => true,
        GameMode.humanVsAi => game.turn == _humanTeam,
        GameMode.aiVsAi => false,
      };

  HexCell? _pickCellAt(Offset position, Size size) {
    if (_raycaster == null || size.width <= 0 || size.height <= 0) return null;
    final ndc = three.Vector2(
      (position.dx / size.width) * 2 - 1,
      -(position.dy / size.height) * 2 + 1,
    );
    _raycaster!.setFromCamera(ndc, _engine.camera);
    // Işın oyun alanının yerel birimine çevrilir (büyük tahtada alan ölçeklidir);
    // eşit ölçekte yön değişmez, yalnızca başlangıç noktası taşınır.
    final orig = _worldToPlay(P3.of(_raycaster!.ray.origin));
    final dir = _raycaster!.ray.direction;
    final ox = orig.x, oy = orig.y, oz = orig.z;
    final dx = dir.x.toDouble(), dy = dir.y.toDouble(), dz = dir.z.toDouble();
    final a = dx * dx + dz * dz;

    HexCell? colCell;
    var bestColT = double.infinity;
    const colRad = 0.80;
    const colRadSq = colRad * colRad;

    HexCell? cylCell;
    var bestRigT = double.infinity;
    const rigRad = 0.40;
    const rigRadSq = rigRad * rigRad;

    final shape = game.shape;
    for (final cell in shape.cells) {
      final (cx, cz) = HexBoard.worldXZ(cell);
      final topY = shape.columnHeight(cell);
      final rx = ox - cx, rz = oz - cz;

      // 1) 3B Amfi Sütunu Üst Tablası ve Yan Gövde Kesişimi
      if (dy.abs() > 1e-6) {
        final tTop = (topY - oy) / dy;
        if (tTop > 0 && tTop < bestColT) {
          final hx = rx + tTop * dx, hz = rz + tTop * dz;
          if (hx * hx + hz * hz <= colRadSq) {
            bestColT = tTop;
            colCell = cell;
          }
        }
      }
      if (a > 1e-8) {
        final b = 2 * (rx * dx + rz * dz);
        final cCol = rx * rx + rz * rz - colRadSq;
        final discCol = b * b - 4 * a * cCol;
        if (discCol >= 0) {
          final sq = math.sqrt(discCol);
          final t0 = (-b - sq) / (2 * a);
          final t1 = (-b + sq) / (2 * a);
          for (final tc in [t0, t1]) {
            if (tc > 0 && tc < bestColT) {
              final hy = oy + tc * dy;
              if (hy >= -0.08 && hy <= topY) {
                bestColT = tc;
                colCell = cell;
                break;
              }
            }
          }
        }

        // 2) Sütun Üstündeki Savaşçı Silindiri Kesişimi
        if (_rigs.containsKey(cell)) {
          final yMin = topY, yMax = topY + 1.10;
          final cRig = rx * rx + rz * rz - rigRadSq;
          final discRig = b * b - 4 * a * cRig;
          if (discRig >= 0) {
            final sq = math.sqrt(discRig);
            final t0 = (-b - sq) / (2 * a);
            final t1 = (-b + sq) / (2 * a);
            for (final tc in [t0, t1]) {
              if (tc > 0 && tc < bestRigT) {
                final hy = oy + tc * dy;
                if (hy >= yMin && hy <= yMax) {
                  bestRigT = tc;
                  cylCell = cell;
                  break;
                }
              }
            }
          }
          if (dy.abs() > 1e-6) {
            final tCap = (yMax - oy) / dy;
            if (tCap > 0 && tCap < bestRigT) {
              final hx = rx + tCap * dx, hz = rz + tCap * dz;
              if (hx * hx + hz * hz <= rigRadSq) {
                bestRigT = tCap;
                cylCell = cell;
              }
            }
          }
        }
      }
    }

    if (_selected != null) {
      if (colCell != null &&
          _targets.contains(colCell) &&
          (cylCell == null || bestColT <= bestRigT + 0.35)) {
        return colCell;
      }
      if (cylCell != null && _targets.contains(cylCell)) return cylCell;
      if (colCell != null && _targets.contains(colCell)) return colCell;
      if (cylCell != null && game.pieceAt(cylCell)?.team == game.turn) return cylCell;
      return colCell ?? cylCell;
    }
    if (cylCell != null &&
        game.pieceAt(cylCell)?.team == game.turn &&
        (colCell == null || bestRigT <= bestColT + 0.65)) {
      return cylCell;
    }
    return colCell ?? cylCell;
  }

  void _onViewportPointerDown(PointerDownEvent e) {
    _keyFocus.requestFocus();
    _pointerCount++;
    if (_pointerCount == 1) {
      _activePointer = e.pointer;
      _downPos = e.localPosition;
      _lastDragPos = e.localPosition;
      _downMs = DateTime.now().millisecondsSinceEpoch;
    } else {
      _activePointer = null;
      _downPos = null;
      _lastDragPos = null;
    }
  }

  void _onViewportPointerMove(PointerMoveEvent e, Size size) {
    // 1) POV modundayken parmak / fare ile etrafa, silahlara ve kendi gövde/bacaklarına tam bakabilme!
    if (_inPovSequence && _povRig != null) {
      _povLookYaw = (_povLookYaw - e.delta.dx * 0.0052).clamp(-1.12, 1.12);
      _povLookPitch = (_povLookPitch - e.delta.dy * 0.0052).clamp(-0.92, 0.42);
      return;
    }

    // 2) Tahtayı Taşıma (Kaydır modu VEYA sağ/orta fare tuşu sürüklemesi)
    final rightOrMiddleMouse =
        (e.buttons & kSecondaryMouseButton) != 0 || (e.buttons & kMiddleMouseButton) != 0;
    if (_panBoardMode || rightOrMiddleMouse) {
      final prev = _lastDragPos;
      _lastDragPos = e.localPosition;
      if (prev != null && _pointerCount == 1) {
        _panBoardByPixels(e.localPosition - prev, size);
      }
    }
  }

  void _onViewportPointerUp(PointerUpEvent e, Size size) {
    final ptr = _activePointer;
    final start = _downPos;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _downMs;
    _pointerCount = math.max(0, _pointerCount - 1);
    _activePointer = null;
    _downPos = null;
    _lastDragPos = null;

    // Düello sürerken kısa dokunuş kalan kapışma turlarını atlayıp son darbeye geçer
    // (POV'da da çalışır; sürükleme ise bakış/kamera için kalır).
    if (_duelActive &&
        !_duelSkip &&
        ptr == e.pointer &&
        start != null &&
        (e.localPosition - start).distance < 8.5 &&
        elapsed < 420) {
      setState(() {
        _duelSkip = true;
        _battleText = '⚔ Son darbe!';
      });
      return;
    }

    if (!_inPovSequence &&
        ptr == e.pointer &&
        start != null &&
        (e.localPosition - start).distance < 8.5 &&
        elapsed < 420) {
      _onTap(e.localPosition, size);
    }
  }

  void _onViewportPointerCancel(PointerCancelEvent _) {
    _pointerCount = math.max(0, _pointerCount - 1);
    _activePointer = null;
    _downPos = null;
    _lastDragPos = null;
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    const step = 28.0;
    final size = Size(math.max(1.0, _engine.width), math.max(1.0, _engine.height));
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyW || key == LogicalKeyboardKey.arrowUp) {
      _panBoardByPixels(const Offset(0, step), size);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS || key == LogicalKeyboardKey.arrowDown) {
      _panBoardByPixels(const Offset(0, -step), size);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.arrowLeft) {
      _panBoardByPixels(const Offset(step, 0), size);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD || key == LogicalKeyboardKey.arrowRight) {
      _panBoardByPixels(const Offset(-step, 0), size);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _onTap(Offset position, Size size) async {
    if (!_ready || _busy || _thinking || size.width <= 0 || size.height <= 0) return;
    if (!_isHumanTurn || game.status != GameStatus.playing) return;
    final cell = _pickCellAt(position, size);
    if (cell == null) return;
    await _selectOrMove(cell);
  }

  Future<void> _selectOrMove(HexCell target) async {
    final chosen = _selected;
    if (chosen != null && _targets.contains(target)) {
      PieceType? promoChoice;
      if (game.needsPromotion(chosen, target)) {
        promoChoice = await _askPromotionChoice(game.turn);
        if (promoChoice == null || !mounted) return;
      }
      final rec = game.playMove(chosen, target, promotion: promoChoice);
      if (rec != null) {
        _hint = null;
        // İnsan hamlesi -> POV Modu seçiliyse karakterin gözüne geçer!
        await _runMove(rec, _generation, humanMove: true);
      }
      return;
    }

    final occupant = game.pieceAt(target);
    if (occupant != null && occupant.team == game.turn) {
      if (target == _selected) {
        _selected = null;
        _targets = [];
        _message = 'Seçim iptal edildi.';
      } else {
        _selected = target;
        _targets = game.legalMoves(target);
        _playSfx(SfxKind.stepArmor);
        _message = _targets.isEmpty
            ? '${occupant.kind.creature} şu an hareket edemez.'
            : '${occupant.kind.creature} (${occupant.kind.role}) • ${_targets.length} yasal hamle';
      }
    } else {
      _selected = null;
      _targets = [];
      _message = 'Sıradaki ordunun bir savaşçısına dokun.';
    }
    _refreshHighlights();
    setState(() {});
  }

  void _refreshHighlights() {
    if (!_ready && _rigs.isEmpty) return;
    _hl.begin();
    final shape = game.shape;
    double hOf(HexCell c) => shape.columnHeight(c);

    final last = game.lastMove;
    if (last != null) {
      _hl.addHex(last.from,
          topY: hOf(last.from), color: 0xE5B454, ringAlpha: 0.55, fillAlpha: 0.12);
      _hl.addHex(last.to,
          topY: hOf(last.to), color: 0xE5B454, ringAlpha: 0.72, fillAlpha: 0.16);
    }

    final hint = _hint;
    if (hint != null) {
      _hl.addHex(hint.$1,
          topY: hOf(hint.$1),
          color: 0xC084FC,
          ringInner: 0.56,
          ringOuter: 0.78,
          ringAlpha: 0.95,
          fillAlpha: 0.24);
      _hl.addHex(hint.$2,
          topY: hOf(hint.$2),
          color: 0xC084FC,
          ringInner: 0.56,
          ringOuter: 0.78,
          ringAlpha: 0.95,
          fillAlpha: 0.28,
          fangs: true);
    }

    final chkKing = game.checkedKingCell;
    if (chkKing != null) {
      _hl.addHex(chkKing,
          topY: hOf(chkKing),
          color: 0xFF2038,
          ringInner: 0.54,
          ringOuter: 0.80,
          ringAlpha: 0.98,
          fillAlpha: 0.32,
          fangs: true);
    }

    // Şah çeken düşman yaratığı ve krala uzanan hücum hattını (lazer koridoru) parlat:
    final threats = game.currentCheckThreats;
    for (final th in threats) {
      // 1. Şah çeken saldırgan taşı alevli çift çemberle vurgula:
      _hl.addHex(th.attackerCell,
          topY: hOf(th.attackerCell),
          color: 0xFF1144,
          ringInner: 0.48,
          ringOuter: 0.84,
          ringAlpha: 1.0,
          fillAlpha: 0.44,
          fangs: true);

      // 2. Saldırgandan Krala uzanan hücum hattı koridorunu çiz:
      for (final rc in th.rayCells) {
        _hl.addHex(rc,
            topY: hOf(rc),
            color: 0xFF2848,
            ringInner: 0.60,
            ringOuter: 0.74,
            ringAlpha: 0.78,
            fillAlpha: 0.24);
      }
    }

    if (_selected != null) {
      _hl.addHex(_selected!,
          topY: hOf(_selected!),
          color: 0x5CE1FF,
          ringInner: 0.58,
          ringOuter: 0.78,
          ringAlpha: 0.96,
          fillAlpha: 0.24);
    }

    for (final t in _targets) {
      final selPiece = _selected == null ? null : game.pieceAt(_selected!);
      final isEpTarget = selPiece?.kind == PieceType.pawn &&
          game.pieceAt(t) == null &&
          (game.isThreePlayer
              ? game.pos3.geo.idxOf(t) == game.pos3.ep
              : t.q != _selected!.q);
      final enemy = game.pieceAt(t) != null || isEpTarget;
      if (enemy) {
        _hl.addHex(t,
            topY: hOf(t),
            color: 0xFF3B4E,
            ringInner: 0.56,
            ringOuter: 0.78,
            ringAlpha: 0.95,
            fillAlpha: 0.26,
            fangs: true);
      } else {
        _hl.addHex(t,
            topY: hOf(t),
            color: 0x34D399,
            ringInner: 0.62,
            ringOuter: 0.76,
            ringAlpha: 0.88,
            fillAlpha: 0.20);
      }
    }

    _hl.commit();
  }

  // ================================================================ OYUN AKIŞI / YAPAY ZEKÂ / GERİ AL
  Future<void> _maybeAi() async {
    if (!_ready || _busy || _thinking || !mounted) return;
    if (game.status != GameStatus.playing || _isHumanTurn) return;
    final gen = _generation;
    setState(() {
      _thinking = true;
      final aiTag = game.isThreePlayer ? '3\'lü YZ • ${_level.label}' : _level.label;
      _message = '${game.turn.title} ordu ($aiTag) hamle hesaplıyor…';
    });
    final sw = Stopwatch()..start();
    final move = game.isThreePlayer
        ? await aiThinkThreePlayer(
            game.pos3,
            _level,
            repetitionHashes: game.repetitionHashes3P,
          )
        : await aiThink(game.pos, _level);
    final wait = 160 - sw.elapsedMilliseconds;
    if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    if (gen != _generation || !mounted) return;
    _thinking = false;
    if (move == null) {
      setState(() {});
      return;
    }
    _hint = null;
    final rec = game.applyEncoded(move);
    // Yapay zekâ hamlesi -> POV açıksa hamle yapan YZ taşının gözünden izlenir
    await _runMove(rec, gen, humanMove: false);
  }

  Future<void> _requestHint() async {
    if (!_ready || _busy || _thinking || _hintBusy || !_isHumanTurn) return;
    if (game.status != GameStatus.playing) return;
    final gen = _generation;
    setState(() {
      _hintBusy = true;
      _message = 'Taktik danışman en güçlü hamleyi arıyor…';
    });
    final best = game.isThreePlayer
        ? await aiThinkThreePlayer(
            game.pos3,
            AiLevel.wizard,
            repetitionHashes: game.repetitionHashes3P,
          )
        : await aiThink(game.pos, AiLevel.wizard);
    if (gen != _generation || !mounted) return;
    _hintBusy = false;
    if (best != null) {
      final from = game.cellOfIndex(Mv.from(best));
      final to = game.cellOfIndex(Mv.to(best));
      final piece = game.pieceAt(from);
      _hint = (from, to);
      _selected = from;
      _targets = game.legalMoves(from);
      _message =
          'İpucu: ${piece?.kind.creature ?? 'Savaşçı'}  ${game.shape.name(from)} → ${game.shape.name(to)}';
      _refreshHighlights();
    }
    setState(() {});
  }

  void _undoTurn() {
    if (!_ready || !game.canUndo || _mode == GameMode.aiVsAi) return;
    _generation++;
    _anim.clear();
    _fx.clear();
    _exitPovImmediate();
    _busy = false;
    _thinking = false;
    _hintBusy = false;
    _selected = null;
    _targets = [];
    _hint = null;
    _battleText = '';

    if (_mode == GameMode.humanVsAi) {
      game.undoSingle();
      while (game.turn != _humanTeam && game.canUndo) {
        game.undoSingle();
      }
    } else {
      game.undoSingle();
    }

    if (_currentMatchId > 0) {
      unawaited(GameDatabase.instance.recordUndo(
        matchId: _currentMatchId,
        newPlyCount: game.ply,
        remainingEncodedMoves: game.exportEncodedMoves(),
      ));
    }

    _rebuildAllRigsFromBoard();
    _refreshHighlights();
    _message = 'Hamle geri alındı. Sıra ${game.turn.title} orduda.';
    setState(() {});
    _maybeAi();
  }

  void _cycleCamera() {
    if (_inPovSequence) return;
    final presets = game.isThreePlayer
        ? const [CamPreset.white, CamPreset.black, CamPreset.emerald, CamPreset.top]
        : const [CamPreset.white, CamPreset.black, CamPreset.top];
    final idx = presets.indexOf(_camPreset);
    final next = presets[(idx + 1) % presets.length];
    _animateCameraToPreset(next);
  }

  void _togglePanMode() {
    if (_inPovSequence) return;
    setState(() {
      _panBoardMode = !_panBoardMode;
      _syncOrbitInteraction();
      _message = _panBoardMode
          ? 'Tahta Taşıma Modu AÇIK: Sürükleyerek tahtayı kaydır, dokunarak hamle yap.'
          : 'Kamera Döndürme Modu AÇIK: Sürükleyerek açıyı değiştir.';
    });
  }

  Future<void> _dissolveEliminatedArmies(MoveRecord rec) async {
    if (rec.eliminatedCells.isEmpty) return;
    final doomed = <CreatureRig>[];
    for (final cell in rec.eliminatedCells) {
      final r = _rigs.remove(cell);
      if (r != null) {
        r.busy = true;
        doomed.add(r);
        final p = _posOf(r);
        final pal = Palette.of(r.team);
        _fx.pillar(p, pal.glow, life: 0.85, height: 2.6);
        _fx.burst(p + const P3(0, 0.5, 0), [pal.glow, 0xFFFFFF],
            count: 14, speed: 1.8, size: 0.042);
      }
    }
    if (doomed.isEmpty) return;
    final names = rec.eliminatedTeams.map((t) => '${t.legion} (${t.title})').join(', ');
    _battleText = '⚔ $names Ordusu Düştü! Kalan ordular savaşa devam ediyor!';
    if (mounted) setState(() {});
    await _anim.play(
      0.46,
      (t) {
        final s = math.max(0.001, 1.0 - easeIn(t));
        for (final r in doomed) {
          r.body.scale.setValues(
            r.baseScale * s,
            r.baseScale * s,
            r.baseScale * s,
          );
          r.body.position.y = 0.35 * t;
        }
      },
      kind: AnimKind.combat,
    );
    for (final r in doomed) {
      _pieceLayer.remove(r.root);
    }
  }

  Future<void> _runMove(MoveRecord rec, int gen, {required bool humanMove}) async {
    _busy = true;
    _selected = null;
    _targets = [];
    _refreshHighlights();
    final name = rec.piece.kind.creature;
    final side = rec.piece.team.title;
    _message = '$side $name: ${game.shape.name(rec.from)} → ${game.shape.name(rec.to)}';
    _battleText = rec.captured == null ? '' : _battleLine(rec.piece.kind, rec.captured!.kind);
    setState(() {});

    // POV Modu açıksa her hamlede (insan veya YZ) hamle yapan taşın gözüne geçilir
    final usePov = _povEnabled;
    if (_currentMatchId > 0) {
      final isHumanCap = humanMove && rec.captured != null;
      unawaited(GameDatabase.instance.recordMove(
        matchId: _currentMatchId,
        ply: game.ply - 1,
        record: rec,
        allEncodedMoves: game.exportEncodedMoves(),
        humanCapture: isHumanCap,
        shape: game.shape,
      ));
    }
    await _animateMove(rec, gen, usePov: usePov);
    if (gen != _generation || !mounted) return;

    if (rec.eliminatedCells.isNotEmpty) {
      await _dissolveEliminatedArmies(rec);
      if (gen != _generation || !mounted) return;
    }

    // Ses kaydı (replik) tamamen bitmeden diğer karakterlerin taşları sırasını salamaz (_busy koruması)
    while (_audio.isVoicePlaying && gen == _generation && mounted) {
      await _anim.wait(0.06, kind: AnimKind.fixed);
    }

    _busy = false;
    await _afterMove(rec, gen);
  }

  String _battleLine(PieceType a, PieceType v) {
    final verb = switch (a) {
      PieceType.pawn => 'çelik teberiyle devirdi',
      PieceType.knight => 'gölgelerden çıkıp ikiz bıçakla biçti',
      PieceType.bishop => 'ejder ateşiyle kül etti',
      PieceType.rook => 'dev savaş balyozuyla yerle bir etti',
      PieceType.queen => 'yaşam özünü son damlasına dek çekti',
      PieceType.king => 'hilal baltasıyla savurup parçaladı',
    };
    return '⚔ ${a.creature}, ${v.creature} savaşçısını $verb!';
  }

  Future<void> _afterMove(MoveRecord rec, int gen) async {
    _refreshHighlights();
    if (game.status != GameStatus.playing) {
      _message = game.statusText;
      if (_currentMatchId > 0) {
        final statusStr = switch (game.status) {
          GameStatus.checkmate => 'checkmate',
          GameStatus.stalemate => 'stalemate',
          _ => 'draw',
        };
        final winner = game.isThreePlayer
            ? (game.pos3.soleSurvivor != null
                ? Team.values[game.pos3.soleSurvivor!]
                : null)
            : (game.turn == Team.white ? Team.black : Team.white);
        final isRated = _mode == GameMode.humanVsAi;
        final elapsedSec = ((DateTime.now().millisecondsSinceEpoch -
                    _matchStartTimestamp) /
                1000)
            .round();
        final oppElo = _level.targetElo;
        final mId = _currentMatchId;
        _currentMatchId = -1;
        GameDatabase.instance
            .finishMatch(
          matchId: mId,
          variant: game.variant,
          finalStatus: statusStr,
          winnerTeam: winner,
          humanTeam: _humanTeam,
          ratedHumanMatch: isRated,
          opponentElo: oppElo,
          elapsedSeconds: elapsedSec,
        )
            .then((p) {
          if (mounted) setState(() => _profile = p);
        });
      }
      setState(() {});
      if (game.status == GameStatus.checkmate) await _checkmateFinale(gen);
      return;
    }
    if (rec.check) {
      _message = 'ŞAH! ${game.turn.title} Barbar Kral tehdit altında!';
    } else if (_isHumanTurn) {
      _message = 'Sıra ${game.turn.title} orduda. Bir savaşçı seç.';
    }
    setState(() {});
    _maybeAi();
  }

  void _restart() {
    if (!_ready) return;
    _generation++;
    _anim.clear();
    _fx.clear();
    _exitPovImmediate();
    game.reset();
    _busy = false;
    _thinking = false;
    _hintBusy = false;
    _selected = null;
    _targets = [];
    _hint = null;
    _battleText = '';
    _message = 'Yeni savaş başladı. Beyaz ordu başlar.';
    _rebuildAllRigsFromBoard();
    _refreshHighlights();
    unawaited(_startNewMatchSession(game.variant));
    setState(() {});
    _maybeAi();
  }

  // ================================================================ POV GEÇİŞİ + 1 SANİYE BEKLEME + HAREKET
  double _yaw(P3 dir) => math.atan2(dir.x, dir.z);

  Future<void> _turnTo(
    CreatureRig r,
    double target, [
    double dur = 0.22,
    AnimKind kind = AnimKind.move,
  ]) {
    final start = r.root.rotation.y.toDouble();
    var delta = (target - start) % (math.pi * 2);
    if (delta > math.pi) delta -= math.pi * 2;
    if (delta.abs() < 0.01) return Future.value();
    return _anim.play(
      dur,
      (t) {
        r.root.rotation.y = start + delta * smooth(t);
        r.facing = r.root.rotation.y.toDouble();
      },
      kind: kind,
    );
  }

  Future<void> _blendToRest(
    CreatureRig r, [
    double dur = 0.26,
    AnimKind kind = AnimKind.move,
  ]) {
    final names = r.parts.keys.where((n) => r.rest.containsKey('$n.rx')).toList();
    final from = {
      for (final n in names)
        n: [
          r.parts[n]!.rotation.x.toDouble(),
          r.parts[n]!.rotation.y.toDouble(),
          r.parts[n]!.rotation.z.toDouble(),
          r.parts[n]!.position.x.toDouble(),
          r.parts[n]!.position.y.toDouble(),
          r.parts[n]!.position.z.toDouble(),
        ],
    };
    final b = r.body;
    final bp = [
      b.position.x.toDouble(),
      b.position.y.toDouble(),
      b.position.z.toDouble(),
      b.rotation.x.toDouble(),
      b.rotation.y.toDouble(),
      b.rotation.z.toDouble(),
      b.scale.x.toDouble(),
      b.scale.y.toDouble(),
      b.scale.z.toDouble(),
    ];
    return _anim.play(
      dur,
      (t) {
        final k = smooth(t);
        double l(double a, double z) => a + (z - a) * k;
        for (final n in names) {
          final p = r.parts[n]!, f = from[n]!;
          p.rotation.x = l(f[0], _rest(r, n, 'rx'));
          p.rotation.y = l(f[1], _rest(r, n, 'ry'));
          p.rotation.z = l(f[2], _rest(r, n, 'rz'));
          p.position.setValues(
            l(f[3], _rest(r, n, 'x')),
            l(f[4], _rest(r, n, 'y')),
            l(f[5], _rest(r, n, 'z')),
          );
        }
        b.position.setValues(l(bp[0], 0), l(bp[1], 0), l(bp[2], 0));
        b.rotation.x = l(bp[3], 0);
        b.rotation.y = l(bp[4], 0);
        b.rotation.z = l(bp[5], 0);
        b.scale.setValues(
          l(bp[6], r.baseScale),
          l(bp[7], r.baseScale),
          l(bp[8], r.baseScale),
        );
      },
      kind: kind,
    );
  }

  Future<void> _enterPovAndReadyPause(
    CreatureRig mover,
    P3 fromPos,
    P3 targetPos,
    bool isAttack,
  ) async {
    final cam = _engine.camera;
    if (cam is! three.PerspectiveCamera) return;

    _inPovSequence = true;
    _povWho = '${mover.team.title} ${mover.kind.creature}';
    _povLookYaw = 0.0;
    _povLookPitch = 0.0;
    _povRoll = 0.0;
    _povReadyExtraPitch = -0.10;
    _povFocusWorld = targetPos + P3(0, isAttack ? 0.56 : 0.16, 0);
    _povFocusWeight = isAttack ? 0.65 : 0.35;
    _syncOrbitInteraction();

    final dir = (targetPos - fromPos).flatNormal;
    await _turnTo(mover, _yaw(dir), 0.22, AnimKind.fixed);
    if (!_inPovSequence) return;

    final startCamPos = P3.of(cam.position);
    final startLook = _orbit != null ? P3.of(_orbit!.target) : targetPos;
    final startFov = cam.fov.toDouble();
    final aspect = (_engine.width / math.max(1.0, _engine.height)).clamp(0.42, 2.6);
    final povFov = aspect < 0.85 ? 84.0 : 76.0;

    // 1) Tahta kamerasından karakterin gözüne pürüzsüz sinematik dalış (kafa içine girmeden gizler)
    await _anim.play(
      0.42,
      (t) {
        if (!_inPovSequence) return;
        final k = smooth(t);
        if (t >= 0.66 && !mover.inPov) {
          mover.setFirstPersonMode(true);
          cam.near = _povNear;
        }
        final (goalEye, goalLook, _) = _computePovCameraPose(mover);
        final p = P3.lerp(startCamPos, goalEye, k);
        final lk = P3.lerp(startLook, goalLook, k);
        cam.fov = startFov + (povFov - startFov) * k;
        cam.updateProjectionMatrix();
        cam.up.setValues(0, 1, 0);
        cam.position.setValues(p.x, p.y, p.z);
        cam.lookAt(three.Vector3(lk.x, lk.y, lk.z));
      },
      kind: AnimKind.fixed,
    );
    if (!_inPovSequence) return;

    mover.setFirstPersonMode(true);
    cam.near = _povNear;
    cam.fov = povFov;
    cam.updateProjectionMatrix();
    _povRig = mover;

    // 2) Harekete geçmeden TAM 1.0 SANİYE BEKLEME + Savaş Narası + Sınıfa Özel FPS Silah/Bacak Selamı!
    _triggerVoice(
      mover.kind,
      isAttack ? VoiceEvent.attack : VoiceEvent.march,
      mover.team,
    );

    if (mounted) {
      setState(() => _povCountdown = 1.0);
    }

    await _anim.play(
      1.0,
      (t) {
        if (!_inPovSequence) return;
        final pulse = math.sin(t * math.pi);
        // İlk yarım saniye hafif aşağı (çizme + silah selamı), ikinci yarım saniye hedefe odak!
        _povReadyExtraPitch = -0.12 * math.sin(math.min(1.0, t * 1.25) * math.pi);
        _povRoll = 0.016 * math.sin(t * math.pi * 2);
        mover.body.position.y = pulse * 0.020;

        switch (mover.kind) {
          case PieceType.pawn:
            // Kalkan kenarına teber vurup cepheye adım hazırlığı
            _idleOffset(mover, 'armL', y: 0.24 * pulse, x: -0.10 * pulse);
            _idleOffset(mover, 'armR', x: 0.14 * pulse, z: 0.18 * pulse);
            _idleOffset(mover, 'legL', x: -0.58 * pulse);
            _idleOffset(mover, 'legR', x: 0.22 * pulse);
          case PieceType.knight:
            // İkiz Şam kukrisini göz önünde çapraz bileme duruşu
            _idleOffset(mover, 'armL', y: 0.34 * pulse, x: -0.18 * pulse, z: 0.16 * pulse);
            _idleOffset(mover, 'armR', y: -0.34 * pulse, x: -0.18 * pulse, z: -0.16 * pulse);
            _idleOffset(mover, 'legL', x: -0.52 * pulse);
          case PieceType.bishop:
            // Devasa kanatları iki yana açıp jilet pençeleri germe
            _idleOffset(mover, 'wingL', z: 0.42 * pulse);
            _idleOffset(mover, 'wingR', z: -0.42 * pulse);
            _idleOffset(mover, 'armL', x: -0.26 * pulse);
            _idleOffset(mover, 'armR', x: -0.26 * pulse);
            _idleOffset(mover, 'legL', x: -0.34 * pulse);
          case PieceType.rook:
            // Kadın Savaş Devi: altın kuşaklı savaş balyozunu önde tartıp çizmesini yere vurma
            _idleOffset(mover, 'armR', x: 0.18 * pulse, z: 0.14 * pulse);
            _idleOffset(mover, 'armL', y: 0.22 * pulse, x: -0.14 * pulse);
            _idleOffset(mover, 'legL', x: -0.62 * pulse);
            _idleOffset(mover, 'legR', x: 0.24 * pulse);
          case PieceType.queen:
            // Kızıl pençeli elde Kan Küresini parlatıp yakut asayı kaldırma
            _idleOffset(mover, 'armL', x: -0.24 * pulse, y: 0.15 * pulse);
            _idleOffset(mover, 'armR', x: 0.12 * pulse, z: 0.12 * pulse);
            _idleOffset(mover, 'legL', x: -0.48 * pulse);
            final orb = mover.parts['orb'];
            final os = 0.044 * (1.0 + 0.42 * pulse);
            orb?.scale.setValues(os, os, os);
          case PieceType.king:
            // Barbar Kral: fildişi savaş borusunu kaldırıp hilal baltayı tartma
            _idleOffset(mover, 'armL', x: -0.38 * pulse, y: 0.22 * pulse);
            _idleOffset(mover, 'armR', x: 0.16 * pulse, z: 0.14 * pulse);
            _idleOffset(mover, 'legL', x: -0.58 * pulse);
        }

        final rem = (1.0 - t).clamp(0.0, 1.0);
        if ((rem - _povCountdown).abs() > 0.08 && mounted) {
          setState(() => _povCountdown = rem);
        }
      },
      kind: AnimKind.fixed,
    );

    _povReadyExtraPitch = 0.0;
    _povRoll = 0.0;
    if (!isAttack) {
      _povFocusWeight = 0.0;
    }
    if (mounted) {
      setState(() => _povCountdown = 0.0);
    }
  }

  Future<void> _exitPovSmoothly(
    CreatureRig mover,
    P3 savedCamPos,
    P3 savedTarget,
    double savedFov,
  ) async {
    if (!_inPovSequence) return;
    final cam = _engine.camera;
    if (cam is! three.PerspectiveCamera) {
      _exitPovImmediate();
      return;
    }

    // Hedef kareye vardıktan sonra kısa sinematik nefes payı
    await _anim.wait(0.32, kind: AnimKind.fixed);
    if (!_inPovSequence) return;

    final (startEye, startLook, _) = _computePovCameraPose(mover);
    _povRig = null;
    _povRoll = 0.0;
    cam.up.setValues(0, 1, 0);
    final startFov = cam.fov.toDouble();

    await _anim.play(
      0.44,
      (t) {
        if (!_inPovSequence) return;
        final k = smooth(t);
        // Kafa ve saçları kamera karakterin arkasına çıktıktan SONRA aç (00:57 saç içi görünme hatasını sıfırlar!)
        if (t >= 0.34 && mover.inPov) {
          mover.setFirstPersonMode(false);
          cam.near = 0.15;
        }
        final p = P3.lerp(startEye, savedCamPos, k);
        final lk = P3.lerp(startLook, savedTarget, k);
        cam.fov = startFov + (savedFov - startFov) * k;
        cam.updateProjectionMatrix();
        cam.position.setValues(p.x, p.y, p.z);
        cam.lookAt(three.Vector3(lk.x, lk.y, lk.z));
      },
      kind: AnimKind.fixed,
    );

    if (mover.inPov) mover.setFirstPersonMode(false);
    cam.up.setValues(0, 1, 0);
    cam.near = 0.15;
    cam.fov = savedFov;
    cam.updateProjectionMatrix();
    _orbit?.target.setValues(savedTarget.x, savedTarget.y, savedTarget.z);
    cam.position.setValues(savedCamPos.x, savedCamPos.y, savedCamPos.z);
    cam.lookAt(three.Vector3(savedTarget.x, savedTarget.y, savedTarget.z));
    _inPovSequence = false;
    _povLookYaw = 0.0;
    _povLookPitch = 0.0;
    _povFocusWorld = null;
    _povFocusWeight = 0.0;
    _povSavedCamPos = null;
    _povSavedTarget = null;
    _syncOrbitInteraction();
    _orbit?.update();
    if (mounted) setState(() {});
  }

  Future<void> _animateMove(MoveRecord rec, int gen, {required bool usePov}) async {
    final mover = _rigs.remove(rec.from)!;
    final victim = rec.capturedAt == null ? null : _rigs.remove(rec.capturedAt!);
    _rigs[rec.to] = mover;
    mover.busy = true;

    final cam = _engine.camera;
    final savedCamPos = P3.of(cam.position);
    final savedTarget = _orbit != null ? P3.of(_orbit!.target) : const P3(0, 0, 0);
    final savedFov = cam is three.PerspectiveCamera ? cam.fov.toDouble() : 50.0;
    _povSavedCamPos = savedCamPos;
    _povSavedTarget = savedTarget;
    _povSavedFov = savedFov;

    try {
      if (usePov) {
        final aimPos = victim != null ? _cellPos(rec.capturedAt!) : _cellPos(rec.to);
        await _enterPovAndReadyPause(mover, _cellPos(rec.from), aimPos, victim != null);
        if (gen != _generation) return;
      } else {
        _triggerVoice(
          mover.kind,
          victim != null ? VoiceEvent.attack : VoiceEvent.march,
          mover.team,
        );
      }

      if (victim == null) {
        await _travel(mover, _cellPos(rec.from), _cellPos(rec.to), alreadyTurned: _inPovSequence);
      } else {
        await _battle(mover, victim, rec, inPov: _inPovSequence);
      }
      if (gen != _generation) return;

      // mp3 bitmeden povdan çıkmak yok! Karakterin repliği tamamen bitene kadar birinci şahıs kamerasında kal
      if (_inPovSequence) {
        var waitClock = 0.0;
        while (_audio.isVoicePlaying && gen == _generation && _inPovSequence) {
          await _anim.play(0.06, (t) {
            waitClock += 0.06;
            _povReadyExtraPitch = math.sin(waitClock * 2.8) * 0.015;
            _povRoll = math.sin(waitClock * 1.5) * 0.006;
          }, kind: AnimKind.fixed);
        }
        _povReadyExtraPitch = 0.0;
        _povRoll = 0.0;
      }

      if (rec.promoted) {
        if (_inPovSequence) {
          await _exitPovSmoothly(mover, savedCamPos, savedTarget, savedFov);
        }
        await _promote(rec.to, rec.piece.team, rec.promotedTo ?? PieceType.queen);
      } else {
        final restFace = mover.defaultFacingFor(game.variant);
        if (_inPovSequence) {
          await _blendToRest(mover, 0.18, AnimKind.fixed);
          await _exitPovSmoothly(mover, savedCamPos, savedTarget, savedFov);
          await _turnTo(mover, restFace, 0.24, AnimKind.move);
          await _blendToRest(mover, 0.16, AnimKind.move);
        } else {
          await _turnTo(mover, restFace, 0.24, AnimKind.move);
          await _blendToRest(mover, 0.18, AnimKind.move);
        }
        mover.busy = false;
      }
    } finally {
      if (_inPovSequence) {
        _exitPovImmediate();
      }
    }
  }

  // ================================================================ 6 KARAKTERE ÖZEL YÜRÜYÜŞ ANİMASYONLARI
  Future<void> _travel(
    CreatureRig r,
    P3 a,
    P3 b, {
    bool alreadyTurned = false,
  }) async {
    final d = (b - a).flatLength;
    if (d < 0.02) return;
    if (!alreadyTurned) {
      await _turnTo(r, _yaw(b - a), 0.22, AnimKind.move);
    }
    switch (r.kind) {
      case PieceType.pawn:
        await _walkVanguard(r, a, b);
      case PieceType.knight:
        await _walkAssassin(r, a, b);
      case PieceType.bishop:
        await _walkDragon(r, a, b);
      case PieceType.rook:
        await _walkGiantess(r, a, b);
      case PieceType.queen:
        await _walkVampire(r, a, b);
      case PieceType.king:
        await _walkBarbarian(r, a, b);
    }
    _place(r, b);
  }

  double _peakColumnAlong(P3 a, P3 b) {
    var peak = math.max(a.y, b.y);
    for (var i = 1; i <= 6; i++) {
      final u = i / 7.0;
      final g = _groundAt(a.x + (b.x - a.x) * u, a.z + (b.z - a.z) * u);
      if (g > peak) peak = g;
    }
    return peak;
  }

  /// 1. Kalkan Muhafızı: Kalkan siperde amfi basamaklarını tırmanan disiplinli şövalye yürüyüşü.
  Future<void> _walkVanguard(CreatureRig r, P3 a, P3 b) async {
    final d = (b - a).flatLength;
    final steps = math.max(3, (d / 0.34).round());
    var prevStep = -1;
    await _anim.play(
      0.55 + d * 0.38,
      (t) {
        _place(r, _stepPathPos(a, b, smooth(t)));
        final phase = t * steps;
        final stepIdx = phase.floor();
        if (stepIdx != prevStep && t < 0.96) {
          prevStep = stepIdx;
          _playSfx(SfxKind.stepArmor);
        }
        final s = math.sin(phase * math.pi);
        r.body.position.y = s.abs() * 0.052;
        if (r.inPov) {
          _povRoll = s * 0.016;
          _idleOffset(r, 'legL', x: s * 0.78);
          _idleOffset(r, 'legR', x: -s * 0.78);
          // POV'da kalkan sağ kenarda açık kalır (önü asla kapatmaz!), sol elde teber ileri salınır
          _idleOffset(r, 'armL', x: s * 0.08);
          _idleOffset(r, 'armR', x: -s * 0.16, z: 0.04);
          _idleOffset(r, 'torso', y: s * 0.05, x: 0.03);
        } else {
          _idleOffset(r, 'legL', x: s * 0.62);
          _idleOffset(r, 'legR', x: -s * 0.62);
          _idleOffset(r, 'armL', x: -0.22 + s * 0.12, y: -0.14);
          _idleOffset(r, 'armR', x: -0.18 - s * 0.34);
          _idleOffset(r, 'torso', y: s * 0.08, x: 0.06);
        }
      },
      kind: AnimKind.move,
    );
    _povRoll = 0.0;
    r.body.position.y = 0;
    _idleOffset(r, 'legL');
    _idleOffset(r, 'legR');
  }

  /// 2. Suikastçi: Kısa yaylanma + tüm amfi sütunlarının ve taşların üzerinden aşan yüksek sıçrayış!
  Future<void> _walkAssassin(CreatureRig r, P3 a, P3 b) async {
    final pal = Palette.of(r.team);
    final d = (b - a).flatLength;
    final stalkEnd = _stepPathPos(a, b, 0.10);

    // Aşama 1: Çevik yaylanma ve ikiz kukri hazırlığı
    _playSfx(SfxKind.stepStealth);
    await _anim.play(
      0.24,
      (t) {
        _place(r, P3.lerp(a, stalkEnd, easeOut(t)));
        final crouch = math.sin(t * math.pi * 0.5);
        r.body.position.y = -0.05 * crouch;
        _idleOffset(r, 'torso', x: r.inPov ? 0.06 * crouch : 0.22 * crouch);
        _idleOffset(r, 'legL', x: -0.45 * crouch);
        _idleOffset(r, 'legR', x: 0.35 * crouch);
        _idleOffset(r, 'armL', x: -0.25 * crouch, y: 0.22 * crouch);
        _idleOffset(r, 'armR', x: -0.25 * crouch, y: -0.22 * crouch);
      },
      kind: AnimKind.move,
    );

    // Aşama 2: Gölge dumanı içinde yüksek kavisli sıçrayış (yüksek amfi sütunlarını da rahatça aşar!)
    _fx.smoke(stalkEnd, 0x1A1824, count: 12, radius: 0.36);
    _playSfx(SfxKind.slashBlade);
    final peakCol = _peakColumnAlong(stalkEnd, b);
    final midBaseY = (stalkEnd.y + b.y) * 0.5;
    final jumpLift = 1.28 + d * 0.08 + math.max(0.0, peakCol - midBaseY);
    await _anim.play(
      0.56 + d * 0.14,
      (t) {
        final p = P3.lerp(stalkEnd, b, smooth(t));
        _place(r, p);
        final air = math.pow(math.sin(math.pi * t), 0.68).toDouble();
        r.body.position.y = air * jumpLift;
        if (r.inPov) {
          _povFocusWorld = b + const P3(0, 0.24, 0);
          _povFocusWeight = 0.72 * air;
          _povRoll = math.sin(t * math.pi * 2) * 0.022;
          _idleOffset(r, 'legL', x: -0.72 * air);
          _idleOffset(r, 'legR', x: 0.36 * air);
          _idleOffset(r, 'armL', x: -0.28 * air, y: 0.18 * air, z: 0.12 * air);
          _idleOffset(r, 'armR', x: -0.28 * air, y: -0.18 * air, z: -0.12 * air);
        } else {
          r.body.rotation.y = smooth(t) * math.pi * 2;
          _idleOffset(r, 'legL', x: -0.58 * air);
          _idleOffset(r, 'legR', x: 0.42 * air);
          _idleOffset(r, 'armL', x: -0.65 * air, z: -0.35 * air);
          _idleOffset(r, 'armR', x: -0.65 * air, z: 0.35 * air);
        }
        if (_fx.rng.nextDouble() < 0.65) {
          _fx.spawn(
            p + P3(_fx.r(0.16), 0.35 + air * 0.45, _fx.r(0.16)),
            color: pal.glow,
            life: 0.32,
            size: 0.04,
            endSize: 0,
          );
        }
      },
      kind: AnimKind.move,
    );
    if (r.inPov) {
      _povFocusWeight = 0.0;
      _povRoll = 0.0;
    }
    r.body.rotation.y = 0;
    r.body.position.y = 0;
    _fx.smoke(b, 0x1A1824, count: 10, radius: 0.34);
    _playSfx(SfxKind.stepStealth);
  }

  /// 3. Ejderha: Dik kanat kalkışı ile tüm amfi sütunlarının üzerinden süzülerek uçuş ve hedefe iniş!
  Future<void> _walkDragon(CreatureRig r, P3 a, P3 b) async {
    final d = (b - a).flatLength;
    final dur = 0.88 + d * 0.24;
    final peakCol = _peakColumnAlong(a, b);
    final midBaseY = (a.y + b.y) * 0.5;
    final lift = 1.38 + d * 0.09 + math.max(0.0, peakCol - midBaseY);
    var prevFlap = -1;
    await _anim.play(
      dur,
      (t) {
        _place(r, P3.lerp(a, b, smooth(t)));
        final air = math.pow(math.sin(math.pi * t), 0.58).toDouble();
        r.body.position.y = air * lift;
        final flapCycles = dur * 2.8;
        final flapIdx = (t * flapCycles).floor();
        if (flapIdx != prevFlap && t < 0.92) {
          prevFlap = flapIdx;
          _playSfx(SfxKind.wingFlap);
        }
        final flap = math.sin(t * flapCycles * math.pi * 2) * 0.72;
        if (r.inPov) {
          _povFocusWorld = b + const P3(0, 0.28, 0);
          _povFocusWeight = 0.78 * air;
          _povRoll = math.sin(t * flapCycles * math.pi * 2) * 0.018;
        }
        _idleOffset(r, 'wingL', z: 0.26 + flap);
        _idleOffset(r, 'wingR', z: -0.26 - flap);
        _idleOffset(r, 'armL', x: -0.28 * air);
        _idleOffset(r, 'armR', x: -0.28 * air);
        _idleOffset(r, 'legL', x: -0.35 * air);
        _idleOffset(r, 'legR', x: -0.35 * air);
        _idleOffset(r, 'torso', x: (r.inPov ? -0.06 : -0.16) * air);
        _idleOffset(r, 'tail', x: 0.28 * air, y: math.sin(t * 10) * 0.18);
      },
      kind: AnimKind.move,
    );
    if (r.inPov) {
      _povFocusWeight = 0.0;
      _povRoll = 0.0;
    }
    _fx.smoke(b, 0x8D8478, count: 8, radius: 0.46, life: 0.5);
    _playSfx(SfxKind.stepStomp);
    r.body.position.y = 0;
  }

  /// 4. Kadın Savaş Devi (Valkür Titan): Amfi sütunlarını titreten 2 kat devasa adımlar!
  Future<void> _walkGiantess(CreatureRig r, P3 a, P3 b) async {
    final d = (b - a).flatLength;
    final steps = math.max(3, (d / 0.82).ceil());
    var lastStep = -1;
    await _anim.play(
      0.68 + d * 0.42,
      (t) {
        final f = t * steps;
        final idx = math.min(steps - 1, f.floor());
        final local = f - idx;
        if (idx != lastStep) {
          lastStep = idx;
          final p = _posOf(r);
          _fx.addShake(r.inPov ? 0.055 : 0.095);
          _fx.smoke(p, 0x8D8478, count: 9, radius: 0.65, life: 0.65);
          _playSfx(SfxKind.stepStomp);
        }
        _place(r, _stepPathPos(a, b, (idx + smooth(local)) / steps));
        final swing = math.sin(f * math.pi);
        r.body.position.y = math.sin(local * math.pi) * 0.13;
        final sway = math.sin(local * math.pi) * (idx.isEven ? 1.0 : -1.0);
        if (r.inPov) {
          _povRoll = sway * 0.024;
          _idleOffset(r, 'legL', x: swing * 0.78);
          _idleOffset(r, 'legR', x: -swing * 0.78);
          _idleOffset(r, 'armR', x: -swing * 0.16, z: 0.04);
          _idleOffset(r, 'armL', x: swing * 0.16);
          _idleOffset(r, 'torso', y: swing * 0.06, x: 0.03);
        } else {
          r.body.rotation.z = sway * 0.042;
          _idleOffset(r, 'legL', x: swing * 0.58);
          _idleOffset(r, 'legR', x: -swing * 0.58);
          _idleOffset(r, 'armR', x: -0.18 - swing * 0.30, z: -0.06);
          _idleOffset(r, 'armL', x: -0.14 + swing * 0.28);
          _idleOffset(r, 'torso', y: swing * 0.11, x: 0.04);
        }
      },
      kind: AnimKind.move,
    );
    _povRoll = 0.0;
    r.body.position.y = 0;
    r.body.rotation.z = 0;
    _idleOffset(r, 'legL');
    _idleOffset(r, 'legR');
  }

  /// 5. Vampir Kraliçe: Amfi sütunları üzerinde kızıl sisle süzülen aristokrat yürüyüşü.
  Future<void> _walkVampire(CreatureRig r, P3 a, P3 b) async {
    final d = (b - a).flatLength;
    final pal = Palette.of(r.team);
    final steps = math.max(3, (d / 0.45).round());
    var prevPulse = -1;
    await _anim.play(
      0.72 + d * 0.32,
      (t) {
        final p = _stepPathPos(a, b, smooth(t));
        _place(r, p);
        final pulseIdx = (t * 3).floor();
        if (pulseIdx != prevPulse) {
          prevPulse = pulseIdx;
          _playSfx(SfxKind.magicGlide);
        }
        final lift = math.sin(math.pi * t);
        final stride = math.sin(t * steps * math.pi);
        r.body.position.y = lift * 0.20;
        if (r.inPov) {
          _povRoll = stride * 0.014;
          _idleOffset(r, 'legL', x: stride * 0.68);
          _idleOffset(r, 'legR', x: -stride * 0.68);
          _idleOffset(r, 'armL', x: -0.14 * lift, y: 0.10 * stride);
          _idleOffset(r, 'armR', x: stride * 0.12);
          _idleOffset(r, 'torso', y: stride * 0.04);
        } else {
          _idleOffset(r, 'legL', x: stride * 0.42);
          _idleOffset(r, 'legR', x: -stride * 0.42);
          _idleOffset(r, 'armL', x: -0.35 - 0.15 * lift, z: 0.16);
          _idleOffset(r, 'armR', x: -0.22 + stride * 0.16);
          _idleOffset(r, 'torso', y: stride * 0.06);
          _idleOffset(r, 'cape', x: -0.48 * lift);
        }
        if (_fx.rng.nextDouble() < 0.58) {
          _fx.spawn(
            p + P3(_fx.r(0.22), 0.18 + _fx.rng.nextDouble() * 0.52, _fx.r(0.22)),
            color: pal.blood,
            life: 0.52,
            size: 0.034,
            velocity: const P3(0, 0.26, 0),
          );
        }
      },
      kind: AnimKind.move,
    );
    _povRoll = 0.0;
    r.body.position.y = 0;
    _idleOffset(r, 'legL');
    _idleOffset(r, 'legR');
  }

  /// 6. Barbar Kral: Amfi sütunlarında savaş borusu ve hilal baltayla heybetli hükümdar yürüyüşü.
  Future<void> _walkBarbarian(CreatureRig r, P3 a, P3 b) async {
    final d = (b - a).flatLength;
    final steps = math.max(3, (d / 0.40).round());
    var prevStep = -1;
    await _anim.play(
      0.66 + d * 0.40,
      (t) {
        _place(r, _stepPathPos(a, b, smooth(t)));
        final phase = t * steps;
        final stepIdx = phase.floor();
        if (stepIdx != prevStep && t < 0.96) {
          prevStep = stepIdx;
          _playSfx(SfxKind.stepArmor);
        }
        final s = math.sin(phase * math.pi);
        r.body.position.y = s.abs() * 0.056;
        if (r.inPov) {
          _povRoll = s * 0.020;
          _idleOffset(r, 'legL', x: s * 0.78);
          _idleOffset(r, 'legR', x: -s * 0.78);
          _idleOffset(r, 'armR', x: -s * 0.18, z: 0.04);
          _idleOffset(r, 'armL', x: s * 0.14);
          _idleOffset(r, 'torso', y: s * 0.06, x: 0.03);
        } else {
          r.body.rotation.z = s * 0.032;
          _idleOffset(r, 'legL', x: s * 0.60);
          _idleOffset(r, 'legR', x: -s * 0.60);
          _idleOffset(r, 'armR', x: -0.22 - s * 0.36);
          _idleOffset(r, 'armL', x: -0.20 + s * 0.28);
          _idleOffset(r, 'torso', y: s * 0.11, x: 0.05);
          _idleOffset(r, 'cape', x: -0.24 - s.abs() * 0.16);
        }
      },
      kind: AnimKind.move,
    );
    _povRoll = 0.0;
    r.body.position.y = 0;
    r.body.rotation.z = 0;
    _idleOffset(r, 'legL');
    _idleOffset(r, 'legR');
  }

  // ================================================================ UZATILMIŞ ÇOK AŞAMALI SİNEMATİK DÖVÜŞ!
  Future<void> _battle(
    CreatureRig a,
    CreatureRig v,
    MoveRecord rec, {
    required bool inPov,
  }) async {
    final ap = _cellPos(rec.from);
    final vp = _cellPos(rec.capturedAt!);
    final dest = _cellPos(rec.to);
    final dir = (vp - ap).flatNormal;
    final dist = (vp - ap).flatLength;
    v.busy = true;

    await Future.wait([
      if (!inPov) _turnTo(a, _yaw(dir), 0.20, AnimKind.move),
      _turnTo(v, _yaw(dir * -1), 0.22, AnimKind.move),
    ]);

    // Savunan savaşçı boş durmak yerine silahını/kalkanını savunma gardına kaldırır!
    unawaited(_braceDefender(v));

    P3 grounded(P3 p) => P3(p.x, _groundAt(p.x, p.z), p.z);

    // POV modunda düşmanın baştan ayağa ekranın tam ortasında görünmesi için ideal düello mesafesi!
    late P3 stand;
    switch (a.kind) {
      case PieceType.knight:
        stand = grounded(inPov ? vp - dir * 0.96 : vp + dir * 0.62);
        await _walkAssassin(a, ap, stand);
        _place(a, stand);
        if (!inPov) {
          await _turnTo(a, _yaw(dir * -1), 0.14, AnimKind.combat);
          await _turnTo(v, _yaw(dir), 0.16, AnimKind.combat);
        }
      case PieceType.bishop:
        final want = inPov ? 1.62 : 1.55;
        stand = grounded(dist > want + 0.12
            ? vp - dir * want
            : (inPov && dist < 1.15 ? vp - dir * 1.22 : ap));
        if ((stand - ap).flatLength > 0.03) {
          await _walkDragon(a, ap, stand);
        }
      case PieceType.queen:
        final want = inPov ? 1.38 : 1.28;
        stand = grounded(dist > want + 0.12
            ? vp - dir * want
            : (inPov && dist < 1.02 ? vp - dir * 1.12 : ap));
        if ((stand - ap).flatLength > 0.03) {
          await _walkVampire(a, ap, stand);
        }
      case PieceType.rook:
        stand = grounded(vp - dir * (inPov ? 1.48 : 1.25));
        if ((stand - ap).flatLength > 0.03) {
          await _walkGiantess(a, ap, stand);
        }
      case PieceType.king:
        final offset = v.kind == PieceType.rook ? 0.35 : 0.0;
        stand = grounded(vp - dir * ((inPov ? 1.02 : 0.78) + offset));
        if ((stand - ap).flatLength > 0.03) {
          await _walkBarbarian(a, ap, stand);
        }
      case PieceType.pawn:
        final offset = v.kind == PieceType.rook ? 0.35 : 0.0;
        stand = grounded(vp - dir * ((inPov ? 0.96 : 0.68) + offset));
        if ((stand - ap).flatLength > 0.03) {
          await _walkVanguard(a, ap, stand);
        }
    }
    _place(a, stand);

    // POV modunda bakışı rakibin göğsüne kilitle ki düello her açıdan net izlensin!
    // Kadın Savaş Devi 2 kat büyük olduğu için saldırırken aşağı bakar, ona saldırılırken yukarı bakılır.
    if (a.inPov) {
      _povFocusWorld = _chest(vp, v.kind == PieceType.rook ? 1.18 : 0.56);
      _povFocusWeight = 0.88;
    }

    // İki tarafın karşılıklı mücadelesi: Kılıç çarpışması, kilitlenme ve savuşturma!
    await _clashAndStruggle(a, v, stand, vp, dir, inPov: a.inPov);

    // Dövüş koreografisi (Dövüş Hızı slider'ı ile bağımsız kontrol edilir!)
    switch (a.kind) {
      case PieceType.pawn:
        await _strikeSpear(a, v, vp, dir);
      case PieceType.knight:
        await _strikeAssassin(a, v, vp, dir, inPov: a.inPov);
      case PieceType.bishop:
        await _strikeDragon(a, v, vp, dir);
      case PieceType.rook:
        await _strikeGiantess(a, v, vp, dir);
      case PieceType.queen:
        await _strikeVampire(a, v, vp, dir);
      case PieceType.king:
        await _strikeBarbarian(a, v, vp, dir, inPov: a.inPov);
    }

    _povFocusWeight = 0.0;

    // Zafer sözü kaldırıldı: Kural gereği yalnızca hareket başladığında konuşulur!

    if ((dest - stand).flatLength > 0.03) {
      await _travel(a, stand, dest, alreadyTurned: a.inPov);
    }
    _place(a, dest);
  }

  /// İki tarafın kılıç kılıca çarpışması, kilitlenme ve savunanın karşı saldırı mücadelesi
  Future<void> _clashAndStruggle(
    CreatureRig a,
    CreatureRig v,
    P3 ap,
    P3 vp,
    P3 dir, {
    required bool inPov,
  }) async {
    final palA = Palette.of(a.team);
    final palV = Palette.of(v.team);
    final big = a.kind == PieceType.rook || v.kind == PieceType.rook;
    final mid = (ap + vp) * 0.5 + P3(0, big ? 0.85 : 0.58, 0);

    // 1. AŞAMA: İki savaşçı birbirine atılır ve silahlar havada kilitlenir!
    _playSfx(SfxKind.clashSteel);
    final clashFutures = <Future<void>>[];

    // Saldıranın atılışı
    clashFutures.add(_poseTo(
      a,
      0.24,
      inPov
          ? {
              'armR': [0.45, -0.22, 0.22],
              'armL': [-0.40, 0.18, 0.16],
              'torso': [0.12, 0.10, null],
            }
          : {
              'armR': [-1.20, -0.20, 0.30],
              'armL': [-0.90, 0.20, -0.20],
              'torso': [0.18, 0.14, null],
              'legL': [-0.38, null, null],
              'legR': [0.38, null, null],
            },
      ease: easeOut,
      extra: (t) => a.body.position.z = 0.14 * easeOut(t),
    ));

    // Savunanın aktif karşılaması (pasif durmaz, silahını/kalkanını öne sürer!)
    clashFutures.add(_poseTo(
      v,
      0.24,
      {
        'armR': [-1.30, 0.22, -0.25],
        'armL': [-1.05, -0.25, 0.25],
        'torso': [0.14, -0.12, null],
        'legL': [0.35, null, null],
        'legR': [-0.35, null, null],
      },
      ease: easeOut,
      extra: (t) => v.body.position.z = 0.12 * easeOut(t),
    ));

    await Future.wait(clashFutures);

    // Kıvılcım fırtınası, çelik çınlaması ve kamera sarsıntısı
    _fx.burst(mid, [0xFFFFFF, 0xFFE082, palA.metal, palV.metal],
        count: 22, speed: 2.8, size: 0.046);
    _fx.flash(mid, 0xFFE082, intensity: 11, life: 0.32);
    _fx.addShake(inPov ? 0.09 : 0.07);

    // Kilitlenme gerilimi (karşılıklı güç mücadelesi - 0.20s titreme)
    await _anim.play(0.20, (t) {
      final wobble = math.sin(t * 32) * 0.02;
      a.body.position.x = wobble;
      v.body.position.x = -wobble;
    }, kind: AnimKind.combat);
    a.body.position.x = 0;
    v.body.position.x = 0;

    // ARA AŞAMA: Karşılıklı kapışma turları (ayarlardaki "Kapışma Turu" kadar).
    // Vuruş-savuşturma, karşı atak, kılıç kilitlenmesi ve sıyrılma birbirini
    // izler; düello hemen bitmez. Ekrana dokunulursa son darbeye geçilir.
    await _duelExchanges(a, v, mid, palA, palV, inPov: inPov);

    // 2. AŞAMA: Savunan gardı kırarak sert bir karşı darbe savurur!
    _playSfx(switch (v.kind) {
      PieceType.bishop => SfxKind.wingFlap,
      PieceType.rook => SfxKind.maulSmash,
      PieceType.queen => SfxKind.magicGlide,
      _ => SfxKind.slashBlade,
    });

    final counterFutures = <Future<void>>[];

    // Savunan öne doğru sert darbe indirir
    counterFutures.add(_poseTo(
      v,
      0.22,
      {
        'armR': [0.65, -0.28, 0.35],
        'armL': [-0.45, 0.15, -0.10],
        'torso': [0.22, 0.20, null],
      },
      ease: easeIn,
      extra: (t) => v.body.position.z = (0.12 + 0.10 * easeIn(t)),
    ));

    // Saldıran bu karşı darbeden ustalıkla sıyrılarak gardını düşmanın açığına yönlendirir (parry & dodge)
    counterFutures.add(_poseTo(
      a,
      0.22,
      inPov
          ? {
              'armR': [-0.15, 0.28, 0.12],
              'armL': [-0.60, -0.22, 0.20],
              'torso': [-0.08, -0.16, null],
            }
          : {
              'armR': [-1.65, 0.25, -0.20],
              'armL': [-0.60, -0.30, 0.15],
              'torso': [-0.14, -0.22, null],
              'legL': [0.28, null, null],
              'legR': [-0.32, null, null],
            },
      ease: easeOut,
      extra: (t) => a.body.position.z = 0.08 * (1 - t),
    ));

    await Future.wait(counterFutures);

    // Kılıç savuşturma kıvılcımı
    _fx.slash(mid + const P3(0, 0.08, 0), palV.glow, a.root.rotation.y.toDouble(),
        tilt: -0.4, size: 0.52);

    // Savunan karşı atağı boşa düşünce sendeleyip dengesini kaybeder
    await _staggerDefender(v, _chest(vp, v.kind == PieceType.rook ? 1.15 : 0.58), palA.glow);
  }

  // ================================================================ UZUN DÜELLO: KAPIŞMA TURLARI
  /// Bitirici darbeden önce [_duelRounds] tur karşılıklı kapışma. Hangi
  /// kapışmaların gelebileceğini ve bir turun kaç kapışmadan oluştuğunu
  /// [_duelComplexity] belirler (sade/kısa ↔ uzun/karmaşık); aynı kapışma art
  /// arda gelmez, turlar ilerledikçe tempo artar.
  Future<void> _duelExchanges(
    CreatureRig a,
    CreatureRig v,
    P3 mid,
    Palette palA,
    Palette palV, {
    required bool inPov,
  }) async {
    final rounds = _duelRounds.isFinite ? math.max(0, _duelRounds.round()) : 0;
    if (rounds == 0) return;
    final gen = _generation;
    final rng = math.Random();
    final baseText = _battleText;
    _duelActive = true;
    _duelSkip = false;
    if (mounted) {
      setState(() => _battleText = '${baseText.isEmpty ? '⚔ Düello' : baseText}  •  Dokun: son darbeye geç');
    }
    try {
      final level = _duelComplexity.isFinite ? math.max(0, _duelComplexity.round()) : 2;
      final pool = _duelPool(level, inPov: inPov);
      // Karmaşıklık arttıkça bir tur birden çok kapışmadan oluşur (üst sınır yok).
      final perRound = 1 + math.max(0, (level - 1) ~/ 2);
      // Sade düello daha kısa ve çevik akar.
      final pace = level == 0 ? 0.85 : 1.0;
      final total = rounds * perRound;
      _DuelExchange? last;
      for (var i = 0; i < total; i++) {
        if (_duelSkip || gen != _generation || !mounted) break;
        var pick = pool[rng.nextInt(pool.length)];
        if (pick == last && pool.length > 1) {
          pick = pool[(pool.indexOf(pick) + 1 + rng.nextInt(pool.length - 1)) % pool.length];
        }
        last = pick;
        // Son turlara doğru tempo artar (süreler %20'ye kadar kısalır).
        final tempo = pace * (1.0 - 0.2 * (total <= 1 ? 1.0 : i / (total - 1)));
        final side = rng.nextBool() ? 1.0 : -1.0;
        switch (pick) {
          case _DuelExchange.press:
            await _exchangePress(a, v, mid, palA, palV, tempo);
          case _DuelExchange.counter:
            await _exchangeCounter(a, v, mid, palA, palV, tempo);
          case _DuelExchange.bind:
            await _exchangeBind(a, v, mid, palA, palV, tempo);
          case _DuelExchange.dodge:
            await _exchangeDodge(a, v, mid, palA, palV, tempo, side);
          case _DuelExchange.combo:
            await _exchangeCombo(a, v, mid, palA, palV, tempo, math.max(2, level));
          case _DuelExchange.feint:
            await _exchangeFeint(a, v, mid, palA, palV, tempo, side);
          case _DuelExchange.circle:
            await _exchangeCircle(a, v, mid, palA, palV, tempo, side);
          case _DuelExchange.bash:
            await _exchangeBash(a, v, mid, palA, palV, tempo);
          case _DuelExchange.knockdown:
            await _exchangeKnockdown(a, v, mid, palA, palV, tempo);
          case _DuelExchange.leap:
            await _exchangeLeap(a, v, mid, palA, palV, tempo);
        }
      }
      if (gen == _generation) {
        await Future.wait([_duelMove(a, _DuelPose.guard, 0.16), _duelMove(v, _DuelPose.guard, 0.16)]);
      }
    } finally {
      _duelActive = false;
      _duelSkip = false;
      if (mounted) setState(() => _battleText = baseText);
    }
  }

  /// Saldıran üstten indirir, savunan silahıyla karşılar ve darbenin ağırlığıyla geri itilir.
  Future<void> _exchangePress(CreatureRig a, CreatureRig v, P3 mid, Palette pa, Palette pv, double t) async {
    await Future.wait([
      _duelMove(a, _DuelPose.windup, 0.24 * t, z: 0.04),
      _duelMove(v, _DuelPose.guard, 0.24 * t),
    ]);
    _playSfx(_swingSfx(a));
    await Future.wait([
      _duelMove(a, _DuelPose.strike, 0.15 * t, z: 0.18, ease: easeIn),
      _duelMove(v, _DuelPose.parry, 0.15 * t, z: -0.03, ease: easeOut),
    ]);
    _duelSpark(mid, pa.metal, pv.metal, power: 1.0);
    await Future.wait([
      _duelMove(v, _DuelPose.parry, 0.16 * t, z: -0.12, ease: easeOut),
      _duelMove(a, _DuelPose.guard, 0.22 * t, z: 0.06),
    ]);
    await _duelMove(v, _DuelPose.guard, 0.18 * t);
  }

  /// Savunan karşı atağa geçer; saldıran gardını kaldırıp darbeyi göğüsler.
  Future<void> _exchangeCounter(CreatureRig a, CreatureRig v, P3 mid, Palette pa, Palette pv, double t) async {
    await Future.wait([
      _duelMove(v, _DuelPose.windup, 0.24 * t, z: 0.04),
      _duelMove(a, _DuelPose.guard, 0.24 * t),
    ]);
    _playSfx(_swingSfx(v));
    await Future.wait([
      _duelMove(v, _DuelPose.strike, 0.15 * t, z: 0.18, ease: easeIn),
      _duelMove(a, _DuelPose.parry, 0.15 * t, z: -0.03, ease: easeOut),
    ]);
    _duelSpark(mid, pv.metal, pa.metal, power: 1.0);
    await Future.wait([
      _duelMove(a, _DuelPose.parry, 0.16 * t, z: -0.12, ease: easeOut),
      _duelMove(v, _DuelPose.guard, 0.22 * t, z: 0.04),
    ]);
    await _duelMove(a, _DuelPose.guard, 0.18 * t);
  }

  /// Kılıçlar kilitlenir: iki taraf itişip kakışır, üstünlük el değiştirir,
  /// sürtünen çelikten kıvılcımlar saçılır; sonra silahlar sıyrılarak ayrılır.
  Future<void> _exchangeBind(CreatureRig a, CreatureRig v, P3 mid, Palette pa, Palette pv, double t) async {
    await Future.wait([
      _duelMove(a, _DuelPose.bind, 0.18 * t, z: 0.14, ease: easeOut),
      _duelMove(v, _DuelPose.bind, 0.18 * t, z: 0.12, ease: easeOut),
    ]);
    _duelSpark(mid, pa.metal, pv.metal, power: 1.25);
    final za = a.body.position.z.toDouble();
    final zv = v.body.position.z.toDouble();
    var nextSpark = 0.22;
    await _anim.play(0.62 * t, (k) {
      final push = math.sin(k * math.pi * 3);
      a.body.position.z = za + 0.05 * push;
      v.body.position.z = zv - 0.05 * push;
      final tremble = math.sin(k * 46) * 0.015;
      a.body.position.x = tremble;
      v.body.position.x = -tremble;
      if (k >= nextSpark) {
        nextSpark += 0.26;
        _duelSpark(mid + P3(_fx.r(0.06), _fx.r(0.05), _fx.r(0.06)), pa.metal, pv.metal, power: 0.45);
      }
    }, kind: AnimKind.combat);
    _playSfx(SfxKind.slashBlade);
    _fx.burst(mid, [0xFFFFFF, 0xFFE082, pa.glow], count: 10, speed: 2.6, size: 0.034);
    await Future.wait([
      _duelMove(a, _DuelPose.guard, 0.20 * t, z: -0.04, ease: easeOut),
      _duelMove(v, _DuelPose.guard, 0.20 * t, z: -0.06, ease: easeOut),
    ]);
    await Future.wait([
      _duelMove(a, _DuelPose.guard, 0.14 * t),
      _duelMove(v, _DuelPose.guard, 0.14 * t),
    ]);
  }

  /// Saldıran yatay savurur, savunan eğilerek kurtulur ve hemen saplamayla
  /// karşılık verir; saldıran yana sıyrılır, silah zırhını sıyırıp geçer.
  Future<void> _exchangeDodge(
    CreatureRig a,
    CreatureRig v,
    P3 mid,
    Palette pa,
    Palette pv,
    double t,
    double side,
  ) async {
    await Future.wait([
      _duelMove(a, _DuelPose.sweepWind, 0.20 * t, z: 0.03),
      _duelMove(v, _DuelPose.guard, 0.20 * t),
    ]);
    _playSfx(_swingSfx(a));
    await Future.wait([
      _duelMove(a, _DuelPose.sweep, 0.16 * t, z: 0.12, ease: easeIn),
      _duelMove(v, _DuelPose.duck, 0.14 * t, y: -0.08, z: -0.02, ease: easeOut),
    ]);
    // Boşa giden savuruşun izi savunanın başının üstünden geçer.
    _fx.slash(mid + const P3(0, 0.22, 0), pa.glow, a.root.rotation.y.toDouble(), tilt: 0.05, size: 0.55);
    _playSfx(_swingSfx(v));
    await Future.wait([
      _duelMove(v, _DuelPose.jab, 0.16 * t, z: 0.14, ease: easeIn),
      _duelMove(a, _DuelPose.sidestep, 0.16 * t, x: 0.14 * side, z: 0.02, ease: easeOut),
    ]);
    _duelSpark(mid + const P3(0, -0.05, 0), pv.metal, pa.metal, power: 0.5);
    await Future.wait([
      _duelMove(a, _DuelPose.guard, 0.20 * t),
      _duelMove(v, _DuelPose.guard, 0.20 * t),
    ]);
  }

  /// Karmaşıklık seviyesine göre gelebilecek kapışmalar. Çevreleme ve sıçrayış
  /// POV'da kullanılmaz (kamera savaşçının gözünde; rakibin yeri sabit kalmalı).
  static List<_DuelExchange> _duelPool(int level, {required bool inPov}) => [
        _DuelExchange.press,
        _DuelExchange.counter,
        if (level >= 1) ...[_DuelExchange.bind, _DuelExchange.dodge],
        if (level >= 2) ...[_DuelExchange.combo, _DuelExchange.feint, if (!inPov) _DuelExchange.circle],
        if (level >= 3) ...[_DuelExchange.bash, _DuelExchange.knockdown],
        if (level >= 4 && !inPov) _DuelExchange.leap,
      ];

  /// Zincirleme kombo: saldıran [hits] darbeyi ara vermeden ardı ardına indirir
  /// (üstten, yandan, saplama), savunan her birini ayrı karşılarken adım adım geriler.
  Future<void> _exchangeCombo(CreatureRig a, CreatureRig v, P3 mid, Palette pa, Palette pv, double t, int hits) async {
    await Future.wait([
      _duelMove(a, _DuelPose.windup, 0.20 * t, z: 0.04),
      _duelMove(v, _DuelPose.guard, 0.20 * t),
    ]);
    const attacks = [_DuelPose.strike, _DuelPose.sweep, _DuelPose.jab];
    const recoils = [_DuelPose.windup, _DuelPose.sweepWind, _DuelPose.windup];
    for (var h = 0; h < hits; h++) {
      if (_duelSkip) break;
      final za = math.min(0.22, 0.10 + 0.02 * h);
      final zv = math.max(-0.14, -0.03 - 0.025 * h);
      if (h > 0) {
        await Future.wait([
          _duelMove(a, recoils[h % 3], 0.13 * t, z: za - 0.06),
          _duelMove(v, _DuelPose.guard, 0.13 * t, z: zv),
        ]);
      }
      _playSfx(_swingSfx(a));
      await Future.wait([
        _duelMove(a, attacks[h % 3], 0.12 * t, z: za + 0.06, ease: easeIn),
        _duelMove(v, _DuelPose.parry, 0.12 * t, z: zv, ease: easeOut),
      ]);
      _duelSpark(mid, pa.metal, pv.metal, power: math.min(1.5, 0.7 + 0.12 * h));
    }
    // Son darbe savunanı geri iter
    await Future.wait([
      _duelMove(v, _DuelPose.parry, 0.16 * t, z: -0.15, ease: easeOut),
      _duelMove(a, _DuelPose.guard, 0.22 * t, z: 0.05),
    ]);
    await Future.wait([
      _duelMove(v, _DuelPose.guard, 0.18 * t),
      _duelMove(a, _DuelPose.guard, 0.18 * t),
    ]);
  }

  /// Aldatmaca: saldıran üstten vuracakmış gibi yapar, savunan gardını yukarı
  /// kaldırınca vazgeçip alttan saplar; savunan son anda yana sıyrılır.
  Future<void> _exchangeFeint(CreatureRig a, CreatureRig v, P3 mid, Palette pa, Palette pv, double t, double side) async {
    await Future.wait([
      _duelMove(a, _DuelPose.windup, 0.22 * t, z: 0.05),
      _duelMove(v, _DuelPose.parry, 0.22 * t, z: -0.02),
    ]);
    await _duelMove(a, _DuelPose.guard, 0.10 * t, z: 0.03);
    _playSfx(_swingSfx(a));
    await Future.wait([
      _duelMove(a, _DuelPose.jab, 0.13 * t, z: 0.18, ease: easeIn),
      _duelMove(v, _DuelPose.sidestep, 0.15 * t, x: -0.12 * side, z: -0.03, ease: easeOut),
    ]);
    _duelSpark(mid + const P3(0, -0.10, 0), pa.metal, pv.metal, power: 0.6);
    await Future.wait([
      _duelMove(a, _DuelPose.guard, 0.20 * t),
      _duelMove(v, _DuelPose.guard, 0.20 * t),
    ]);
  }

  /// Çevreleme: iki savaşçı göz göze, gardda birbirinin etrafında yarım daire
  /// çizer, döndükleri yerde sert bir darbe değişimi olur, sonra yerlerine döner.
  Future<void> _exchangeCircle(CreatureRig a, CreatureRig v, P3 mid, Palette pa, Palette pv, double t, double side) async {
    final pa0 = _posOf(a);
    final pv0 = _posOf(v);
    final ya0 = a.root.rotation.y.toDouble();
    final yv0 = v.root.rotation.y.toDouble();
    final c = (pa0 + pv0) * 0.5;
    final lift = mid.y - c.y;
    final angle = 0.75 * side;

    Future<void> orbit(double from, double to, double dur) => _anim.play(dur, (k) {
          final ang = from + (to - from) * smooth(k);
          final cs = math.cos(ang);
          final sn = math.sin(ang);
          for (final (rig, p0) in [(a, pa0), (v, pv0)]) {
            final rx = p0.x - c.x;
            final rz = p0.z - c.z;
            final x = c.x + rx * cs - rz * sn;
            final z = c.z + rx * sn + rz * cs;
            _place(rig, P3(x, _groundAt(x, z), z));
          }
          final d = _posOf(v) - _posOf(a);
          a.root.rotation.y = _yaw(d.flatNormal);
          v.root.rotation.y = _yaw((d * -1).flatNormal);
          // Yan adımların hafif iniş-kalkışı
          final bob = (math.sin(k * math.pi * 4)).abs() * 0.03;
          a.body.position.y = bob;
          v.body.position.y = bob;
        }, kind: AnimKind.combat);

    await Future.wait([_duelMove(a, _DuelPose.guard, 0.14 * t), _duelMove(v, _DuelPose.guard, 0.14 * t)]);
    await orbit(0.0, angle, 0.75 * t);
    final mid2 = (_posOf(a) + _posOf(v)) * 0.5 + P3(0, lift, 0);
    await _duelMove(a, _DuelPose.windup, 0.18 * t, z: 0.04);
    _playSfx(_swingSfx(a));
    await Future.wait([
      _duelMove(a, _DuelPose.strike, 0.14 * t, z: 0.17, ease: easeIn),
      _duelMove(v, _DuelPose.parry, 0.14 * t, z: -0.04, ease: easeOut),
    ]);
    _duelSpark(mid2, pa.metal, pv.metal, power: 1.0);
    await Future.wait([_duelMove(a, _DuelPose.guard, 0.18 * t), _duelMove(v, _DuelPose.guard, 0.18 * t)]);
    await orbit(angle, 0.0, 0.75 * t);
    _place(a, pa0);
    _place(v, pv0);
    a.root.rotation.y = ya0;
    v.root.rotation.y = yv0;
    a.body.position.y = 0;
    v.body.position.y = 0;
  }

  /// Kalkan / tekme darbesi: saldıran gardı açmak için tekme savurur, savunan
  /// sendeleyip geri adım atar; çarptığı yerden toz kalkar.
  Future<void> _exchangeBash(CreatureRig a, CreatureRig v, P3 mid, Palette pa, Palette pv, double t) async {
    await Future.wait([
      _duelMove(a, _DuelPose.bashWind, 0.18 * t),
      _duelMove(v, _DuelPose.guard, 0.18 * t),
    ]);
    await Future.wait([
      _duelMove(a, _DuelPose.bash, 0.12 * t, z: 0.20, ease: easeIn),
      _duelMove(v, _DuelPose.stagger, 0.14 * t, z: -0.16, ease: easeOut),
    ]);
    _playSfx(SfxKind.stepStomp);
    final vpos = _posOf(v);
    _fx.smoke(P3(vpos.x, _groundAt(vpos.x, vpos.z) + 0.05, vpos.z), 0x8A7F70, count: 6, radius: 0.25, life: 0.7);
    _fx.burst(mid + const P3(0, -0.18, 0), [0xFFFFFF, pa.metal], count: 8, speed: 1.6, size: 0.03);
    _fx.addShake(_inPovSequence ? 0.06 : 0.04);
    await Future.wait([
      _duelMove(a, _DuelPose.guard, 0.20 * t, z: 0.04),
      _duelMove(v, _DuelPose.guard, 0.26 * t),
    ]);
    await _duelMove(a, _DuelPose.guard, 0.10 * t);
  }

  /// Diz çöktürme: saldıran tüm gücünü toplayıp indirir; savunan bloklar ama
  /// darbenin ağırlığıyla dizinin üstüne çöker, yerden ikinci darbeyi de
  /// karşılar, sonra doğrulup saldıranı geri iter.
  Future<void> _exchangeKnockdown(CreatureRig a, CreatureRig v, P3 mid, Palette pa, Palette pv, double t) async {
    await Future.wait([
      _duelMove(a, _DuelPose.windup, 0.34 * t, z: -0.02),
      _duelMove(v, _DuelPose.guard, 0.30 * t),
    ]);
    _fx.flash(mid + const P3(0, 0.25, 0), pa.glow, intensity: 8, life: 0.45);
    _playSfx(_swingSfx(a));
    await Future.wait([
      _duelMove(a, _DuelPose.strike, 0.14 * t, z: 0.20, ease: easeIn),
      _duelMove(v, _DuelPose.parry, 0.14 * t, z: -0.04, ease: easeOut),
    ]);
    _duelSpark(mid, pa.metal, pv.metal, power: 1.6);
    final vpos = _posOf(v);
    _fx.shockwave(vpos, pa.glow, radius: 1.0, life: 0.45, y: _groundAt(vpos.x, vpos.z) + 0.05);
    await _duelMove(v, _DuelPose.kneel, 0.18 * t, y: -0.20, z: -0.10, ease: easeOut);
    await _duelMove(a, _DuelPose.windup, 0.18 * t, z: 0.08);
    _playSfx(_swingSfx(a));
    await Future.wait([
      _duelMove(a, _DuelPose.strike, 0.13 * t, z: 0.20, ease: easeIn),
      _duelMove(v, _DuelPose.kneelBlock, 0.13 * t, y: -0.20, z: -0.10),
    ]);
    _duelSpark(mid + const P3(0, -0.18, 0), pa.metal, pv.metal, power: 1.2);
    await Future.wait([
      _duelMove(v, _DuelPose.guard, 0.30 * t),
      _duelMove(a, _DuelPose.guard, 0.26 * t, z: -0.04),
    ]);
    await _duelMove(a, _DuelPose.guard, 0.12 * t);
  }

  /// Sıçrayış darbesi: saldıran çömelip havaya fırlar, yukarıdan iner;
  /// savunan silahını başının üstüne kaldırır, çarpışma yeri sarsar.
  Future<void> _exchangeLeap(CreatureRig a, CreatureRig v, P3 mid, Palette pa, Palette pv, double t) async {
    await Future.wait([
      _duelMove(a, _DuelPose.crouch, 0.18 * t, y: -0.10),
      _duelMove(v, _DuelPose.guard, 0.18 * t),
    ]);
    _playSfx(_swingSfx(a));
    final b = a.body;
    await Future.wait([
      _anim.play(0.42 * t, (k) {
        b.position.y = -0.10 + 0.55 * math.sin(math.pi * k) + 0.10 * k;
        b.position.z = 0.22 * smooth(k);
      }, kind: AnimKind.combat),
      _poseTo(a, 0.30 * t, _duelPose(a, _DuelPose.windup)),
      _poseTo(v, 0.32 * t, _duelPose(v, _DuelPose.kneelBlock)),
    ]);
    await Future.wait([
      _duelMove(a, _DuelPose.strike, 0.10 * t, z: 0.22, ease: easeIn),
      _duelMove(v, _DuelPose.kneelBlock, 0.12 * t, y: -0.12, z: -0.06),
    ]);
    _duelSpark(mid + const P3(0, 0.08, 0), pa.metal, pv.metal, power: 1.8);
    final vpos = _posOf(v);
    _fx.shockwave(vpos, 0xFFE082, radius: 1.4, life: 0.5, y: _groundAt(vpos.x, vpos.z) + 0.05);
    _fx.addShake(_inPovSequence ? 0.10 : 0.07);
    await Future.wait([
      _duelMove(a, _DuelPose.guard, 0.24 * t, z: 0.04),
      _duelMove(v, _DuelPose.guard, 0.28 * t),
    ]);
    await _duelMove(a, _DuelPose.guard, 0.10 * t);
  }

  /// Silahların buluştuğu anın kıvılcımı, çelik sesi ve hafif sarsıntı.
  void _duelSpark(P3 at, int c1, int c2, {double power = 1.0}) {
    _playSfx(SfxKind.clashSteel);
    final p = at + P3(_fx.r(0.08), _fx.r(0.06), _fx.r(0.08));
    _fx.burst(p, [0xFFFFFF, 0xFFE082, c1, c2],
        count: (10 + 10 * power).round(), speed: 2.0 + 0.9 * power, size: 0.036 + 0.008 * power);
    _fx.flash(p, 0xFFE082, intensity: 5 + 5 * power, life: 0.24);
    _fx.addShake((_inPovSequence ? 0.05 : 0.03) * power);
  }

  /// Savaşçının silah savuruş sesi (ejderha kanat, dev balyoz, vampir büyü...).
  SfxKind _swingSfx(CreatureRig r) => switch (r.kind) {
        PieceType.bishop => SfxKind.wingFlap,
        PieceType.rook => SfxKind.maulSmash,
        PieceType.queen => SfxKind.magicGlide,
        PieceType.king => SfxKind.axeCleave,
        PieceType.knight || PieceType.pawn => SfxKind.slashBlade,
      };

  /// Düello pozuna geçer; gövde (ileri/geri [z], yana [x], aşağı [y]) da
  /// birlikte kayar. POV'daki savaşçının kayması kamerayı oynattığı için azaltılır.
  Future<void> _duelMove(
    CreatureRig r,
    _DuelPose pose,
    double dur, {
    double z = 0,
    double x = 0,
    double y = 0,
    double Function(double)? ease,
  }) {
    final b = r.body;
    final k = r.inPov ? 0.6 : 1.0;
    final z0 = b.position.z.toDouble();
    final x0 = b.position.x.toDouble();
    final y0 = b.position.y.toDouble();
    final e = ease ?? smooth;
    return _poseTo(r, dur, _duelPose(r, pose), ease: e, extra: (t) {
      final s = e(t);
      b.position.z = z0 + (z * k - z0) * s;
      b.position.x = x0 + (x * k - x0) * s;
      b.position.y = y0 + (y * k - y0) * s;
    });
  }

  /// Düello pozları. İnsansı savaşçılarda kol/gövde/bacak, ejderhada ayrıca
  /// kanat/boyun/çene oynar (olmayan parçalar yok sayılır). POV'daki savaşçı
  /// için kollar kameranın görüş alanında kalacak şekilde ayrı pozlar kullanılır.
  Map<String, List<double?>> _duelPose(CreatureRig r, _DuelPose p) {
    double rest(String part, String axis) => r.rest['$part.r$axis'] ?? 0.0;
    if (r.inPov) {
      return switch (p) {
        _DuelPose.guard => {
            'armR': [0.30, -0.15, 0.18],
            'armL': [-0.30, 0.15, 0.14],
            'torso': [0.04, 0.0, rest('torso', 'z')],
          },
        _DuelPose.windup || _DuelPose.sweepWind || _DuelPose.bashWind || _DuelPose.crouch => {
            'armR': [-0.30, 0.40, 0.30],
            'armL': [-0.45, 0.10, 0.20],
            'torso': [-0.06, -0.16, null],
          },
        _DuelPose.strike || _DuelPose.sweep || _DuelPose.jab || _DuelPose.bash => {
            'armR': [0.80, -0.32, 0.34],
            'armL': [-0.35, 0.18, 0.16],
            'torso': [0.10, 0.18, null],
          },
        _DuelPose.parry ||
        _DuelPose.duck ||
        _DuelPose.sidestep ||
        _DuelPose.stagger ||
        _DuelPose.kneel ||
        _DuelPose.kneelBlock =>
          {
            'armR': [-0.12, 0.45, 0.10],
            'armL': [-0.70, -0.25, 0.25],
            'torso': [-0.08, -0.14, null],
          },
        _DuelPose.bind => {
            'armR': [0.45, -0.22, 0.22],
            'armL': [-0.40, 0.18, 0.16],
            'torso': [0.12, 0.10, null],
          },
      };
    }
    return switch (p) {
      _DuelPose.guard => {
          'armR': [-1.05, 0.15, 0.25],
          'armL': [-0.85, -0.15, -0.20],
          'torso': [0.06, 0.0, rest('torso', 'z')],
          'legL': [-0.30, null, rest('legL', 'z')],
          'legR': [0.30, null, rest('legR', 'z')],
          'wingL': [null, null, 0.70],
          'wingR': [null, null, -0.70],
          'neck': [-0.15, rest('neck', 'y'), null],
          'jaw': [0.15, null, null],
        },
      _DuelPose.windup => {
          'armR': [-2.30, 0.35, 0.45],
          'armL': [-0.70, -0.20, -0.25],
          'torso': [-0.14, -0.24, null],
          'legL': [-0.42, null, null],
          'legR': [0.40, null, null],
          'wingL': [null, null, 1.05],
          'wingR': [null, null, -1.05],
          'neck': [-0.50, null, null],
          'jaw': [0.60, null, null],
        },
      _DuelPose.strike => {
          'armR': [0.55, -0.35, 0.20],
          'armL': [-0.95, 0.20, -0.15],
          'torso': [0.26, 0.26, null],
          'legL': [-0.55, null, null],
          'legR': [0.48, null, null],
          'wingL': [null, null, 0.85],
          'wingR': [null, null, -0.85],
          'neck': [0.30, null, null],
          'jaw': [0.10, null, null],
        },
      _DuelPose.parry => {
          'armR': [-1.75, 0.30, -0.35],
          'armL': [-1.35, -0.25, 0.30],
          'torso': [-0.10, -0.10, null],
          'legL': [0.30, null, null],
          'legR': [-0.34, null, null],
          'wingL': [null, null, 1.15],
          'wingR': [null, null, -1.15],
          'neck': [-0.35, null, null],
          'jaw': [0.35, null, null],
        },
      _DuelPose.bind => {
          'armR': [-1.40, -0.20, 0.30],
          'armL': [-1.10, 0.20, -0.20],
          'torso': [0.20, 0.12, null],
          'legL': [-0.45, null, null],
          'legR': [0.42, null, null],
          'wingL': [null, null, 0.95],
          'wingR': [null, null, -0.95],
          'neck': [0.10, null, null],
          'jaw': [0.45, null, null],
        },
      _DuelPose.sweepWind => {
          'armR': [-1.25, 0.95, 0.95],
          'armL': [-0.60, -0.20, -0.20],
          'torso': [-0.04, 0.42, null],
          'legL': [-0.30, null, null],
          'legR': [0.34, null, null],
          'wingL': [null, null, 1.10],
          'wingR': [null, null, -0.60],
          'neck': [-0.20, 0.40, null],
          'jaw': [0.40, null, null],
        },
      _DuelPose.sweep => {
          'armR': [-1.05, -0.95, -0.65],
          'armL': [-0.80, 0.25, 0.20],
          'torso': [0.12, -0.42, null],
          'legL': [-0.40, null, null],
          'legR': [0.40, null, null],
          'wingL': [null, null, 0.60],
          'wingR': [null, null, -1.10],
          'neck': [0.10, -0.40, null],
          'jaw': [0.15, null, null],
        },
      _DuelPose.duck => {
          'armR': [-0.90, 0.20, -0.30],
          'armL': [-1.00, -0.20, 0.30],
          'torso': [0.55, 0.0, null],
          'legL': [-0.70, null, null],
          'legR': [0.65, null, null],
          'wingL': [null, null, 0.30],
          'wingR': [null, null, -0.30],
          'neck': [0.35, null, null],
          'jaw': [0.05, null, null],
        },
      _DuelPose.jab => {
          'armR': [0.95, -0.20, 0.25],
          'armL': [-0.60, 0.20, -0.20],
          'torso': [0.30, 0.20, null],
          'legL': [-0.60, null, null],
          'legR': [0.55, null, null],
          'wingL': [null, null, 0.90],
          'wingR': [null, null, -0.90],
          'neck': [0.40, null, null],
          'jaw': [0.55, null, null],
        },
      _DuelPose.sidestep => {
          'armR': [-1.20, 0.35, 0.30],
          'armL': [-0.70, -0.30, -0.20],
          'torso': [-0.08, -0.45, 0.10],
          'legL': [-0.20, null, 0.18],
          'legR': [0.25, null, 0.10],
          'wingL': [null, null, 1.00],
          'wingR': [null, null, -1.00],
          'neck': [-0.20, -0.30, null],
          'jaw': [0.25, null, null],
        },
      // Tekme / kalkan darbesine hazırlık: ağırlık arka ayakta, kalkan kolu içeride.
      _DuelPose.bashWind => {
          'armR': [-1.10, 0.25, 0.30],
          'armL': [-0.60, -0.40, -0.30],
          'torso': [0.05, -0.22, null],
          'legL': [-0.20, null, null],
          'legR': [0.35, null, null],
          'wingL': [null, null, 1.00],
          'wingR': [null, null, -1.00],
          'neck': [-0.25, null, null],
          'jaw': [0.30, null, null],
        },
      // Ön tekme + kalkan itişi (ejderhada kuyruk/kanat savuruşu gibi okunur).
      _DuelPose.bash => {
          'armR': [-0.95, 0.20, 0.30],
          'armL': [-1.45, 0.30, 0.10],
          'torso': [-0.18, 0.10, null],
          'legL': [0.15, null, null],
          'legR': [-1.30, null, null],
          'wingL': [null, null, 0.50],
          'wingR': [null, null, -0.50],
          'neck': [0.30, null, null],
          'jaw': [0.50, null, null],
        },
      _DuelPose.stagger => {
          'armR': [-0.40, null, -0.45],
          'armL': [-0.30, null, 0.50],
          'torso': [-0.40, 0.25, null],
          'legL': [0.35, null, null],
          'legR': [-0.15, null, null],
          'wingL': [null, null, 1.20],
          'wingR': [null, null, -1.20],
          'neck': [-0.45, null, null],
          'jaw': [0.50, null, null],
        },
      // Darbenin ağırlığıyla diz çökme (gövde aşağı iner, bacaklar açılır).
      _DuelPose.kneel => {
          'armR': [-1.20, 0.20, 0.20],
          'armL': [-1.10, -0.20, -0.20],
          'torso': [-0.20, 0.0, null],
          'legL': [-0.90, null, null],
          'legR': [0.90, null, null],
          'wingL': [null, null, 0.40],
          'wingR': [null, null, -0.40],
          'neck': [0.20, null, null],
          'jaw': [0.20, null, null],
        },
      // Yerden silahı başının üstüne kaldırıp darbeyi karşılama.
      _DuelPose.kneelBlock => {
          'armR': [-2.20, 0.30, -0.20],
          'armL': [-2.00, -0.30, 0.30],
          'torso': [-0.30, 0.0, null],
          'legL': [-0.90, null, null],
          'legR': [0.90, null, null],
          'wingL': [null, null, 1.25],
          'wingR': [null, null, -1.25],
          'neck': [-0.40, null, null],
          'jaw': [0.40, null, null],
        },
      // Sıçrayış öncesi çömelme.
      _DuelPose.crouch => {
          'armR': [-1.60, 0.30, 0.40],
          'armL': [-0.90, -0.20, -0.20],
          'torso': [0.35, 0.0, null],
          'legL': [-0.70, null, null],
          'legR': [0.60, null, null],
          'wingL': [null, null, 0.30],
          'wingR': [null, null, -0.30],
          'neck': [0.20, null, null],
          'jaw': [0.10, null, null],
        },
    };
  }

  Future<void> _braceDefender(CreatureRig v) {
    if (v.kind == PieceType.bishop) {
      return _poseTo(v, 0.30, {
        'wingL': [null, null, 0.75],
        'wingR': [null, null, -0.75],
        'jaw': [0.42, null, null],
      });
    }
    return _poseTo(v, 0.30, {
      'armL': [-0.72, null, -0.25],
      'armR': [-0.95, null, 0.20],
      'legL': [-0.24, null, null],
      'legR': [0.24, null, null],
      'torso': [-0.08, null, null],
    });
  }

  Future<void> _staggerDefender(CreatureRig v, P3 hitPos, int sparkColor) async {
    _playSfx(SfxKind.clashSteel);
    _fx.burst(hitPos, [0xFFFFFF, sparkColor, 0xFFD27D], count: 16, speed: 2.1, size: 0.038);
    _fx.flash(hitPos, sparkColor, intensity: 9, life: 0.30);
    _fx.addShake(0.06);
    await _poseTo(
      v,
      0.26,
      {
        'torso': [-0.28, 0.18, null],
        'armL': [-0.25, null, 0.35],
        'armR': [-0.35, null, -0.28],
      },
      extra: (t) => v.body.position.z = -0.10 * math.sin(math.pi * t),
    );
  }

  P3 _chest(P3 p, [double h = 0.58]) => p + P3(0, h, 0);

  Future<void> _poseTo(
    CreatureRig r,
    double dur,
    Map<String, List<double?>> targets, {
    double Function(double)? ease,
    void Function(double t)? extra,
    AnimKind kind = AnimKind.combat,
  }) {
    final starts = <String, List<double>>{};
    for (final n in targets.keys) {
      final p = r.parts[n];
      if (p != null) {
        starts[n] = [
          p.rotation.x.toDouble(),
          p.rotation.y.toDouble(),
          p.rotation.z.toDouble(),
        ];
      }
    }
    final e = ease ?? smooth;
    return _anim.play(
      dur,
      (t) {
        final k = e(t);
        for (final entry in targets.entries) {
          final p = r.parts[entry.key];
          final s = starts[entry.key];
          if (p == null || s == null) continue;
          final g = entry.value;
          if (g[0] != null) p.rotation.x = s[0] + (g[0]! - s[0]) * k;
          if (g.length > 1 && g[1] != null) p.rotation.y = s[1] + (g[1]! - s[1]) * k;
          if (g.length > 2 && g[2] != null) p.rotation.z = s[2] + (g[2]! - s[2]) * k;
        }
        extra?.call(t);
      },
      kind: kind,
    );
  }

  /// 1. Kalkan Muhafızı Düellosu: Kalkan Çarpışması -> Gard Kırma -> Ağır Teber Saplaması!
  Future<void> _strikeSpear(CreatureRig a, CreatureRig v, P3 vp, P3 dir) async {
    final pal = Palette.of(a.team);
    final hit = _chest(vp, v.kind == PieceType.rook ? 1.15 : 0.58);
    final fp = a.inPov;

    // 1. Hamle: Sağdaki şövalye kalkanıyla rakibin gardına çarpıp sarsma!
    await _poseTo(
      a,
      0.34,
      fp
          ? {
              'armL': [-0.38, -0.18, 0.24],
              'armR': [0.35, -0.05, 0.15],
              'legL': [-0.52, null, null],
              'legR': [0.34, null, null],
              'torso': [0.06, 0.14, null],
            }
          : {
              'armL': [-1.05, -0.35, null],
              'armR': [-0.65, null, null],
              'legL': [-0.42, null, null],
              'legR': [0.36, null, null],
              'torso': [0.16, 0.22, null],
            },
      extra: (t) => a.body.position.z = 0.14 * smooth(t),
    );
    await _staggerDefender(v, hit, pal.metal);

    // 2. Hamle: Kalkanı tekrar yana açıp çelik teberi geriye çekerek güç toplama
    await _poseTo(
      a,
      0.38,
      fp
          ? {
              'armL': [-0.14, -0.76, 0.10],
              'armR': [0.18, 0.12, 0.08],
              'legL': [0.28, null, null],
              'legR': [-0.46, null, null],
              'torso': [-0.08, -0.16, null],
            }
          : {
              'armL': [-0.45, -0.15, null],
              'armR': [-1.35, 0.18, null],
              'legL': [0.28, null, null],
              'legR': [-0.46, null, null],
              'torso': [-0.20, -0.28, null],
            },
      extra: (t) => a.body.position.z = 0.14 * (1 - t),
    );

    // 3. Hamle: Yıkıcı teber saplaması (POV'da teber bıçağı doğrudan rakibin göğsüne uzanır!)
    await _poseTo(
      a,
      0.22,
      fp
          ? {
              'armR': [0.96, -0.26, 0.36],
              'legL': [-0.68, null, null],
              'legR': [0.48, null, null],
              'torso': [0.10, 0.16, null],
            }
          : {
              'armR': [1.38, -0.10, null],
              'legL': [-0.62, null, null],
              'legR': [0.52, null, null],
              'torso': [0.28, 0.28, null],
            },
      ease: easeOut,
      extra: (t) => a.body.position.z = (fp ? 0.18 : 0.22) * easeOut(t),
    );
    _playSfx(SfxKind.clashSteel);
    _fx.slash(hit, pal.glow, a.root.rotation.y.toDouble(), tilt: 0.45, size: 0.62);
    _fx.burst(hit, [pal.glow, 0xFFFFFF, pal.metal], count: 24, speed: 2.5, size: 0.044);
    _fx.flash(hit, pal.glow, intensity: 14);
    final death = _kill(v, DeathMode.topple, dir, a.team);
    await _anim.wait(0.28, kind: AnimKind.combat);
    await _blendToRest(a, 0.34, AnimKind.combat);
    await death;
  }

  /// 2. Suikastçi Düellosu: Çapraz Kukri Çarpışması -> Ters Kesik -> İkiz X-Biçme!
  Future<void> _strikeAssassin(
    CreatureRig a,
    CreatureRig v,
    P3 vp,
    P3 dir, {
    required bool inPov,
  }) async {
    final pal = Palette.of(a.team);
    final hit = _chest(vp, v.kind == PieceType.rook ? 1.15 : 0.60);
    final yaw = a.root.rotation.y.toDouble();

    // 1. Hamle: Sol kadrajdaki kukri ile hızlı çapraz ilk kesik
    await _poseTo(
      a,
      0.26,
      inPov
          ? {
              'armR': [-0.82, 0.22, -0.36],
              'armL': [-0.18, 0.24, 0.18],
              'legL': [-0.52, null, null],
              'legR': [0.42, null, null],
              'torso': [-0.06, -0.16, null],
            }
          : {
              'armR': [-2.1, 0.25, null],
              'armL': [-0.9, -0.25, null],
              'legL': [-0.48, null, null],
              'legR': [0.45, null, null],
              'torso': [-0.14, -0.24, null],
            },
    );
    await _poseTo(
      a,
      0.16,
      inPov
          ? {
              'armR': [0.05, -0.46, 0.28],
              'torso': [0.08, 0.18, null],
            }
          : {
              'armR': [-0.25, -0.30, null],
              'torso': [0.20, 0.28, null],
            },
      ease: easeOut,
    );
    _fx.slash(hit, pal.glow, yaw, tilt: -0.65, size: 0.54);
    await _staggerDefender(v, hit, pal.glow);

    // 2. Hamle: Sağ kadrajdaki kukri ile ters çapraz darbe
    _playSfx(SfxKind.slashBlade);
    await _poseTo(
      a,
      0.22,
      inPov
          ? {
              'armL': [-0.84, -0.22, 0.36],
              'armR': [-0.24, -0.16, -0.14],
              'torso': [-0.05, 0.16, null],
            }
          : {
              'armL': [-2.15, -0.25, null],
              'armR': [-0.85, 0.20, null],
              'torso': [-0.12, 0.26, null],
            },
    );
    await _poseTo(
      a,
      0.16,
      inPov
          ? {
              'armL': [0.05, 0.46, -0.28],
              'torso': [0.08, -0.16, null],
            }
          : {
              'armL': [-0.20, 0.32, null],
              'torso': [0.22, -0.24, null],
            },
      ease: easeOut,
    );
    _fx.slash(hit + const P3(0, 0.06, 0), 0xFFFFFF, yaw, tilt: 0.68, size: 0.56);
    _fx.burst(hit, [pal.blood, pal.glow], count: 16, speed: 1.9, size: 0.036);

    // 3. Hamle: İkiz bıçak X-infaz darbesi!
    await _poseTo(
      a,
      0.26,
      inPov
          ? {
              'armR': [-0.88, 0.28, -0.42],
              'armL': [-0.88, -0.28, 0.42],
              'torso': [-0.08, 0.0, null],
            }
          : {
              'armR': [-2.35, 0.35, -0.35],
              'armL': [-2.35, -0.35, 0.35],
              'torso': [-0.18, 0.0, null],
            },
      extra: (t) => a.body.position.y = 0.10 * t,
    );

    await _anim.play(
      0.28,
      (t) {
        if (!inPov) {
          a.body.rotation.y = smooth(t) * math.pi * 2;
        }
        final k = easeOut(t);
        if (inPov) {
          _setRot(a, 'armR', x: -0.88 + 0.96 * k, y: 0.28 - 0.72 * k, z: -0.42 + 0.72 * k);
          _setRot(a, 'armL', x: -0.88 + 0.96 * k, y: -0.28 + 0.72 * k, z: 0.42 - 0.72 * k);
        } else {
          _setRot(a, 'armR', x: -2.35 + 2.1 * k, z: -0.35 + 0.65 * k);
          _setRot(a, 'armL', x: -2.35 + 2.1 * k, z: 0.35 - 0.65 * k);
        }
        a.body.position.y = 0.10 * (1 - t);
        a.body.position.z = 0.15 * math.sin(math.pi * t);
      },
      kind: AnimKind.combat,
    );
    a.body.rotation.y = 0;

    _playSfx(SfxKind.slashBlade);
    _fx.slash(hit + const P3(0, -0.06, 0), pal.glow, yaw + math.pi / 2, tilt: 0.12, size: 0.66);
    _fx.slash(hit + const P3(0, 0.05, 0), 0xFFFFFF, yaw, tilt: -0.78, size: 0.52);
    _fx.burst(hit, [pal.blood, pal.glow, 0xFFFFFF], count: 28, speed: 2.5, size: 0.042);
    _fx.flash(hit, pal.glow, intensity: 16);
    final death = _kill(v, DeathMode.slash, !inPov ? dir * -1 : dir, a.team);
    await _anim.wait(0.24, kind: AnimKind.combat);
    await _blendToRest(a, 0.32, AnimKind.combat);
    await death;
  }

  /// 3. Ejderha Düellosu: Kanat Fırtınası & Pençe Sarsıntısı -> Uzun Ejder Ateşi Nefesi!
  Future<void> _strikeDragon(CreatureRig a, CreatureRig v, P3 vp, P3 dir) async {
    final pal = Palette.of(a.team);
    final target = _chest(vp, v.kind == PieceType.rook ? 1.15 : 0.48);
    final fp = a.inPov;

    // 1. Hamle: Kanat fırtınası ve pençe savuruşu ile rakibi sendeletme
    _playSfx(SfxKind.wingFlap);
    await _poseTo(a, 0.42, {
      'torso': [fp ? -0.10 : -0.36, null, null],
      'neck': [-0.42, null, null],
      'wingL': [null, null, 1.08],
      'wingR': [null, null, -1.08],
      'armL': [-0.78, null, null],
      'armR': [-0.78, null, null],
      'jaw': [0.58, null, null],
    }, extra: (t) => a.body.position.y = 0.14 * smooth(t));
    await _staggerDefender(v, target, pal.fire);

    // 2. Hamle: Boğazda kor ateşin toplanması ve kesintisiz ejder ateşi seli!
    a.parts['mouthGlow']?.visible = true;
    _playSfx(SfxKind.dragonFire);
    _fx.flash(_chest(_posOf(a), 0.9), pal.fire, intensity: 12, life: 1.4);
    Future<void>? death;
    final mouth = a.parts['mouth']!;
    final fireColors = [pal.fireCore, pal.fire, pal.fire, mixColor(pal.fire, 0xFF2200, 0.5)];
    await _anim.play(
      1.35,
      (t) {
        final lunge = easeOut(math.min(1.0, t * 3.5));
        _setRot(a, 'torso', x: fp ? (-0.10 + 0.16 * lunge) : (-0.36 + 0.48 * lunge));
        _setRot(a, 'neck', x: -0.42 + 0.68 * lunge);
        final flap = math.sin(t * 16) * 0.26;
        _setRot(a, 'wingL', z: 1.02 + flap);
        _setRot(a, 'wingR', z: -1.02 - flap);
        _setRot(a, 'armL', x: -0.52 + 0.22 * math.sin(t * 12));
        _setRot(a, 'armR', x: -0.52 - 0.22 * math.sin(t * 12));
        final mp = _worldToPlay(P3.of(mouth.getWorldPosition(three.Vector3())));
        if (t < 0.92) {
          for (var k = 0; k < 4; k++) {
            final aim = target + P3(_fx.r(0.20), _fx.r(0.20), _fx.r(0.20));
            final vel = (aim - mp) * (2.0 + _fx.rng.nextDouble() * 0.65);
            _fx.spawn(
              mp,
              color: fireColors[_fx.rng.nextInt(fireColors.length)],
              velocity: vel + P3(_fx.r(0.25), _fx.r(0.25), _fx.r(0.25)),
              life: 0.44 + _fx.rng.nextDouble() * 0.16,
              size: 0.044,
              endSize: 0.18 + _fx.rng.nextDouble() * 0.07,
              drag: 0.3,
            );
          }
        }
        if (t > 0.28 && death == null) death = _kill(v, DeathMode.burn, dir, a.team);
      },
      kind: AnimKind.combat,
    );
    a.parts['mouthGlow']?.visible = false;
    await _blendToRest(a, 0.36, AnimKind.combat);
    await (death ?? Future.value());
  }

  /// 4. Kadın Savaş Devi (Valkür Titan) Düellosu: Kol Kalkanı Darbesi -> Yeri Yaran Balyoz İnfazı!
  Future<void> _strikeGiantess(CreatureRig a, CreatureRig v, P3 vp, P3 dir) async {
    final pal = Palette.of(a.team);
    final hit = _chest(vp, v.kind == PieceType.rook ? 1.15 : 0.56);
    final fp = a.inPov;

    // 1. Hamle: Dikenli Valkür kol kalkanıyla düşman gardını savurma!
    await _poseTo(
      a,
      0.34,
      fp
          ? {
              'armL': [-0.62, 0.10, 0.18],
              'armR': [0.35, -0.05, 0.18],
              'legL': [-0.54, null, null],
              'legR': [0.36, null, null],
              'torso': [0.06, 0.16, null],
            }
          : {
              'armL': [-1.15, -0.42, null],
              'armR': [-0.75, null, null],
              'legL': [-0.44, null, null],
              'legR': [0.36, null, null],
              'torso': [0.16, 0.30, null],
            },
      extra: (t) => a.body.position.z = 0.14 * smooth(t),
    );
    await _staggerDefender(v, hit, pal.metal);

    // 2. Hamle: Altın kuşaklı dev savaş balyozunu göz önünde yukarı kaldırıp güç toplama!
    await _poseTo(
      a,
      0.50,
      fp
          ? {
              'armR': [-0.22, 0.08, 0.16],
              'armL': [-0.48, -0.46, -0.14],
              'legL': [-0.52, null, null],
              'legR': [0.42, null, null],
              'torso': [-0.08, -0.14, null],
            }
          : {
              'armR': [-2.62, 0.12, null],
              'armL': [-0.85, -0.18, null],
              'legL': [-0.48, null, null],
              'legR': [0.42, null, null],
              'torso': [-0.28, -0.20, null],
            },
      extra: (t) => a.body.position.y = 0.08 * smooth(t),
    );

    // 3. Hamle: Yeryüzünü çatlatan balyoz inişi (POV'da dev balyoz başı doğrudan düşmanın üstüne iner!)
    await _poseTo(
      a,
      0.18,
      fp
          ? {
              'armR': [0.92, -0.24, 0.38],
              'armL': [-0.36, -0.35, -0.10],
              'torso': [0.12, 0.14, null],
            }
          : {
              'armR': [-0.26, -0.06, null],
              'armL': [-0.38, null, null],
              'torso': [0.42, 0.18, null],
            },
      ease: easeIn,
      extra: (t) {
        a.body.position.y = 0.08 * (1 - t);
        a.body.position.z = 0.16 * t;
      },
    );
    _playSfx(SfxKind.maulSmash);
    _fx.shockwave(vp, pal.glow, radius: 2.85, life: 0.58);
    _fx.shockwave(vp, 0xC9B9A0, radius: 1.85, life: 0.48);
    _fx.burst(vp + const P3(0, 0.22, 0), [0x6E6A66, 0x8C7B6A, pal.glow],
        count: 36, speed: 4.2, size: 0.080, shards: true, glow: false, gravity: -8);
    _fx.smoke(vp, 0x9A8F80, count: 22, radius: 0.95);
    _fx.flash(_chest(vp, 0.5), pal.glow, intensity: 22);
    _fx.addShake(fp ? 0.26 : 0.42);
    final death = _kill(v, DeathMode.crush, dir, a.team);
    await _anim.wait(0.32, kind: AnimKind.combat);
    await _blendToRest(a, 0.38, AnimKind.combat);
    await death;
  }

  /// 5. Vampir Kraliçe Düellosu: Kan Mührü Halkası -> Yarasa Sürüsü & Yaşam Özü Çekimi!
  Future<void> _strikeVampire(CreatureRig a, CreatureRig v, P3 vp, P3 dir) async {
    final pal = Palette.of(a.team);
    final hit = _chest(vp, v.kind == PieceType.rook ? 1.15 : 0.52);
    final fp = a.inPov;

    // 1. Hamle: Kan kadehi asasını ve pençeli eli kaldırıp düşmanın altında kızıl mühür patlatma
    _playSfx(SfxKind.magicGlide);
    await _poseTo(
      a,
      0.44,
      fp
          ? {
              'armL': [-0.46, 0.24, 0.18],
              'armR': [0.22, -0.18, 0.28],
              'legL': [-0.32, null, null],
              'legR': [0.26, null, null],
            }
          : {
              'armL': [-1.25, -0.22, 0.65],
              'armR': [-1.68, 0.18, null],
              'legL': [-0.22, null, null],
              'legR': [0.22, null, null],
              'cape': [-0.58, null, null],
            },
      extra: (t) => a.body.position.y = 0.20 * smooth(t),
    );
    _fx.shockwave(vp, pal.blood, radius: 1.15, life: 0.55);
    await _staggerDefender(v, hit, pal.blood);

    // 2. Hamle: Yarasa sürüsü saldırısı ve sağ eldeki Kan Küresine akan kızıl yaşam özü!
    _playSfx(SfxKind.bloodDrain);
    final swarm = <three.Group>[];
    for (var i = 0; i < 6; i++) {
      final bat = _factory.makeBat(pal, size: 1.28);
      _fx.layer.add(bat);
      swarm.add(bat);
    }
    final orbObj = a.parts['orb'];
    final startFallback = _chest(_posOf(a), 0.92);
    _fx.flash(hit, pal.blood, intensity: 15, life: 1.35);
    Future<void>? death;
    await _anim.play(
      1.35,
      (t) {
        final drainTarget = orbObj != null
            ? _worldToPlay(P3.of(orbObj.getWorldPosition(three.Vector3())))
            : startFallback;
        for (var i = 0; i < swarm.length; i++) {
          final bat = swarm[i];
          final arrive = math.min(1.0, t * 2.2);
          final ang = t * 9.5 + i * math.pi / 3;
          final rad = 0.36 + 0.08 * math.sin(t * 6 + i);
          final circle =
              hit + P3(math.cos(ang) * rad, 0.16 * math.sin(t * 8 + i * 2), math.sin(ang) * rad);
          final p = P3.lerp(drainTarget, circle, smooth(arrive));
          bat.position.setValues(p.x, p.y, p.z);
          bat.rotation.y = -ang;
          for (final w in bat.children) {
            final side = w.userData['side'];
            if (side is double) w.rotation.z = side * 0.8 * math.sin(t * 40 + i);
          }
        }
        for (var k = 0; k < 3; k++) {
          final from = hit + P3(_fx.r(0.26), _fx.r(0.30), _fx.r(0.26));
          final vel = (drainTarget - from) * 1.85;
          _fx.spawn(from,
              color: k == 0 ? 0xFF3050 : pal.blood,
              velocity: vel,
              life: 0.52,
              size: 0.036,
              endSize: 0.010);
        }
        final s = 0.044 * (1.35 + 0.55 * math.sin(t * 20));
        orbObj?.scale.setValues(s, s, s);
        if (t > 0.25 && death == null) {
          death = _kill(v, DeathMode.drain, dir, a.team);
        }
      },
      kind: AnimKind.combat,
    );
    for (final bat in swarm) {
      _fx.burst(P3.of(bat.position), [pal.blood], count: 4, speed: 1, size: 0.03, gravity: 0);
      _fx.layer.remove(bat);
    }
    await _blendToRest(a, 0.36, AnimKind.combat);
    await (death ?? Future.value());
  }

  /// 6. Barbar Kral Düellosu: Savaş Borusu & Yatay Balta Yarma -> Havaya Fırlatan İnfaz!
  Future<void> _strikeBarbarian(
    CreatureRig a,
    CreatureRig v,
    P3 vp,
    P3 dir, {
    required bool inPov,
  }) async {
    final pal = Palette.of(a.team);
    final hit = _chest(vp, v.kind == PieceType.rook ? 1.15 : 0.54);
    final yaw0 = a.root.rotation.y.toDouble();
    final from = _posOf(a);

    // 1. Hamle: Fildişi savaş borusunu kaldırıp yatay hilal balta darbesiyle gardı kırma!
    await _poseTo(
      a,
      0.36,
      inPov
          ? {
              'armL': [-0.62, 0.24, 0.20],
              'armR': [0.22, 0.25, 0.08],
              'legL': [-0.48, null, null],
              'legR': [0.38, null, null],
              'torso': [-0.06, -0.18, null],
            }
          : {
              'armL': [-1.45, -0.25, 0.35],
              'armR': [-1.55, 0.45, -0.55],
              'legL': [-0.42, null, null],
              'legR': [0.38, null, null],
              'torso': [-0.14, -0.32, null],
            },
    );
    await _poseTo(
      a,
      0.20,
      inPov
          ? {
              'armR': [0.76, -0.42, 0.42],
              'torso': [0.08, 0.20, null],
            }
          : {
              'armR': [-0.65, -0.45, 0.25],
              'torso': [0.18, 0.34, null],
            },
      ease: easeOut,
    );
    _fx.slash(hit, pal.glow, yaw0, tilt: 0.08, size: 0.78, life: 0.42);
    await _staggerDefender(v, hit, pal.glow);

    // 2. Hamle: Çift ağızlı hilal baltayı yukarı kaldırıp yıkıcı infaz darbesi!
    await _poseTo(
      a,
      0.42,
      inPov
          ? {
              'armR': [-0.18, 0.05, 0.16],
              'armL': [-0.36, 0.14, 0.18],
              'legL': [-0.52, null, null],
              'legR': [0.42, null, null],
              'torso': [-0.08, 0.0, null],
            }
          : {
              'armR': [-2.50, 0.0, null],
              'armL': [-0.85, null, 0.45],
              'legL': [-0.46, null, null],
              'legR': [0.44, null, null],
              'torso': [-0.26, 0.0, null],
            },
      extra: (t) => a.body.position.y = 0.14 * smooth(t),
    );

    if (!inPov) {
      await _anim.play(
        0.38,
        (t) {
          a.root.rotation.y = yaw0 + math.pi * 2 * smooth(t);
          _place(a, from + dir * (0.14 * t));
        },
        kind: AnimKind.combat,
      );
      a.root.rotation.y = yaw0;
    }

    _playSfx(SfxKind.axeCleave);
    await _poseTo(
      a,
      0.18,
      inPov
          ? {
              'armR': [0.92, -0.20, 0.36],
              'torso': [0.12, 0.0, null],
            }
          : {
              'armR': [-0.35, 0.0, _rest(a, 'armR', 'rz')],
              'torso': [0.42, 0.0, null],
            },
      ease: easeIn,
      extra: (t) => a.body.position.y = 0.14 * (1 - t),
    );

    _fx.burst(hit, [pal.metal, pal.glow, 0xFFFFFF], count: 32, speed: 3.2, size: 0.050);
    _fx.shockwave(vp, pal.glow, radius: 1.35);
    _fx.slash(hit, 0xFFFFFF, yaw0 + math.pi / 2, tilt: math.pi / 2, size: 0.64);
    _fx.flash(hit, pal.glow, intensity: 19);
    _fx.addShake(0.24);
    final death = _kill(v, DeathMode.launch, dir, a.team);
    await _anim.wait(0.28, kind: AnimKind.combat);
    await _blendToRest(a, 0.36, AnimKind.combat);
    await death;
  }

  // ================================================================ ÖLÜM EFEKTLERİ (PBR KORUMALI)
  void _tintDeath(
    three.MeshStandardMaterial mat, {
    int? toward,
    double k = 0,
    int? emissive,
    double? opacity,
  }) {
    if (toward != null) {
      setHexRgb(mat.color, mixColor(0xFFFFFF, toward, k));
    }
    if (emissive != null && mat.emissive != null) {
      setHexRgb(mat.emissive!, emissive);
    }
    if (opacity != null) {
      mat.opacity = opacity;
    }
  }

  Future<void> _fadeOut(
    three.MeshStandardMaterial mat,
    double dur, [
    void Function(double t)? extra,
  ]) {
    return _anim.play(
      dur,
      (t) {
        _tintDeath(mat, opacity: 1 - t);
        extra?.call(t);
      },
      kind: AnimKind.combat,
    );
  }

  Future<void> _kill(CreatureRig v, DeathMode mode, P3 dir, Team killer) async {
    v.busy = true;
    v.dying = true;
    final mat = _factory.isolateForDeath(v);
    final pal = Palette.of(v.team);
    final kp = Palette.of(killer);
    final base = _posOf(v);
    final b = v.body;
    final bs = v.baseScale;

    await _anim.play(
      0.14,
      (t) {
        final c = mixColor(0x777777, 0x000000, t);
        _tintDeath(mat, emissive: c);
        b.position.x = math.sin(t * 40) * 0.032;
      },
      kind: AnimKind.combat,
    );
    _tintDeath(mat, emissive: 0);
    b.position.x = 0;

    switch (mode) {
      case DeathMode.topple:
        await _anim.play(
          0.56,
          (t) {
            b.rotation.x = -1.45 * easeIn(t);
            b.position.z = -0.16 * t;
          },
          kind: AnimKind.combat,
        );
        _fx.smoke(base, 0x8D8478, count: 8, radius: 0.46);
        await _fadeOut(mat, 0.38, (t) => b.position.y = -0.14 * t);
      case DeathMode.slash:
        await _anim.play(0.16, (t) => b.rotation.x = -0.24 * t, kind: AnimKind.combat);
        await _anim.play(
          0.48,
          (t) {
            b.rotation.z = 1.48 * easeIn(t);
            b.rotation.x = -0.24 * (1 - t);
            if (_fx.rng.nextDouble() < 0.45) {
              _fx.spawn(_chest(base, 0.5),
                  color: kp.blood,
                  velocity: P3(_fx.r(1), 1.2, _fx.r(1)),
                  life: 0.48,
                  size: 0.030,
                  gravity: -4);
            }
          },
          kind: AnimKind.combat,
        );
        _fx.smoke(base, 0x2A2633, count: 8, radius: 0.46);
        await _fadeOut(mat, 0.34);
      case DeathMode.burn:
        var ash = false;
        await _anim.play(
          1.05,
          (t) {
            final flicker = 0.5 + 0.5 * math.sin(t * 45);
            _tintDeath(
              mat,
              toward: 0x160C08,
              k: t,
              emissive: mixColor(0x000000, kp.fire, flicker * (1 - t) * 0.85),
            );
            b.scale.setValues(bs * (1 + 0.05 * t), bs * (1 - 0.28 * t), bs * (1 + 0.05 * t));
            if (_fx.rng.nextDouble() < 0.75) {
              _fx.spawn(
                base + P3(_fx.r(0.24), 0.2 + _fx.rng.nextDouble() * 0.75, _fx.r(0.24)),
                color: _fx.rng.nextBool() ? kp.fire : kp.fireCore,
                velocity: P3(_fx.r(0.2), 0.9 + _fx.rng.nextDouble(), _fx.r(0.2)),
                life: 0.58,
                size: 0.048,
                endSize: 0.0,
              );
            }
            if (t > 0.62) _tintDeath(mat, opacity: 1 - (t - 0.62) / 0.38);
            if (t > 0.65 && !ash) {
              ash = true;
              _fx.burst(base + const P3(0, 0.4, 0), [0x2A2522, 0x4A403A, kp.fire],
                  count: 26, speed: 1.4, size: 0.038, shards: true, glow: false, gravity: -3);
            }
          },
          kind: AnimKind.combat,
        );
      case DeathMode.crush:
        await _anim.play(
          0.16,
          (t) {
            final k = easeOut(t);
            b.scale.setValues(bs * (1 + 0.48 * k), bs * (1 - 0.82 * k), bs * (1 + 0.48 * k));
          },
          kind: AnimKind.combat,
        );
        _fx.burst(base + const P3(0, 0.1, 0), [pal.armor, pal.metal, pal.dark],
            count: 22, speed: 2.3, size: 0.048, shards: true, glow: false, gravity: -7);
        await _anim.wait(0.24, kind: AnimKind.combat);
        await _fadeOut(mat, 0.42, (t) => b.scale.y = bs * (0.18 * (1 - t) + 0.02));
      case DeathMode.drain:
        await _anim.play(
          1.05,
          (t) {
            final pulse = 0.5 + 0.5 * math.sin(t * 30);
            _tintDeath(
              mat,
              toward: 0xD8D4E4,
              k: t,
              emissive: mixColor(0, kp.blood, pulse * 0.55 * (1 - t)),
            );
            b.position.y = 0.36 * smooth(t);
            b.rotation.y = t * t * 5.5;
            final s = bs * (1 - 0.52 * t);
            b.scale.setValues(s, s, s);
          },
          kind: AnimKind.combat,
        );
        _fx.burst(_chest(base, 0.7), [kp.blood, 0xFF3050, 0x2A0A14],
            count: 26, speed: 2.0, size: 0.042, gravity: -1);
        await _fadeOut(mat, 0.28, (t) {
          final s = bs * (0.48 * (1 - t) + 0.01);
          b.scale.setValues(s, s, s);
        });
      case DeathMode.launch:
        await _anim.play(
          0.72,
          (t) {
            final p = base + dir * (1.38 * easeOut(t)) + P3(0, math.sin(math.pi * t) * 0.90, 0);
            _place(v, p);
            b.rotation.x = -t * 5.2;
            b.rotation.z = t * 1.4;
          },
          kind: AnimKind.combat,
        );
        final land = _posOf(v);
        _fx.shockwave(land, 0xC9B9A0, radius: 0.80, life: 0.36);
        _fx.burst(land + const P3(0, 0.2, 0), [pal.armor, pal.metal],
            count: 16, speed: 1.8, size: 0.046, shards: true, glow: false, gravity: -6);
        _fx.addShake(0.12);
        await _fadeOut(mat, 0.34);
    }

    final soul = _posOf(v) + const P3(0, 0.55, 0);
    for (var i = 0; i < 5; i++) {
      _fx.spawn(
        soul + P3(_fx.r(0.1), i * 0.08, _fx.r(0.1)),
        color: pal.glow,
        velocity: P3(0, 1.0 + i * 0.14, 0),
        life: 0.82,
        size: 0.055,
        endSize: 0,
      );
    }
    _pieceLayer.remove(v.root);
  }

  // ================================================================ TERFİ & ŞAH-MAT FİNALİ
  Future<void> _promote(HexCell cell, Team team, PieceType targetKind) async {
    final old = _rigs[cell];
    if (old == null) return;
    final pal = Palette.of(team);
    final p = _cellPos(cell);
    _fx.pillar(p, pal.glow, life: 1.1);
    _fx.flash(_chest(p, 0.8), pal.glow, intensity: 18, life: 0.9);
    await _anim.play(
      0.36,
      (t) {
        final s = math.max(0.001, 1 - easeIn(t));
        old.body.scale.setValues(s, s, s);
        old.body.rotation.y = t * 7;
      },
      kind: AnimKind.combat,
    );
    _pieceLayer.remove(old.root);
    _rigs.remove(cell);
    _fx.burst(_chest(p, 0.6), [pal.glow, pal.blood, 0xFFFFFF],
        count: 30, speed: 2.2, size: 0.048, gravity: -1);
    final promoted = _spawnRig(ChessPiece(team, targetKind), cell);
    promoted.busy = true;
    promoted.body.scale.setValues(0.001, 0.001, 0.001);
    _playSfx(SfxKind.magicGlide);
    _message = 'Kalkan Muhafızı, ${targetKind.creature} sınıfına yükseldi!';
    if (mounted) setState(() {});
    await _anim.play(
      0.46,
      (t) {
        final s = math.max(0.001, easeOutBack(t));
        promoted.body.scale.setValues(
          promoted.baseScale * s,
          promoted.baseScale * s,
          promoted.baseScale * s,
        );
      },
      kind: AnimKind.combat,
    );
    promoted.body.scale.setValues(
      promoted.baseScale,
      promoted.baseScale,
      promoted.baseScale,
    );
    promoted.busy = false;
  }

  Future<void> _checkmateFinale(int gen) async {
    if (game.isThreePlayer) {
      final survIdx = game.pos3.soleSurvivor;
      if (survIdx == null) return;
      final winner = Team.values[survIdx];
      final wpal = Palette.of(winner);
      _playSfx(SfxKind.clashSteel);
      final kCell = game.kingCellOf(winner);
      if (kCell != null) {
        final kp = _cellPos(kCell);
        _fx.pillar(kp, wpal.glow, life: 1.5, height: 4.0);
        _fx.flash(_chest(kp, 1.0), wpal.glow, intensity: 22, life: 1.3);
      }
      final winners = _rigs.values.where((r) => r.team == winner).toList();
      for (final r in winners) {
        r.busy = true;
      }
      await _anim.play(
        1.2,
        (t) {
          for (final r in winners) {
            r.body.position.y = (math.sin((t * 3 + r.phase / 6) * math.pi * 2)).abs() * 0.15;
          }
        },
        kind: AnimKind.combat,
      );
      for (final r in winners) {
        r.body.position.y = 0;
        r.busy = false;
      }
      return;
    }

    final k = game.pos.kingOf(game.pos.side);
    if (k < 0) return;
    final king = _rigs[Position.cellOf(k)];
    if (king == null) return;
    king.busy = true;
    final mat = _factory.isolateForDeath(king);
    final base = _posOf(king);
    final winner = king.team == Team.white ? Team.black : Team.white;
    final wpal = Palette.of(winner);
    _playSfx(SfxKind.clashSteel);
    _fx.pillar(base, wpal.glow, life: 1.4, height: 3.8);
    _fx.flash(_chest(base, 1.0), wpal.glow, intensity: 20, life: 1.2);
    await _anim.play(
      1.05,
      (t) {
        _tintDeath(mat, toward: 0x4E5058, k: t);
        king.body.rotation.x = 1.22 * easeIn(t);
        king.body.position.y = -0.10 * t;
      },
      kind: AnimKind.combat,
    );
    if (gen != _generation) return;
    _fx.burst(_chest(base, 0.3), [0x55555C, wpal.glow],
        count: 26, speed: 1.5, size: 0.048, gravity: -3);
    final winners = _rigs.values.where((r) => r.team == winner).toList();
    for (final r in winners) {
      r.busy = true;
    }
    await _anim.play(
      1.1,
      (t) {
        for (final r in winners) {
          r.body.position.y = (math.sin((t * 3 + r.phase / 6) * math.pi * 2)).abs() * 0.14;
        }
      },
      kind: AnimKind.combat,
    );
    for (final r in winners) {
      r.body.position.y = 0;
      r.busy = false;
    }
  }

  // ================================================================ MOBİL ALT PANELLER (SLIDER'LAR & AYARLAR)
  Future<PieceType?> _askPromotionChoice(Team team) {
    const choices = [
      (PieceType.queen, 'Uzun menzilli büyü ve yaşam özü emişi'),
      (PieceType.rook, 'Düz hatlarda yıkıcı Valkür savaş balyozu'),
      (PieceType.bishop, 'Çapraz hatlarda uçan ejder ateşi'),
      (PieceType.knight, 'Engellerin arkasına gölge sıçrayışı'),
    ];
    return showModalBottomSheet<PieceType>(
      context: context,
      backgroundColor: const Color(0xFF0E1524),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Savaşçı Terfisi Seç',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Son hatta ulaşan Kalkan Muhafızı hangi sınıfa yükselsin?',
                style: TextStyle(fontSize: 12.5, color: Color(0xFFA8B4CA)),
              ),
              const SizedBox(height: 12),
              for (final (kind, desc) in choices)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  leading: CreatureBadge(kind: kind, team: team, size: 42),
                  title: Text(kind.creature, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle:
                      Text(desc, style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8C0))),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFD4A854)),
                  onTap: () => Navigator.pop(ctx, kind),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedSlidersSection(void Function(void Function()) setSheet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.directions_walk_rounded, size: 16, color: Color(0xFF5CE1FF)),
            const SizedBox(width: 6),
            const Text('HAREKET HIZI',
                style: TextStyle(fontSize: 11, letterSpacing: 1.1, color: Color(0xFFC8A464))),
            const Spacer(),
            Text(
              '${_moveSpeed.toStringAsFixed(2)}x',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF5CE1FF)),
            ),
          ],
        ),
        Slider(
          value: _moveSpeed,
          min: 0.35,
          max: 2.20,
          divisions: 37,
          activeColor: const Color(0xFF5CE1FF),
          onChanged: (v) {
            setState(() {
              _moveSpeed = v;
              _anim.moveSpeed = v;
            });
            _persistSettings();
            setSheet(() {});
          },
        ),
        Row(
          children: [
            const Icon(Icons.sports_martial_arts_rounded, size: 16, color: Color(0xFFFF6B57)),
            const SizedBox(width: 6),
            const Text('DÖVÜŞ HIZI (KOREOGRAFİ)',
                style: TextStyle(fontSize: 11, letterSpacing: 1.1, color: Color(0xFFC8A464))),
            const Spacer(),
            Text(
              '${_combatSpeed.toStringAsFixed(2)}x',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFFFF8866)),
            ),
          ],
        ),
        Slider(
          value: _combatSpeed,
          min: 0.30,
          max: 2.00,
          divisions: 34,
          activeColor: const Color(0xFFFF6B57),
          onChanged: (v) {
            setState(() {
              _combatSpeed = v;
              _anim.combatSpeed = v;
            });
            _persistSettings();
            setSheet(() {});
          },
        ),
        const SizedBox(height: 4),
        AtmosphereSlider(
          icon: Icons.sports_kabaddi_rounded,
          color: const Color(0xFFFFA24A),
          title: 'KAPIŞMA TURU (DÜELLO UZUNLUĞU)',
          value: _duelRounds,
          sliderMax: AtmosphereLimits.duelRoundsSlider,
          divisions: 8,
          unit: AtmosphereUnit.rounds,
          offLabel: 'Tek çarpışma',
          describe: _duelLabel,
          onChanged: (v) {
            _duelRounds = v.roundToDouble();
            _persistSettings();
            setSheet(() {});
          },
        ),
        AtmosphereSlider(
          icon: Icons.auto_awesome_motion_rounded,
          color: const Color(0xFFE879F9),
          title: 'DÜELLO KARMAŞIKLIĞI (SADE ↔ DESTANSI)',
          value: _duelComplexity,
          sliderMax: AtmosphereLimits.duelComplexitySlider,
          divisions: 4,
          unit: AtmosphereUnit.level,
          offLabel: 'Sv. 0 · Sade',
          describe: _duelComplexityLabel,
          onChanged: (v) {
            _duelComplexity = v.roundToDouble();
            _persistSettings();
            setSheet(() {});
          },
        ),
        Text(
          _duelComplexityHint(_duelComplexity),
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF98A8C2)),
        ),
        const SizedBox(height: 2),
        const Text(
          'Kapışma Turu kaç tur süreceğini, Karmaşıklık her turun ne kadar sade/kısa ya da '
          'uzun/karmaşık olacağını belirler. Düello sürerken ekrana dokunursan son darbeye geçilir.',
          style: TextStyle(fontSize: 10.5, color: Color(0xFF98A8C2)),
        ),
      ],
    );
  }

  static String? _duelComplexityLabel(double v) => switch (v.round()) {
        <= 0 => 'Sade',
        1 => 'Klasik',
        2 => 'Usta',
        3 => 'Büyük Usta',
        4 => 'Destansı',
        _ => 'Efsanevi',
      };

  static String _duelComplexityHint(double v) {
    final lv = v.isFinite ? math.max(0, v.round()) : 2;
    return switch (lv) {
      0 => 'Sade: tek vuruş–savuşturma ve karşı atak; kısa ve hızlı turlar.',
      1 => 'Klasik: + kılıç kilitlenmesi, eğilip kaçma ve karşılık.',
      2 => 'Usta: + 2 vuruşluk kombolar, aldatmaca, birbirinin etrafında dönme.',
      3 => 'Büyük Usta: + 3 vuruşluk kombo, kalkan/tekme darbesi, diz çöktürme; turda 2 kapışma.',
      4 => 'Destansı: + 4 vuruşluk kombo ve havadan sıçrayış darbesi; turda 2 kapışma.',
      _ => 'Efsanevi: $lv vuruşluk kombolar, turda ${1 + (lv - 1) ~/ 2} kapışma; her seviye daha da uzatır.',
    };
  }

  static String? _duelLabel(double v) {
    if (v < 3) return 'Kısa Düello';
    if (v < 6) return 'Uzun Kapışma';
    if (v <= 8) return 'Destansı Düello';
    return 'Bitmeyen Savaş';
  }

  /// Tek bir ses kanalı satırı: simge, başlık/açıklama, yüzde, aç/kapa kutusu ve
  /// kendi kaydırıcısı. Kanal kapalıyken kaydırıcı soluk ve devre dışıdır.
  Widget _buildVolumeChannel({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool enabled,
    required double value,
    required ValueChanged<bool> onToggle,
    required ValueChanged<double> onChanged,
    Widget? action,
  }) {
    const muted = Color(0xFF7E8EA8);
    final tint = enabled ? color : muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, letterSpacing: 1.1, color: Color(0xFFC8A464))),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF93A3BE))),
                  ],
                ),
              ),
              if (action != null) action,
              const SizedBox(width: 4),
              Text(
                enabled ? '%${(value * 100).round()}' : 'Kapalı',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: tint),
              ),
              Checkbox(
                value: enabled,
                activeColor: color,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => onToggle(v ?? true),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.18),
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.14),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Ayarlar sayfasındaki ses karışımı: müzik, konuşma, efekt ve atmosfer
  /// kanallarının her biri kendi kaydırıcısıyla bağımsız ayarlanır.
  Widget _buildAudioMixerSection(void Function(void Function()) setSheet, int elevenCount) {
    void changed(void Function() fn) {
      setState(fn);
      _persistSettings();
      setSheet(() {});
    }

    void stormChanged(void Function() fn) {
      fn();
      _applyStormAudio();
      _persistSettings();
      setSheet(() {});
    }

    final voiceSubtitle = elevenCount >= 36
        ? 'ElevenLabs: $elevenCount ses (6 karakter × 6 replik kura torbası)'
        : (elevenCount > 0 ? 'ElevenLabs: $elevenCount ses aktif' : 'Yerleşik karakter savaş naraları');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SES KARIŞIMI',
            style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Color(0xFFC8A464))),
        const SizedBox(height: 2),
        const Text(
          'Her kanalın kendi kaydırıcısı var: müzik, konuşmalar, efektler ve atmosfer birbirini etkilemez.',
          style: TextStyle(fontSize: 10.5, color: Color(0xFF98A8C2)),
        ),
        const SizedBox(height: 8),
        _buildVolumeChannel(
          icon: _audio.bgmEnabled ? Icons.music_note_rounded : Icons.music_off_rounded,
          color: const Color(0xFFFFD166),
          title: 'FON MÜZİĞİ',
          subtitle: 'Orkestral karanlık fantezi müziği',
          enabled: _audio.bgmEnabled,
          value: _audio.bgmVolume,
          onToggle: (v) => changed(() => _audio.setBgmEnabled(v)),
          onChanged: (v) => changed(() => _audio.setBgmVolume(v)),
        ),
        _buildVolumeChannel(
          icon: Icons.record_voice_over_rounded,
          color: const Color(0xFF5CE1FF),
          title: 'KARAKTER KONUŞMALARI',
          subtitle: voiceSubtitle,
          enabled: _audio.voiceEnabled,
          value: _audio.voiceVolume,
          onToggle: (v) => changed(() => _audio.voiceEnabled = v),
          onChanged: (v) => changed(() => _audio.setVoiceVolume(v)),
          action: IconButton(
            tooltip: 'Örnek konuşma dinle',
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            color: const Color(0xFF5CE1FF),
            onPressed: _audio.voiceEnabled
                ? () => _audio.previewVoice(PieceType.values[math.Random().nextInt(PieceType.values.length)])
                : null,
            icon: const Icon(Icons.play_circle_outline_rounded),
          ),
        ),
        _buildVolumeChannel(
          icon: Icons.hardware_rounded,
          color: const Color(0xFFFF8866),
          title: 'ADIM & SİLAH SESLERİ',
          subtitle: 'Yürüyüş, çarpışma ve büyü efektleri',
          enabled: _audio.sfxEnabled,
          value: _audio.sfxVolume,
          onToggle: (v) => changed(() => _audio.sfxEnabled = v),
          onChanged: (v) => changed(() => _audio.setSfxVolume(v)),
        ),
        const SizedBox(height: 4),
        AtmosphereSlider(
          icon: Icons.air_rounded,
          color: const Color(0xFF9EC4F0),
          title: 'ATMOSFER: RÜZGÂR & GİZEMLİ UĞULTU',
          value: _ambienceVolume,
          sliderMax: AtmosphereLimits.volumeSlider,
          divisions: 20,
          onChanged: (v) => stormChanged(() => _ambienceVolume = v),
        ),
        AtmosphereSlider(
          icon: Icons.thunderstorm_rounded,
          color: const Color(0xFFB9A4FF),
          title: 'ATMOSFER: GÖK GÜRÜLTÜSÜ',
          value: _thunderVolume,
          sliderMax: AtmosphereLimits.volumeSlider,
          divisions: 20,
          onChanged: (v) => stormChanged(() => _thunderVolume = v),
        ),
      ],
    );
  }

  void _showSpeedSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E1524),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed_rounded, color: Color(0xFFD4A854), size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Hareket & Dövüş Hızı Ayarı',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _moveSpeed = 0.80;
                          _combatSpeed = 0.70;
                          _duelRounds = 4.0;
                          _duelComplexity = 2.0;
                          _anim.moveSpeed = 0.80;
                          _anim.combatSpeed = 0.70;
                        });
                        _persistSettings();
                        setSheet(() {});
                      },
                      child: const Text('Varsayılan'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _buildSpeedSlidersSection(setSheet),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSettingsSheet() {
    final elevenCount = _audio.countAvailableElevenLabsFiles();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1524),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: Color(0xFFD4A854), size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Savaş & Kamera Ayarları',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('MASA DÜZENİ & AMFİ SÜTUNLAR',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Color(0xFFC8A464))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in BoardVariant.values)
                      ChoiceChip(
                        avatar: Icon(
                          v == BoardVariant.threePlayer
                              ? Icons.hexagon_rounded
                              : Icons.safety_divider_rounded,
                          size: 16,
                          color: game.variant == v
                              ? const Color(0xFF34D399)
                              : const Color(0xFFA0AEC6),
                        ),
                        label: Text(v.label, style: const TextStyle(fontSize: 12.5)),
                        selected: game.variant == v,
                        selectedColor: const Color(0xFF1F3D3A),
                        onSelected: (_) {
                          _switchVariant(v);
                          setSheet(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  game.isThreePlayer
                      ? '3 cepheli amfi: Üç ordunun Kral & Kraliçesi en yüksek taht sütunlarında; ortaya ve yan köşelere indikçe sütunlar alçalır. Özel 3\'lü YZ devrede.'
                      : '2 cepheli amfi: Kral & Kraliçe en yüksek altın sütunlarda; ortaya ve yan kanatlara indikçe her altıgen sütun kademeli alçalır.',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF98A8C2)),
                ),
                if (game.isThreePlayer) ...[
                  const SizedBox(height: 10),
                  const Text('3 KİŞİLİK TAHTA BOYUTU',
                      style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Color(0xFFC8A464))),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in BoardSize.values)
                        ChoiceChip(
                          label: Text('${s.label} • ${s.cellCount}',
                              style: const TextStyle(fontSize: 12.5)),
                          selected: game.boardSize3P == s,
                          selectedColor: const Color(0xFF1F3D3A),
                          onSelected: (_) {
                            _switchVariant(BoardVariant.threePlayer, size: s);
                            setSheet(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Ordular her boyutta kendi köşesinden başlar; tahta büyüdükçe aradaki meydan genişler, savaş yavaşlar. Boyut değişince yeni savaş kurulur.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF98A8C2)),
                  ),
                ],
                const Divider(height: 16, color: Color(0xFF202E46)),
                // POV Modu Checkbox
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: const Color(0xFFD4A854),
                  value: _povEnabled,
                  title: const Text(
                    'POV Modu (Birinci Şahıs Karakter Gözü)',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Senin ve YZ ordularının her hamlesinde hamle yapan taşın gözüne geçer, 1 sn bekler ve gövde/el/bacak görünümüyle ilerler.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFFA0AEC6)),
                  ),
                  onChanged: (val) {
                    setState(() => _povEnabled = val ?? false);
                    _persistSettings();
                    setSheet(() {});
                  },
                ),
                const Divider(height: 16, color: Color(0xFF202E46)),
                _buildSpeedSlidersSection(setSheet),
                const Divider(height: 16, color: Color(0xFF202E46)),
                _buildAudioMixerSection(setSheet, elevenCount),
                const SizedBox(height: 10),
                const Text('OYUN MODU',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Color(0xFFC8A464))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in GameMode.values)
                      ChoiceChip(
                        label: Text(m.labelFor(game.variant),
                            style: const TextStyle(fontSize: 12.5)),
                        selected: _mode == m,
                        selectedColor: const Color(0xFF2B4268),
                        onSelected: (_) {
                          setState(() => _mode = m);
                          _persistSettings();
                          setSheet(() {});
                          _maybeAi();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        game.isThreePlayer ? '3 KİŞİLİK YAPAY ZEKÂ SEVİYESİ' : 'YAPAY ZEKÂ SEVİYESİ (24 KADEME)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, letterSpacing: 1.2, color: Color(0xFFC8A464)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '~${_level.targetElo} ELO',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF5CE1FF)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1B2D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: switch (_level.tier) {
                        >= 19 => const Color(0xFFE24A68),
                        >= 13 => const Color(0xFF9D65CD),
                        >= 7 => const Color(0xFF5CE1FF),
                        _ => const Color(0xFFE5A93C),
                      },
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: switch (_level.tier) {
                                >= 19 => const Color(0x33E24A68),
                                >= 13 => const Color(0x339D65CD),
                                >= 7 => const Color(0x335CE1FF),
                                _ => const Color(0x33E5A93C),
                              },
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'KADEME ${_level.tier} / 24',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: switch (_level.tier) {
                                  >= 19 => const Color(0xFFFF6B88),
                                  >= 13 => const Color(0xFFD3A4FF),
                                  >= 7 => const Color(0xFF7FE6FF),
                                  _ => const Color(0xFFFFCC70),
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _level.label,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _level.category,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SliderTheme(
                        data: SliderTheme.of(ctx).copyWith(
                          trackHeight: 5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                          activeTrackColor: switch (_level.tier) {
                            >= 19 => const Color(0xFFE24A68),
                            >= 13 => const Color(0xFF9D65CD),
                            >= 7 => const Color(0xFF5CE1FF),
                            _ => const Color(0xFFE5A93C),
                          },
                          inactiveTrackColor: const Color(0xFF1E2D44),
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: _level.tier.toDouble(),
                          min: 1,
                          max: 24,
                          divisions: 23,
                          onChanged: (val) {
                            final targetTier = val.round().clamp(1, 24);
                            final nextLvl = AiLevel.values.firstWhere(
                              (l) => l.tier == targetTier,
                              orElse: () => AiLevel.lvl12,
                            );
                            setState(() => _level = nextLvl);
                            _persistSettings();
                            setSheet(() {});
                          },
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _quickAiChip(setSheet, 'KOLAY (K4)', AiLevel.lvl4),
                          _quickAiChip(setSheet, 'ORTA (K10)', AiLevel.lvl10),
                          _quickAiChip(setSheet, 'ZOR (K17)', AiLevel.lvl17),
                          _quickAiChip(setSheet, 'EFSANE (K24)', AiLevel.lvl24),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_mode == GameMode.humanVsAi) ...[
                  const SizedBox(height: 12),
                  const Text('KOMUTA ETTİĞİN ORDU',
                      style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Color(0xFFC8A464))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _teamSelectButton(
                          ctx: ctx,
                          team: Team.white,
                          title: 'Gümüş Şafak',
                          sub: 'Beyaz Ordu',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _teamSelectButton(
                          ctx: ctx,
                          team: Team.black,
                          title: 'Kızıl Obsidyen',
                          sub: 'Siyah Ordu',
                        ),
                      ),
                    ],
                  ),
                  if (game.isThreePlayer) ...[
                    const SizedBox(height: 8),
                    _teamSelectButton(
                      ctx: ctx,
                      team: Team.emerald,
                      title: 'Zümrüt Fırtına',
                      sub: 'Zümrüt Ordu (Kuzeybatı Amfi Cephesi)',
                    ),
                  ],
                ],
                const Divider(height: 18, color: Color(0xFF202E46)),
                const Text('GRAFİK & PERFORMANS OPTİMİZASYONU',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Color(0xFFC8A464))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final q in GraphicsQuality.values)
                      ChoiceChip(
                        label: Text(q.label, style: const TextStyle(fontSize: 12)),
                        selected: _graphicsQuality == q,
                        selectedColor: const Color(0xFF2B4268),
                        onSelected: (_) {
                          setState(() {
                            _graphicsQuality = q;
                            _fx.particleScale = q.particleScale;
                          });
                          _applyStormVisuals();
                          _persistSettings();
                          setSheet(() {});
                        },
                      ),
                  ],
                ),
                const Divider(height: 22, color: Color(0xFF202E46)),
                _buildStormSettingsSection(setSheet),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFD166),
                    side: const BorderSide(color: Color(0xFF7A5C28)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showSqliteArchiveSheet();
                  },
                  icon: const Icon(Icons.military_tech_rounded, size: 18),
                  label: const Text('Sefer Günlüğü ve Komutan Kariyeri'),
                ),
                const Divider(height: 22, color: Color(0xFF202E46)),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B7A),
                    side: const BorderSide(color: Color(0xFF8B2838), width: 1.2),
                    backgroundColor: const Color(0x224A1018),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  ),
                  onPressed: () => _confirmResetAllProgress(ctx),
                  icon: const Icon(Icons.delete_forever_rounded, size: 18, color: Color(0xFFFF6B7A)),
                  label: const Text(
                    'Tüm Sefer ve Oyun Kayıtlarını Sıfırla',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmResetAllProgress(BuildContext sheetContext) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xCC03050B),
      builder: (dlgCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xF5131A2D),
                Color(0xF526111C),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFB83B4B), width: 1.5),
            boxShadow: const [
              BoxShadow(color: Color(0x99000000), blurRadius: 28, offset: Offset(0, 8)),
              BoxShadow(color: Color(0x33B83B4B), blurRadius: 18),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x26FF5C72),
                  border: Border.all(color: const Color(0x88FF5C72), width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Color(0x44FF5C72), blurRadius: 16),
                  ],
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Color(0xFFFF6B7A),
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'SEFERİ VE KAYITLARI SIFIRLA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  color: Color(0xFFFFD166),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x4D060912),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x33B83B4B)),
                ),
                child: const Text(
                  'Bu işlem tüm geçmiş muharebe kayıtlarını, hamle günlüğünü, kazanılan zaferleri ve komutan ELO derecelerini (1200 başlangıç seviyesine) kalıcı olarak sıfırlar.\n\nAntik savaş arenasını sıfırlamak istediğine emin misin?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Color(0xFFD8E4F8),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC0D0E8),
                        side: const BorderSide(color: Color(0xFF334664)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dlgCtx, false),
                      child: const Text('Vazgeç',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB82838),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dlgCtx, true),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Evet, Sıfırla',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    if (sheetContext.mounted) {
      Navigator.pop(sheetContext);
    }

    final resetProfile = await GameDatabase.instance.resetAllData();
    final resetDiag = await GameDatabase.instance.loadDiagnostics();

    if (!mounted) return;
    setState(() {
      _profile = resetProfile;
      _dbDiagnostics = resetDiag;
      _activeSavedMatch = null;
      _currentMatchId = -1;
    });
    _restart();
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF141E30),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFD4A854), width: 1.1),
          ),
          content: const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD166), size: 19),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tüm sefer kayıtları ve ELO puanları sıfırlandı. Yeni bir çağ başlıyor.',
                  style: TextStyle(color: Color(0xFFF2F6FC), fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      );
  }

  Widget _quickAiChip(
    void Function(void Function()) setSheet,
    String label,
    AiLevel target,
  ) {
    final active = _level == target;
    return InkWell(
      onTap: () {
        setState(() => _level = target);
        _persistSettings();
        setSheet(() {});
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2A3D5B) : const Color(0xFF142033),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? const Color(0xFF5CE1FF) : const Color(0xFF223550),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? const Color(0xFF5CE1FF) : const Color(0xFF90A8CA),
          ),
        ),
      ),
    );
  }

  Widget _teamSelectButton({
    required BuildContext ctx,
    required Team team,
    required String title,
    required String sub,
  }) {
    final active = _humanTeam == team;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        if (_humanTeam == team) return;
        Navigator.pop(ctx);
        _humanTeam = team;
        _restart();
        final preset = switch (team) {
          Team.white => CamPreset.white,
          Team.black => CamPreset.black,
          Team.emerald => CamPreset.emerald,
        };
        _animateCameraToPreset(preset);
        _persistSettings();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: active ? const Color(0xFF223556) : const Color(0xFF141D2E),
          border: Border.all(
            color: active ? const Color(0xFFD4A854) : const Color(0xFF2B3850),
            width: active ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            CreatureBadge(kind: PieceType.king, team: team, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  Text(sub, style: const TextStyle(fontSize: 11, color: Color(0xFF9AA8C0))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSqliteArchiveSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1524),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.82,
            maxChildSize: 0.94,
            minChildSize: 0.45,
            builder: (_, scrollCtrl) => FutureBuilder<List<SavedMatchSummary>>(
              future: GameDatabase.instance.loadRecentMatches(limit: 40),
              builder: (ctx, snap) {
                final recent = snap.data ?? const <SavedMatchSummary>[];

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: ListView(
                    controller: scrollCtrl,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF394864),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const BrandCrestLogo(size: 28, glow: false),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Sefer Günlüğü & Zafer Kayıtları',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Komutan Kariyer Kartı
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF142036), Color(0xFF221426)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFD4A854), width: 1.1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.military_tech_rounded,
                                    size: 20, color: Color(0xFFFFD166)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _profile.commanderName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFFE599),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Kazanma: %${_profile.winRate.toStringAsFixed(1)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF34D399),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _sqliteMiniStat('2P ELO', '${_profile.elo2P}', const Color(0xFF5CE1FF)),
                                _sqliteMiniStat('3P ELO', '${_profile.elo3P}', const Color(0xFF34D399)),
                                _sqliteMiniStat('Maç', '${_profile.gamesPlayed}', const Color(0xFFE2E8F4)),
                                _sqliteMiniStat('Zafer', '${_profile.wins}', const Color(0xFFFFD166)),
                                _sqliteMiniStat('Yenilgi', '${_profile.losses}', const Color(0xFFFF6B7A)),
                                _sqliteMiniStat('Avlanan', '${_profile.totalCaptures}', const Color(0xFFFFA07A)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Sefer Bilgileri ve Antik Rütbe Kartı
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1220),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF233652)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.shield_moon_rounded,
                                    size: 16, color: Color(0xFF5CE1FF)),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'KUZEY DİYARI SEFER BİLGİLERİ',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 1.1,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF90A8CA),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0x3334D399),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF34D399)),
                                  ),
                                  child: Text(
                                    switch (_profile.elo2P) {
                                      >= 1650 => 'Başbüyücü Mareşal',
                                      >= 1400 => 'Antik Şövalye',
                                      >= 1250 => 'Gümüş Muhafız',
                                      _ => 'Savaş Çırağı',
                                    },
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF6EE7B7),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Gliński Kuralları • Amfitiyatro Yükseklik Hiyerarşisi • 36 ve 48 Savaşçı Arenası',
                              style: TextStyle(fontSize: 11, color: Color(0xFFC2D4EB)),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Toplam Cephe Deneyimi: ${(_profile.playSeconds ~/ 60)} dakika • Kayıtlı Muharebe Sayısı: ${recent.length}',
                              style: const TextStyle(fontSize: 10.5, color: Color(0xFF7E92B0)),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),
                      const Text(
                        'MUHAREBE GEÇMİŞİ',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFC8A464),
                        ),
                      ),
                      const SizedBox(height: 6),

                      if (recent.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'Henüz tamamlanmış veya kaydedilmiş bir maç yok.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF7E92B0)),
                            ),
                          ),
                        )
                      else
                        for (final m in recent)
                          _buildMatchHistoryTile(m, ctx),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _sqliteMiniStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: const TextStyle(fontSize: 9.5, color: Color(0xFF8BA0BE))),
      ],
    );
  }

  Widget _buildMatchHistoryTile(SavedMatchSummary m, BuildContext sheetCtx) {
    final statusColor = switch (m.status) {
      'checkmate' => const Color(0xFFFFD166),
      'draw' || 'stalemate' => const Color(0xFF34D399),
      'active' => const Color(0xFF5CE1FF),
      _ => const Color(0xFF8898B0),
    };
    final statusLabel = switch (m.status) {
      'checkmate' => 'Şah Mat',
      'stalemate' => 'Pat',
      'draw' => 'Berabere',
      'active' => 'Devam Ediyor',
      _ => 'Terk Edildi',
    };
    final date = DateTime.fromMillisecondsSinceEpoch(m.updatedAtMs);
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF121B2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF22324C)),
      ),
      child: Row(
        children: [
          Icon(
            m.variant == BoardVariant.threePlayer
                ? Icons.hexagon_rounded
                : Icons.safety_divider_rounded,
            size: 20,
            color: m.variant == BoardVariant.threePlayer
                ? const Color(0xFF34D399)
                : const Color(0xFF5CE1FF),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${m.boardLabel} • ${m.plyCount} Hamle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                            fontSize: 9.5, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${m.modeName} • $dateStr ${m.winnerTeam != null ? '• Kazanan: ${m.winnerTeam!.legion}' : ''}',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF8EA2C0)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Muharebe Hamle Dökümü',
            icon: const Icon(Icons.receipt_long_rounded, size: 19, color: Color(0xFFD4A854)),
            onPressed: () => _showMatchMovesModal(m.id),
          ),
        ],
      ),
    );
  }

  void _showMatchMovesModal(int matchId) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0C1424),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long_rounded, color: Color(0xFFD4A854), size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Muharebe #$matchId • Hamle Günlüğü',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: FutureBuilder<List<MoveLogEntry>>(
                  future: GameDatabase.instance.loadMovesForMatch(matchId),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    final moves = snap.data ?? const [];
                    if (moves.isEmpty) {
                      return const Center(
                        child: Text('Bu maç için henüz detaylı hamle kaydedilmemiş.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF7E92B0))),
                      );
                    }
                    return ListView.builder(
                      itemCount: moves.length,
                      itemBuilder: (ctx, i) {
                        final m = moves[i];
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 2.5),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141E32),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF22314E)),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '#${m.ply + 1}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFD4A854)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${m.team.toUpperCase()} ${m.piece}: ${m.fromCell} → ${m.toCell}${m.capturedPiece != null ? ' (vurdu: ${m.capturedPiece})' : ''}${m.promoted ? ' [TERFİ]' : ''}',
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFFE2EAF8)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBestiary() {
    const rows = [
      (
        PieceType.king,
        'Barbar Kral',
        'Kuzey Hükümdarı',
        'Kurt postu mantosu, fildişi savaş borusu ve çift ağızlı hilal baltasıyla her yöne 1 adım ilerler; gardı kırıp rakibi savurur.'
      ),
      (
        PieceType.queen,
        'Vampir Kraliçe',
        'Kan Kontesi',
        'Yırtmaçlı gotik kadife elbisesi ve yarasa sürüsüyle 12 yönün tamamında kızıl sis içinde süzülür; düşmanın yaşam özünü çeker.'
      ),
      (
        PieceType.rook,
        'Kadın Savaş Devi',
        'Valkür Titan',
        'Kanatlı Valkür tacı, kol kalkanı ve dev dövme savaş balyozuyla 6 dikey/yatay eksende yeri sarsarak yürür ve düşmanı ezer.'
      ),
      (
        PieceType.bishop,
        'Ejderha',
        'Antik Ejder',
        'Dört parmaklı deri kanatlarıyla 6 çapraz eksende göğe yükselip uçar; pençe fırtınası ve büyülü ejder ateşi püskürtür.'
      ),
      (
        PieceType.knight,
        'Suikastçi',
        'Gölge Avcısı',
        'Alçak avcı koşusu ve gölge sıçrayışıyla engellerin üzerinden aşar; ikiz Şam çeliği kukri bıçaklarıyla üçlü darbe indirir.'
      ),
      (
        PieceType.pawn,
        'Kalkan Muhafızı',
        'Zırhlı Öncü Şövalye',
        'Perçinli kalkanını siper ederek yürür, kalkan darbesiyle gardı açıp çelik teberiyle devirir; son hatta üst sınıfa terfi eder.'
      ),
    ];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1524),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.70,
        maxChildSize: 0.90,
        minChildSize: 0.45,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF394864),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.auto_stories_rounded, color: Color(0xFFD4A854), size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Savaşçılar Kitabı & Ses Testi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [
                    for (final (kind, name, role, desc) in rows)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141E30),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF25344E)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CreatureBadge(kind: kind, team: _humanTeam, size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(name,
                                            style: const TextStyle(
                                                fontSize: 14.5, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text('• $role',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 11.5, color: Color(0xFFD4A854))),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(desc,
                                      style: const TextStyle(
                                          fontSize: 12, color: Color(0xFFB4C0D4), height: 1.35)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Savaş Narasını Dinle',
                              onPressed: () => _triggerVoice(kind, VoiceEvent.attack, _humanTeam),
                              icon: const Icon(Icons.volume_up_rounded, color: Color(0xFF5CE1FF)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================ MOBİL OYUN ARAYÜZÜ (HUD)
  Widget _buildFallenRow(Team team) {
    final list = game.fallen.where((p) => p.team == team).toList();
    if (list.isEmpty) {
      return const Text('—', style: TextStyle(fontSize: 11, color: Color(0xFF5D6B82)));
    }
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final p in list.take(12))
          CreatureBadge(kind: p.kind, team: p.team, size: 19, framed: true),
        if (list.length > 12)
          Text('+${list.length - 12}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFC6AB7E))),
      ],
    );
  }

  /// Kırmızı "ŞAH!" rozeti. Yer daralınca saldıran taşın adı "…" ile kısalır.
  Widget _buildCheckBadge() {
    final threats = game.currentCheckThreats;
    final text = threats.isNotEmpty
        ? 'ŞAH! • ${threats.first.attackerPiece.team.title} ${threats.first.attackerPiece.kind.creature} [${game.shape.name(threats.first.attackerCell)}]'
        : 'ŞAH!';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF243B),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Color(0x66FF243B), blurRadius: 8, spreadRadius: 1),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final turnName = game.turn.banner;
    final selPiece = _selected == null ? null : game.pieceAt(_selected!);
    final inCheck = game.inCheckNow && game.status == GameStatus.playing;
    final winnerTeam = game.isThreePlayer
        ? (game.pos3.soleSurvivor != null ? Team.values[game.pos3.soleSurvivor!] : Team.white)
        : (game.turn == Team.white ? Team.black : Team.white);

    return Scaffold(
      body: Focus(
        focusNode: _keyFocus,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. TAM EKRAN 3B SAVAŞ ARENASI
            LayoutBuilder(
              builder: (context, constraints) {
                final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
                return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _onViewportPointerDown,
                  onPointerMove: (e) => _onViewportPointerMove(e, viewSize),
                  onPointerUp: (e) => _onViewportPointerUp(e, viewSize),
                  onPointerCancel: _onViewportPointerCancel,
                  child: _engine.build(),
                );
              },
            ),

            // 2A. POV SİNEMATİK VİZÖR ARAYÜZÜ (Üst görüş hattını kapatmaz, alt yazı alta iner!)
            if (!_showLaunchScreen && _inPovSequence) ...[
              // Hafif FPS nişangâhı ve 1.0 sn hazırlık halkası
              IgnorePointer(
                child: Center(
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_povCountdown > 0.01)
                          SizedBox(
                            width: 38,
                            height: 38,
                            child: CircularProgressIndicator(
                              value: (1.0 - _povCountdown).clamp(0.0, 1.0),
                              strokeWidth: 2.2,
                              color: const Color(0xFFFFD166),
                              backgroundColor: const Color(0x33FFFFFF),
                            ),
                          ),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xCCFFD166),
                            border: Border.all(color: const Color(0xAA000000), width: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Üst sol kompakt vizör etiketi + üst sağ "Tahtaya Dön" düğmesi
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: Row(
                      children: [
                        // Etiket kalan genişliğe sığar; dar pencerede "…" ile kısalır.
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xCC0A101E),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xAAFFD166)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.visibility_rounded,
                                      size: 15, color: Color(0xFFFFD166)),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      _povCountdown > 0.01
                                          ? 'POV • $_povWho • Hazırlanıyor (${_povCountdown.toStringAsFixed(1)}s)'
                                          : 'POV • $_povWho • Fare/parmakla bak',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFFFE599),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if ((_povLookYaw.abs() > 0.04 || _povLookPitch.abs() > 0.04)) ...[
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() {
                              _povLookYaw = 0.0;
                              _povLookPitch = 0.0;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xCC0A101E),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF354A6E)),
                              ),
                              child: const Text(
                                'Bakışı Sıfırla',
                                style: TextStyle(fontSize: 11, color: Color(0xFFD6E0F2)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _skipCurrentPovToBoard,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xD8182238),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFD4A854)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.grid_view_rounded,
                                    size: 14, color: Color(0xFFD4A854)),
                                SizedBox(width: 5),
                                Text(
                                  'Tahtaya Dön',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFFFD166),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Alt orta sinematik alt yazı (karakter savaş narası / sesli komutu)
              if (_activeVoice != null)
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xDA0E1628), Color(0xDA221222)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xCCD4A854), width: 1.1),
                            boxShadow: const [
                              BoxShadow(color: Color(0x88000000), blurRadius: 14),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CreatureBadge(
                                kind: _activeVoice!.kind,
                                team: _activeVoiceTeam,
                                size: 30,
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.graphic_eq_rounded,
                                            size: 14, color: Color(0xFFFFB74D)),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            '${_activeVoice!.speaker} • ${_activeVoice!.warCry}',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFFFD166),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '“${_activeVoice!.text}”',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.8,
                                        fontStyle: FontStyle.italic,
                                        color: Color(0xFFF2F5FC),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],

            // 2B. TAHTA MODU ÜST BAŞLIK + POV CHECKBOX + TAHTA KAYDIRMA HAPI
            if (!_showLaunchScreen && !_inPovSequence)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xDA0C1322),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: inCheck ? const Color(0xFFFF3B4E) : const Color(0xFF2B3B56),
                              width: inCheck ? 1.5 : 1.0,
                            ),
                            boxShadow: const [
                              BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4)),
                            ],
                          ),
                          child: Row(
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => _setLaunchScreenVisible(true),
                                child: const Tooltip(
                                  message: 'Ana Menü / Sefer Seçimi',
                                  child: Padding(
                                    padding: EdgeInsets.all(2.0),
                                    child: BrandCrestLogo(size: 34, glow: false),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              CreatureBadge(
                                kind: PieceType.king,
                                team: game.turn,
                                size: 36,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, box) {
                                    // Dar pencerede ŞAH rozeti başlığın altına kendi satırına iner;
                                    // her iki durumda da metin kısalır, asla taşmaz.
                                    final checkBelow = box.maxWidth < 330;
                                    final checkBadge = inCheck ? _buildCheckBadge() : null;
                                    final title = Text(
                                      turnName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.9,
                                        color: Colors.white,
                                      ),
                                    );
                                    final inlineBadge = checkBadge != null && !checkBelow;
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            // Rozet yanındayken ordu adı tam kalır (en çok yarı genişlik),
                                            // yalnızca rozet kısalır.
                                            if (inlineBadge)
                                              ConstrainedBox(
                                                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.45),
                                                child: title,
                                              )
                                            else
                                              Flexible(child: title),
                                            if (inlineBadge) ...[
                                              const SizedBox(width: 6),
                                              Flexible(child: checkBadge),
                                            ],
                                            if (_thinking || _hintBusy) ...[
                                              const SizedBox(width: 8),
                                              const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Color(0xFF5CE1FF),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (checkBadge != null && checkBelow) ...[
                                          const SizedBox(height: 3),
                                          checkBadge,
                                        ],
                                        const SizedBox(height: 2),
                                        Text(
                                          '${game.boardLabel} • ${_mode.labelFor(game.variant)} • ${_level.label} • Hamle ${(game.ply ~/ game.activeTeams.length) + 1}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 11, color: Color(0xFFA8B5CC)),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Sefer Günlüğü & Zaferler',
                                onPressed: _showSqliteArchiveSheet,
                                icon: const Icon(Icons.military_tech_rounded,
                                    size: 21, color: Color(0xFFFFD166)),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Savaşçılar Kitabı',
                                onPressed: _showBestiary,
                                icon: const Icon(Icons.auto_stories_rounded,
                                    size: 20, color: Color(0xFFD8B268)),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Savaş Ayarları',
                                onPressed: _showSettingsSheet,
                                icon: const Icon(Icons.tune_rounded,
                                    size: 20, color: Color(0xFFD8DAE4)),
                              ),
                            ],
                          ),
                        ),

                        // Hızlı POV Checkbox + Tahtayı Taşı + 3 Kişilik Masa + Ortala Kontrol Satırı
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => setState(() => _povEnabled = !_povEnabled),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _povEnabled
                                        ? const Color(0xD8233454)
                                        : const Color(0xBE0B111E),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _povEnabled
                                          ? const Color(0xFFD4A854)
                                          : const Color(0xFF24324A),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: Checkbox(
                                          value: _povEnabled,
                                          activeColor: const Color(0xFFD4A854),
                                          visualDensity: VisualDensity.compact,
                                          onChanged: (v) => setState(() => _povEnabled = v ?? false),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'POV Modu',
                                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _togglePanMode,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _panBoardMode
                                        ? const Color(0xD81E4258)
                                        : const Color(0xBE0B111E),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _panBoardMode
                                          ? const Color(0xFF5CE1FF)
                                          : const Color(0xFF24324A),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _panBoardMode
                                            ? Icons.open_with_rounded
                                            : Icons.threed_rotation_rounded,
                                        size: 15,
                                        color: _panBoardMode
                                            ? const Color(0xFF5CE1FF)
                                            : const Color(0xFFB8C6DE),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        _panBoardMode ? 'Tahtayı Taşı' : 'Döndür',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: _panBoardMode
                                              ? const Color(0xFF5CE1FF)
                                              : const Color(0xFFD6E0F2),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // 3 Kişilik Masa ↔ 2 Kişilik Düello Hızlı Geçiş Düğmesi
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _switchVariant(
                                  game.isThreePlayer
                                      ? BoardVariant.twoPlayer
                                      : BoardVariant.threePlayer,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: game.isThreePlayer
                                        ? const Color(0xDF12382E)
                                        : const Color(0xBE0B111E),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: game.isThreePlayer
                                          ? const Color(0xFF34D399)
                                          : const Color(0xFF34504A),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.hexagon_rounded,
                                        size: 15,
                                        color: game.isThreePlayer
                                            ? const Color(0xFF34D399)
                                            : const Color(0xFF8BE2BA),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        game.isThreePlayer
                                            ? '3 Kişilik Masa (Aktif)'
                                            : '3 Kişilik Masa Aç',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: game.isThreePlayer
                                              ? const Color(0xFF6EE7B7)
                                              : const Color(0xFFD6E0F2),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_boardPanned)
                                InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _recenterBoard,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xBE0B111E),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFD4A854)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.center_focus_strong_rounded,
                                            size: 14, color: Color(0xFFD4A854)),
                                        SizedBox(width: 4),
                                        Text('Ortala',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFFD4A854))),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Seçili Savaşçı veya Savaş Bildirimi Hapı
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xBE0B111E),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: const Color(0xFF202D44)),
                          ),
                          child: Row(
                            children: [
                              if (selPiece != null) ...[
                                CreatureBadge(kind: selPiece.kind, team: selPiece.team, size: 24),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  _battleText.isNotEmpty && selPiece == null
                                      ? _battleText
                                      : _message,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.8,
                                    color: _battleText.isNotEmpty && selPiece == null
                                        ? const Color(0xFFFF9B73)
                                        : const Color(0xFFE2E8F4),
                                    fontWeight: _battleText.isNotEmpty && selPiece == null
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Tahta Görünümü Sesli Komut Kartı
                        if (_activeVoice != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xE6161F36), Color(0xE6261424)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFD4A854), width: 1.1),
                            ),
                            child: Row(
                              children: [
                                CreatureBadge(
                                  kind: _activeVoice!.kind,
                                  team: _activeVoiceTeam,
                                  size: 30,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.graphic_eq_rounded,
                                              size: 14, color: Color(0xFFFFB74D)),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              '${_activeVoice!.speaker} • ${_activeVoice!.warCry}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFFFD166),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '“${_activeVoice!.text}”',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontStyle: FontStyle.italic,
                                          color: Color(0xFFF2F5FC),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

            // 3. OYUN SONU ZAFER / RÖVANŞ KARTI
            if (!_showLaunchScreen && game.status != GameStatus.playing && !_busy)
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xF20D1526),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFD4A854), width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Color(0xAA000000), blurRadius: 24),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CreatureBadge(
                        kind: PieceType.king,
                        team: winnerTeam,
                        size: 56,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        game.statusText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (game.canUndo && _mode != GameMode.aiVsAi) ...[
                            OutlinedButton.icon(
                              onPressed: _undoTurn,
                              icon: const Icon(Icons.undo_rounded, size: 18),
                              label: const Text('Geri Al'),
                            ),
                            const SizedBox(width: 10),
                          ],
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFC89B48),
                              foregroundColor: const Color(0xFF0A0F1A),
                            ),
                            onPressed: _restart,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Yeni Savaş',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // 4. ALT MOBİL KOMUTA DOCKU VE DÜŞEN SAVAŞÇILAR
            if (!_showLaunchScreen && !_inPovSequence)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      decoration: BoxDecoration(
                        color: const Color(0xE00C1322),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF283750)),
                        boxShadow: const [
                          BoxShadow(color: Color(0x77000000), blurRadius: 14, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (game.fallen.isNotEmpty) ...[
                            Row(
                              children: [
                                const Text('Kayıplar:',
                                    style: TextStyle(fontSize: 10.5, color: Color(0xFF93A2BC))),
                                const SizedBox(width: 6),
                                Expanded(child: _buildFallenRow(Team.white)),
                                const SizedBox(width: 6),
                                Expanded(child: _buildFallenRow(Team.black)),
                                if (game.isThreePlayer) ...[
                                  const SizedBox(width: 6),
                                  Expanded(child: _buildFallenRow(Team.emerald)),
                                ],
                              ],
                            ),
                            const Divider(height: 12, color: Color(0xFF1F2B40)),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _dockBtn(
                                icon: Icons.undo_rounded,
                                label: 'Geri Al',
                                enabled: _ready && game.canUndo && _mode != GameMode.aiVsAi,
                                onTap: _undoTurn,
                              ),
                              _dockBtn(
                                icon: Icons.bolt_rounded,
                                label: 'İpucu',
                                enabled: _ready &&
                                    !_busy &&
                                    !_thinking &&
                                    _isHumanTurn &&
                                    game.status == GameStatus.playing,
                                accent: _hint != null,
                                onTap: _requestHint,
                              ),
                              _dockBtn(
                                icon: Icons.cameraswitch_rounded,
                                label: switch (_camPreset) {
                                  CamPreset.white => 'Beyaz',
                                  CamPreset.black => 'Siyah',
                                  CamPreset.emerald => 'Zümrüt',
                                  CamPreset.top => 'Tepeden',
                                },
                                enabled: _ready,
                                onTap: _cycleCamera,
                              ),
                              _dockBtn(
                                icon: Icons.speed_rounded,
                                label: 'Hız Ayarı',
                                enabled: true,
                                accent: true,
                                onTap: _showSpeedSheet,
                              ),
                              _dockBtn(
                                icon: Icons.refresh_rounded,
                                label: 'Yeni',
                                enabled: _ready,
                                onTap: _restart,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // 5. RESMİ AÇILIŞ EKRANI / LOBİ & KARİYER (Dark-Fantasy Crest + Canlı SQLite)
            if (_showLaunchScreen)
              WizardLaunchScreen(
                bootReady: _bootReady,
                bootStatus: _bootStatus,
                bootProgress: _bootProgress,
                profile: _profile,
                activeMatch: _activeSavedMatch,
                diagnostics: _dbDiagnostics,
                onResumeSavedMatch: () {
                  if (_activeSavedMatch != null) {
                    if (_activeSavedMatch!.id == _currentMatchId && _currentMatchId > 0) {
                      _setLaunchScreenVisible(false);
                      _maybeAi();
                    } else {
                      _resumeSavedMatch();
                    }
                  }
                },
                onStartVariant: (variant, size) {
                  _startMatchFromLaunch(variant, size);
                },
                onOpenArchive: _showSqliteArchiveSheet,
                onOpenSettings: _showSettingsSheet,
                initialBoardSize3P: game.boardSize3P,
              ),
          ],
        ),
      ),
    );
  }

  Widget _dockBtn({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    final fg = !enabled
        ? const Color(0xFF4C5970)
        : (accent ? const Color(0xFFD8B268) : const Color(0xFFE4EAF6));
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: fg),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uzun düellodaki kapışma pozları (bkz. `_duelPose`).
enum _DuelPose {
  guard,
  windup,
  strike,
  parry,
  bind,
  sweepWind,
  sweep,
  duck,
  jab,
  sidestep,
  bashWind,
  bash,
  stagger,
  kneel,
  kneelBlock,
  crouch,
}

/// Düellodaki kapışma türleri; hangilerinin geleceğini karmaşıklık seviyesi belirler.
enum _DuelExchange { press, counter, bind, dodge, combo, feint, circle, bash, knockdown, leap }
