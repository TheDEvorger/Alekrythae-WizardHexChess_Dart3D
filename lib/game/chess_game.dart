import 'dart:math' as math;
import 'dart:typed_data';

import 'hex_board.dart';
import 'three_player_game.dart';

enum Team { white, black, emerald }

extension TeamInfo on Team {
  String get title => switch (this) {
        Team.white => 'Beyaz',
        Team.black => 'Siyah',
        Team.emerald => 'Zümrüt',
      };

  String get legion => switch (this) {
        Team.white => 'Gümüş Şafak',
        Team.black => 'Kızıl Obsidyen',
        Team.emerald => 'Zümrüt Fırtına',
      };

  String get banner => switch (this) {
        Team.white => 'BEYAZ ORDU',
        Team.black => 'SİYAH ORDU',
        Team.emerald => 'ZÜMRÜT ORDU',
      };

  double defaultFacingFor(BoardVariant variant) {
    if (variant == BoardVariant.twoPlayer) {
      return this == Team.white ? math.pi : 0.0;
    }
    return switch (this) {
      Team.white => math.pi,
      Team.black => -math.pi / 3.0,
      Team.emerald => math.pi / 3.0,
    };
  }
}

/// Kod sırası önemlidir: tahtadaki sayısal kod = index + 1.
enum PieceType { pawn, knight, bishop, rook, queen, king }

extension PieceTypeInfo on PieceType {
  int get code => index + 1;

  /// Oyundaki karanlık-fantezi karakter adı (klasik satranç taşı adı yok).
  String get creature => switch (this) {
        PieceType.pawn => 'Kalkan Muhafızı',
        PieceType.knight => 'Suikastçi',
        PieceType.bishop => 'Ejderha',
        PieceType.rook => 'Kadın Savaş Devi',
        PieceType.queen => 'Vampir Kraliçe',
        PieceType.king => 'Barbar Kral',
      };

  /// Kısa unvan / rol açıklaması.
  String get role => switch (this) {
        PieceType.pawn => 'Öncü Piyade',
        PieceType.knight => 'Gölge Avcısı',
        PieceType.bishop => 'Antik Ejder',
        PieceType.rook => 'Valkür Titan',
        PieceType.queen => 'Kan Kontesi',
        PieceType.king => 'Kuzey Hükümdarı',
      };
}

class ChessPiece {
  const ChessPiece(this.team, this.kind);

  final Team team;
  final PieceType kind;

  int get code => team == Team.white ? kind.code : -kind.code;

  static ChessPiece? fromCode(int code) {
    if (code == 0 || code.abs() > 6) return null;
    return ChessPiece(
      code > 0 ? Team.white : Team.black,
      PieceType.values[code.abs() - 1],
    );
  }

  static ChessPiece? fromByte3P(int b) {
    if (b == 0 || b == Position.off) return null;
    final t = ThreePlayerPosition.teamOfByte(b);
    final k = ThreePlayerPosition.kindCodeOfByte(b);
    if (t < 0 || t >= 3 || k < 1 || k > 6) return null;
    return ChessPiece(Team.values[t], PieceType.values[k - 1]);
  }
}

/// Hamle kodlaması (tek int):
/// bit 0..8: from | bit 9..17: to | bit 18..20: bayraklar | bit 21..23: terfi kodu (2..5).
abstract final class Mv {
  static const int doublePush = 1 << 18;
  static const int enPassant = 1 << 19;
  static const int promotion = 1 << 20;

  static int make(int from, int to, [int flags = 0, int promoCode = 5]) =>
      from |
      (to << 9) |
      flags |
      ((flags & promotion != 0 ? promoCode : 0) << 21);

  static int from(int m) => m & 511;
  static int to(int m) => (m >> 9) & 511;
  static bool isDouble(int m) => m & doublePush != 0;
  static bool isEp(int m) => m & enPassant != 0;
  static bool isPromo(int m) => m & promotion != 0;
  static int promoCode(int m) {
    final c = (m >> 21) & 7;
    return (c >= 2 && c <= 5) ? c : 5;
  }
}

/// Hızlı, dolgulu (padded) dizi üzerinde tam 2 kişilik Gliński kural motoru.
class Position {
  static const int span = 17; // q,r ∈ [-8, 8] (3 hücre dolgu)
  static const int cellsTotal = span * span;
  static const int off = 99;

  static int idx(int q, int r) => (q + 8) * span + (r + 8);
  static HexCell cellOf(int i) => HexCell(i ~/ span - 8, i % span - 8);
  static int idxOf(HexCell c) => idx(c.q, c.r);

