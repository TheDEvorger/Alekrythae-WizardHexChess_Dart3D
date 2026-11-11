import 'dart:math' as math;
import 'dart:typed_data';

import 'chess_game.dart';
import 'hex_board.dart';

/// 3 kişilik altıgen satranç için bir hamle geri alma kaydı (elenen orduların taşları dâhil).
class _UndoFrame3P {
  _UndoFrame3P({
    required this.move,
    required this.prevSide,
    required this.captured,
    required this.capSq,
    required this.prevEp,
    required this.prevEpPawnSq,
    required this.prevHalfmove,
    required this.prevAliveMask,
    required this.eliminatedPieces,
  });

  final int move;
  final int prevSide;
  final int captured;
  final int capSq;
  final int prevEp;
  final int prevEpPawnSq;
  final int prevHalfmove;
  final int prevAliveMask;
  final List<(int sqIdx, int pieceByte)> eliminatedPieces;
}

/// Seçilen tahta boyutuna göre 3 kişilik kural motorunun dolgulu (padded) dizi geometrisi.
/// Dizi her yönde 3 hücre dolgu taşır (atın en uzun sıçrayışı), böylece hiçbir
/// hamle dizinin dışına taşmaz ya da bir satırdan ötekine sarmaz.
/// Klasik boyut eski 17'lik dizilimi birebir korur: kayıtlı hamle kodları geçerli kalır.
/// En büyük (Dev) tahtada bile tahta içi indeksler 9 bite sığar (≤ 448), [Mv] kodlaması değişmez.
class Hex3Geometry {
  Hex3Geometry._(this.size)
      : radius = size.radius,
        pad = size.radius + 3,
        span = size.radius * 2 + 7 {
    cellsTotal = span * span;
    List<int> dirs(List<(int, int)> axial) => List<int>.of(
          [for (final (dq, dr) in axial) dq * span + dr],
          growable: false,
        );
    // Yön sıraları eski sabit tablolarla aynıdır (hamle üretim sırası değişmez).
    rookDirs = dirs(const [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]);
    bishopDirs = dirs(const [(2, -1), (1, 1), (-1, 2), (-2, 1), (-1, -1), (1, -2)]);
    kingDirs = List<int>.of([...rookDirs, ...bishopDirs], growable: false);
    knightDirs = dirs(const [
      (1, 2), (2, 1), (-1, 3), (-2, 3), (-3, 2), (-3, 1), //
      (-1, -2), (-2, -1), (1, -3), (2, -3), (3, -2), (3, -1),
    ]);
    pawnFwd = dirs(const [(0, 1), (-1, 0), (1, -1)]);
    pawnCaps = List<List<int>>.of([
      dirs(const [(1, 0), (-1, 1)]),
      dirs(const [(-1, 1), (0, -1)]),
      dirs(const [(0, -1), (1, 0)]),
    ], growable: false);
    boardCells = List<int>.of([
      for (var q = -radius; q <= radius; q++)
        for (var r = -radius; r <= radius; r++)
          if (contains(HexCell(q, r))) idx(q, r),
    ], growable: false);

    // Güney ordusunun Klasik dizilimi büyük tahtada kendi köşesine (0, -R, +R) kaydırılır:
    // her ordu kenardan başlar, aradaki meydan genişler.
    final shift = radius - HexBoard.radius;
    baseCamp = List<(HexCell, PieceType)>.unmodifiable([
      for (final (c, k) in ThreePlayerPosition._classicCamp)
        (HexCell(c.q, c.r - shift), k),
    ]);

    pawnStartMasks = List<Uint8List>.generate(3, (t) {
      final m = Uint8List(cellsTotal);
      for (final (cell, kind) in baseCamp) {
        if (kind == PieceType.pawn) {
          m[idxOf(ThreePlayerPosition.rot120(cell, t))] = 1;
        }
      }
      return m;
    }, growable: false);

    promoMasks = List<Uint8List>.generate(3, (t) {
      final m = Uint8List(cellsTotal);
      final fwd = pawnFwd[t];
      for (final i in boardCells) {
        if (!contains(cellOf(i + fwd))) m[i] = 1;
      }
      return m;
    }, growable: false);
  }

