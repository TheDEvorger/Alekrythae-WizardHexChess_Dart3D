import 'dart:math' as math;

import '../game/chess_game.dart';
import '../game/hex_board.dart';

/// Canlı (production) sürüm için uyarlanabilir grafik kalite profilleri.
enum GraphicsQuality {
  performance('Akıcı (Mobil / 60+ FPS)', 0.92, 0.50),
  balanced('Dengeli (Önerilen)', 1.15, 0.85),
  ultra('Ultra Detay (Masaüstü)', 1.35, 1.00);

  const GraphicsQuality(this.label, this.pixelScale, this.particleScale);
  final String label;
  final double pixelScale;
  final double particleScale;

  static GraphicsQuality fromName(String? raw) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return GraphicsQuality.balanced;
  }
}

/// Atmosfer ayarlarının kaydırıcı aralıkları. Kaydırıcı yalnızca bu aralığı
/// kapsar; yanındaki elle giriş kutusunun ÜST SINIRI YOKTUR: daha yüksek her
/// değer o etkinin dozunu artırmaya devam eder (yalnızca negatifler 0'a çekilir).
abstract final class AtmosphereLimits {
  static const double stormSlider = 3.0;
  static const double mysticSlider = 1.0;
  static const double lightningRateSlider = 4.0;

  /// Yıldırım kanalının çaktıktan sonra havada kalma süresi (saniye).
  static const double lingerSlider = 3.0;

  static const double fogSlider = 3.0;

  /// Düello kapışma turu (bitirici darbeden önceki karşılıklı vuruş turu).
  static const double duelRoundsSlider = 8.0;

  /// Düello karmaşıklığı seviyesi (0 sade … 4 destansı; elle daha yükseği).
  static const double duelComplexitySlider = 4.0;

  /// Ses düzeyleri: %100'ün üstü yumuşak sınırlayıcılı yükseltme ile çalınır.
  static const double volumeSlider = 1.0;
}

/// Fırtına girdabının shader kalitesi. [auto] grafik kalitesini izler;
/// [cinematic] 6 katman gürültü, tüm bulutlarda hacim ışığı ve en çok rüzgâr/ışık izi.
enum StormQuality {
  auto('Otomatik'),
  low('Düşük'),
  medium('Orta'),
  high('Yüksek'),
  cinematic('Sinematik');

  const StormQuality(this.label);
  final String label;

  static StormQuality fromName(String? raw) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return StormQuality.auto;
  }
}

/// SQLite `app_settings` tablosunda saklanan tüm kullanıcı tercihleri.
class PersistedSettings {
  const PersistedSettings({
    this.variant = BoardVariant.twoPlayer,
    this.boardSize3P = BoardSize.classic,
    this.modeName = 'humanVsAi',
    this.aiLevelName = 'wizard',
    this.humanTeam = Team.white,
    this.povEnabled = true,
    this.moveSpeed = 0.80,
    this.combatSpeed = 0.70,
    this.duelRounds = 4.0,
    this.duelComplexity = 2.0,
    this.voiceEnabled = true,
    this.sfxEnabled = true,
    this.bgmEnabled = true,
    this.bgmVolume = 0.55,
    this.voiceVolume = 0.90,
    this.sfxVolume = 0.85,
    this.graphicsQuality = GraphicsQuality.balanced,
    this.stormIntensity = 1.5,
    this.hauntLevel = 0.75,
    this.lightningRate = 1.5,
    this.thunderVolume = 1.0,
    this.ambienceVolume = 0.7,
    this.stormFog = 1.0,
    this.lightningLinger = 1.2,
    this.stormQuality = StormQuality.auto,
  });

  final BoardVariant variant;

  /// 3 kişilik masa için son seçilen tahta boyutu (Klasik / Geniş / Büyük / Dev).
  final BoardSize boardSize3P;
  final String modeName;
  final String aiLevelName;
  final Team humanTeam;
  final bool povEnabled;
  final double moveSpeed;
  final double combatSpeed;

  /// Bitirici darbeden önce iki savaşçının karşılıklı kapıştığı tur sayısı
  /// (0 = tek çarpışma; kaydırıcı 0..8, elle sınırsız).
  final double duelRounds;

  /// Düellonun sadeliği/kısalığı ↔ uzunluğu/karmaşıklığı (0 = sade, 2 = usta;
  /// kaydırıcı 0..4, elle sınırsız). Seviye arttıkça yeni hamle türleri
  /// (kombo, aldatma, çevreleme, diz çöktürme, sıçrayış) ve tur başına daha
  /// çok kapışma gelir.
  final double duelComplexity;
  final bool voiceEnabled;
  final bool sfxEnabled;
  final bool bgmEnabled;
  /// Fon müziği ses düzeyi (0..1).
  final double bgmVolume;

  /// Karakter konuşmaları / savaş naraları ses düzeyi (0..1).
  final double voiceVolume;

