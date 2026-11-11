import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'chess_game.dart';
import 'hex_board.dart';

/// Oyunun 24 Kademeli Profesyonel Yapay Zekâsı:
/// - Kademe 1 - 6 (KOLAY): Acemi gafı (blunder), rastgele hamle olasılığı, yüzeysel arama (Harbi Kolay).
/// - Kademe 7 - 12 (ORTA): Sıfır gaf, dengeli taş ve merkez hakimiyeti, 2-3 derinlik (Harbi Orta).
/// - Kademe 13 - 18 (ZOR): Katı sükûnet araması (quiescence), killer ve history sezgiselleri (Harbi Zor).
/// - Kademe 19 - 24 (EFSANEVİ): Derin alfa-beta iteratif arama, 5-7 derinlik, kusursuz taktik hesap (Büyük Üstat).
enum AiLevel {
  lvl1(
    tier: 1,
    label: 'Acemi Köylü',
    category: 'Kolay • Çırak',
    targetElo: 600,
    maxDepth: 1,
    timeMs: 70,
    noise: 180,
    blunderChance: 0.45,
    depth3p: 1,
    time3p: 100,
  ),
  lvl2(
    tier: 2,
    label: 'Kalkan Taşıyıcı',
    category: 'Kolay • Çırak',
    targetElo: 700,
    maxDepth: 1,
    timeMs: 85,
    noise: 140,
    blunderChance: 0.38,
    depth3p: 1,
    time3p: 120,
  ),
  lvl3(
    tier: 3,
    label: 'Çırak Muhafız',
    category: 'Kolay • Çırak',
    targetElo: 800,
    maxDepth: 1,
    timeMs: 100,
    noise: 110,
    blunderChance: 0.30,
    depth3p: 1,
    time3p: 140,
  ),
  lvl4(
    tier: 4,
    label: 'Hisar Gözcüsü',
    category: 'Kolay • Çırak',
    targetElo: 900,
    maxDepth: 2,
    timeMs: 120,
    noise: 85,
    blunderChance: 0.24,
    depth3p: 1,
    time3p: 160,
  ),
  lvl5(
    tier: 5,
    label: 'Gezgin Devriye',
    category: 'Kolay • Çırak',
    targetElo: 1000,
    maxDepth: 2,
    timeMs: 140,
    noise: 65,
    blunderChance: 0.18,
    depth3p: 2,
    time3p: 190,
  ),
  lvl6(
    tier: 6,
    label: 'Sınır Avcısı',
    category: 'Kolay • Çırak',
    targetElo: 1100,
    maxDepth: 2,
    timeMs: 160,
    noise: 50,
    blunderChance: 0.12,
    depth3p: 2,
    time3p: 220,
  ),

  // ================= 7 - 12: ORTA (Savaşçı & Şövalye) =================
  lvl7(
    tier: 7,
    label: 'Demir Muhafız',
    category: 'Orta • Savaşçı',
    targetElo: 1200,
    maxDepth: 2,
    timeMs: 180,
    noise: 35,
    blunderChance: 0.07,
    depth3p: 2,
    time3p: 250,
  ),
  lvl8(
    tier: 8,
    label: 'Tunç Şövalye',
    category: 'Orta • Savaşçı',
    targetElo: 1300,
    maxDepth: 3,
    timeMs: 210,
    noise: 24,
    blunderChance: 0.04,
    depth3p: 2,
    time3p: 290,
  ),
  lvl9(
    tier: 9,
    label: 'Gümüş Muhafız',
    category: 'Orta • Savaşçı',
    targetElo: 1400,
    maxDepth: 3,
    timeMs: 250,
    noise: 16,
    blunderChance: 0.02,
    depth3p: 2,
    time3p: 330,
  ),
  lvl10(
    tier: 10,
    label: 'Vadi Akıncısı',
    category: 'Orta • Savaşçı',
    targetElo: 1500,
    maxDepth: 3,
    timeMs: 290,
    noise: 10,
    blunderChance: 0.01,
    depth3p: 3,
    time3p: 380,
  ),
  lvl11(
    tier: 11,
    label: 'Buz Yolu Şövalyesi',
    category: 'Orta • Savaşçı',
    targetElo: 1600,
    maxDepth: 3,
    timeMs: 340,
    noise: 5,
    blunderChance: 0.0,
    depth3p: 3,
    time3p: 430,
  ),
  lvl12(
    tier: 12,
    label: 'Antik Şövalye',
    category: 'Orta • Savaşçı',
    targetElo: 1700,
    maxDepth: 3,
    timeMs: 400,
    noise: 2,
    blunderChance: 0.0,
    depth3p: 3,
    time3p: 490,
  ),