  static final List<Hex3Geometry> _all = List<Hex3Geometry>.unmodifiable(
    [for (final s in BoardSize.values) Hex3Geometry._(s)],
  );

  static Hex3Geometry of(BoardSize size) => _all[size.index];

  final BoardSize size;
  final int radius;
  final int pad;
  final int span;
  late final int cellsTotal;

  late final List<int> rookDirs;
  late final List<int> bishopDirs;
  late final List<int> kingDirs;
  late final List<int> knightDirs;

  /// Her ordunun kendi merkezine doğru ileri piyon adımı (dizide indeks farkı).
  late final List<int> pawnFwd;

  /// Her ordunun iki çapraz piyon alma yönü.
  late final List<List<int>> pawnCaps;

  /// Tahta içi hücre indeksleri (q artan, sonra r artan sırada).
  late final List<int> boardCells;

  /// Güney (Beyaz) ordusunun bu boyuttaki başlangıç dizilimi.
  late final List<(HexCell, PieceType)> baseCamp;
  late final List<Uint8List> pawnStartMasks;
  late final List<Uint8List> promoMasks;

  /// Uzun süreli ateşkes sınırı (piyon oynamadan ve taş alınmadan geçen yarım hamle):
  /// büyük tahtada ordular arası mesafe uzadığı için sınır da uzar (120/140/160/180).
  int get halfmoveDrawLimit => 120 + 20 * (radius - HexBoard.radius);

  int idx(int q, int r) => (q + pad) * span + (r + pad);
  int idxOf(HexCell c) => idx(c.q, c.r);
  HexCell cellOf(int i) => HexCell(i ~/ span - pad, i % span - pad);

  bool contains(HexCell c) =>
      math.max(c.q.abs(), math.max(c.r.abs(), (c.q + c.r).abs())) <= radius;

  /// İki hücre indeksi arasındaki altıgen (küp) mesafe.
  int distance(int a, int b) {
    final dq = a ~/ span - b ~/ span;
    final dr = a % span - b % span;
    return math.max(dq.abs(), math.max(dr.abs(), (dq + dr).abs()));
  }

  /// Hücrenin merkeze altıgen mesafesi (0 merkez .. R kenar).
  int ring(int i) {
    final q = i ~/ span - pad, r = i % span - pad;
    return math.max(q.abs(), math.max(r.abs(), (q + r).abs()));
  }
}

/// Altıgen amfi tahtasında 120° döngüsel simetrili 3 kişilik satranç kural motoru
/// (Klasik 91, Geniş 127, Büyük 169, Dev 217 hücre).
/// Ordular: 0 = Beyaz (Güney), 1 = Siyah (Kuzeydoğu 120°), 2 = Zümrüt (Kuzeybatı 240°).
class ThreePlayerPosition {
  static const int off = Position.off; // 99

  static int encodePiece(int teamIdx, int pieceCode) => (teamIdx << 3) | pieceCode;
  static int teamOfByte(int b) => b >> 3;
  static int kindCodeOfByte(int b) => b & 7;

  static HexCell rot120(HexCell c, int teamIdx) {
    final q = c.q, r = c.r, s = -q - r;
    return switch (teamIdx) {
      0 => c,
      1 => HexCell(s, q),
      _ => HexCell(r, s),
    };
  }

  /// Güney cephesi (Team.white = 0) için 16 savaşçılık simetrik Klasik başlangıç dizilimi;
  /// diğer 2 ordu tam 120° ve 240° döndürülerek elde edilir.
  static const List<(HexCell, PieceType)> _classicCamp = [
    (HexCell(1, -5), PieceType.king),
    (HexCell(-1, -4), PieceType.queen),
    (HexCell(0, -5), PieceType.bishop),
    (HexCell(0, -4), PieceType.bishop),
    (HexCell(0, -3), PieceType.bishop),
    (HexCell(-2, -3), PieceType.knight),
    (HexCell(2, -5), PieceType.knight),
    (HexCell(-3, -2), PieceType.rook),
    (HexCell(3, -5), PieceType.rook),
    (HexCell(-3, -1), PieceType.pawn),
    (HexCell(-2, -2), PieceType.pawn),
    (HexCell(-1, -2), PieceType.pawn),
    (HexCell(0, -2), PieceType.pawn),
    (HexCell(1, -3), PieceType.pawn),
    (HexCell(2, -4), PieceType.pawn),
    (HexCell(3, -4), PieceType.pawn),
  ];