  static const List<int> rookDirs = [17, 16, -1, -17, -16, 1];
  static const List<int> bishopDirs = [33, 18, -15, -33, -18, 15];
  static const List<int> kingDirs = [
    17,
    16,
    -1,
    -17,
    -16,
    1,
    33,
    18,
    -15,
    -33,
    -18,
    15
  ];
  static const List<int> knightDirs = [
    19,
    35,
    -14,
    -31,
    -49,
    -50,
    -19,
    -35,
    14,
    31,
    49,
    50
  ];

  static final List<int> boardCells = [
    for (final c in HexBoard.cells) idxOf(c),
  ];

  static final Uint8List _whiteStart =
      _mask(const ['b1', 'c2', 'd3', 'e4', 'f5', 'g4', 'h3', 'i2', 'k1']);
  static final Uint8List _blackStart =
      _mask(const ['b7', 'c7', 'd7', 'e7', 'f7', 'g7', 'h7', 'i7', 'k7']);

  static Uint8List _mask(List<String> names) {
    final m = Uint8List(cellsTotal);
    for (final n in names) {
      m[idxOf(HexBoard.parse(n))] = 1;
    }
    return m;
  }

  static bool _inside(int i) {
    final q = i ~/ span - 8, r = i % span - 8;
    return HexBoard.contains(HexCell(q, r));
  }

  static final Uint8List whitePromo = () {
    final m = Uint8List(cellsTotal);
    for (final i in boardCells) {
      if (!_inside(i + 1)) m[i] = 1;
    }
    return m;
  }();
  static final Uint8List blackPromo = () {
    final m = Uint8List(cellsTotal);
    for (final i in boardCells) {
      if (!_inside(i - 1)) m[i] = 1;
    }
    return m;
  }();

  final Int8List sq = Int8List(cellsTotal);
  int side = 1; // 1 = beyaz, -1 = siyah
  int ep = -1;
  int halfmove = 0;
  int ply = 0;
  int whiteKing = -1;
  int blackKing = -1;
  final List<int> _undo = [];

  Position();

  Position.copy(Position o) {
    sq.setAll(0, o.sq);
    side = o.side;
    ep = o.ep;
    halfmove = o.halfmove;
    ply = o.ply;
    whiteKing = o.whiteKing;
    blackKing = o.blackKing;
  }

  List<int> serialize() => [...sq, side, ep, halfmove, ply];

  factory Position.deserialize(List<int> data) {
    final p = Position();
    for (var i = 0; i < cellsTotal; i++) {
      p.sq[i] = data[i];
    }
    p.side = data[cellsTotal];
    p.ep = data[cellsTotal + 1];
    p.halfmove = data[cellsTotal + 2];
    p.ply = data[cellsTotal + 3];
    p._findKings();
    return p;
  }

  void _findKings() {
    whiteKing = blackKing = -1;
    for (final i in boardCells) {
      if (sq[i] == 6) whiteKing = i;
      if (sq[i] == -6) blackKing = i;
    }
  }

  void setupStart() {
    sq.fillRange(0, cellsTotal, off);
    for (final i in boardCells) {
      sq[i] = 0;
    }
    const white = {
      'g1': PieceType.king,
      'e1': PieceType.queen,
      'c1': PieceType.rook,
      'i1': PieceType.rook,
      'd1': PieceType.knight,
      'h1': PieceType.knight,
      'f1': PieceType.bishop,
      'f2': PieceType.bishop,
      'f3': PieceType.bishop,
      'b1': PieceType.pawn,
      'c2': PieceType.pawn,
      'd3': PieceType.pawn,
      'e4': PieceType.pawn,
      'f5': PieceType.pawn,
      'g4': PieceType.pawn,
      'h3': PieceType.pawn,
      'i2': PieceType.pawn,
      'k1': PieceType.pawn,
    };
    const black = {
      'e10': PieceType.king,
      'g10': PieceType.queen,
      'c8': PieceType.rook,
      'i8': PieceType.rook,
      'd9': PieceType.knight,
      'h9': PieceType.knight,
      'f9': PieceType.bishop,
      'f10': PieceType.bishop,
      'f11': PieceType.bishop,
      'b7': PieceType.pawn,
      'c7': PieceType.pawn,
      'd7': PieceType.pawn,
      'e7': PieceType.pawn,
      'f7': PieceType.pawn,
      'g7': PieceType.pawn,
      'h7': PieceType.pawn,
      'i7': PieceType.pawn,
      'k7': PieceType.pawn,
    };
    for (final e in white.entries) {
      sq[idxOf(HexBoard.parse(e.key))] = e.value.code;
    }
    for (final e in black.entries) {
      sq[idxOf(HexBoard.parse(e.key))] = -e.value.code;
    }
    side = 1;
    ep = -1;
    halfmove = 0;
    ply = 0;
    _undo.clear();
    _findKings();
  }

  int kingOf(int s) => s > 0 ? whiteKing : blackKing;

