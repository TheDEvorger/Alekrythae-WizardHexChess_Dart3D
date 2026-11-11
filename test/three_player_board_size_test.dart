import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wizard_hex_chess_dart3d/data/game_database.dart';
import 'package:wizard_hex_chess_dart3d/game/chess_game.dart';
import 'package:wizard_hex_chess_dart3d/game/hex_board.dart';
import 'package:wizard_hex_chess_dart3d/game/three_player_ai.dart';
import 'package:wizard_hex_chess_dart3d/game/three_player_game.dart';

// ---------------------------------------------------------------------------
// Bağımsız başvuru hamle üreticisi: dolgulu dizi kullanmaz, doğrudan altıgen
// koordinatlarla ve `contains` ile çalışır. Motorun dizi geometrisindeki her
// taşma / satır sarması hatası bu karşılaştırmada yakalanır.
// ---------------------------------------------------------------------------
const _rook = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)];
const _bishop = [(2, -1), (1, 1), (-1, 2), (-2, 1), (-1, -1), (1, -2)];
const _knight = [
  (1, 2), (2, 1), (-1, 3), (-2, 3), (-3, 2), (-3, 1), //
  (-1, -2), (-2, -1), (1, -3), (2, -3), (3, -2), (3, -1),
];
const _pawnFwd = [(0, 1), (-1, 0), (1, -1)];
const _pawnCaps = [
  [(1, 0), (-1, 1)],
  [(-1, 1), (0, -1)],
  [(0, -1), (1, 0)],
];

class _RefBoard {
  _RefBoard(ThreePlayerPosition p)
      : radius = p.geo.radius,
        alive = p.aliveMask,
        side = p.side,
        ep = p.ep >= 0 ? p.geo.cellOf(p.ep) : null,
        epPawn = p.epPawnSq >= 0 ? p.geo.cellOf(p.epPawnSq) : null {
    for (final i in p.geo.boardCells) {
      final b = p.sq[i];
      if (b != 0) cells[p.geo.cellOf(i)] = (b >> 3, b & 7);
    }
    for (final (cell, kind) in p.geo.baseCamp) {
      if (kind != PieceType.pawn) continue;
      for (var t = 0; t < 3; t++) {
        pawnStart[t].add(ThreePlayerPosition.rot120(cell, t));
      }
    }
  }

  final int radius;
  final int alive;
  final int side;
  final HexCell? ep;
  final HexCell? epPawn;
  final Map<HexCell, (int, int)> cells = {};
  final List<Set<HexCell>> pawnStart = [{}, {}, {}];

  bool on(HexCell c) =>
      math.max(c.q.abs(), math.max(c.r.abs(), (c.q + c.r).abs())) <= radius;
  HexCell add(HexCell c, (int, int) d) => HexCell(c.q + d.$1, c.r + d.$2);
  bool isAlive(int t) => (alive & (1 << t)) != 0;

  bool attackedBy(Map<HexCell, (int, int)> b, HexCell target, int t, int aliveMask) {
    if ((aliveMask & (1 << t)) == 0) return false;
    bool has(HexCell c, int kind) => b[c] == (t, kind);
    for (final d in _pawnCaps[t]) {
      if (has(HexCell(target.q - d.$1, target.r - d.$2), 1)) return true;
    }
    for (final d in _knight) {
      if (has(add(target, d), 2)) return true;
    }
    for (final d in [..._rook, ..._bishop]) {
      if (has(add(target, d), 6)) return true;
    }
    for (final (dirs, kind) in [(_rook, 4), (_bishop, 3)]) {
      for (final d in dirs) {
        var c = add(target, d);
        while (on(c) && !b.containsKey(c)) {
          c = add(c, d);
        }
        if (on(c) && (has(c, kind) || has(c, 5))) return true;
      }
    }
    return false;
  }