  ThreePlayerPosition([BoardSize size = BoardSize.classic])
      : geo = Hex3Geometry.of(size),
        sq = Int8List(Hex3Geometry.of(size).cellsTotal);

  ThreePlayerPosition.copy(ThreePlayerPosition o)
      : geo = o.geo,
        sq = Int8List.fromList(o.sq) {
    kings.setAll(0, o.kings);
    side = o.side;
    aliveMask = o.aliveMask;
    ep = o.ep;
    epPawnSq = o.epPawnSq;
    halfmove = o.halfmove;
    ply = o.ply;
  }

  final Hex3Geometry geo;
  BoardSize get size => geo.size;

  final Int8List sq;
  final Int32List kings = Int32List(3)..fillRange(0, 3, -1);
  int side = 0; // 0 = white, 1 = black, 2 = emerald
  int aliveMask = 0x7; // bit 0, 1, 2
  int ep = -1;
  int epPawnSq = -1;
  int halfmove = 0;
  int ply = 0;

  /// Son `makeMove` çağrısında elenen ordular ve kaldırılan taş konumları (UI animasyonu için).
  List<int> lastEliminatedTeams = const [];
  List<HexCell> lastEliminatedCells = const [];

  final List<_UndoFrame3P> _undo = [];

  bool isAlive(int teamIdx) => (aliveMask & (1 << teamIdx)) != 0;

  int get aliveCount =>
      (aliveMask & 1) + ((aliveMask >> 1) & 1) + ((aliveMask >> 2) & 1);

  int? get soleSurvivor {
    if (aliveCount != 1) return null;
    for (var t = 0; t < 3; t++) {
      if (isAlive(t)) return t;
    }
    return null;
  }

  /// `[boyut, ...hücreler, sıra, canlılar, ep, epPiyon, yarımHamle, ply]`
  List<int> serialize() => [
        geo.size.index,
        ...sq,
        side,
        aliveMask,
        ep,
        epPawnSq,
        halfmove,
        ply,
      ];

  /// [serialize] çıktısının uzunluğu (boyuta bağlı).
  static int serializedLength(BoardSize size) =>
      Hex3Geometry.of(size).cellsTotal + 7;

  factory ThreePlayerPosition.deserialize(List<int> data) {
    final p = ThreePlayerPosition(BoardSize.values[data[0]]);
    final n = p.geo.cellsTotal;
    for (var i = 0; i < n; i++) {
      p.sq[i] = data[i + 1];
    }
    p.side = data[n + 1];
    p.aliveMask = data[n + 2];
    p.ep = data[n + 3];
    p.epPawnSq = data[n + 4];
    p.halfmove = data[n + 5];
    p.ply = data[n + 6];
    p._findKings();
    return p;
  }

  void _findKings() {
    kings.fillRange(0, 3, -1);
    for (final i in geo.boardCells) {
      final b = sq[i];
      if (b != 0 && b != off && kindCodeOfByte(b) == 6) {
        final t = teamOfByte(b);
        if (t >= 0 && t < 3) kings[t] = i;
      }
    }
  }

  void setupStart() {
    sq.fillRange(0, geo.cellsTotal, off);
    for (final i in geo.boardCells) {
      sq[i] = 0;
    }
    for (var t = 0; t < 3; t++) {
      for (final (cell, kind) in geo.baseCamp) {
        final rc = rot120(cell, t);
        sq[geo.idxOf(rc)] = encodePiece(t, kind.code);
      }
    }
    side = 0;
    aliveMask = 0x7;
    ep = -1;
    epPawnSq = -1;
    halfmove = 0;
    ply = 0;
    lastEliminatedTeams = const [];
    lastEliminatedCells = const [];
    _undo.clear();
    _findKings();
  }

  bool _isEnemyByte(int b, int myTeam) =>
      b != 0 && b != off && teamOfByte(b) != myTeam;

