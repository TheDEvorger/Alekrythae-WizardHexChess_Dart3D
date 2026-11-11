import 'package:flutter_test/flutter_test.dart';
import 'package:wizard_hex_chess_dart3d/data/game_database.dart';
import 'package:wizard_hex_chess_dart3d/game/chess_game.dart';
import 'package:wizard_hex_chess_dart3d/game/hex_board.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SQLite Kalıcılık ve Canlı Veri Motoru Testleri', () {
    late GameDatabase db;

    setUp(() async {
      db = await GameDatabase.openForTesting(':memory:');
    });

    tearDown(() async {
      await db.close();
    });

    test('SQLite bootstrap şemayı ve başlangıç ayarlarını oluşturur', () async {
      final diag = await db.loadDiagnostics();
      expect(diag.dbPath, equals(':memory:'));
      expect(diag.sqliteVersion, isNotEmpty);
      expect(diag.activeMatches, equals(0));
      expect(diag.completedMatches, equals(0));

      final boot = await db.loadBootstrap();
      expect(boot.settings.povEnabled, isTrue);
      expect(boot.settings.graphicsQuality, equals(GraphicsQuality.balanced));
      expect(boot.settings.moveSpeed, closeTo(0.80, 0.01));
      expect(boot.settings.combatSpeed, closeTo(0.70, 0.01));
      expect(boot.profile.elo2P, equals(1200));
      expect(boot.profile.elo3P, equals(1200));
    });

    test('Ayarlar güncellenip SQLite tablosuna yazılır', () async {
      const updated = PersistedSettings(
        moveSpeed: 0.95,
        combatSpeed: 0.85,
        povEnabled: false,
        graphicsQuality: GraphicsQuality.ultra,
        modeName: 'passAndPlay',
        aiLevelName: 'archmage',
      );

      await db.saveSettingsImmediate(updated);
      final boot = await db.loadBootstrap();
      expect(boot.settings.moveSpeed, closeTo(0.95, 0.001));
      expect(boot.settings.combatSpeed, closeTo(0.85, 0.001));
      expect(boot.settings.povEnabled, isFalse);
      expect(boot.settings.graphicsQuality, equals(GraphicsQuality.ultra));
      expect(boot.settings.modeName, equals('passAndPlay'));
      expect(boot.settings.aiLevelName, equals('archmage'));
    });

    test('Fırtına, yıldırım, sis ve gizemli atmosfer ayarları kaydedilip geri yüklenir', () async {
      final fresh = await db.loadBootstrap();
      expect(fresh.settings.stormIntensity, closeTo(1.5, 0.001));
      expect(fresh.settings.stormFog, closeTo(1.0, 0.001));
      expect(fresh.settings.lightningLinger, closeTo(1.2, 0.001));
      expect(fresh.settings.stormQuality, equals(StormQuality.auto));

      const updated = PersistedSettings(
        stormIntensity: 2.0,
        hauntLevel: 0.35,
        lightningRate: 2.75,
        thunderVolume: 0.6,
        ambienceVolume: 0.0,
        stormFog: 2.4,
        lightningLinger: 2.5,
        stormQuality: StormQuality.cinematic,
      );
      await db.saveSettingsImmediate(updated);
      final boot = await db.loadBootstrap();
      expect(boot.settings.stormIntensity, closeTo(2.0, 0.001));
      expect(boot.settings.hauntLevel, closeTo(0.35, 0.001));
      expect(boot.settings.lightningRate, closeTo(2.75, 0.001));
      expect(boot.settings.thunderVolume, closeTo(0.6, 0.001));
      expect(boot.settings.ambienceVolume, closeTo(0.0, 0.001));
      expect(boot.settings.stormFog, closeTo(2.4, 0.001));
      expect(boot.settings.lightningLinger, closeTo(2.5, 0.001));
      expect(boot.settings.stormQuality, equals(StormQuality.cinematic));

      // Elle girilen, kaydırıcı sınırının üstündeki değerler korunur
      const manual = PersistedSettings(
        stormIntensity: 4.5,
        hauntLevel: 2.0,
        thunderVolume: 1.5,
        stormFog: 6.0,
      );
      await db.saveSettingsImmediate(manual);
      final manualBoot = await db.loadBootstrap();
      expect(manualBoot.settings.stormIntensity, closeTo(4.5, 0.001));
      expect(manualBoot.settings.hauntLevel, closeTo(2.0, 0.001));
      expect(manualBoot.settings.thunderVolume, closeTo(1.5, 0.001));
      expect(manualBoot.settings.stormFog, closeTo(6.0, 0.001));

      // Atmosfer ayarlarının üst sınırı yok; bozuk / negatif / sonsuz değerler elenir
      final parsed = PersistedSettings.fromKeyValues({
        'storm_intensity': '99',
        'lightning_rate': 'abc',
        'storm_fog': '-3',
        'lightning_linger': '1e9',
        'thunder_volume': 'Infinity',
        'storm_quality': 'yok',
      });
      expect(parsed.stormIntensity, closeTo(99.0, 0.001));
      expect(parsed.lightningRate, closeTo(1.5, 0.001));
      expect(parsed.stormFog, closeTo(0.0, 0.001));
      expect(parsed.lightningLinger, closeTo(1e9, 0.001));
      expect(parsed.thunderVolume, closeTo(1.0, 0.001), reason: 'sonsuz değer varsayılana döner');
      expect(parsed.stormQuality, equals(StormQuality.auto));

      // Ses kanalları birbirinden bağımsız saklanır: müzik, konuşma, efekt
      const mixer = PersistedSettings(bgmVolume: 0.20, voiceVolume: 0.95, sfxVolume: 0.40, ambienceVolume: 1.8);
      await db.saveSettingsImmediate(mixer);
      final mixerBoot = await db.loadBootstrap();
      expect(mixerBoot.settings.bgmVolume, closeTo(0.20, 0.001));
      expect(mixerBoot.settings.voiceVolume, closeTo(0.95, 0.001));
      expect(mixerBoot.settings.sfxVolume, closeTo(0.40, 0.001));
      expect(mixerBoot.settings.ambienceVolume, closeTo(1.8, 0.001));

      // Düello kapışma turu: varsayılan 4, üst sınırı yok, negatif 0'a çekilir
      expect(const PersistedSettings().duelRounds, 4.0);
      await db.saveSettingsImmediate(const PersistedSettings(duelRounds: 25));
      expect((await db.loadBootstrap()).settings.duelRounds, closeTo(25.0, 0.001));
      expect(PersistedSettings.fromKeyValues({'duel_rounds': '-2'}).duelRounds, 0.0);
      expect(PersistedSettings.fromKeyValues({}).duelRounds, 4.0, reason: 'eski kayıtlarda varsayılan');

      // Düello karmaşıklığı: varsayılan 2 (Usta), üst sınırı yok
      expect(const PersistedSettings().duelComplexity, 2.0);
      await db.saveSettingsImmediate(const PersistedSettings(duelComplexity: 9));
      expect((await db.loadBootstrap()).settings.duelComplexity, closeTo(9.0, 0.001));
      expect(PersistedSettings.fromKeyValues({}).duelComplexity, 2.0);

      // Eski kayıtlarda konuşma/efekt anahtarı yoksa varsayılanlar kullanılır
      final legacy = PersistedSettings.fromKeyValues({'bgm_volume': '0.3', 'voice_volume': '7'});
      expect(legacy.bgmVolume, closeTo(0.3, 0.001));
      expect(legacy.voiceVolume, closeTo(1.0, 0.001));
      expect(legacy.sfxVolume, closeTo(0.85, 0.001));
    });

    test('Maç başlatma, hamle kaydetme, geri alma ve maç bitirme SQLite işlem akışı', () async {
      // 1. Yeni maç oluştur
      final matchId = await db.startNewMatch(
        variant: BoardVariant.twoPlayer,
        modeName: 'humanVsAi',
        aiLevelName: 'wizard',
        humanTeam: Team.white,
      );
      expect(matchId, greaterThan(0));

      // 2. Hamleleri kaydet
      await db.recordMove(
        matchId: matchId,
        ply: 0,
        record: MoveRecord(
          piece: const ChessPiece(Team.white, PieceType.pawn),
          from: HexBoard.parse('f5'),
          to: HexBoard.parse('f6'),
          captured: null,
          promotedTo: null,
          encoded: 12345,
        ),
        allEncodedMoves: [12345],
        humanCapture: false,
      );
      await db.recordMove(
        matchId: matchId,
        ply: 1,
        record: MoveRecord(
          piece: const ChessPiece(Team.black, PieceType.knight),
          from: HexBoard.parse('g9'),
          to: HexBoard.parse('f7'),
          captured: const ChessPiece(Team.white, PieceType.pawn),
          promotedTo: null,
          encoded: 67890,
        ),
        allEncodedMoves: [12345, 67890],
        humanCapture: false,
      );

      // Aktif maçı doğrula
      final boot = await db.loadBootstrap();
      expect(boot.activeMatch, isNotNull);
      expect(boot.activeMatch!.id, equals(matchId));
      expect(boot.activeMatch!.variant, equals(BoardVariant.twoPlayer));
      expect(boot.activeMatch!.plyCount, equals(2));

      // Hamle kayıtlarını kontrol et
      final logs = await db.loadMovesForMatch(matchId);
      expect(logs.length, equals(2));
      expect(logs[0].fromCell, equals('f5'));
      expect(logs[1].capturedPiece, equals('pawn'));

      // 3. Hamle geri alma (recordUndo)
      await db.recordUndo(
        matchId: matchId,
        newPlyCount: 1,
        remainingEncodedMoves: [12345],
      );
      final trimmedLogs = await db.loadMovesForMatch(matchId);
      expect(trimmedLogs.length, equals(1));
      expect(trimmedLogs.first.ply, equals(0));

      // 4. Maçı zaferle sonuçlandır ve ELO güncelle
      final updatedProfile = await db.finishMatch(
        matchId: matchId,
        variant: BoardVariant.twoPlayer,
        finalStatus: 'checkmate',
        winnerTeam: Team.white,
        humanTeam: Team.white,
        ratedHumanMatch: true,
        opponentElo: 1200,
        elapsedSeconds: 180,
      );

      expect(updatedProfile.wins, equals(1));
      expect(updatedProfile.gamesPlayed, equals(1));
      expect(updatedProfile.elo2P, greaterThan(1200));

      final matches = await db.loadRecentMatches();
      expect(matches.length, equals(1));
      expect(matches.first.id, equals(matchId));
      expect(matches.first.winnerTeam, equals(Team.white));
      expect(matches.first.status, equals('checkmate'));

      // Maç tamamlandığı için artık aktif maç kalmamalı
      final bootAfter = await db.loadBootstrap();
      expect(bootAfter.activeMatch, isNull);
    });

    test('ELO puanlama formülü beklenen matematiksel oranlarla çalışır', () {
      final winElo = PlayerProfileStats.computeNextElo(
        currentElo: 1200,
        opponentElo: 1200,
        score: 1.0,
      );
      expect(winElo, equals(1214)); // 1200 + 28 * (1.0 - 0.5) = 1214

      final lossElo = PlayerProfileStats.computeNextElo(
        currentElo: 1200,
        opponentElo: 1200,
        score: 0.0,
      );
      expect(lossElo, equals(1186)); // 1200 + 28 * (0.0 - 0.5) = 1186

      final drawElo = PlayerProfileStats.computeNextElo(
        currentElo: 1200,
        opponentElo: 1200,
        score: 0.5,
      );
      expect(drawElo, equals(1200));
    });

    test('Hamle dizisi JSON serileştirme ve geri yükleme oyunu birebir yeniden kurar', () {
      final game1 = ChessGame(variant: BoardVariant.twoPlayer);
      // Birkaç yasal hamle yapalım
      final from1 = HexBoard.parse('f5');
      final to1 = HexBoard.parse('f6');
      expect(game1.play(from1, to1), isTrue);

      final from2 = HexBoard.parse('g7');
      final to2 = HexBoard.parse('g6');
      expect(game1.play(from2, to2), isTrue);

      final encodedMoves = game1.exportEncodedMoves();
      expect(encodedMoves.length, equals(2));

      // İkinci boş oyun başlatıp hamleleri SQLite'tan gelir gibi geri yükle
      final game2 = ChessGame();
      final ok = game2.restoreFromEncodedMoves(BoardVariant.twoPlayer, encodedMoves);
      expect(ok, isTrue);
      expect(game2.turn, equals(game1.turn));
      expect(game2.ply, equals(game1.ply));
      expect(game2.pieceAt(HexBoard.parse('f6')), isNotNull);
      expect(game2.pieceAt(HexBoard.parse('g6')), isNotNull);
    });

    test('3 Kişilik masada hamle serileştirme ve geri yükleme', () {
      final game3 = ChessGame(variant: BoardVariant.threePlayer);
      final moves = game3.pos3.legalMoves();
      expect(moves, isNotEmpty);
      game3.applyEncoded(moves.first);
      expect(game3.turn, equals(Team.black));

      final encoded = game3.exportEncodedMoves();
      final restored = ChessGame();
      final success = restored.restoreFromEncodedMoves(BoardVariant.threePlayer, encoded);
      expect(success, isTrue);
      expect(restored.variant, equals(BoardVariant.threePlayer));
      expect(restored.turn, equals(Team.black));
      expect(restored.ply, equals(1));
    });

    test('resetAllData tüm maçları temizler ve komutan kariyerini 1200 başlangıç seviyesine döndürür', () async {
      // 1. Bir maç ve hamle kaydet
      final matchId = await db.startNewMatch(
        variant: BoardVariant.twoPlayer,
        modeName: 'humanVsAi',
        aiLevelName: 'wizard',
        humanTeam: Team.white,
      );
      expect(matchId, greaterThan(0));

      final rec = MoveRecord(
        from: HexBoard.parse('f5'),
        to: HexBoard.parse('f6'),
        piece: const ChessPiece(Team.white, PieceType.pawn),
        encoded: 12345,
      );
      await db.recordMove(
        matchId: matchId,
        ply: 0,
        record: rec,
        allEncodedMoves: [rec.encoded],
        humanCapture: false,
      );

      // Maçı zaferle bitir ve ELO kazan
      final p1 = await db.finishMatch(
        matchId: matchId,
        variant: BoardVariant.twoPlayer,
        finalStatus: 'checkmate',
        winnerTeam: Team.white,
        humanTeam: Team.white,
        ratedHumanMatch: true,
        opponentElo: 1200,
        elapsedSeconds: 45,
      );
      expect(p1.wins, equals(1));
      expect(p1.elo2P, greaterThan(1200));

      // 2. Şimdi oyunu ve kayıtları sıfırla
      final pReset = await db.resetAllData();
      expect(pReset.elo2P, equals(1200));
      expect(pReset.elo3P, equals(1200));
      expect(pReset.wins, equals(0));
      expect(pReset.losses, equals(0));
      expect(pReset.draws, equals(0));
      expect(pReset.gamesPlayed, equals(0));

      // Geçmiş maçların da silindiğini doğrula
      final recent = await db.loadRecentMatches();
      expect(recent, isEmpty);
    });
  });
}