  /// (from, to, bayrak, terfi) dörtlüleri; bayrak: 0 normal, 1 çift adım, 2 geçerken alma.
  Set<(HexCell, HexCell, int, int)> legal() {
    final out = <(HexCell, HexCell, int, int)>{};
    final me = side;
    void addMove(HexCell from, HexCell to, int flag, int promo) {
      // Yasallık: hamleden sonra kendi şahı hiçbir canlı düşmanca tehdit edilmiyor
      final b = Map<HexCell, (int, int)>.of(cells);
      var aliveAfter = alive;
      final victim = b[to];
      if (flag == 2) b.remove(epPawn);
      final piece = b.remove(from)!;
      b[to] = promo != 0 ? (me, promo) : piece;
      if (victim != null && victim.$2 == 6) aliveAfter &= ~(1 << victim.$1);
      final king = b.entries.firstWhere((e) => e.value == (me, 6)).key;
      for (var t = 0; t < 3; t++) {
        if (t != me && attackedBy(b, king, t, aliveAfter)) return;
      }
      out.add((from, to, flag, promo));
    }

    bool enemy(HexCell c) => cells[c] != null && cells[c]!.$1 != me;
    for (final e in cells.entries.toList()) {
      final (t, kind) = e.value;
      if (t != me) continue;
      final from = e.key;
      switch (kind) {
        case 1:
          final one = add(from, _pawnFwd[me]);
          bool promoAt(HexCell c) => !on(add(c, _pawnFwd[me]));
          void pawnTo(HexCell to, int flag) {
            if (promoAt(to)) {
              for (final p in const [5, 4, 3, 2]) {
                addMove(from, to, flag, p);
              }
            } else {
              addMove(from, to, flag, 0);
            }
          }
          if (on(one) && !cells.containsKey(one)) {
            pawnTo(one, 0);
            final two = add(one, _pawnFwd[me]);
            if (!promoAt(one) &&
                pawnStart[me].contains(from) &&
                on(two) &&
                !cells.containsKey(two)) {
              addMove(from, two, 1, 0);
            }
          }
          for (final d in _pawnCaps[me]) {
            final to = add(from, d);
            if (!on(to)) continue;
            if (enemy(to)) {
              pawnTo(to, 0);
            } else if (to == ep && !cells.containsKey(to) && epPawn != null && enemy(epPawn!)) {
              addMove(from, to, 2, 0);
            }
          }
        case 2:
          for (final d in _knight) {
            final to = add(from, d);
            if (on(to) && (!cells.containsKey(to) || enemy(to))) addMove(from, to, 0, 0);
          }
        case 6:
          for (final d in [..._rook, ..._bishop]) {
            final to = add(from, d);
            if (on(to) && (!cells.containsKey(to) || enemy(to))) addMove(from, to, 0, 0);
          }
        default:
          final dirs = [
            if (kind == 4 || kind == 5) ..._rook,
            if (kind == 3 || kind == 5) ..._bishop,
          ];
          for (final d in dirs) {
            var to = add(from, d);
            while (on(to)) {
              if (cells.containsKey(to)) {
                if (enemy(to)) addMove(from, to, 0, 0);
                break;
              }
              addMove(from, to, 0, 0);
              to = add(to, d);
            }
          }
      }
    }
    return out;
  }
}

Set<(HexCell, HexCell, int, int)> _engineLegal(ThreePlayerPosition p) => {
      for (final m in p.legalMoves(allPromotions: true))
        (
          p.geo.cellOf(Mv.from(m)),
          p.geo.cellOf(Mv.to(m)),
          Mv.isDouble(m) ? 1 : (Mv.isEp(m) ? 2 : 0),
          Mv.isPromo(m) ? Mv.promoCode(m) : 0,
        ),
    };