  bool attackedByTeam(int targetSq, int byTeam) {
    if (!isAlive(byTeam)) return false;
    final g = geo;
    final pawnByte = encodePiece(byTeam, 1);
    for (final d in g.pawnCaps[byTeam]) {
      if (sq[targetSq - d] == pawnByte) return true;
    }
    final knightByte = encodePiece(byTeam, 2);
    for (final d in g.knightDirs) {
      if (sq[targetSq + d] == knightByte) return true;
    }
    final kingByte = encodePiece(byTeam, 6);
    for (final d in g.kingDirs) {
      if (sq[targetSq + d] == kingByte) return true;
    }
    final rookByte = encodePiece(byTeam, 4);
    final queenByte = encodePiece(byTeam, 5);
    final bishopByte = encodePiece(byTeam, 3);
    for (final d in g.rookDirs) {
      var t = targetSq + d;
      while (sq[t] == 0) {
        t += d;
      }
      final p = sq[t];
      if (p == rookByte || p == queenByte) return true;
    }
    for (final d in g.bishopDirs) {
      var t = targetSq + d;
      while (sq[t] == 0) {
        t += d;
      }
      final p = sq[t];
      if (p == bishopByte || p == queenByte) return true;
    }
    return false;
  }

  bool attackedByAnyEnemy(int targetSq, int myTeam) {
    for (var t = 0; t < 3; t++) {
      if (t != myTeam && isAlive(t) && attackedByTeam(targetSq, t)) {
        return true;
      }
    }
    return false;
  }

  bool inCheck([int? teamIdx]) {
    final t = teamIdx ?? side;
    if (!isAlive(t)) return false;
    final k = kings[t];
    return k >= 0 && attackedByAnyEnemy(k, t);
  }

  void pseudoMovesFor(
    int teamIdx,
    List<int> out, {
    bool capturesOnly = false,
    bool allPromotions = false,
  }) {
    if (!isAlive(teamIdx)) return;
    final g = geo;
    for (final from in g.boardCells) {
      final b = sq[from];
      if (b == 0 || b == off || teamOfByte(b) != teamIdx) continue;
      switch (kindCodeOfByte(b)) {
        case 1:
          _pawnMoves(from, teamIdx, out, capturesOnly, allPromotions);
        case 2:
          for (final d in g.knightDirs) {
            final t = from + d, q = sq[t];
            if (q == off) continue;
            if (q == 0) {
              if (!capturesOnly) out.add(Mv.make(from, t));
            } else if (_isEnemyByte(q, teamIdx)) {
              out.add(Mv.make(from, t));
            }
          }
        case 3:
          _slide(from, teamIdx, g.bishopDirs, out, capturesOnly);
        case 4:
          _slide(from, teamIdx, g.rookDirs, out, capturesOnly);
        case 5:
          _slide(from, teamIdx, g.rookDirs, out, capturesOnly);
          _slide(from, teamIdx, g.bishopDirs, out, capturesOnly);
        case 6:
          for (final d in g.kingDirs) {
            final t = from + d, q = sq[t];
            if (q == off) continue;
            if (q == 0) {
              if (!capturesOnly) out.add(Mv.make(from, t));
            } else if (_isEnemyByte(q, teamIdx)) {
              out.add(Mv.make(from, t));
            }
          }
      }
    }
  }

  void _slide(
    int from,
    int teamIdx,
    List<int> dirs,
    List<int> out,
    bool capOnly,
  ) {
    for (final d in dirs) {
      var t = from + d;
      while (true) {
        final q = sq[t];
        if (q == 0) {
          if (!capOnly) out.add(Mv.make(from, t));
        } else {
          if (_isEnemyByte(q, teamIdx)) out.add(Mv.make(from, t));
          break;
        }
        t += d;
      }
    }
  }

  void _addPromo(int from, int to, List<int> out, bool allPromos) {
    out.add(Mv.make(from, to, Mv.promotion, 5));
    if (allPromos) {
      out.add(Mv.make(from, to, Mv.promotion, 4));
      out.add(Mv.make(from, to, Mv.promotion, 3));
      out.add(Mv.make(from, to, Mv.promotion, 2));
    }
  }

