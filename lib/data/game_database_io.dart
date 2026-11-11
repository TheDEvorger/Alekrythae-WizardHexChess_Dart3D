import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../game/chess_game.dart';
import '../game/hex_board.dart';
import 'game_models.dart';

/// Canlı (production) ortam için tasarlanmış, arka plan Isolate üzerinde çalışan,
/// WAL + PreparedStatement + Debounce optimizasyonlu SQLite veritabanı yöneticisi.
class GameDatabase {
  GameDatabase._();

  static final GameDatabase instance = GameDatabase._();

  /// Birim testleri için özel veritabanı örneği oluşturur (`:memory:` veya geçici dosya).
  static Future<GameDatabase> openForTesting(String dbPath) async {
    final db = GameDatabase._();
    await db.init(overrideDbPath: dbPath);
    return db;
  }

  SendPort? _workerCmdPort;
  ReceivePort? _replyPort;
  Isolate? _workerIsolate;
  int _nextReqId = 1;
  final Map<int, Completer<Object?>> _pending = {};

  Timer? _settingsDebounce;
  PersistedSettings? _queuedSettings;
  bool _initialized = false;
  String _dbPath = '';

  bool get isReady => _initialized && _workerCmdPort != null;
  String get dbPath => _dbPath;

  Future<InitialDatabaseBootstrap> init({String? overrideDbPath}) async {
    if (_initialized && _workerCmdPort != null) {
      return loadBootstrap();
    }

    if (overrideDbPath != null && overrideDbPath.isNotEmpty) {
      _dbPath = overrideDbPath;
    } else {
      try {
        final supportDir = await getApplicationSupportDirectory();
        await supportDir.create(recursive: true);
        _dbPath = p.join(supportDir.path, 'wizard_hex_chess_live.sqlite');
      } catch (_) {
        final fallback = Directory(
          p.join(Directory.systemTemp.path, 'wizard_hex_chess_db'),
        );
        await fallback.create(recursive: true);
        _dbPath = p.join(fallback.path, 'wizard_hex_chess_live.sqlite');
      }
    }

    final handshake = ReceivePort();
    _replyPort = ReceivePort();
    _replyPort!.listen(_onWorkerReply);

    _workerIsolate = await Isolate.spawn<_WorkerInitMsg>(
      _sqliteWorkerEntry,
      _WorkerInitMsg(
        dbPath: _dbPath,
        handshakePort: handshake.sendPort,
        replyPort: _replyPort!.sendPort,
      ),
      debugName: 'WizardHexSqliteWorker',
    );

    final first = await handshake.first;
    handshake.close();
    if (first is _WorkerInitError) {
      throw StateError('SQLite başlatılamadı: ${first.message}');
    }
    _workerCmdPort = first as SendPort;
    _initialized = true;

    return loadBootstrap();
  }

  void _onWorkerReply(dynamic raw) {
    if (raw is! List || raw.length < 3) return;
    final id = raw[0] as int;
    final ok = raw[1] as bool;
    final payload = raw[2];
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (ok) {
      completer.complete(payload);
    } else {
      completer.completeError(StateError(payload?.toString() ?? 'SQLite hatası'));
    }
  }

  Future<T> _request<T>(String op, [Map<String, Object?> args = const {}]) {
    final port = _workerCmdPort;
    if (port == null) {
      return Future<T>.error(StateError('SQLite henüz hazır değil.'));
    }
    final id = _nextReqId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    port.send([id, op, args]);
    return completer.future.then((v) => v as T);
  }

  Future<InitialDatabaseBootstrap> loadBootstrap() async {
    final map =
        await _request<Map<String, Object?>>('bootstrap');
    return _decodeBootstrap(map);
  }

  /// Slider/checkbox gibi sık değişen ayarları 250 ms birleştirerek (coalescing)
  /// tek bir atomik SQLite transaction halinde diske yazar.
  void scheduleSaveSettings(PersistedSettings settings) {
    _queuedSettings = settings;
    _settingsDebounce?.cancel();
    _settingsDebounce = Timer(const Duration(milliseconds: 250), () {
      flushPendingSettings();
    });
  }