/// Ordu 0'ı K+V, ordu 1'i yalnız şah olarak kurar; ordu 2 elenmiş (düello oyun sonu).
ThreePlayerPosition _duelQueenVsKing(BoardSize size, HexCell wk, HexCell wq, HexCell bk) {
  final p = ThreePlayerPosition(size)..setupStart();
  for (final i in p.geo.boardCells) {
    p.sq[i] = 0;
  }
  p.sq[p.geo.idxOf(wk)] = ThreePlayerPosition.encodePiece(0, 6);
  p.sq[p.geo.idxOf(wq)] = ThreePlayerPosition.encodePiece(0, 5);
  p.sq[p.geo.idxOf(bk)] = ThreePlayerPosition.encodePiece(1, 6);
  p.aliveMask = 0x3;
  p.side = 0;
  return ThreePlayerPosition.deserialize(p.serialize());
}

void main() {
  group('Tahta boyutu geometrisi', () {
    test('Her boyutun hücre sayısı, kare adları ve geri çevrilebilir gösterimi doğrudur', () {
      for (final size in BoardSize.values) {
        final shape = BoardShape.of(BoardVariant.threePlayer, size);
        expect(shape.cells.length, size.cellCount, reason: size.label);
        expect(shape.cells.toSet().length, size.cellCount);
        for (final c in shape.cells) {
          expect(shape.parse(shape.name(c)), c, reason: '${size.label} ${shape.name(c)}');
        }
        expect(() => shape.parse('j2'), throwsFormatException);
      }
      expect([for (final s in BoardSize.values) s.cellCount], [91, 127, 169, 217]);
      expect(BoardShape.of(BoardVariant.threePlayer, BoardSize.giant).name(const HexCell(0, 0)), 'i9');
      // 2 kişilik düello her zaman Klasik kalır
      expect(BoardShape.of(BoardVariant.twoPlayer, BoardSize.giant).size, BoardSize.classic);
      expect(BoardShape.of(BoardVariant.threePlayer).playScale, 1.0);
      expect(BoardShape.of(BoardVariant.twoPlayer).playScale, 1.0);
    });

    test('Dizi geometrisi: Klasik eski 17\'lik dizilimdir, tahta içi indeksler 9 bite sığar', () {
      final classic = Hex3Geometry.of(BoardSize.classic);
      expect(classic.span, Position.span);
      expect(classic.rookDirs, Position.rookDirs);
      expect(classic.bishopDirs, Position.bishopDirs);
      expect(classic.knightDirs, Position.knightDirs);
      expect(classic.kingDirs, Position.kingDirs);
      expect(classic.boardCells, Position.boardCells);
      for (final size in BoardSize.values) {
        final g = Hex3Geometry.of(size);
        expect(g.boardCells.length, size.cellCount);
        for (final i in g.boardCells) {
          expect(i, lessThan(512), reason: 'Mv kodlaması 9 bit: ${size.label}');
          expect(g.idxOf(g.cellOf(i)), i);
          // Her yöne 3 hücre (atın en uzun sıçrayışı) dizinin içinde kalır
          for (final d in g.knightDirs) {
            expect(i + d, inInclusiveRange(0, g.cellsTotal - 1));
          }
        }
      }
    });

    test('Ordular her boyutta kendi köşesinden 16 savaşçıyla başlar; şahlar taht zirvesindedir', () {
      for (final size in BoardSize.values) {
        final game = ChessGame(variant: BoardVariant.threePlayer, boardSize: size);
        expect(game.boardSize, size);
        expect(game.pieces.length, 48);
        final shape = game.shape;
        final r = size.radius;
        for (final team in Team.values) {
          final own = game.pieces.entries.where((e) => e.value.team == team).toList();
          expect(own.length, 16);
          final bishopColors = own
              .where((e) => e.value.kind == PieceType.bishop)
              .map((e) => HexBoard.colorIndex(e.key))
              .toSet();
          expect(bishopColors.length, 3, reason: '${size.label} ${team.title}');
          final king = own.firstWhere((e) => e.value.kind == PieceType.king).key;
          final queen = own.firstWhere((e) => e.value.kind == PieceType.queen).key;
          // Şah ve vezir kendi köşesinin kenarında, en yüksek sütunlarda
          expect(math.max(king.q.abs(), math.max(king.r.abs(), king.s.abs())), r);
          expect(shape.columnHeight(king), greaterThanOrEqualTo(1.45));
          expect(shape.columnHeight(queen), greaterThanOrEqualTo(1.41));
          // Rotasyon simetrisi
          for (final e in own) {
            final base = game.pieces[ThreePlayerPosition.rot120(e.key, (3 - team.index) % 3)];
            expect(base?.kind, e.value.kind);
          }
        }
        // Büyük tahtada merkez meydan alçak ve düzdür
        if (size != BoardSize.classic) {
          expect(shape.columnHeight(const HexCell(0, 0)), lessThan(0.21));
          expect(shape.playScale, lessThan(1.0));
        }
      }
    });

    test('Klasik 3 kişilik amfi yükseklikleri ve 2 kişilik tahta değişmedi', () {
      final s3 = BoardShape.of(BoardVariant.threePlayer);
      expect(s3.columnHeight(const HexCell(1, -5)), 1.46);
      expect(s3.columnHeight(const HexCell(0, 0)), closeTo(0.30 + (((0) % 7) - 3) * 0.0055, 1e-9));
      expect(HexBoard.columnHeight(HexBoard.parse('g1'), BoardVariant.twoPlayer),
          greaterThanOrEqualTo(1.45));
    });
  });

  group('Kural motoru — bağımsız başvuru üreticiyle karşılaştırma', () {
    for (final size in BoardSize.values) {
      test('${size.label}: rastgele oyunlarda her konumda yasal hamleler birebir aynı', () {
        var checked = 0, promoSeen = 0, epSeen = 0, inCheck = 0, eliminations = 0;
        for (var g = 0; g < 8; g++) {
          final rng = math.Random(1000 * size.index + g);
          final p = ThreePlayerPosition(size)..setupStart();
          for (var ply = 0; ply < 220 && p.aliveCount > 1; ply++) {
            final ref = _RefBoard(p).legal();
            final eng = _engineLegal(p);
            expect(eng, ref, reason: '${size.label} oyun $g yarım hamle $ply');
            checked++;
            if (p.inCheck()) inCheck++;
            for (final (_, _, flag, promo) in eng) {
              if (flag == 2) epSeen++;
              if (promo != 0) promoSeen++;
            }
            final moves = p.legalMoves(allPromotions: true);
            if (moves.isEmpty) break;
            // Taş alan ve piyon hamlelerini kayır: elenme, terfi, geçerken alma ve
            // oyun sonu konumları da denenir
            final caps = [for (final m in moves) if (p.sq[Mv.to(m)] != 0 || Mv.isPromo(m)) m];
            final pawns = [
              for (final m in moves)
                if (ThreePlayerPosition.kindCodeOfByte(p.sq[Mv.from(m)]) == 1) m
            ];
            final roll = rng.nextDouble();
            final m = caps.isNotEmpty && roll < 0.45
                ? caps[rng.nextInt(caps.length)]
                : (pawns.isNotEmpty && roll < 0.70
                    ? pawns[rng.nextInt(pawns.length)]
                    : moves[rng.nextInt(moves.length)]);
            final before = p.aliveCount;
            p.makeMove(m);
            if (p.aliveCount < before) eliminations++;
          }
        }
        expect(checked, greaterThan(600));
        // Karşılaştırma zor durumları da kapsamalı (geçerken alma ve elenme
        // aşağıdaki karışık dizilim testinde kesin olarak denenir)
        expect(promoSeen, greaterThan(0), reason: 'terfi');
        expect(inCheck, greaterThan(10), reason: 'şah altındaki konumlar');
        expect(eliminations + epSeen, greaterThanOrEqualTo(0));
      });

      test('${size.label}: taşlar tahtanın her yerine dağıtıldığında (köşe/kenar, geçerken alma) aynı', () {
        final rng = math.Random(4242 + size.index);
        final g = Hex3Geometry.of(size);
        final shape = BoardShape.of(BoardVariant.threePlayer, size);
        var checked = 0, epSeen = 0, edgeMoves = 0, eliminations = 0;
        for (var sample = 0; sample < 250; sample++) {
          final p = ThreePlayerPosition(size)..setupStart();
          for (final i in g.boardCells) {
            p.sq[i] = 0;
          }
          final free = List<HexCell>.of(shape.cells)..shuffle(rng);
          var k = 0;
          for (var t = 0; t < 3; t++) {
            p.sq[g.idxOf(free[k++])] = ThreePlayerPosition.encodePiece(t, 6);
          }
          final extra = 8 + rng.nextInt(18);
          for (var e = 0; e < extra; e++) {
            final c = free[k++];
            final t = rng.nextInt(3);
            final kind = 1 + rng.nextInt(5);
            if (kind == 1 && g.promoMasks[t][g.idxOf(c)] == 1) continue;
            p.sq[g.idxOf(c)] = ThreePlayerPosition.encodePiece(t, kind);
          }
          final mover = rng.nextInt(3);
          final next = (mover + 1) % 3;
          // Geçerken alma kurulumu: hamle sırasındaki ordunun başlangıç karesinde bir piyon,
          // sıradaki ordunun piyonu atlanan kareyi çapraz alabilecek yerde.
          final starts = [
            for (final (c, kind) in g.baseCamp)
              if (kind == PieceType.pawn) ThreePlayerPosition.rot120(c, mover)
          ]..shuffle(rng);
          for (final s in starts) {
            final epCell = g.idxOf(s) + g.pawnFwd[mover];
            final two = epCell + g.pawnFwd[mover];
            if (p.sq[g.idxOf(s)] != 0 || p.sq[epCell] != 0 || p.sq[two] != 0) continue;
            final capAt = epCell - g.pawnCaps[next][rng.nextInt(2)];
            if (p.sq[capAt] != 0 || g.promoMasks[next][capAt] == 1) continue;
            p.sq[g.idxOf(s)] = ThreePlayerPosition.encodePiece(mover, 1);
            p.sq[capAt] = ThreePlayerPosition.encodePiece(next, 1);
            break;
          }
          p.side = mover;
          p.aliveMask = rng.nextDouble() < 0.2 ? (0x7 & ~(1 << ((mover + 2) % 3))) : 0x7;
          for (var t = 0; t < 3; t++) {
            if (!p.isAlive(t)) {
              for (final i in g.boardCells) {
                if (p.sq[i] != 0 && ThreePlayerPosition.teamOfByte(p.sq[i]) == t) p.sq[i] = 0;
              }
            }
          }
          final pos = ThreePlayerPosition.deserialize(p.serialize());
          for (var ply = 0; ply < 6 && pos.aliveCount > 1; ply++) {
            final eng = _engineLegal(pos);
            expect(eng, _RefBoard(pos).legal(), reason: '${size.label} dizilim $sample yarım hamle $ply');
            checked++;
            for (final (from, to, flag, _) in eng) {
              if (flag == 2) epSeen++;
              if (g.ring(g.idxOf(from)) == size.radius || g.ring(g.idxOf(to)) == size.radius) {
                edgeMoves++;
              }
            }
            final moves = pos.legalMoves(allPromotions: true);
            if (moves.isEmpty) break;
            final doubles = [for (final m in moves) if (Mv.isDouble(m)) m];
            final aliveBefore = pos.aliveCount;
            pos.makeMove(doubles.isNotEmpty && ply == 0
                ? doubles[rng.nextInt(doubles.length)]
                : moves[rng.nextInt(moves.length)]);
            if (pos.aliveCount < aliveBefore) eliminations++;
          }
        }
        expect(checked, greaterThan(800));
        expect(epSeen, greaterThan(0), reason: 'geçerken alma');
        expect(edgeMoves, greaterThan(1000), reason: 'kenar/köşe hamleleri');
        expect(eliminations, greaterThan(0), reason: 'ordu elenmesi');
      });
    }

    test('makeMove / unmakeMove her boyutta konumu birebir geri getirir', () {
      for (final size in BoardSize.values) {
        final rng = math.Random(77 + size.index);
        final p = ThreePlayerPosition(size)..setupStart();
        final keys = <String>[p.key];
        for (var i = 0; i < 120 && p.aliveCount > 1; i++) {
          final moves = p.legalMoves(allPromotions: true);
          if (moves.isEmpty) break;
          p.makeMove(moves[rng.nextInt(moves.length)]);
          keys.add(p.key);
        }
        for (var i = keys.length - 1; i > 0; i--) {
          expect(p.key, keys[i]);
          p.unmakeMove();
        }
        expect(p.key, keys.first);
      }
    });

    test('Serileştirme, kayıttan geri yükleme ve tekrar özeti her boyutta korunur', () {
      for (final size in BoardSize.values) {
        final game = ChessGame(variant: BoardVariant.threePlayer, boardSize: size);
        final rng = math.Random(5 + size.index);
        for (var i = 0; i < 40 && game.status == GameStatus.playing; i++) {
          final moves = game.pos3.legalMoves();
          game.applyEncoded(moves[rng.nextInt(moves.length)]);
        }
        final snap = ThreePlayerPosition.deserialize(game.pos3.serialize());
        expect(snap.size, size);
        expect(snap.key, game.pos3.key);
        expect(snap.repetitionHash, game.pos3.repetitionHash);

        final restored = ChessGame();
        expect(
          restored.restoreFromEncodedMoves(
            BoardVariant.threePlayer,
            game.exportEncodedMoves(),
            size: size,
          ),
          isTrue,
        );
        expect(restored.boardSize, size);
        expect(restored.pos3.key, game.pos3.key);
      }
    });

    test('Beraberlik sınırı tahta büyüdükçe uzar', () {
      expect(
        [for (final s in BoardSize.values) Hex3Geometry.of(s).halfmoveDrawLimit],
        [120, 140, 160, 180],
      );
    });
  });

  group('Yapay zekâ — büyük tahtalar', () {
    test('Her boyutta her ordu için yasal hamle seçer', () {
      for (final size in BoardSize.values) {
        final game = ChessGame(variant: BoardVariant.threePlayer, boardSize: size);
        for (var i = 0; i < 6; i++) {
          final ai = ThreePlayerHexAi(maxDepth: 2, timeMs: 1 << 30, noise: 0, seed: i);
          final m = ai.bestMove(ThreePlayerPosition.copy(game.pos3));
          expect(m, isNotNull);
          expect(game.pos3.legalMoves(), contains(m), reason: '${size.label} $i');
          game.applyEncoded(m!);
        }
      }
    });

    test('Dev tahtanın uzak köşesinde tek hamlede matı bulur', () {
      // Siyah şah Dev tahtanın (8, -8) köşesinde (eski 17'lik dizide sarma yapacak
      // bölge). Tek hamlede bitirilebilen ve siyahın şahta olmadığı bir K+V dizilimi aranır.
      const bk = HexCell(8, -8);
      final shape = BoardShape.of(BoardVariant.threePlayer, BoardSize.giant);
      ThreePlayerPosition? found;
      search:
      for (final wk in shape.cells) {
        if (Hex3Geometry.of(BoardSize.giant).distance(
              Hex3Geometry.of(BoardSize.giant).idxOf(wk),
              Hex3Geometry.of(BoardSize.giant).idxOf(bk),
            ) !=
            2) {
          continue;
        }
        for (final wq in shape.cells) {
          if (wq == wk || wq == bk) continue;
          final p = _duelQueenVsKing(BoardSize.giant, wk, wq, bk);
          if (p.inCheck(1)) continue;
          for (final m in p.legalMoves()) {
            final t = ThreePlayerPosition.copy(p)..makeMove(m);
            if (t.soleSurvivor == 0) {
              found = p;
              break search;
            }
          }
        }
      }
      expect(found, isNotNull);
      final ai = ThreePlayerHexAi(maxDepth: 3, timeMs: 1 << 30, noise: 0);
      final m = ai.bestMove(ThreePlayerPosition.copy(found!))!;
      found.makeMove(m);
      expect(found.soleSurvivor, 0, reason: 'mat ya da pat ile siyah elenmeli');
    });

    test('Oyun sonu sıkıştırması: Dev tahtada Vezir + Şah, yalnız şahı süre dolmadan bitirir', () {
      final p = _duelQueenVsKing(
        BoardSize.giant,
        const HexCell(0, -8),
        const HexCell(-1, -7),
        const HexCell(0, 8),
      );
      var plies = 0;
      while (p.aliveCount > 1 && plies < 160) {
        final ai = ThreePlayerHexAi(maxDepth: 4, timeMs: 400, noise: 0, seed: plies);
        final m = ai.bestMove(ThreePlayerPosition.copy(p));
        if (m == null) break;
        p.makeMove(m);
        plies++;
      }
      expect(p.soleSurvivor, 0, reason: '$plies yarım hamlede bitmedi');
      expect(plies, lessThan(Hex3Geometry.of(BoardSize.giant).halfmoveDrawLimit));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('Üç kez tekrar beraberliğine götüren hamleyi kazanırken seçmez', () {
      final p = _duelQueenVsKing(
        BoardSize.large,
        const HexCell(0, -7),
        const HexCell(-2, 0),
        const HexCell(0, 7),
      );
      final ai = ThreePlayerHexAi(maxDepth: 2, timeMs: 1 << 30, noise: 0);
      final first = ai.bestMove(ThreePlayerPosition.copy(p))!;
      final after = ThreePlayerPosition.copy(p)..makeMove(first);
      // Aynı hamlenin varacağı konum oyunda zaten iki kez görülmüş olsun
      final ai2 = ThreePlayerHexAi(
        maxDepth: 2,
        timeMs: 1 << 30,
        noise: 0,
        repetitionHashes: {after.repetitionHash},
      );
      final second = ai2.bestMove(ThreePlayerPosition.copy(p))!;
      expect(second, isNot(first));
    });
  });

  group('Kalıcılık', () {
    late GameDatabase db;
    setUp(() async {
      db = await GameDatabase.openForTesting(':memory:');
    });
    tearDown(() async {
      await db.close();
    });

    test('Maçın tahta boyutu ve 3\'lü boyut tercihi SQLite\'a yazılıp geri okunur', () async {
      final game = ChessGame(variant: BoardVariant.threePlayer, boardSize: BoardSize.giant);
      final id = await db.startNewMatch(
        variant: BoardVariant.threePlayer,
        boardSize: BoardSize.giant,
        modeName: 'humanVsAi',
        aiLevelName: 'wizard',
        humanTeam: Team.white,
      );
      // Dev tahtada Klasik'te olmayan karelere giden hamle de kaydedilebilmeli
      final m = game.pos3.legalMoves().first;
      final rec = game.applyEncoded(m);
      await db.recordMove(
        matchId: id,
        ply: 0,
        record: rec,
        allEncodedMoves: game.exportEncodedMoves(),
        humanCapture: false,
        shape: game.shape,
      );
      final recent = await db.loadRecentMatches();
      expect(recent.first.boardSize, BoardSize.giant);
      expect(recent.first.boardLabel, contains('Dev'));
      final moves = await db.loadMovesForMatch(id);
      expect(moves.single.fromCell, game.shape.name(rec.from));

      await db.saveSettingsImmediate(
        const PersistedSettings(variant: BoardVariant.threePlayer, boardSize3P: BoardSize.large),
      );
      final back = PersistedSettings.fromKeyValues(
        const PersistedSettings(boardSize3P: BoardSize.large).toKeyValues(),
      );
      expect(back.boardSize3P, BoardSize.large);
      expect(PersistedSettings.fromKeyValues(const {}).boardSize3P, BoardSize.classic);
    });
  });
}
