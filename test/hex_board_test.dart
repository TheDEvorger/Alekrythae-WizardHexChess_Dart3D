import 'package:flutter_test/flutter_test.dart';
import 'package:wizard_hex_chess_dart3d/audio/voice_catalog.dart';
import 'package:wizard_hex_chess_dart3d/game/ai.dart';
import 'package:wizard_hex_chess_dart3d/game/chess_game.dart';
import 'package:wizard_hex_chess_dart3d/game/hex_board.dart';
import 'package:wizard_hex_chess_dart3d/game/three_player_ai.dart';
import 'package:wizard_hex_chess_dart3d/game/three_player_game.dart';
import 'package:wizard_hex_chess_dart3d/render/creatures.dart';

void main() {
  test('Gliński tahtası 91 benzersiz hücreden oluşur', () {
    expect(HexBoard.cells.length, 91);
    expect(HexBoard.cells.toSet().length, 91);
    expect(HexBoard.name(const HexCell(0, 0)), 'f6');
  });

  test('Kare gösterimi tersine çevrilebilir', () {
    for (final cell in HexBoard.cells) {
      expect(HexBoard.parse(HexBoard.name(cell)), cell);
    }
    expect(() => HexBoard.parse('j2'), throwsFormatException);
    expect(() => HexBoard.parse('a10'), throwsFormatException);
  });

  test('2 kişilik oyunda her oyuncuda 18 taş ve üç farklı renkli fil vardır', () {
    final game = ChessGame();
    expect(game.pieces.length, 36);
    for (final team in const [Team.white, Team.black]) {
      final own = game.pieces.entries
          .where((entry) => entry.value.team == team)
          .toList();
      expect(own.length, 18);
      expect(own.where((e) => e.value.kind == PieceType.pawn).length, 9);
      final bishopColors = own
          .where((e) => e.value.kind == PieceType.bishop)
          .map((e) => HexBoard.colorIndex(e.key))
          .toSet();
      expect(bishopColors.length, 3);
    }
  });

  test('Amfi altıgen sütun yükseklikleri 2 ve 3 kişilik modda Kral/Kraliçe zirvesinden ortaya ve yanlara alçalır', () {
    double h2(String name) =>
        HexBoard.columnHeight(HexBoard.parse(name), BoardVariant.twoPlayer);

    // 2 kişilik mod: Beyaz & Siyah Kral/Kraliçe en yüksekte (>= 1.42)
    expect(h2('g1'), greaterThanOrEqualTo(1.45)); // Beyaz Kral
    expect(h2('e1'), greaterThanOrEqualTo(1.41)); // Beyaz Kraliçe
    expect(h2('e10'), greaterThanOrEqualTo(1.45)); // Siyah Kral
    expect(h2('g10'), greaterThanOrEqualTo(1.41)); // Siyah Kraliçe

    // Ortaya geldikçe kademeli alçalır
    expect(h2('g1'), greaterThan(h2('f3')));
    expect(h2('f3'), greaterThan(h2('f5')));
    expect(h2('f5'), greaterThan(h2('f6')));

    // Yan kanatlara gittikçe kademeli alçalır
    expect(h2('g1'), greaterThan(h2('i1')));
    expect(h2('i1'), greaterThan(h2('k1')));
    expect(h2('k1'), greaterThan(h2('l1')));
    expect(h2('e1'), greaterThan(h2('c1')));
    expect(h2('c1'), greaterThan(h2('b1')));
    expect(h2('b1'), greaterThan(h2('a1')));

    // 3 kişilik mod: 3 cephede (120° simetrik) Kral ve Kraliçe en yüksekte; orta ve yan köşeler aşağıda
    double h3(HexCell c) => HexBoard.columnHeight(c, BoardVariant.threePlayer);
    const wKing = HexCell(1, -5);
    const wQueen = HexCell(-1, -4);
    final bKing = ThreePlayerPosition.rot120(wKing, 1);
    final bQueen = ThreePlayerPosition.rot120(wQueen, 1);
    final eKing = ThreePlayerPosition.rot120(wKing, 2);
    final eQueen = ThreePlayerPosition.rot120(wQueen, 2);

    for (final royal in [wKing, wQueen, bKing, bQueen, eKing, eQueen]) {
      expect(h3(royal), greaterThanOrEqualTo(1.41));
      expect(h3(royal), greaterThan(h3(const HexCell(0, 0))));
      expect(h3(royal), greaterThan(h3(const HexCell(-5, 0))));
      expect(h3(royal), greaterThan(h3(const HexCell(0, 5))));
      expect(h3(royal), greaterThan(h3(const HexCell(5, -5))));
    }

    // 3B arena her iki varyantta da tüm 91 sütunu hatasız inşa eder
    final factory = CreatureFactory();
    final tileColors = [0x9A8C76, 0x6E6254, 0x453E3A];
    final arena2 = factory.buildArena(tileColors, variant: BoardVariant.twoPlayer);
    final arena3 = factory.buildArena(tileColors, variant: BoardVariant.threePlayer);
    expect(arena2.$1.geometry, isNotNull);
    expect(arena2.$2.geometry, isNotNull);
    expect(arena3.$1.geometry, isNotNull);
    expect(arena3.$2.geometry, isNotNull);
  });

  test('3 kişilik altıgen masa ve özel 3\'lü yapay zekâ 3 ordu için yasal çalışır', () {
    final game3 = ChessGame(variant: BoardVariant.threePlayer);
    expect(game3.pieces.length, 48);
    for (final team in Team.values) {
      final own = game3.pieces.entries.where((e) => e.value.team == team).toList();
      expect(own.length, 16);
      expect(own.where((e) => e.value.kind == PieceType.pawn).length, 7);
      final dragonColors = own
          .where((e) => e.value.kind == PieceType.bishop)
          .map((e) => HexBoard.colorIndex(e.key))
          .toSet();
      expect(dragonColors.length, 3);
    }

    // Serileştirme / geri yükleme doğrulaması
    final snap = ThreePlayerPosition.deserialize(game3.pos3.serialize());
    expect(snap.key, game3.pos3.key);

    // 3 ayrı ordunun sırayla özel 3 kişilik yapay zekâ ile hamle üretmesi (Beyaz -> Siyah -> Zümrüt -> Beyaz)
    final ai3 = ThreePlayerHexAi(maxDepth: 2, timeMs: 450, noise: 0);
    expect(game3.turn, Team.white);

    final mWhite = ai3.bestMove(game3.pos3);
    expect(mWhite, isNotNull);
    expect(game3.pos3.legalMoves(), contains(mWhite));
    game3.applyEncoded(mWhite!);
    expect(game3.turn, Team.black);

    final mBlack = ai3.bestMove(game3.pos3);
    expect(mBlack, isNotNull);
    expect(game3.pos3.legalMoves(), contains(mBlack));
    game3.applyEncoded(mBlack!);
    expect(game3.turn, Team.emerald);

    final mEmerald = ai3.bestMove(game3.pos3);
    expect(mEmerald, isNotNull);
    expect(game3.pos3.legalMoves(), contains(mEmerald));
    game3.applyEncoded(mEmerald!);
    expect(game3.turn, Team.white);
    expect(game3.ply, 3);

    // Geri al (undoSingle) tüm 3 ordu sırasını kusursuz geri sarar
    expect(game3.undoSingle(), isNotNull);
    expect(game3.turn, Team.emerald);
    expect(game3.undoSingle(), isNotNull);
    expect(game3.turn, Team.black);
    expect(game3.undoSingle(), isNotNull);
    expect(game3.turn, Team.white);
    expect(game3.pieces.length, 48);
  });

  test('3 kişilik dizilim her ordunun kendi ekseninde ayna simetrik, piyon duvarı kesintisiz', () {
    final game3 = ChessGame(variant: BoardVariant.threePlayer);
    final white = {
      for (final e in game3.pieces.entries)
        if (e.value.team == Team.white) e.key: e.value.kind,
    };

    // Beyaz ordunun ekseni q = 0 (köşe (0,-5) → merkez); aynası (q, r) → (-q, q + r).
    // Şah ve Vezir birbirinin aynasıdır, diğer tüm taşlar kendi türüne yansır.
    for (final MapEntry(key: c, value: kind) in white.entries) {
      final mirrored = white[HexCell(-c.q, c.q + c.r)];
      final expected = switch (kind) {
        PieceType.king => PieceType.queen,
        PieceType.queen => PieceType.king,
        _ => kind,
      };
      expect(mirrored, expected, reason: '${HexBoard.name(c)} aynası');
    }

    // 7 piyon birbirine bitişik tek bir zincir (V duvarı) oluşturur.
    final pawns = [
      for (final e in white.entries)
        if (e.value == PieceType.pawn) e.key,
    ];
    bool adjacent(HexCell a, HexCell b) {
      final dq = a.q - b.q, dr = a.r - b.r;
      return [dq.abs(), dr.abs(), (dq + dr).abs()].reduce((x, y) => x > y ? x : y) == 1;
    }

    final reached = {pawns.first};
    var grew = true;
    while (grew) {
      grew = false;
      for (final p in pawns) {
        if (!reached.contains(p) && reached.any((r) => adjacent(p, r))) {
          reached.add(p);
          grew = true;
        }
      }
    }
    expect(reached.length, 7);

    // Siyah ve Zümrüt, Beyaz'ın tam 120° / 240° döndürülmüş kopyasıdır.
    for (final t in [Team.black, Team.emerald]) {
      for (final MapEntry(key: c, value: kind) in white.entries) {
        final p = game3.pieces[ThreePlayerPosition.rot120(c, t.index)];
        expect(p?.team, t);
        expect(p?.kind, kind);
      }
    }
  });

  test('Yaratık kimlikleri, POV birinci şahıs uzuvları ve ses kataloğu doğru üretilir', () {
    expect(PieceType.bishop.creature, 'Ejderha');
    expect(PieceType.knight.creature, 'Suikastçi');
    expect(PieceType.rook.creature, 'Kadın Savaş Devi');
    expect(PieceType.queen.creature, 'Vampir Kraliçe');
    expect(PieceType.king.creature, 'Barbar Kral');
    expect(PieceType.pawn.creature, 'Kalkan Muhafızı');
    expect(kVoiceCatalog.length, 24);

    final factory = CreatureFactory();
    for (final team in Team.values) {
      for (final kind in PieceType.values) {
        final rig = factory.build(ChessPiece(team, kind));
        expect(rig.body.children, isNotEmpty);
        // POV birinci şahıs görünümü için her karakterde gövde, boyun kapağı (povHide), iki kol ve iki bacak eklemi bulunmalıdır
        expect(rig.parts['head'], isNotNull);
        expect(rig.parts['povHide'], isNotNull);
        expect(rig.parts['torso'], isNotNull);
        expect(rig.parts['armL'], isNotNull);
        expect(rig.parts['armR'], isNotNull);
        expect(rig.parts['legL'], isNotNull);
        expect(rig.parts['legR'], isNotNull);
        expect(rig.povLocalEye.z, greaterThan(0.10));

        final origArmRx = rig.boardRest['armR.rx']!;
        final origArmLx = rig.boardRest['armL.x']!;

        rig.setFirstPersonMode(true);
        expect(rig.inPov, isTrue);
        expect(rig.parts['head']!.visible, isFalse);
        expect(rig.parts['povHide']!.visible, isFalse);
        expect(rig.parts['torso']!.visible, isTrue);
        expect(rig.parts['armL']!.visible, isTrue);
        expect(rig.parts['armR']!.visible, isTrue);
        expect(rig.parts['legL']!.visible, isTrue);
        expect(rig.parts['legR']!.visible, isTrue);

        rig.setFirstPersonMode(false);
        expect(rig.inPov, isFalse);
        expect(rig.parts['head']!.visible, isTrue);
        expect(rig.parts['povHide']!.visible, isTrue);
        expect(rig.parts['armR']!.rotation.x, closeTo(origArmRx, 1e-6));
        expect(rig.parts['armL']!.position.x, closeTo(origArmLx, 1e-6));

        if (kind == PieceType.queen) {
          expect(rig.orbiters.length, 2);
        }
        if (kind == PieceType.bishop) {
          expect(rig.parts['wingL'], isNotNull);
          expect(rig.parts['wingR'], isNotNull);
          expect(rig.parts['jaw'], isNotNull);
        }
      }
    }
  });

  test('Başlangıçta beyaz oynar, rakip taş seçilemez', () {
    final game = ChessGame();
    expect(game.turn, Team.white);
    expect(game.pseudoLegalMoves(HexBoard.parse('f11')), isEmpty);
  });

  test('Hamle yapınca sıra değişir ve yeni oyun sıfırlar', () {
    final game = ChessGame();
    final from = HexBoard.parse('f5');
    final choices = game.pseudoLegalMoves(from);
    expect(choices, isNotEmpty);
    expect(game.play(from, choices.first), isTrue);
    expect(game.turn, Team.black);
    expect(game.ply, 1);
    game.reset();
    expect(game.turn, Team.white);
    expect(game.pieces.length, 36);
    expect(game.ply, 0);
  });

  test('makeMove / unmakeMove durumu korur ve şahı açıkta bırakan hamle elenir', () {
    final pos = Position()..setupStart();
    final before = pos.key;
    for (final m in pos.legalMoves()) {
      final me = pos.side;
      pos.makeMove(m);
      expect(pos.attacked(pos.kingOf(me), -me), isFalse);
      pos.unmakeMove();
      expect(pos.key, before);
    }

    // Açmaz testi: beyaz Barbar Kral f1, beyaz Dev f3, siyah Dev f9
    for (final i in Position.boardCells) {
      pos.sq[i] = 0;
    }
    pos.whiteKing = Position.idxOf(HexBoard.parse('f1'));
    pos.blackKing = Position.idxOf(HexBoard.parse('b7'));
    pos.sq[pos.whiteKing] = 6;
    pos.sq[pos.blackKing] = -6;
    final pinned = Position.idxOf(HexBoard.parse('f3'));
    pos.sq[pinned] = 4; // beyaz Dev
    pos.sq[Position.idxOf(HexBoard.parse('f9'))] = -4; // siyah Dev
    pos.side = 1;

    final pinnedMoves = pos
        .legalMoves()
        .where((m) => Mv.from(m) == pinned)
        .map((m) => Position.cellOf(Mv.to(m)).q)
        .toSet();
    // Açmazdaki Dev yalnızca f dikeyinde (q == 0) kalabilir.
    expect(pinnedMoves, equals({0}));
  });

  test('Geçerken alma (en passant) ve Vampir Kraliçe terfisi çalışır', () {
    final game = ChessGame();
    for (final i in Position.boardCells) {
      game.pos.sq[i] = 0;
    }
    game.pos.whiteKing = Position.idxOf(HexBoard.parse('g1'));
    game.pos.blackKing = Position.idxOf(HexBoard.parse('e10'));
    game.pos.sq[game.pos.whiteKing] = 6;
    game.pos.sq[game.pos.blackKing] = -6;
    // Beyaz piyon e4'ten iki adım e6'ya çıksın, siyah piyon d5'ten e5'e geçerken alsın.
    game.pos.sq[Position.idxOf(HexBoard.parse('e4'))] = 1;
    game.pos.sq[Position.idxOf(HexBoard.parse('d5'))] = -1;
    game.pos.side = 1;

    expect(game.play(HexBoard.parse('e4'), HexBoard.parse('e6')), isTrue);
    final epRec = game.playMove(HexBoard.parse('d5'), HexBoard.parse('e5'));
    expect(epRec, isNotNull);
    expect(epRec!.captured?.kind, PieceType.pawn);
    expect(epRec.capturedAt, HexBoard.parse('e6'));
    expect(game.pieceAt(HexBoard.parse('e6')), isNull);

    // Beyaz piyon f10 -> f11 terfi
    game.pos.sq[Position.idxOf(HexBoard.parse('f10'))] = 1;
    final promoRec = game.playMove(HexBoard.parse('f10'), HexBoard.parse('f11'));
    expect(promoRec, isNotNull);
    expect(promoRec!.promoted, isTrue);
    expect(game.pieceAt(HexBoard.parse('f11'))?.kind, PieceType.queen);
  });

  test('Dahili yapay zekâ yasal hamle üretir ve tek hamlede matı bulur', () {
    final startPos = Position()..setupStart();
    final clone = Position.deserialize(startPos.serialize());
    expect(clone.key, startPos.key);

    final openingAi = HexChessAi(maxDepth: 2, timeMs: 500, noise: 0);
    final openingMove = openingAi.bestMove(startPos);
    expect(openingMove, isNotNull);
    expect(startPos.legalMoves(), contains(openingMove));

    // Tek hamlede mat kurulumu: siyah Şah f11 köşesinde sıkışmış.
    final matePos = Position()..setupStart();
    for (final i in Position.boardCells) {
      matePos.sq[i] = 0;
    }
    matePos.whiteKing = Position.idxOf(HexBoard.parse('f9'));
    matePos.blackKing = Position.idxOf(HexBoard.parse('f11'));
    matePos.sq[matePos.whiteKing] = 6;
    matePos.sq[matePos.blackKing] = -6;
    matePos.sq[Position.idxOf(HexBoard.parse('d8'))] = 5; // beyaz Vampir Kraliçe
    matePos.side = 1;

    final tacticAi = HexChessAi(maxDepth: 3, timeMs: 800, noise: 0);
    final best = tacticAi.bestMove(matePos);
    expect(best, isNotNull);
    matePos.makeMove(best!);
    expect(matePos.inCheck(), isTrue);
    expect(matePos.legalMoves(), isEmpty);
  });
}