  // ================= 13 - 18: ZOR (Büyücü & Üstat) =================
  lvl13(
    tier: 13,
    label: 'Rün Büyücüsü',
    category: 'Zor • Büyücü',
    targetElo: 1800,
    maxDepth: 4,
    timeMs: 460,
    noise: 0,
    blunderChance: 0.0,
    depth3p: 3,
    time3p: 560,
  ),
  lvl14(
    tier: 14,
    label: 'Gölge Büyücüsü',
    category: 'Zor • Büyücü',
    targetElo: 1900,
    maxDepth: 4,
    timeMs: 530,
    noise: 0,
    blunderChance: 0.0,
    depth3p: 3,
    time3p: 640,
  ),
  lvl15(
    tier: 15,
    label: 'Fırtına Büyücüsü',
    category: 'Zor • Büyücü',
    targetElo: 2000,
    maxDepth: 4,
    timeMs: 610,
    noise: 0,
    blunderChance: 0.0,
    depth3p: 3,
    time3p: 720,
  ),
  lvl16(
    tier: 16,
    label: 'Yüksek Büyücü',
    category: 'Zor • Büyücü',
    targetElo: 2100,
    maxDepth: 4,
    timeMs: 700,
    noise: 0,
    blunderChance: 0.0,
    depth3p: 4,
    time3p: 820,
  ),
  lvl17(
    tier: 17,
    label: 'Amfi Mareşali',
    category: 'Zor • Büyücü',
    targetElo: 2200,
    maxDepth: 5,
    timeMs: 800,
    noise: 0,
    blunderChance: 0.0,
    depth3p: 4,
    time3p: 930,
  ),
  lvl18(
    tier: 18,
    label: 'Buz Ejderi Efendisi',
    category: 'Zor • Büyücü',
    targetElo: 2300,
    maxDepth: 5,
    timeMs: 920,
    noise: 0,
    blunderChance: 0.0,
    depth3p: 4,
    time3p: 1050,
  ),

  // ================= 19 - 24: HARBİ ZOR (Başbüyücü & Efsanevi Üstat) =================
  lvl19(
    tier: 19,
    label: 'Kan Kontu Mareşali',
    category: 'Efsanevi • Başbüyücü',
    targetElo: 2400,
    maxDepth: 5,
    timeMs: 1060,
    noise: 0,
    blunderChance: 0.0,
    depth3p: 4,
    time3p: 1200,
  ),
  lvl20(
    tier: 20,
    label: 'Kuzey Hükümdarı',
    category: 'Efsanevi • Başbüyücü',
    targetElo: 2500,
    maxDepth: 5,
    timeMs: 1220,
    noise: 0,
    blunderChance: 0.0,
    depth3p: 4,
    time3p: 1400,
  ),
  lvl21(
    tier: 21,
    label: 'Obsidyen Başkomutan',
    category: 'Efsanevi • Başbüyücü',
    targetElo: 2600,
    maxDepth: 6,
    timeMs: 1420,
    noise: 0,
    blunderChance: 0.0,
    depth3p: 5,
    time3p: 1650,
  ),
  lvl22(
    tier: 22,
    label: 'Titanyum Başbüyücü',
    category: 'Efsanevi • Başbüyücü',
    targetElo: 2700,
    maxDepth: 6,
    timeMs: 1660,
    noise: 0,
    blunderChance: 0.0,
    depth3p: 5,
    time3p: 1950,
  ),
  lvl23(
    tier: 23,
    label: 'Zaman Bükücü Üstat',
    category: 'Efsanevi • Başbüyücü',
    targetElo: 2800,
    maxDepth: 6,
    timeMs: 1950,
    noise: 0,
    blunderChance: 0.0,
    depth3p: 5,
    time3p: 2300,
  ),
  lvl24(
    tier: 24,
    label: 'Antik Büyük Üstat',
    category: 'Efsanevi • Başbüyücü',
    targetElo: 2900,
    maxDepth: 7,
    timeMs: 2300,
    noise: 0,
    blunderChance: 0.0,
    depth3p: 5,
    time3p: 2700,
  );