  void _pawnMoves(
    int from,
    int teamIdx,
    List<int> out,
    bool capOnly,
    bool allPromos,
  ) {
    final g = geo;
    final fwd = g.pawnFwd[teamIdx];
    final promo = g.promoMasks[teamIdx];
    final one = from + fwd;
    if (sq[one] == 0) {
      if (promo[one] == 1) {
        _addPromo(from, one, out, allPromos);
      } else if (!capOnly) {
        out.add(Mv.make(from, one));
        final two = one + fwd;
        if (g.pawnStartMasks[teamIdx][from] == 1 && sq[two] == 0) {
          out.add(Mv.make(from, two, Mv.doublePush));
        }
      }
    }
    for (final d in g.pawnCaps[teamIdx]) {
      final t = from + d, q = sq[t];
      if (_isEnemyByte(q, teamIdx)) {
        if (promo[t] == 1) {
          _addPromo(from, t, out, allPromos);
        } else {
          out.add(Mv.make(from, t));
        }
      } else if (t == ep && q == 0 && epPawnSq >= 0) {
        final epByte = sq[epPawnSq];
        if (_isEnemyByte(epByte, teamIdx)) {
          out.add(Mv.make(from, t, Mv.enPassant));
        }
      }
    }
  }

  int _nextAliveAfter(int current) {
    for (var step = 1; step <= 3; step++) {
      final cand = (current + step) % 3;
      if (isAlive(cand)) return cand;
    }
    return current;
  }

  /// Yalnızca tahtadaki taşı oynatır (tur ilerletmeden meşruiyet kontrolü için hızlı iç yardımcı).
  bool _isMoveLegalFor(int m, int moverTeam) {
    final from = Mv.from(m), to = Mv.to(m);
    final piece = sq[from];
    var capSq = to;
    var captured = sq[to];
    if (Mv.isEp(m) && epPawnSq >= 0) {
      capSq = epPawnSq;
      captured = sq[capSq];
      sq[capSq] = 0;
    }
    final prevTo = sq[to];
    sq[to] = Mv.isPromo(m) ? encodePiece(moverTeam, Mv.promoCode(m)) : piece;
    sq[from] = 0;
    final prevKing = kings[moverTeam];
    if (kindCodeOfByte(piece) == 6) kings[moverTeam] = to;

    var prevEnemyAlive = aliveMask;
    if (captured != 0 && captured != off && kindCodeOfByte(captured) == 6) {
      aliveMask &= ~(1 << teamOfByte(captured));
    }

    final kingSq = kings[moverTeam];
    final safe = kingSq >= 0 && !attackedByAnyEnemy(kingSq, moverTeam);

    aliveMask = prevEnemyAlive;
    kings[moverTeam] = prevKing;
    sq[from] = piece;
    sq[to] = prevTo;
    if (capSq != to) sq[capSq] = captured;
    return safe;
  }

  List<int> legalMovesFor(int teamIdx, {bool allPromotions = false}) {
    if (!isAlive(teamIdx)) return const [];
    final pseudo = <int>[];
    pseudoMovesFor(teamIdx, pseudo, allPromotions: allPromotions);
    final res = <int>[];
    for (final m in pseudo) {
      if (_isMoveLegalFor(m, teamIdx)) {
        res.add(m);
      }
    }
    return res;
  }

  List<int> legalMoves({bool allPromotions = false}) =>
      legalMovesFor(side, allPromotions: allPromotions);