  Future<void> flushPendingSettings() async {
    _settingsDebounce?.cancel();
    _settingsDebounce = null;
    final pending = _queuedSettings;
    if (pending == null || !isReady) return;
    _queuedSettings = null;
    await saveSettingsImmediate(pending);
  }

  Future<void> saveSettingsImmediate(PersistedSettings settings) async {
    if (!isReady) return;
    await _request<Object?>('save_settings', {
      'entries': settings.toKeyValues(),
    });
  }

  /// Yeni bir maç oturumu başlatır (önceki yarım kalan aktif maçları temiz biçimde arşivler).
  Future<int> startNewMatch({
    required BoardVariant variant,
    BoardSize boardSize = BoardSize.classic,
    required String modeName,
    required String aiLevelName,
    required Team humanTeam,
  }) async {
    if (!isReady) return -1;
    return _request<int>('start_match', {
      'variant': variant.name,
      'board_size': (variant == BoardVariant.threePlayer
              ? boardSize
              : BoardSize.classic)
          .name,
      'mode': modeName,
      'ai_level': aiLevelName,
      'human_team': humanTeam.name,
    });
  }

  /// Tek bir atomik `BEGIN IMMEDIATE ... COMMIT` işlemi içinde hamleyi `match_moves`
  /// tablosuna ekler, `matches` anlık görüntüsünü günceller ve esir sayacını artırır.
  Future<void> recordMove({
    required int matchId,
    required int ply,
    required MoveRecord record,
    required List<int> allEncodedMoves,
    required bool humanCapture,
    BoardShape? shape,
  }) async {
    if (!isReady || matchId <= 0) return;
    final names = shape ?? BoardShape.of(BoardVariant.twoPlayer);
    await _request<Object?>('record_move', {
      'match_id': matchId,
      'ply': ply,
      'team': record.piece.team.name,
      'piece': record.piece.kind.name,
      'from_cell': names.name(record.from),
      'to_cell': names.name(record.to),
      'captured_piece': record.captured?.kind.name,
      'promoted': record.promoted ? 1 : 0,
      'encoded_move': record.encoded,
      'encoded_moves_json': jsonEncode(allEncodedMoves),
      'human_capture': humanCapture ? 1 : 0,
    });
  }

  /// Hamle geri alındığında (`undoSingle`) ilgili hamle satırlarını siler ve anlık durumu günceller.
  Future<void> recordUndo({
    required int matchId,
    required int newPlyCount,
    required List<int> remainingEncodedMoves,
  }) async {
    if (!isReady || matchId <= 0) return;
    await _request<Object?>('record_undo', {
      'match_id': matchId,
      'ply_count': newPlyCount,
      'encoded_moves_json': jsonEncode(remainingEncodedMoves),
    });
  }

  /// Maç tamamlandığında sonucu kaydeder, ELO puanını ve kariyer istatistiklerini günceller.
  Future<PlayerProfileStats> finishMatch({
    required int matchId,
    required BoardVariant variant,
    required String finalStatus, // 'checkmate', 'stalemate', 'draw'
    required Team? winnerTeam,
    required Team humanTeam,
    required bool ratedHumanMatch,
    required int opponentElo,
    required int elapsedSeconds,
  }) async {
    if (!isReady) return const PlayerProfileStats();
    final map = await _request<Map<String, Object?>>('finish_match', {
      'match_id': matchId,
      'variant': variant.name,
      'status': finalStatus,
      'winner_team': winnerTeam?.name,
      'human_team': humanTeam.name,
      'rated': ratedHumanMatch ? 1 : 0,
      'opponent_elo': opponentElo,
      'elapsed_seconds': elapsedSeconds,
    });
    return _decodeProfile(map);
  }