  const AiLevel({
    required this.tier,
    required this.label,
    required this.category,
    required this.targetElo,
    required this.maxDepth,
    required this.timeMs,
    required this.noise,
    required this.blunderChance,
    required this.depth3p,
    required this.time3p,
  });

  final int tier;
  final String label;
  final String category;
  final int targetElo;
  final int maxDepth;
  final int timeMs;
  final int noise;
  final double blunderChance;
  final int depth3p;
  final int time3p;

  /// Geriye dönük uyumluluk takma adları:
  static const AiLevel apprentice = AiLevel.lvl4;
  static const AiLevel wizard = AiLevel.lvl12;
  static const AiLevel archmage = AiLevel.lvl20;

  static AiLevel fromKey(String? name) => switch (name) {
        'apprentice' => AiLevel.lvl4,
        'wizard' => AiLevel.lvl12,
        'archmage' => AiLevel.lvl20,
        _ => AiLevel.values.firstWhere(
            (l) => l.name == name,
            orElse: () => AiLevel.lvl12,
          ),
      };
}

/// Arka planda (ayrı isolate) düşünür; 3D sahne kesinlikle donmaz.
Future<int?> aiThink(Position position, AiLevel level) {
  final payload = <int>[
    ...position.serialize(),
    level.maxDepth,
    level.timeMs,
    level.noise,
    (level.blunderChance * 1000).toInt(),
    DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
  ];
  return compute(_aiEntry, payload);
}

int? _aiEntry(List<int> payload) {
  final n = Position.cellsTotal + 4;
  final pos = Position.deserialize(payload.sublist(0, n));
  final engine = HexChessAi(
    maxDepth: payload[n],
    timeMs: payload[n + 1],
    noise: payload[n + 2],
    blunderChance: payload[n + 3] / 1000.0,
    seed: payload[n + 4],
  );
  return engine.bestMove(pos);
}

class HexChessAi {
  HexChessAi({
    required this.maxDepth,
    required this.timeMs,
    this.noise = 0,
    this.blunderChance = 0.0,
    int seed = 7,
  }) : _rng = math.Random(seed);

  final int maxDepth;
  final int timeMs;
  final int noise;
  final double blunderChance;
  final math.Random _rng;

  static const int mate = 100000;
  static const List<int> value = [0, 100, 305, 340, 510, 950, 0];

  final Stopwatch _clock = Stopwatch();
  bool _abort = false;
  int _nodes = 0;
  final Int32List _history = Int32List(Position.cellsTotal * Position.cellsTotal);
  final List<List<int>> _killers = List.generate(64, (_) => [0, 0]);
  final List<List<int>> _movePool = List.generate(80, (_) => <int>[]);
  final List<List<int>> _scorePool = List.generate(80, (_) => <int>[]);
  final Map<int, int> _rootNoise = {};

  int get nodes => _nodes;

  static final Int16List _central = _buildCentral();
  static final Int16List _whiteAdvance = _buildAdvance(1);
  static final Int16List _blackAdvance = _buildAdvance(-1);

  static Int16List _buildCentral() {
    final t = Int16List(Position.cellsTotal);
    for (final i in Position.boardCells) {
      final c = Position.cellOf(i);
      final d = math.max(c.q.abs(), math.max(c.r.abs(), (c.q + c.r).abs()));
      t[i] = 5 - d;
    }
    return t;
  }