  /// Hamleyi uygular, sıradaki ordu mat/pat olduysa otomatik eler ve kalan ordularla savaşı sürdürür.
  int makeMove(int m, {bool resolveEliminations = true}) {
    final moverTeam = side;
    final from = Mv.from(m), to = Mv.to(m);
    final piece = sq[from];
    var capSq = to;
    var captured = sq[to];

    final prevEp = ep;
    final prevEpPawn = epPawnSq;
    final prevHm = halfmove;
    final prevAlive = aliveMask;
    final elimPieces = <(int, int)>[];

    if (Mv.isEp(m) && epPawnSq >= 0) {
      capSq = epPawnSq;
      captured = sq[capSq];
      sq[capSq] = 0;
    }

    sq[to] = Mv.isPromo(m) ? encodePiece(moverTeam, Mv.promoCode(m)) : piece;
    sq[from] = 0;
    if (kindCodeOfByte(piece) == 6) kings[moverTeam] = to;

    final elimTeams = <int>[];
    final elimCells = <HexCell>[];

    void eliminateTeam(int deadTeam) {
      if (!isAlive(deadTeam)) return;
      aliveMask &= ~(1 << deadTeam);
      kings[deadTeam] = -1;
      elimTeams.add(deadTeam);
      for (final i in geo.boardCells) {
        final b = sq[i];
        if (b != 0 && b != off && teamOfByte(b) == deadTeam) {
          elimPieces.add((i, b));
          elimCells.add(geo.cellOf(i));
          sq[i] = 0;
        }
      }
    }

    // Üçlü çapraz ateşte şah doğrudan düşürüldüyse o krallık anında çöker
    if (captured != 0 && captured != off && kindCodeOfByte(captured) == 6) {
      eliminateTeam(teamOfByte(captured));
    }

    if (Mv.isDouble(m)) {
      ep = from + geo.pawnFwd[moverTeam];
      epPawnSq = to;
    } else {
      ep = -1;
      epPawnSq = -1;
    }

    halfmove =
        (kindCodeOfByte(piece) == 1 || captured != 0) ? 0 : halfmove + 1;
    ply++;
    side = _nextAliveAfter(moverTeam);

    // Sırası gelen ordunun hiçbir yasal hamlesi kalmadıysa krallığı düşer ve sıra hayatta kalana geçer!
    if (resolveEliminations && aliveCount > 1) {
      for (var guard = 0; guard < 2 && aliveCount > 1; guard++) {
        if (legalMovesFor(side).isEmpty) {
          final fallenTeam = side;
          eliminateTeam(fallenTeam);
          side = _nextAliveAfter(fallenTeam);
        } else {
          break;
        }
      }
    }

    lastEliminatedTeams = elimTeams;
    lastEliminatedCells = elimCells;

    _undo.add(
      _UndoFrame3P(
        move: m,
        prevSide: moverTeam,
        captured: captured,
        capSq: capSq,
        prevEp: prevEp,
        prevEpPawnSq: prevEpPawn,
        prevHalfmove: prevHm,
        prevAliveMask: prevAlive,
        eliminatedPieces: elimPieces,
      ),
    );

    return captured;
  }

  bool get canUnmake => _undo.isNotEmpty;

  void unmakeMove() {
    final u = _undo.removeLast();
    for (final (idx, b) in u.eliminatedPieces) {
      sq[idx] = b;
      if (kindCodeOfByte(b) == 6) {
        kings[teamOfByte(b)] = idx;
      }
    }
    aliveMask = u.prevAliveMask;
    side = u.prevSide;
    ep = u.prevEp;
    epPawnSq = u.prevEpPawnSq;
    halfmove = u.prevHalfmove;
    ply--;

    final from = Mv.from(u.move), to = Mv.to(u.move);
    final moved = Mv.isPromo(u.move) ? encodePiece(side, 1) : sq[to];
    sq[from] = moved;
    if (u.capSq != to) {
      sq[to] = 0;
      sq[u.capSq] = u.captured;
    } else {
      sq[to] = u.captured;
    }
    if (kindCodeOfByte(moved) == 6) kings[side] = from;
    if (u.captured != 0 &&
        u.captured != off &&
        kindCodeOfByte(u.captured) == 6) {
      kings[teamOfByte(u.captured)] = u.capSq;
    }
    lastEliminatedTeams = const [];
    lastEliminatedCells = const [];
  }

  bool get onlyKings {
    for (final i in geo.boardCells) {
      final b = sq[i];
      if (b != 0 && b != off && kindCodeOfByte(b) != 6) return false;
    }
    return true;
  }

  String get key => '${sq.join(',')}|$side|$aliveMask|$ep';

  /// Üç kez tekrar takibi için konum özeti (FNV-1a: taşlar, sıra, canlı ordular,
  /// geçerken alma). Oyun geçmişi ve yapay zekâ isolate'i aynı özeti kullanır.
  int get repetitionHash {
    var h = 0x811C9DC5;
    for (final i in geo.boardCells) {
      h = ((h ^ (sq[i] & 0xFF)) * 0x01000193) & 0x7FFFFFFF;
    }
    h = ((h ^ side) * 0x01000193) & 0x7FFFFFFF;
    h = ((h ^ aliveMask) * 0x01000193) & 0x7FFFFFFF;
    h = ((h ^ (ep & 0x3FF)) * 0x01000193) & 0x7FFFFFFF;
    return h;
  }
}