  bool attacked(int s, int by) {
    if (by > 0) {
      if (sq[s - 17] == 1 || sq[s + 16] == 1) return true;
    } else {
      if (sq[s + 17] == -1 || sq[s - 16] == -1) return true;
    }
    final knight = 2 * by, king = 6 * by;
    for (final d in knightDirs) {
      if (sq[s + d] == knight) return true;
    }
    for (final d in kingDirs) {
      if (sq[s + d] == king) return true;
    }
    final rook = 4 * by, queen = 5 * by, bishop = 3 * by;
    for (final d in rookDirs) {
      var t = s + d;
      while (sq[t] == 0) {
        t += d;
      }
      final p = sq[t];
      if (p == rook || p == queen) return true;
    }
    for (final d in bishopDirs) {
      var t = s + d;
      while (sq[t] == 0) {
        t += d;
      }
      final p = sq[t];
      if (p == bishop || p == queen) return true;
    }
    return false;
  }

  bool inCheck([int? who]) {
    final s = who ?? side;
    final k = kingOf(s);
    return k >= 0 && attacked(k, -s);
  }

  bool _enemy(int p, int s) => p != 0 && p != off && (p > 0) != (s > 0);

  void pseudoMoves(List<int> out,
      {bool capturesOnly = false, bool allPromotions = false}) {
    final s = side;
    for (final from in boardCells) {
      final p = sq[from];
      if (p == 0 || (p > 0) != (s > 0)) continue;
      switch (p.abs()) {
        case 1:
          _pawnMoves(from, s, out, capturesOnly, allPromotions);
        case 2:
          for (final d in knightDirs) {
            final t = from + d, q = sq[t];
            if (q == off) continue;
            if (q == 0) {
              if (!capturesOnly) out.add(Mv.make(from, t));
            } else if (_enemy(q, s)) {
              out.add(Mv.make(from, t));
            }
          }
        case 3:
          _slide(from, s, bishopDirs, out, capturesOnly);
        case 4:
          _slide(from, s, rookDirs, out, capturesOnly);
        case 5:
          _slide(from, s, rookDirs, out, capturesOnly);
          _slide(from, s, bishopDirs, out, capturesOnly);
        case 6:
          for (final d in kingDirs) {
            final t = from + d, q = sq[t];
            if (q == off) continue;
            if (q == 0) {
              if (!capturesOnly) out.add(Mv.make(from, t));
            } else if (_enemy(q, s)) {
              out.add(Mv.make(from, t));
            }
          }
      }
    }
  }