  static Int16List _buildAdvance(int side) {
    final t = Int16List(Position.cellsTotal);
    for (final i in Position.boardCells) {
      var steps = 0;
      var c = Position.cellOf(i);
      while (true) {
        final next = HexCell(c.q, c.r + side);
        if (!HexBoard.contains(next)) break;
        c = next;
        steps++;
      }
      final progress = 10 - steps;
      t[i] = progress * 6 + (steps <= 2 ? (3 - steps) * 26 : 0);
    }
    return t;
  }

  int? bestMove(Position pos) {
    final root = pos.legalMoves();
    if (root.isEmpty) return null;
    if (root.length == 1) return root.first;

    // Harbi Kolay kademeler için acemi gafı / hata olasılığı:
    if (blunderChance > 0.0 && _rng.nextDouble() < blunderChance) {
      // Saldırıya açık olmayan ya da rastgele bir hamle seç
      return root[_rng.nextInt(root.length)];
    }

    for (final m in root) {
      _rootNoise[m] = noise > 0 ? _rng.nextInt(noise + 1) : 0;
    }
    _clock
      ..reset()
      ..start();
    _abort = false;
    var best = root[_rng.nextInt(root.length)];
    for (var depth = 1; depth <= maxDepth; depth++) {
      final (move, score) = _searchRoot(pos, root, depth, best);
      if (_abort) break;
      best = move;
      if (score.abs() > mate - 200) break;
      if (_clock.elapsedMilliseconds > timeMs * 0.48) break;
    }
    return best;
  }

  (int, int) _searchRoot(Position pos, List<int> moves, int depth, int pvMove) {
    moves.sort((a, b) {
      if (a == pvMove) return -1;
      if (b == pvMove) return 1;
      return _orderScore(pos, b, 0) - _orderScore(pos, a, 0);
    });
    var alpha = -mate - 1;
    const beta = mate + 1;
    var bestMove = moves.first;
    for (final m in moves) {
      pos.makeMove(m);
      final score = -_search(pos, depth - 1, -beta, -alpha, 1) + (_rootNoise[m] ?? 0);
      pos.unmakeMove();
      if (_abort) break;
      if (score > alpha) {
        alpha = score;
        bestMove = m;
      }
    }
    return (bestMove, alpha);
  }

  int _search(Position pos, int depth, int alpha, int beta, int ply) {
    if ((++_nodes & 511) == 0 && _clock.elapsedMilliseconds > timeMs) {
      _abort = true;
    }
    if (_abort || pos.halfmove >= 100) return 0;

    final me = pos.side;
    final inCheck = pos.attacked(pos.kingOf(me), -me);
    if (inCheck && ply < 24) depth++;
    if (depth <= 0 || ply >= 78) return _quiesce(pos, alpha, beta, ply);

    final moves = _movePool[ply]..clear();
    pos.pseudoMoves(moves);
    final scores = _scorePool[ply]..clear();
    for (var i = 0; i < moves.length; i++) {
      scores.add(_orderScore(pos, moves[i], ply));
    }

    var legal = 0;
    var best = -mate - 1;
    for (var i = 0; i < moves.length; i++) {
      var bi = i;
      for (var j = i + 1; j < moves.length; j++) {
        if (scores[j] > scores[bi]) bi = j;
      }
      if (bi != i) {
        final tm = moves[i];
        moves[i] = moves[bi];
        moves[bi] = tm;
        final ts = scores[i];
        scores[i] = scores[bi];
        scores[bi] = ts;
      }
      final m = moves[i];
      final captured = pos.makeMove(m);
      if (pos.attacked(pos.kingOf(me), -me)) {
        pos.unmakeMove();
        continue;
      }
      legal++;
      final score = -_search(pos, depth - 1, -beta, -alpha, ply + 1);
      pos.unmakeMove();
      if (_abort) return 0;
      if (score > best) best = score;
      if (score > alpha) {
        alpha = score;
        if (alpha >= beta) {
          if (captured == 0 && ply < 64) {
            final k = _killers[ply];
            if (k[0] != m) {
              k[1] = k[0];
              k[0] = m;
            }
            _history[Mv.from(m) * Position.cellsTotal + Mv.to(m)] += depth * depth;
          }
          break;
        }
      }
    }
    if (legal == 0) {
      return inCheck ? -mate + ply : -250;
    }
    return best;
  }