  Future<List<MoveLogEntry>> loadMovesForMatch(int matchId) async {
    if (!isReady || matchId <= 0) return const [];
    final list = await _request<List<Object?>>('load_moves', {
      'match_id': matchId,
    });
    return [
      for (final raw in list.cast<Map<String, Object?>>())
        MoveLogEntry(
          ply: raw['ply'] as int,
          team: raw['team'] as String,
          piece: raw['piece'] as String,
          fromCell: raw['from_cell'] as String,
          toCell: raw['to_cell'] as String,
          capturedPiece: raw['captured_piece'] as String?,
          promoted: (raw['promoted'] as int) != 0,
          encodedMove: raw['encoded_move'] as int,
          createdAtMs: raw['created_at'] as int,
        ),
    ];
  }

  Future<List<SavedMatchSummary>> loadRecentMatches({int limit = 20}) async {
    if (!isReady) return const [];
    final list = await _request<List<Object?>>('recent_matches', {
      'limit': limit,
    });
    return [
      for (final raw in list.cast<Map<String, Object?>>()) _decodeMatch(raw),
    ];
  }

  Future<SqliteDiagnostics> loadDiagnostics() async {
    final map = await _request<Map<String, Object?>>('diagnostics');
    return _decodeDiagnostics(map);
  }

  /// Tüm geçmiş maçları, hamle dökümlerini ve komutan kariyer istatistiklerini sıfırlar.
  Future<PlayerProfileStats> resetAllData() async {
    if (!isReady) return const PlayerProfileStats();
    await flushPendingSettings();
    final map = await _request<Map<String, Object?>>('reset_all_data');
    return _decodeProfile(map);
  }

  /// Uygulama arka plana alındığında bekleyen yazmaları tamamlar ve WAL checkpoint çalıştırır.
  Future<void> onAppBackgrounded() async {
    if (!isReady) return;
    await flushPendingSettings();
    await _request<Object?>('checkpoint');
  }

  Future<void> close() async {
    await flushPendingSettings();
    if (_workerCmdPort != null) {
      try {
        await _request<Object?>('close');
      } catch (_) {}
    }
    _workerCmdPort = null;
    _replyPort?.close();
    _replyPort = null;
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _initialized = false;
  }

  // ---------------------------------------------------------------- Decode yardımcıları
  static InitialDatabaseBootstrap _decodeBootstrap(Map<String, Object?> map) {
    final settingsRaw =
        (map['settings'] as Map).cast<String, String>();
    final profileRaw =
        (map['profile'] as Map).cast<String, Object?>();
    final activeRaw = map['active_match'] as Map?;
    final recentRaw = (map['recent_matches'] as List).cast<Map>();
    final diagRaw = (map['diagnostics'] as Map).cast<String, Object?>();

    return InitialDatabaseBootstrap(
      settings: PersistedSettings.fromKeyValues(settingsRaw),
      profile: _decodeProfile(profileRaw),
      activeMatch: activeRaw == null
          ? null
          : _decodeMatch(activeRaw.cast<String, Object?>()),
      recentMatches: [
        for (final r in recentRaw) _decodeMatch(r.cast<String, Object?>()),
      ],
      diagnostics: _decodeDiagnostics(diagRaw),
    );
  }

  static PlayerProfileStats _decodeProfile(Map<String, Object?> m) =>
      PlayerProfileStats(
        commanderName: (m['commander_name'] as String?) ?? 'Kuzey Komutanı',
        elo2P: (m['elo_2p'] as int?) ?? 1200,
        elo3P: (m['elo_3p'] as int?) ?? 1200,
        gamesPlayed: (m['games_played'] as int?) ?? 0,
        wins: (m['wins'] as int?) ?? 0,
        losses: (m['losses'] as int?) ?? 0,
        draws: (m['draws'] as int?) ?? 0,
        totalCaptures: (m['total_captures'] as int?) ?? 0,
        playSeconds: (m['play_seconds'] as int?) ?? 0,
      );

