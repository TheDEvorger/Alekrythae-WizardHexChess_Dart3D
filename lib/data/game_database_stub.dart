import '../game/chess_game.dart';
import '../game/hex_board.dart';
import 'game_models.dart';

/// Web derlemeleri için bellek-içi yedek veritabanı adaptörü.
class GameDatabase {
  GameDatabase._();

  static final GameDatabase instance = GameDatabase._();

  static Future<GameDatabase> openForTesting(String dbPath) async {
    final db = GameDatabase._();
    await db.init(overrideDbPath: dbPath);
    return db;
  }

  bool _ready = false;
  PersistedSettings _settings = const PersistedSettings();
  final PlayerProfileStats _profile = const PlayerProfileStats();
  final List<SavedMatchSummary> _matches = [];
  final Map<int, List<MoveLogEntry>> _moves = {};
  int _nextId = 1;

  bool get isReady => _ready;
  String get dbPath => 'web-memory';

  Future<InitialDatabaseBootstrap> init({String? overrideDbPath}) async {
    _ready = true;
    return loadBootstrap();
  }

  Future<InitialDatabaseBootstrap> loadBootstrap() async {
    SavedMatchSummary? active;
    for (final m in _matches) {
      if (m.isActive) {
        active = m;
        break;
      }
    }
    return InitialDatabaseBootstrap(
      settings: _settings,
      profile: _profile,
      activeMatch: active,
      recentMatches: List<SavedMatchSummary>.of(_matches),
      diagnostics: SqliteDiagnostics(
        sqliteVersion: 'web-fallback',
        journalMode: 'memory',
        synchronousMode: 1,
        foreignKeysEnabled: true,
        dbPath: dbPath,
        dbSizeBytes: 0,
        activeMatches: active == null ? 0 : 1,
        completedMatches: _matches.where((m) => !m.isActive).length,
      ),
    );
  }

  void scheduleSaveSettings(PersistedSettings settings) {
    _settings = settings;
  }

  Future<void> flushPendingSettings() async {}

  Future<void> saveSettingsImmediate(PersistedSettings settings) async {
    _settings = settings;
  }

  Future<int> startNewMatch({
    required BoardVariant variant,
    BoardSize boardSize = BoardSize.classic,
    required String modeName,
    required String aiLevelName,
    required Team humanTeam,
  }) async {
    final id = _nextId++;
    final now = DateTime.now().millisecondsSinceEpoch;
    _matches.insert(
      0,
      SavedMatchSummary(
        id: id,
        variant: variant,
        boardSize:
            variant == BoardVariant.threePlayer ? boardSize : BoardSize.classic,
        modeName: modeName,
        aiLevelName: aiLevelName,
        humanTeam: humanTeam,
        status: 'active',
        winnerTeam: null,
        plyCount: 0,
        encodedMoves: const [],
        startedAtMs: now,
        updatedAtMs: now,
      ),
    );
    _moves[id] = [];
    return id;
  }

  Future<void> recordMove({
    required int matchId,
    required int ply,
    required MoveRecord record,
    required List<int> allEncodedMoves,
    required bool humanCapture,
    BoardShape? shape,
  }) async {}

  Future<void> recordUndo({
    required int matchId,
    required int newPlyCount,
    required List<int> remainingEncodedMoves,
  }) async {}

  Future<PlayerProfileStats> finishMatch({
    required int matchId,
    required BoardVariant variant,
    required String finalStatus,
    required Team? winnerTeam,
    required Team humanTeam,
    required bool ratedHumanMatch,
    required int opponentElo,
    required int elapsedSeconds,
  }) async =>
      _profile;

  Future<List<MoveLogEntry>> loadMovesForMatch(int matchId) async =>
      _moves[matchId] ?? const [];

  Future<List<SavedMatchSummary>> loadRecentMatches({int limit = 20}) async =>
      _matches.take(limit).toList();

  Future<SqliteDiagnostics> loadDiagnostics() async =>
      (await loadBootstrap()).diagnostics;

  Future<PlayerProfileStats> resetAllData() async {
    _matches.clear();
    _moves.clear();
    return const PlayerProfileStats();
  }

  Future<void> onAppBackgrounded() async {}

  Future<void> close() async {
    _ready = false;
  }
}