  int _quiesce(Position pos, int alpha, int beta, int ply) {
    if ((++_nodes & 511) == 0 && _clock.elapsedMilliseconds > timeMs) {
      _abort = true;
    }
    if (_abort) return 0;
    final stand = evaluate(pos);
    if (stand >= beta) return stand;
    if (stand > alpha) alpha = stand;
    if (ply >= 76) return stand;

    final moves = _movePool[ply]..clear();
    pos.pseudoMoves(moves, capturesOnly: true);
    final scores = _scorePool[ply]..clear();
    for (var i = 0; i < moves.length; i++) {
      scores.add(_orderScore(pos, moves[i], 63));
    }
    final me = pos.side;
    for (var i = 0; i < moves.length; i++) {
      var bi = i;
      for (var j = i + 1; j < moves.length; j++) {
        if (scores[j] > scores[bi]) bi = j;
      }
      if (bi != i) {
        final tm = moves[i];
        moves[i] = moves[bi];
        moves[bi] = tm;
        final ts = scores[i];
        scores[i] = scores[bi];
        scores[bi] = ts;
      }
      final m = moves[i];
      pos.makeMove(m);
      if (pos.attacked(pos.kingOf(me), -me)) {
        pos.unmakeMove();
        continue;
      }
      final score = -_quiesce(pos, -beta, -alpha, ply + 1);
      pos.unmakeMove();
      if (_abort) return 0;
      if (score >= beta) return score;
      if (score > alpha) alpha = score;
    }
    return alpha;
  }

  int _orderScore(Position pos, int m, int ply) {
    final to = Mv.to(m), from = Mv.from(m);
    final victim = Mv.isEp(m) ? 1 : pos.sq[to].abs();
    var s = 0;
    if (victim != 0) {
      s = 100000 + value[victim] * 10 - value[pos.sq[from].abs()] ~/ 10;
    }
    if (Mv.isPromo(m)) s += 90000;
    if (victim == 0 && ply < 64) {
      final k = _killers[ply];
      if (k[0] == m) {
        s += 80000;
      } else if (k[1] == m) {
        s += 70000;
      }
      s += _history[from * Position.cellsTotal + to].clamp(0, 60000);
    }
    return s;
  }

  int evaluate(Position pos) {
    var score = 0;
    var queens = 0;
    var heavy = 0;
    var wDragons = 0, bDragons = 0;
    for (final i in Position.boardCells) {
      final p = pos.sq[i];
      if (p == 0) continue;
      final a = p.abs();
      if (a == 5) queens++;
      if (a >= 3 && a <= 5) heavy++;
      if (p == 3) wDragons++;
      if (p == -3) bDragons++;
    }
    // Gliński'de üç farklı renkli hücreyi kontrol eden Ejderha üçlüsü/çifti avantajı
    if (wDragons >= 3) {
      score += 55;
    } else if (wDragons == 2) {
      score += 22;
    }
    if (bDragons >= 3) {
      score -= 55;
    } else if (bDragons == 2) {
      score -= 22;
    }

    final endgame = queens == 0 || heavy <= 3;
    for (final i in Position.boardCells) {
      final p = pos.sq[i];
      if (p == 0) continue;
      final a = p.abs();
      final c = _central[i];
      var v = value[a];
      switch (a) {
        case 1:
          v += p > 0 ? _whiteAdvance[i] : _blackAdvance[i];
          v += c * 2;
        case 2:
          v += c * 9 - 12;
        case 3:
          v += c * 6;
        case 4:
          v += c * 3;
        case 5:
          v += c * 4;
        case 6:
          v += endgame ? c * 12 : -c * 10;
      }
      score += p > 0 ? v : -v;
    }
    return score * pos.side;
  }
}