  static SavedMatchSummary _decodeMatch(Map<String, Object?> m) {
    final vName = m['variant'] as String?;
    final variant = vName == BoardVariant.threePlayer.name
        ? BoardVariant.threePlayer
        : BoardVariant.twoPlayer;

    Team parseTeam(String? s) {
      for (final t in Team.values) {
        if (t.name == s) return t;
      }
      return Team.white;
    }

    Team? parseNullableTeam(String? s) {
      if (s == null || s.isEmpty) return null;
      for (final t in Team.values) {
        if (t.name == s) return t;
      }
      return null;
    }

    final rawJson = (m['encoded_moves_json'] as String?) ?? '[]';
    List<int> moves;
    try {
      moves = (jsonDecode(rawJson) as List).cast<int>();
    } catch (_) {
      moves = const [];
    }

    return SavedMatchSummary(
      id: m['id'] as int,
      variant: variant,
      boardSize: variant == BoardVariant.threePlayer
          ? BoardSize.fromName(m['board_size'] as String?)
          : BoardSize.classic,
      modeName: (m['mode'] as String?) ?? 'humanVsAi',
      aiLevelName: (m['ai_level'] as String?) ?? 'wizard',
      humanTeam: parseTeam(m['human_team'] as String?),
      status: (m['status'] as String?) ?? 'active',
      winnerTeam: parseNullableTeam(m['winner_team'] as String?),
      plyCount: (m['ply_count'] as int?) ?? moves.length,
      encodedMoves: moves,
      startedAtMs: (m['started_at'] as int?) ?? 0,
      updatedAtMs: (m['updated_at'] as int?) ?? 0,
    );
  }

  static SqliteDiagnostics _decodeDiagnostics(Map<String, Object?> m) =>
      SqliteDiagnostics(
        sqliteVersion: (m['sqlite_version'] as String?) ?? '',
        journalMode: (m['journal_mode'] as String?) ?? '',
        synchronousMode: (m['synchronous'] as int?) ?? 1,
        foreignKeysEnabled: ((m['foreign_keys'] as int?) ?? 0) != 0,
        dbPath: (m['db_path'] as String?) ?? '',
        dbSizeBytes: (m['db_size_bytes'] as int?) ?? 0,
        activeMatches: (m['active_matches'] as int?) ?? 0,
        completedMatches: (m['completed_matches'] as int?) ?? 0,
      );
}

// ==================================================================== ARKA PLAN SQLITE WORKER ISOLATE
class _WorkerInitMsg {
  const _WorkerInitMsg({
    required this.dbPath,
    required this.handshakePort,
    required this.replyPort,
  });

  final String dbPath;
  final SendPort handshakePort;
  final SendPort replyPort;
}

class _WorkerInitError {
  const _WorkerInitError(this.message);
  final String message;
}

void _sqliteWorkerEntry(_WorkerInitMsg init) {
  late final _SqliteWorkerEngine engine;
  try {
    engine = _SqliteWorkerEngine(init.dbPath);
  } catch (e) {
    init.handshakePort.send(_WorkerInitError(e.toString()));
    return;
  }

  final cmdPort = ReceivePort();
  init.handshakePort.send(cmdPort.sendPort);

  cmdPort.listen((dynamic msg) {
    if (msg is! List || msg.length < 3) return;
    final id = msg[0] as int;
    final op = msg[1] as String;
    final args = (msg[2] as Map).cast<String, Object?>();

    try {
      final res = engine.handle(op, args);
      init.replyPort.send([id, true, res]);
      if (op == 'close') {
        cmdPort.close();
      }
    } catch (e) {
      init.replyPort.send([id, false, e.toString()]);
    }
  });
}

class _SqliteWorkerEngine {
  _SqliteWorkerEngine(this.dbPath) {
    db = dbPath == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(dbPath);
    _configurePragmas();
    _migrateSchema();
    _prepareHotStatements();
    _pruneAncientArchives();
  }

  /// 1: ilk şema • 2: `matches.board_size` (3 kişilik masa tahta boyutu).
  static const int _targetSchemaVersion = 2;
  static const int _maxArchivedMatches = 200;

  final String dbPath;
  late final Database db;

  late final PreparedStatement _stmtUpsertSetting;
  late final PreparedStatement _stmtInsertMove;
  late final PreparedStatement _stmtUpdateMatchMoves;
  late final PreparedStatement _stmtTrimMovesAfterUndo;
  late final PreparedStatement _stmtIncrementCaptures;