  void _slide(int from, int s, List<int> dirs, List<int> out, bool capOnly) {
    for (final d in dirs) {
      var t = from + d;
      while (true) {
        final q = sq[t];
        if (q == 0) {
          if (!capOnly) out.add(Mv.make(from, t));
        } else {
          if (_enemy(q, s)) out.add(Mv.make(from, t));
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
      int from, int s, List<int> out, bool capOnly, bool allPromos) {
    final fwd = s > 0 ? 1 : -1;
    final promo = s > 0 ? whitePromo : blackPromo;
    final one = from + fwd;
    if (sq[one] == 0) {
      if (promo[one] == 1) {
        _addPromo(from, one, out, allPromos);
      } else if (!capOnly) {
        out.add(Mv.make(from, one));
        final start = s > 0 ? _whiteStart : _blackStart;
        final two = one + fwd;
        if (start[from] == 1 && sq[two] == 0) {
          out.add(Mv.make(from, two, Mv.doublePush));
        }
      }
    }
    final caps = s > 0 ? const [17, -16] : const [-17, 16];
    for (final d in caps) {
      final t = from + d, q = sq[t];
      if (_enemy(q, s)) {
        if (promo[t] == 1) {
          _addPromo(from, t, out, allPromos);
        } else {
          out.add(Mv.make(from, t));
        }
      } else if (t == ep && q == 0) {
        out.add(Mv.make(from, t, Mv.enPassant));
      }
    }
  }

  int makeMove(int m) {
    final from = Mv.from(m), to = Mv.to(m);
    final piece = sq[from];
    var captured = sq[to];
    var capSq = to;
    if (Mv.isEp(m)) {
      capSq = to - (side > 0 ? 1 : -1);
      captured = sq[capSq];
      sq[capSq] = 0;
    }
    _undo
      ..add(m)
      ..add(captured)
      ..add(ep)
      ..add(halfmove);
    sq[to] = Mv.isPromo(m) ? Mv.promoCode(m) * side : piece;
    sq[from] = 0;
    if (piece == 6) whiteKing = to;
    if (piece == -6) blackKing = to;
    ep = Mv.isDouble(m) ? (from + to) ~/ 2 : -1;
    halfmove = (piece.abs() == 1 || captured != 0) ? 0 : halfmove + 1;
    side = -side;
    ply++;
    return captured;
  }

  bool get canUnmake => _undo.length >= 4;

  void unmakeMove() {
    final hm = _undo.removeLast();
    final prevEp = _undo.removeLast();
    final captured = _undo.removeLast();
    final m = _undo.removeLast();
    side = -side;
    ply--;
    halfmove = hm;
    ep = prevEp;
    final from = Mv.from(m), to = Mv.to(m);
    final moved = Mv.isPromo(m) ? side : sq[to];
    sq[from] = moved;
    if (Mv.isEp(m)) {
      sq[to] = 0;
      sq[to - (side > 0 ? 1 : -1)] = captured;
    } else {
      sq[to] = captured;
    }
    if (moved == 6) whiteKing = from;
    if (moved == -6) blackKing = from;
  }

  List<int> legalMoves({bool allPromotions = false}) {
    final pseudo = <int>[];
    pseudoMoves(pseudo, allPromotions: allPromotions);
    final result = <int>[];
    final me = side;
    for (final m in pseudo) {
      makeMove(m);
      if (!attacked(kingOf(me), -me)) result.add(m);
      unmakeMove();
    }
    return result;
  }

  bool get onlyKings {
    for (final i in boardCells) {
      final p = sq[i].abs();
      if (p != 0 && p != 6) return false;
    }
    return true;
  }

  String get key => '${sq.join(',')}|$side|$ep';
}

enum GameStatus { playing, checkmate, stalemate, draw }

/// Şah çeken düşman taşını ve Kral ile arasındaki hücum hattını (lazer koridoru) temsil eder.
class CheckThreat {
  const CheckThreat({
    required this.kingCell,
    required this.attackerCell,
    required this.attackerPiece,
    required this.rayCells,
  });

  final HexCell kingCell;
  final HexCell attackerCell;
  final ChessPiece attackerPiece;
  final List<HexCell> rayCells;
}

class MoveRecord {
  MoveRecord({
    required this.encoded,
    required this.from,
    required this.to,
    required this.piece,
    this.captured,
    this.capturedAt,
    this.promotedTo,
    this.check = false,
    this.eliminatedTeams = const [],
    this.eliminatedCells = const [],
  });

  final int encoded;
  final HexCell from;
  final HexCell to;
  final ChessPiece piece;
  final ChessPiece? captured;
  final HexCell? capturedAt;
  final PieceType? promotedTo;
  final bool check;
  final List<Team> eliminatedTeams;
  final List<HexCell> eliminatedCells;

  bool get promoted => promotedTo != null;
}

class ChessGame {
  ChessGame({
    BoardVariant variant = BoardVariant.twoPlayer,
    BoardSize boardSize = BoardSize.classic,
  })  : _variant = variant,
        _size3p = boardSize,
        pos3 = ThreePlayerPosition(boardSize) {
    reset();
  }

  BoardVariant _variant;
  BoardVariant get variant => _variant;
  bool get isThreePlayer => _variant == BoardVariant.threePlayer;

  /// 3 kişilik masa için seçili tahta boyutu (2 kişilik düello her zaman Klasik).
  BoardSize _size3p;

  /// Etkin tahta boyutu: 2 kişilikte her zaman Klasik.
  BoardSize get boardSize => isThreePlayer ? _size3p : BoardSize.classic;

  /// 3 kişilik masa için seçili boyut (2 kişilik oynanırken de hatırlanır).
  BoardSize get boardSize3P => _size3p;

  /// Arayüz etiketi: "3 Kişilik Masa • Dev" ya da "2 Kişilik Düello".
  String get boardLabel =>
      isThreePlayer ? '${_variant.label} • ${_size3p.label}' : _variant.label;

  /// Etkin masanın hücreleri, kare adları ve amfi sütun yükseklikleri.
  BoardShape get shape => BoardShape.of(_variant, boardSize);

  final Position pos = Position();
  ThreePlayerPosition pos3;

  final List<String> _history = [];

  /// 3 kişilik konum özetleri (yapay zekânın üç kez tekrar beraberliğinden kaçınması için).
  final List<int> _hash3History = [];
  final List<MoveRecord> moveLog = [];
  final List<ChessPiece> fallen = [];
  GameStatus status = GameStatus.playing;
  String statusText = '';
  MoveRecord? lastMove;

  /// Masa düzenini (ve 3 kişilikte isteğe bağlı olarak tahta boyutunu) değiştirip yeni oyun kurar.
  void setVariant(BoardVariant next, {BoardSize? size}) {
    _variant = next;
    if (size != null) _size3p = size;
    if (pos3.size != _size3p) pos3 = ThreePlayerPosition(_size3p);
    reset();
  }

  /// 2 kişilik oyun sürerken 3'lü masa için boyut tercihini oyunu bozmadan kaydeder
  /// (3 kişilikte boyut değişimi yeni oyun ister: [setVariant] kullanılır).
  void rememberBoardSize3P(BoardSize size) {
    if (isThreePlayer) return;
    _size3p = size;
  }

  /// Etkin masanın dizi indeksini hücreye çevirir (hamle kodlarındaki from/to için).
  HexCell cellOfIndex(int i) =>
      isThreePlayer ? pos3.geo.cellOf(i) : Position.cellOf(i);

  int _idxOf(HexCell c) =>
      isThreePlayer ? pos3.geo.idxOf(c) : Position.idxOf(c);

  /// Oyunda şimdiden iki kez görülmüş 3 kişilik konumlar: oraya dönen hamle
  /// üç kez tekrar beraberliği olur.
  List<int> get repetitionHashes3P {
    if (!isThreePlayer) return const [];
    final counts = <int, int>{};
    for (final h in _hash3History) {
      counts[h] = (counts[h] ?? 0) + 1;
    }
    return [
      for (final e in counts.entries)
        if (e.value >= 2) e.key
    ];
  }

  /// SQLite kalıcılığı için baştan sona tüm yasal hamle kodlarını dışa aktarır.
  List<int> exportEncodedMoves() =>
      List<int>.unmodifiable([for (final r in moveLog) r.encoded]);

  /// SQLite kaydından tahtayı, elenen orduları, düşen savaşçıları ve geri-al yığınını %100 geri yükler.
  bool restoreFromEncodedMoves(
    BoardVariant targetVariant,
    List<int> moves, {
    BoardSize size = BoardSize.classic,
  }) {
    setVariant(targetVariant, size: size);
    try {
      for (final m in moves) {
        final legals = isThreePlayer
            ? pos3.legalMoves(allPromotions: true)
            : pos.legalMoves(allPromotions: true);
        if (!legals.contains(m)) {
          reset();
          return false;
        }
        applyEncoded(m);
      }
      return true;
    } catch (_) {
      reset();
      return false;
    }
  }

  List<Team> get activeTeams => isThreePlayer
      ? const [Team.white, Team.black, Team.emerald]
      : const [Team.white, Team.black];

  bool isTeamAlive(Team t) => isThreePlayer
      ? pos3.isAlive(t.index)
      : (t == Team.white || t == Team.black);

  Team get turn => isThreePlayer
      ? Team.values[pos3.side]
      : (pos.side > 0 ? Team.white : Team.black);

  int get ply => isThreePlayer ? pos3.ply : pos.ply;
  bool get canUndo => moveLog.isNotEmpty;

  bool get inCheckNow => isThreePlayer ? pos3.inCheck() : pos.inCheck();

  HexCell? get checkedKingCell {
    if (!inCheckNow) return null;
    if (isThreePlayer) {
      final k = pos3.kings[pos3.side];
      return k >= 0 ? pos3.geo.cellOf(k) : null;
    }
    final k = pos.kingOf(pos.side);
    return k >= 0 ? Position.cellOf(k) : null;
  }

  /// Krala şah çeken tüm düşman yaratıkları ve aradaki tehdit çizgilerini döndürür.
  List<CheckThreat> get currentCheckThreats {
    if (!inCheckNow) return const [];
    final threats = <CheckThreat>[];

    if (isThreePlayer) {
      final myTeam = pos3.side;
      final kingSq = pos3.kings[myTeam];
      if (kingSq < 0) return const [];
      final g = pos3.geo;
      final kingCell = g.cellOf(kingSq);

      for (var byTeam = 0; byTeam < 3; byTeam++) {
        if (byTeam == myTeam || !pos3.isAlive(byTeam)) continue;
        final enemyTeam = Team.values[byTeam];

        // Piyon saldırıları
        final pawnByte = ThreePlayerPosition.encodePiece(byTeam, 1);
        for (final d in g.pawnCaps[byTeam]) {
          final atkSq = kingSq - d;
          if (atkSq >= 0 && atkSq < g.cellsTotal && pos3.sq[atkSq] == pawnByte) {
            threats.add(CheckThreat(
              kingCell: kingCell,
              attackerCell: g.cellOf(atkSq),
              attackerPiece: ChessPiece(enemyTeam, PieceType.pawn),
              rayCells: const [],
            ));
          }
        }

        // Suikastçi (At / Knight) saldırıları
        final knightByte = ThreePlayerPosition.encodePiece(byTeam, 2);
        for (final d in g.knightDirs) {
          final atkSq = kingSq + d;
          if (atkSq >= 0 && atkSq < g.cellsTotal && pos3.sq[atkSq] == knightByte) {
            threats.add(CheckThreat(
              kingCell: kingCell,
              attackerCell: g.cellOf(atkSq),
              attackerPiece: ChessPiece(enemyTeam, PieceType.knight),
              rayCells: const [],
            ));
          }
        }

        // Kale ve Kraliçe (Ortogonal) saldırıları
        final rookByte = ThreePlayerPosition.encodePiece(byTeam, 4);
        final queenByte = ThreePlayerPosition.encodePiece(byTeam, 5);
        for (final d in g.rookDirs) {
          var t = kingSq + d;
          final ray = <HexCell>[];
          while (t >= 0 && t < g.cellsTotal && pos3.sq[t] == 0) {
            ray.add(g.cellOf(t));
            t += d;
          }
          if (t >= 0 && t < g.cellsTotal) {
            final p = pos3.sq[t];
            if (p == rookByte || p == queenByte) {
              threats.add(CheckThreat(
                kingCell: kingCell,
                attackerCell: g.cellOf(t),
                attackerPiece: ChessPiece(
                  enemyTeam,
                  p == rookByte ? PieceType.rook : PieceType.queen,
                ),
                rayCells: ray,
              ));
            }
          }
        }

        // Ejderha ve Kraliçe (Çapraz / Diagonal) saldırıları
        final bishopByte = ThreePlayerPosition.encodePiece(byTeam, 3);
        for (final d in g.bishopDirs) {
          var t = kingSq + d;
          final ray = <HexCell>[];
          while (t >= 0 && t < g.cellsTotal && pos3.sq[t] == 0) {
            ray.add(g.cellOf(t));
            t += d;
          }
          if (t >= 0 && t < g.cellsTotal) {
            final p = pos3.sq[t];
            if (p == bishopByte || p == queenByte) {
              threats.add(CheckThreat(
                kingCell: kingCell,
                attackerCell: g.cellOf(t),
                attackerPiece: ChessPiece(
                  enemyTeam,
                  p == bishopByte ? PieceType.bishop : PieceType.queen,
                ),
                rayCells: ray,
              ));
            }
          }
        }
      }
      return threats;
    }

    // 2 Kişilik Klasik Mod
    final me = pos.side;
    final kingSq = pos.kingOf(me);
    if (kingSq < 0) return const [];
    final kingCell = Position.cellOf(kingSq);
    final by = -me;
    final enemyTeam = by > 0 ? Team.white : Team.black;

    // Piyon tehditleri
    if (by > 0) {
      if (kingSq - 17 >= 0 && pos.sq[kingSq - 17] == 1) {
        threats.add(CheckThreat(
          kingCell: kingCell,
          attackerCell: Position.cellOf(kingSq - 17),
          attackerPiece: ChessPiece(enemyTeam, PieceType.pawn),
          rayCells: const [],
        ));
      }
      if (kingSq + 16 < Position.cellsTotal && pos.sq[kingSq + 16] == 1) {
        threats.add(CheckThreat(
          kingCell: kingCell,
          attackerCell: Position.cellOf(kingSq + 16),
          attackerPiece: ChessPiece(enemyTeam, PieceType.pawn),
          rayCells: const [],
        ));
      }
    } else {
      if (kingSq + 17 < Position.cellsTotal && pos.sq[kingSq + 17] == -1) {
        threats.add(CheckThreat(
          kingCell: kingCell,
          attackerCell: Position.cellOf(kingSq + 17),
          attackerPiece: ChessPiece(enemyTeam, PieceType.pawn),
          rayCells: const [],
        ));
      }
      if (kingSq - 16 >= 0 && pos.sq[kingSq - 16] == -1) {
        threats.add(CheckThreat(
          kingCell: kingCell,
          attackerCell: Position.cellOf(kingSq - 16),
          attackerPiece: ChessPiece(enemyTeam, PieceType.pawn),
          rayCells: const [],
        ));
      }
    }

    // Suikastçi (At) tehditleri
    final knight = 2 * by;
    for (final d in Position.knightDirs) {
      final t = kingSq + d;
      if (t >= 0 && t < Position.cellsTotal && pos.sq[t] == knight) {
        threats.add(CheckThreat(
          kingCell: kingCell,
          attackerCell: Position.cellOf(t),
          attackerPiece: ChessPiece(enemyTeam, PieceType.knight),
          rayCells: const [],
        ));
      }
    }

    // Kale ve Kraliçe (Ortogonal) tehditleri
    final rook = 4 * by, queen = 5 * by, bishop = 3 * by;
    for (final d in Position.rookDirs) {
      var t = kingSq + d;
      final ray = <HexCell>[];
      while (t >= 0 && t < Position.cellsTotal && pos.sq[t] == 0) {
        ray.add(Position.cellOf(t));
        t += d;
      }
      if (t >= 0 && t < Position.cellsTotal) {
        final p = pos.sq[t];
        if (p == rook || p == queen) {
          threats.add(CheckThreat(
            kingCell: kingCell,
            attackerCell: Position.cellOf(t),
            attackerPiece: ChessPiece(
              enemyTeam,
              p == rook ? PieceType.rook : PieceType.queen,
            ),
            rayCells: ray,
          ));
        }
      }
    }

    // Ejderha ve Kraliçe (Çapraz) tehditleri
    for (final d in Position.bishopDirs) {
      var t = kingSq + d;
      final ray = <HexCell>[];
      while (t >= 0 && t < Position.cellsTotal && pos.sq[t] == 0) {
        ray.add(Position.cellOf(t));
        t += d;
      }
      if (t >= 0 && t < Position.cellsTotal) {
        final p = pos.sq[t];
        if (p == bishop || p == queen) {
          threats.add(CheckThreat(
            kingCell: kingCell,
            attackerCell: Position.cellOf(t),
            attackerPiece: ChessPiece(
              enemyTeam,
              p == bishop ? PieceType.bishop : PieceType.queen,
            ),
            rayCells: ray,
          ));
        }
      }
    }

    return threats;
  }

  HexCell? kingCellOf(Team t) {
    if (isThreePlayer) {
      final k = pos3.kings[t.index];
      return k >= 0 ? pos3.geo.cellOf(k) : null;
    }
    if (t == Team.emerald) return null;
    final k = t == Team.white ? pos.whiteKing : pos.blackKing;
    return k >= 0 ? Position.cellOf(k) : null;
  }

  Map<HexCell, ChessPiece> get pieces => isThreePlayer
      ? {
          for (final i in pos3.geo.boardCells)
            if (pos3.sq[i] != 0 && pos3.sq[i] != Position.off)
              pos3.geo.cellOf(i): ChessPiece.fromByte3P(pos3.sq[i])!,
        }
      : {
          for (final i in Position.boardCells)
            if (pos.sq[i] != 0)
              Position.cellOf(i): ChessPiece.fromCode(pos.sq[i])!,
        };

  ChessPiece? pieceAt(HexCell c) {
    if (!shape.contains(c)) return null;
    final idx = _idxOf(c);
    return isThreePlayer
        ? ChessPiece.fromByte3P(pos3.sq[idx])
        : ChessPiece.fromCode(pos.sq[idx]);
  }

  void reset() {
    _hash3History.clear();
    if (isThreePlayer) {
      pos3.setupStart();
      _history
        ..clear()
        ..add(pos3.key);
      _hash3History.add(pos3.repetitionHash);
    } else {
      pos.setupStart();
      _history
        ..clear()
        ..add(pos.key);
    }
    moveLog.clear();
    fallen.clear();
    status = GameStatus.playing;
    statusText = '';
    lastMove = null;
  }

  List<int> _legalFrom(HexCell from, {bool allPromos = false}) {
    if (status != GameStatus.playing) return const [];
    if (!shape.contains(from)) return const [];
    final f = _idxOf(from);
    final moves = isThreePlayer
        ? pos3.legalMoves(allPromotions: allPromos)
        : pos.legalMoves(allPromotions: allPromos);
    return [
      for (final m in moves)
        if (Mv.from(m) == f) m
    ];
  }

  List<HexCell> legalMoves(HexCell from) =>
      {for (final m in _legalFrom(from)) cellOfIndex(Mv.to(m))}.toList();

  List<HexCell> pseudoLegalMoves(HexCell from) => legalMoves(from);

  bool needsPromotion(HexCell from, HexCell to) {
    if (!shape.contains(to)) return false;
    final t = _idxOf(to);
    for (final m in _legalFrom(from)) {
      if (Mv.to(m) == t && Mv.isPromo(m)) return true;
    }
    return false;
  }

  bool play(HexCell from, HexCell to, {PieceType? promotion}) =>
      playMove(from, to, promotion: promotion) != null;

  MoveRecord? playMove(HexCell from, HexCell to, {PieceType? promotion}) {
    if (!shape.contains(to)) return null;
    final t = _idxOf(to);
    final wantCode = (promotion ?? PieceType.queen).code;
    for (final m in _legalFrom(from, allPromos: promotion != null)) {
      if (Mv.to(m) == t) {
        if (Mv.isPromo(m) && Mv.promoCode(m) != wantCode) continue;
        return applyEncoded(m);
      }
    }
    return null;
  }

  MoveRecord applyEncoded(int m) {
    if (isThreePlayer) {
      final from = Mv.from(m), to = Mv.to(m);
      final mover = ChessPiece.fromByte3P(pos3.sq[from])!;
      final capSq =
          Mv.isEp(m) && pos3.epPawnSq >= 0 ? pos3.epPawnSq : to;
      final capturedByte = pos3.makeMove(m);
      final captured = ChessPiece.fromByte3P(capturedByte);
      if (captured != null) fallen.add(captured);
      _history.add(pos3.key);
      _hash3History.add(pos3.repetitionHash);
      final promoType =
          Mv.isPromo(m) ? PieceType.values[Mv.promoCode(m) - 1] : null;
      final elimTeams = [
        for (final ti in pos3.lastEliminatedTeams) Team.values[ti]
      ];
      final elimCells = List<HexCell>.of(pos3.lastEliminatedCells);
      final g = pos3.geo;
      final record = MoveRecord(
        encoded: m,
        from: g.cellOf(from),
        to: g.cellOf(to),
        piece: mover,
        captured: captured,
        capturedAt: captured == null ? null : g.cellOf(capSq),
        promotedTo: promoType,
        check: pos3.inCheck(),
        eliminatedTeams: elimTeams,
        eliminatedCells: elimCells,
      );
      moveLog.add(record);
      lastMove = record;
      _updateStatus3P();
      return record;
    }

    final from = Mv.from(m), to = Mv.to(m);
    final mover = ChessPiece.fromCode(pos.sq[from])!;
    final capSq = Mv.isEp(m) ? to - pos.side : to;
    final capturedCode = pos.makeMove(m);
    final captured = ChessPiece.fromCode(capturedCode);
    if (captured != null) fallen.add(captured);
    _history.add(pos.key);
    final promoType =
        Mv.isPromo(m) ? PieceType.values[Mv.promoCode(m) - 1] : null;
    final record = MoveRecord(
      encoded: m,
      from: Position.cellOf(from),
      to: Position.cellOf(to),
      piece: mover,
      captured: captured,
      capturedAt: captured == null ? null : Position.cellOf(capSq),
      promotedTo: promoType,
      check: pos.inCheck(),
    );
    moveLog.add(record);
    lastMove = record;
    _updateStatus2P();
    return record;
  }

  MoveRecord? undoSingle() {
    if (isThreePlayer) {
      if (!pos3.canUnmake || moveLog.isEmpty) return null;
      pos3.unmakeMove();
      final undone = moveLog.removeLast();
      if (_history.length > 1) _history.removeLast();
      if (_hash3History.length > 1) _hash3History.removeLast();
      if (undone.captured != null && fallen.isNotEmpty) {
        fallen.removeLast();
      }
      lastMove = moveLog.isEmpty ? null : moveLog.last;
      status = GameStatus.playing;
      statusText = '';
      _updateStatus3P();
      return undone;
    }

    if (!pos.canUnmake || moveLog.isEmpty) return null;
    pos.unmakeMove();
    final undone = moveLog.removeLast();
    if (_history.length > 1) _history.removeLast();
    if (undone.captured != null && fallen.isNotEmpty) {
      fallen.removeLast();
    }
    lastMove = moveLog.isEmpty ? null : moveLog.last;
    status = GameStatus.playing;
    statusText = '';
    _updateStatus2P();
    return undone;
  }

  void _updateStatus2P() {
    final moves = pos.legalMoves();
    final mover = turn == Team.white ? 'Siyah' : 'Beyaz';
    if (moves.isEmpty) {
      if (pos.inCheck()) {
        status = GameStatus.checkmate;
        statusText = 'ŞAH MAT! $mover Ordusu zafer kazandı!';
      } else {
        status = GameStatus.stalemate;
        statusText = 'PAT! Gliński kuralı: $mover ¾ puan alır.';
      }
    } else if (pos.halfmove >= 100) {
      status = GameStatus.draw;
      statusText = 'Berabere (50 hamle kuralı).';
    } else if (pos.onlyKings) {
      status = GameStatus.draw;
      statusText = 'Berabere (yetersiz kuvvet).';
    } else if (_history.where((k) => k == pos.key).length >= 3) {
      status = GameStatus.draw;
      statusText = 'Berabere (üç kez konum tekrarı).';
    }
  }

  void _updateStatus3P() {
    final survivor = pos3.soleSurvivor;
    if (survivor != null) {
      final champ = Team.values[survivor];
      status = GameStatus.checkmate;
      statusText =
          'MUTLAK ZAFER! ${champ.legion} (${champ.title} Ordu) 3 Kişilik Amfi Arenanın Hükümdarı Oldu!';
      return;
    }
    if (pos3.halfmove >= pos3.geo.halfmoveDrawLimit) {
      status = GameStatus.draw;
      statusText = 'Berabere (uzun süreli ateşkes).';
    } else if (pos3.onlyKings) {
      status = GameStatus.draw;
      statusText = 'Berabere (yalnızca hükümdarlar kaldı).';
    } else if (_history.where((k) => k == pos3.key).length >= 3) {
      status = GameStatus.draw;
      statusText = 'Berabere (üç kez konum tekrarı).';
    }
  }
}