  /// Adım, çarpışma ve silah efektleri ses düzeyi (0..1).
  final double sfxVolume;
  final GraphicsQuality graphicsQuality;

  /// Fırtına gücü (kaydırıcı 0..3, elle sınırsız): girdap hızı, bulut
  /// yoğunluğu, türbülans, rüzgâr, yağmur.
  final double stormIntensity;

  /// Gizemli atmosfer (kaydırıcı 0..1, elle sınırsız): bulut içi ışıltı,
  /// ışık izleri ve uğultular.
  final double hauntLevel;

  /// Yıldırım sıklığı (kaydırıcı 0..4, elle sınırsız; 0 = kapalı).
  final double lightningRate;

  /// Gök gürültüsü ses düzeyi (kaydırıcı 0..1, elle sınırsız).
  final double thunderVolume;

  /// Rüzgâr ve gizemli uğultu ses düzeyi (kaydırıcı 0..1, elle sınırsız).
  final double ambienceVolume;

  /// Fırtınayı saran sis yoğunluğu (0 = açık hava, 1 = varsayılan; elle sınırsız).
  final double stormFog;

  /// Yıldırımın çaktıktan sonra havada parlamaya devam etme süresi (saniye).
  final double lightningLinger;

  final StormQuality stormQuality;

  Map<String, String> toKeyValues() => {
        'board_variant': variant.name,
        'board_size_3p': boardSize3P.name,
        'game_mode': modeName,
        'ai_level': aiLevelName,
        'human_team': humanTeam.name,
        'pov_enabled': povEnabled ? '1' : '0',
        'move_speed': moveSpeed.toStringAsFixed(3),
        'combat_speed': combatSpeed.toStringAsFixed(3),
        'duel_rounds': duelRounds.toStringAsFixed(3),
        'duel_complexity': duelComplexity.toStringAsFixed(3),
        'voice_enabled': voiceEnabled ? '1' : '0',
        'sfx_enabled': sfxEnabled ? '1' : '0',
        'bgm_enabled': bgmEnabled ? '1' : '0',
        'bgm_volume': bgmVolume.toStringAsFixed(3),
        'voice_volume': voiceVolume.toStringAsFixed(3),
        'sfx_volume': sfxVolume.toStringAsFixed(3),
        'graphics_quality': graphicsQuality.name,
        'storm_intensity': stormIntensity.toStringAsFixed(3),
        'storm_haunt': hauntLevel.toStringAsFixed(3),
        'lightning_rate': lightningRate.toStringAsFixed(3),
        'thunder_volume': thunderVolume.toStringAsFixed(3),
        'storm_ambience_volume': ambienceVolume.toStringAsFixed(3),
        'storm_fog': stormFog.toStringAsFixed(3),
        'lightning_linger': lightningLinger.toStringAsFixed(3),
        'storm_quality': stormQuality.name,
      };

  static PersistedSettings fromKeyValues(Map<String, String> map) {
    BoardVariant parseVariant(String? s) =>
        s == BoardVariant.threePlayer.name
            ? BoardVariant.threePlayer
            : BoardVariant.twoPlayer;
    Team parseTeam(String? s) {
      for (final t in Team.values) {
        if (t.name == s) return t;
      }
      return Team.white;
    }

    double parseDouble(String? s, double fallback, double min, double max) {
      final v = double.tryParse(s ?? '');
      if (v == null || !v.isFinite) return fallback;
      return v.clamp(min, max);
    }

    /// Atmosfer ayarları: üst sınır yok, yalnızca negatif değerler 0'a çekilir.
    double parseDose(String? s, double fallback) => parseDouble(s, fallback, 0.0, double.infinity);

    return PersistedSettings(
      variant: parseVariant(map['board_variant']),
      boardSize3P: BoardSize.fromName(map['board_size_3p']),
      modeName: map['game_mode'] ?? 'humanVsAi',
      aiLevelName: map['ai_level'] ?? 'wizard',
      humanTeam: parseTeam(map['human_team']),
      povEnabled: (map['pov_enabled'] ?? '1') != '0',
      moveSpeed: parseDouble(map['move_speed'], 0.80, 0.35, 2.20),
      combatSpeed: parseDouble(map['combat_speed'], 0.70, 0.30, 2.00),
      duelRounds: parseDose(map['duel_rounds'], 4.0),
      duelComplexity: parseDose(map['duel_complexity'], 2.0),
      voiceEnabled: (map['voice_enabled'] ?? '1') != '0',
      sfxEnabled: (map['sfx_enabled'] ?? '1') != '0',
      bgmEnabled: (map['bgm_enabled'] ?? '1') != '0',
      bgmVolume: parseDouble(map['bgm_volume'], 0.55, 0.0, 1.0),
      voiceVolume: parseDouble(map['voice_volume'], 0.90, 0.0, 1.0),
      sfxVolume: parseDouble(map['sfx_volume'], 0.85, 0.0, 1.0),
      graphicsQuality: GraphicsQuality.fromName(map['graphics_quality']),
      stormIntensity: parseDose(map['storm_intensity'], 1.5),
      hauntLevel: parseDose(map['storm_haunt'], 0.75),
      lightningRate: parseDose(map['lightning_rate'], 1.5),
      thunderVolume: parseDose(map['thunder_volume'], 1.0),
      ambienceVolume: parseDose(map['storm_ambience_volume'], 0.7),
      stormFog: parseDose(map['storm_fog'], 1.0),
      lightningLinger: parseDose(map['lightning_linger'], 1.2),
      stormQuality: StormQuality.fromName(map['storm_quality']),
    );
  }
}