  void _configurePragmas() {
    // Canlı oyun performansı için WAL + NORMAL senkronizasyon + RAM önbellek + mmap I/O
    db.execute('PRAGMA busy_timeout = 5000;');
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA temp_store = MEMORY;');
    db.execute('PRAGMA cache_size = -8000;'); // ~8 MB sayfa önbelleği
    db.execute('PRAGMA mmap_size = 67108864;'); // 64 MB bellek eşlemeli okuma
    db.execute('PRAGMA wal_autocheckpoint = 1000;');
  }

  void _migrateSchema() {
    final verRow = db.select('PRAGMA user_version;');
    final currentVersion =
        verRow.isEmpty ? 0 : (verRow.first.values.first as int? ?? 0);

    if (currentVersion < 1) {
      _inTransaction(() {
        db.execute('''
          CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT NOT NULL PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          ) STRICT;
        ''');

        db.execute('''
          CREATE TABLE IF NOT EXISTS player_profile (
            id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
            commander_name TEXT NOT NULL,
            elo_2p INTEGER NOT NULL DEFAULT 1200,
            elo_3p INTEGER NOT NULL DEFAULT 1200,
            games_played INTEGER NOT NULL DEFAULT 0,
            wins INTEGER NOT NULL DEFAULT 0,
            losses INTEGER NOT NULL DEFAULT 0,
            draws INTEGER NOT NULL DEFAULT 0,
            total_captures INTEGER NOT NULL DEFAULT 0,
            play_seconds INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
          ) STRICT;
        ''');

        db.execute('''
          INSERT OR IGNORE INTO player_profile (
            id, commander_name, elo_2p, elo_3p, games_played,
            wins, losses, draws, total_captures, play_seconds, updated_at
          ) VALUES (1, 'Kuzey Komutanı', 1200, 1200, 0, 0, 0, 0, 0, 0, ?);
        ''', [_nowMs()]);

        db.execute('''
          CREATE TABLE IF NOT EXISTS matches (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            variant TEXT NOT NULL,
            mode TEXT NOT NULL,
            ai_level TEXT NOT NULL,
            human_team TEXT NOT NULL,
            status TEXT NOT NULL,
            winner_team TEXT,
            ply_count INTEGER NOT NULL DEFAULT 0,
            encoded_moves_json TEXT NOT NULL DEFAULT '[]',
            started_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          ) STRICT;
        ''');

        db.execute('''
          CREATE INDEX IF NOT EXISTS idx_matches_status_updated
          ON matches (status, updated_at DESC);
        ''');

        db.execute('''
          CREATE TABLE IF NOT EXISTS match_moves (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            match_id INTEGER NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
            ply INTEGER NOT NULL,
            team TEXT NOT NULL,
            piece TEXT NOT NULL,
            from_cell TEXT NOT NULL,
            to_cell TEXT NOT NULL,
            captured_piece TEXT,
            promoted INTEGER NOT NULL DEFAULT 0,
            encoded_move INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            UNIQUE (match_id, ply)
          ) STRICT;
        ''');

        db.execute('''
          CREATE INDEX IF NOT EXISTS idx_match_moves_match_ply
          ON match_moves (match_id, ply);
        ''');

        db.execute('PRAGMA user_version = 1;');
      });
    }

    if (currentVersion < 2) {
      _inTransaction(() {
        // Eski maçların hepsi Klasik tahtada oynandı: varsayılan değer onları doğru etiketler.
        final cols = db.select('PRAGMA table_info(matches);');
        final hasCol = cols.any((r) => r['name'] == 'board_size');
        if (!hasCol) {
          db.execute(
            "ALTER TABLE matches ADD COLUMN board_size TEXT NOT NULL DEFAULT 'classic';",
          );
        }
        db.execute('PRAGMA user_version = $_targetSchemaVersion;');
      });
    }
  }

  void _prepareHotStatements() {
    _stmtUpsertSetting = db.prepare('''
      INSERT INTO app_settings (key, value, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        updated_at = excluded.updated_at;
    ''');

    _stmtInsertMove = db.prepare('''
      INSERT INTO match_moves (
        match_id, ply, team, piece, from_cell, to_cell,
        captured_piece, promoted, encoded_move, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(match_id, ply) DO UPDATE SET
        team = excluded.team,
        piece = excluded.piece,
        from_cell = excluded.from_cell,
        to_cell = excluded.to_cell,
        captured_piece = excluded.captured_piece,
        promoted = excluded.promoted,
        encoded_move = excluded.encoded_move,
        created_at = excluded.created_at;
    ''');

    _stmtUpdateMatchMoves = db.prepare('''
      UPDATE matches
      SET ply_count = ?, encoded_moves_json = ?, updated_at = ?
      WHERE id = ?;
    ''');

    _stmtTrimMovesAfterUndo = db.prepare('''
      DELETE FROM match_moves WHERE match_id = ? AND ply >= ?;
    ''');

    _stmtIncrementCaptures = db.prepare('''
      UPDATE player_profile
      SET total_captures = total_captures + 1, updated_at = ?
      WHERE id = 1;
    ''');
  }

  void _pruneAncientArchives() {
    _inTransaction(() {
      // Hamlesiz kalmış boş eski 'active' kayıtları temizle
      db.execute(
        "DELETE FROM matches WHERE status = 'active' AND ply_count = 0;",
      );
      // En güncel _maxArchivedMatches tamamlanmış maçı tut, daha eskileri CASCADE ile sil
      db.execute('''
        DELETE FROM matches
        WHERE status != 'active'
          AND id NOT IN (
            SELECT id FROM matches
            WHERE status != 'active'
            ORDER BY updated_at DESC
            LIMIT $_maxArchivedMatches
          );
      ''');
    });
  }