/// SQLite `player_profile` tablosunda tutulan oyuncu kariyer ve ELO verisi.
class PlayerProfileStats {
  const PlayerProfileStats({
    this.commanderName = 'Kuzey Komutanı',
    this.elo2P = 1200,
    this.elo3P = 1200,
    this.gamesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.totalCaptures = 0,
    this.playSeconds = 0,
  });

  final String commanderName;
  final int elo2P;
  final int elo3P;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final int totalCaptures;
  final int playSeconds;

  double get winRate =>
      gamesPlayed <= 0 ? 0.0 : (wins * 100.0) / gamesPlayed;

  static int computeNextElo({
    required int currentElo,
    required int opponentElo,
    required double score, // 1.0 zafer, 0.5 berabere, 0.0 yenilgi
  }) {
    final expected =
        1.0 / (1.0 + math.pow(10.0, (opponentElo - currentElo) / 400.0));
    final next = (currentElo + 28.0 * (score - expected)).round();
    return next.clamp(400, 3200);
  }
}

/// SQLite `matches` tablosundaki aktif veya tamamlanmış maç özeti.
class SavedMatchSummary {
  const SavedMatchSummary({
    required this.id,
    required this.variant,
    this.boardSize = BoardSize.classic,
    required this.modeName,
    required this.aiLevelName,
    required this.humanTeam,
    required this.status,
    required this.winnerTeam,
    required this.plyCount,
    required this.encodedMoves,
    required this.startedAtMs,
    required this.updatedAtMs,
  });

  final int id;
  final BoardVariant variant;

  /// Maçın tahta boyutu (2 kişilik ve eski kayıtlarda Klasik).
  final BoardSize boardSize;
  final String modeName;
  final String aiLevelName;
  final Team humanTeam;
  final String status; // 'active', 'checkmate', 'stalemate', 'draw', 'abandoned'
  final Team? winnerTeam;
  final int plyCount;
  final List<int> encodedMoves;
  final int startedAtMs;
  final int updatedAtMs;

  bool get isActive => status == 'active' && encodedMoves.isNotEmpty;

  /// Arşiv ve devam düğmesi için masa etiketi: "3 Kişilik Masa • Dev" gibi.
  String get boardLabel => variant == BoardVariant.threePlayer
      ? '${variant.label} • ${boardSize.label}'
      : variant.label;
}

/// SQLite `match_moves` tablosundaki tekil hamle kaydı.
class MoveLogEntry {
  const MoveLogEntry({
    required this.ply,
    required this.team,
    required this.piece,
    required this.fromCell,
    required this.toCell,
    this.capturedPiece,
    this.promoted = false,
    required this.encodedMove,
    required this.createdAtMs,
  });

  final int ply;
  final String team;
  final String piece;
  final String fromCell;
  final String toCell;
  final String? capturedPiece;
  final bool promoted;
  final int encodedMove;
  final int createdAtMs;
}

/// Canlı SQLite sağlık ve optimizasyon tanılama raporu.
class SqliteDiagnostics {
  const SqliteDiagnostics({
    required this.sqliteVersion,
    required this.journalMode,
    required this.synchronousMode,
    required this.foreignKeysEnabled,
    required this.dbPath,
    required this.dbSizeBytes,
    required this.activeMatches,
    required this.completedMatches,
  });

  final String sqliteVersion;
  final String journalMode;
  final int synchronousMode;
  final bool foreignKeysEnabled;
  final String dbPath;
  final int dbSizeBytes;
  final int activeMatches;
  final int completedMatches;
}

/// Açılış ekranında tek seferde yüklenen başlangıç veritabanı paketi.
class InitialDatabaseBootstrap {
  const InitialDatabaseBootstrap({
    required this.settings,
    required this.profile,
    required this.activeMatch,
    required this.recentMatches,
    required this.diagnostics,
  });

  final PersistedSettings settings;
  final PlayerProfileStats profile;
  final SavedMatchSummary? activeMatch;
  final List<SavedMatchSummary> recentMatches;
  final SqliteDiagnostics diagnostics;
}