  T _inTransaction<T>(T Function() body) {
    db.execute('BEGIN IMMEDIATE;');
    try {
      final result = body();
      db.execute('COMMIT;');
      return result;
    } catch (_) {
      try {
        db.execute('ROLLBACK;');
      } catch (_) {}
      rethrow;
    }
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  Object? handle(String op, Map<String, Object?> args) {
    return switch (op) {
      'bootstrap' => _handleBootstrap(),
      'save_settings' => _handleSaveSettings(args),
      'start_match' => _handleStartMatch(args),
      'record_move' => _handleRecordMove(args),
      'record_undo' => _handleRecordUndo(args),
      'finish_match' => _handleFinishMatch(args),
      'load_moves' => _handleLoadMoves(args),
      'recent_matches' => _queryRecentMatches((args['limit'] as int?) ?? 20),
      'reset_all_data' => _handleResetAllData(),
      'diagnostics' => _queryDiagnostics(),
      'checkpoint' => _handleCheckpoint(),
      'close' => _handleClose(),
      _ => throw UnsupportedError('Bilinmeyen SQLite komutu: $op'),
    };
  }

  Map<String, Object?> _handleBootstrap() {
    final settingsRows = db.select('SELECT key, value FROM app_settings;');
    final settingsMap = <String, String>{
      for (final row in settingsRows)
        row['key'] as String: row['value'] as String,
    };

    final activeRows = db.select('''
      SELECT * FROM matches
      WHERE status = 'active' AND ply_count > 0
      ORDER BY updated_at DESC
      LIMIT 1;
    ''');

    return {
      'settings': settingsMap,
      'profile': _queryProfile(),
      'active_match': activeRows.isEmpty ? null : _rowToMap(activeRows.first),
      'recent_matches': _queryRecentMatches(15),
      'diagnostics': _queryDiagnostics(),
    };
  }

  Object? _handleSaveSettings(Map<String, Object?> args) {
    final entries = (args['entries'] as Map).cast<String, String>();
    final now = _nowMs();
    _inTransaction(() {
      entries.forEach((k, v) {
        _stmtUpsertSetting.execute([k, v, now]);
      });
    });
    return null;
  }

  int _handleStartMatch(Map<String, Object?> args) {
    final now = _nowMs();
    return _inTransaction(() {
      // Önceki yarım kalmış maçları 'abandoned' olarak kapat, hamlesizleri sil
      db.execute(
        "DELETE FROM matches WHERE status = 'active' AND ply_count = 0;",
      );
      db.execute(
        "UPDATE matches SET status = 'abandoned', updated_at = ? WHERE status = 'active';",
        [now],
      );
      db.execute('''
        INSERT INTO matches (
          variant, board_size, mode, ai_level, human_team, status,
          winner_team, ply_count, encoded_moves_json, started_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, 'active', NULL, 0, '[]', ?, ?);
      ''', [
        args['variant'],
        (args['board_size'] as String?) ?? BoardSize.classic.name,
        args['mode'],
        args['ai_level'],
        args['human_team'],
        now,
        now,
      ]);
      return db.lastInsertRowId;
    });
  }

  Object? _handleRecordMove(Map<String, Object?> args) {
    final now = _nowMs();
    final matchId = args['match_id'] as int;
    final ply = args['ply'] as int;
    final movesJson = args['encoded_moves_json'] as String;
    final humanCap = (args['human_capture'] as int? ?? 0) != 0;

    _inTransaction(() {
      _stmtInsertMove.execute([
        matchId,
        ply,
        args['team'],
        args['piece'],
        args['from_cell'],
        args['to_cell'],
        args['captured_piece'],
        args['promoted'],
        args['encoded_move'],
        now,
      ]);
      _stmtUpdateMatchMoves.execute([ply + 1, movesJson, now, matchId]);
      if (humanCap) {
        _stmtIncrementCaptures.execute([now]);
      }
    });
    return null;
  }

  Object? _handleRecordUndo(Map<String, Object?> args) {
    final now = _nowMs();
    final matchId = args['match_id'] as int;
    final plyCount = args['ply_count'] as int;
    final movesJson = args['encoded_moves_json'] as String;

    _inTransaction(() {
      _stmtTrimMovesAfterUndo.execute([matchId, plyCount]);
      _stmtUpdateMatchMoves.execute([plyCount, movesJson, now, matchId]);
    });
    return null;
  }

  Map<String, Object?> _handleFinishMatch(Map<String, Object?> args) {
    final now = _nowMs();
    final matchId = args['match_id'] as int;
    final variant = args['variant'] as String;
    final status = args['status'] as String;
    final winnerTeam = args['winner_team'] as String?;
    final humanTeam = args['human_team'] as String;
    final rated = (args['rated'] as int? ?? 0) != 0;
    final opponentElo = (args['opponent_elo'] as int?) ?? 1200;
    final elapsedSeconds = (args['elapsed_seconds'] as int?) ?? 0;

    return _inTransaction(() {
      if (matchId > 0) {
        db.execute('''
          UPDATE matches
          SET status = ?, winner_team = ?, updated_at = ?
          WHERE id = ?;
        ''', [status, winnerTeam, now, matchId]);
      }

      final prof = _queryProfile();
      var elo2p = prof['elo_2p'] as int;
      var elo3p = prof['elo_3p'] as int;
      var games = (prof['games_played'] as int) + 1;
      var wins = prof['wins'] as int;
      var losses = prof['losses'] as int;
      var draws = prof['draws'] as int;
      final playSec = (prof['play_seconds'] as int) + elapsedSeconds;

      if (rated) {
        final double score;
        if (winnerTeam == null) {
          score = 0.5;
          draws++;
        } else if (winnerTeam == humanTeam) {
          score = 1.0;
          wins++;
        } else {
          score = 0.0;
          losses++;
        }

        if (variant == BoardVariant.threePlayer.name) {
          elo3p = PlayerProfileStats.computeNextElo(
            currentElo: elo3p,
            opponentElo: opponentElo,
            score: score,
          );
        } else {
          elo2p = PlayerProfileStats.computeNextElo(
            currentElo: elo2p,
            opponentElo: opponentElo,
            score: score,
          );
        }
      } else {
        if (winnerTeam == null) {
          draws++;
        } else if (winnerTeam == humanTeam) {
          wins++;
        } else {
          losses++;
        }
      }

      db.execute('''
        UPDATE player_profile
        SET elo_2p = ?, elo_3p = ?, games_played = ?,
            wins = ?, losses = ?, draws = ?, play_seconds = ?, updated_at = ?
        WHERE id = 1;
      ''', [elo2p, elo3p, games, wins, losses, draws, playSec, now]);

      return _queryProfile();
    });
  }

  List<Map<String, Object?>> _handleLoadMoves(Map<String, Object?> args) {
    final matchId = args['match_id'] as int;
    final rows = db.select('''
      SELECT ply, team, piece, from_cell, to_cell,
             captured_piece, promoted, encoded_move, created_at
      FROM match_moves
      WHERE match_id = ?
      ORDER BY ply ASC;
    ''', [matchId]);
    return [for (final r in rows) _rowToMap(r)];
  }

  Map<String, Object?> _queryProfile() {
    final rows = db.select('SELECT * FROM player_profile WHERE id = 1;');
    return rows.isEmpty ? const {} : _rowToMap(rows.first);
  }

  List<Map<String, Object?>> _queryRecentMatches(int limit) {
    final rows = db.select('''
      SELECT * FROM matches
      WHERE ply_count > 0
      ORDER BY updated_at DESC
      LIMIT ?;
    ''', [limit]);
    return [for (final r in rows) _rowToMap(r)];
  }

  Map<String, Object?> _queryDiagnostics() {
    final jm = db.select('PRAGMA journal_mode;');
    final sy = db.select('PRAGMA synchronous;');
    final fk = db.select('PRAGMA foreign_keys;');
    final activeCnt = db
        .select("SELECT COUNT(*) AS c FROM matches WHERE status = 'active' AND ply_count > 0;")
        .first['c'] as int;
    final doneCnt = db
        .select("SELECT COUNT(*) AS c FROM matches WHERE status != 'active' AND ply_count > 0;")
        .first['c'] as int;

    var sizeBytes = 0;
    if (dbPath != ':memory:' && dbPath.isNotEmpty) {
      final f = File(dbPath);
      if (f.existsSync()) {
        sizeBytes = f.lengthSync();
      }
    }

    return {
      'sqlite_version': sqlite3.version.libVersion,
      'journal_mode': jm.isEmpty ? '' : jm.first.values.first.toString(),
      'synchronous': sy.isEmpty ? 1 : (sy.first.values.first as int? ?? 1),
      'foreign_keys': fk.isEmpty ? 0 : (fk.first.values.first as int? ?? 0),
      'db_path': dbPath,
      'db_size_bytes': sizeBytes,
      'active_matches': activeCnt,
      'completed_matches': doneCnt,
    };
  }

  Map<String, Object?> _handleResetAllData() {
    final now = _nowMs();
    return _inTransaction(() {
      db.execute('DELETE FROM match_moves;');
      db.execute('DELETE FROM matches;');
      db.execute('''
        UPDATE player_profile
        SET elo_2p = 1200,
            elo_3p = 1200,
            games_played = 0,
            wins = 0,
            losses = 0,
            draws = 0,
            total_captures = 0,
            play_seconds = 0,
            updated_at = ?
        WHERE id = 1;
      ''', [now]);
      return _queryProfile();
    });
  }

  Object? _handleCheckpoint() {
    try {
      db.execute('PRAGMA optimize;');
      if (dbPath != ':memory:') {
        db.execute('PRAGMA wal_checkpoint(PASSIVE);');
      }
    } catch (_) {}
    return null;
  }

  Object? _handleClose() {
    _handleCheckpoint();
    _stmtUpsertSetting.close();
    _stmtInsertMove.close();
    _stmtUpdateMatchMoves.close();
    _stmtTrimMovesAfterUndo.close();
    _stmtIncrementCaptures.close();
    db.close();
    return null;
  }

  static Map<String, Object?> _rowToMap(Row row) {
    final out = <String, Object?>{};
    for (final k in row.keys) {
      out[k] = row[k];
    }
    return out;
  }
}

