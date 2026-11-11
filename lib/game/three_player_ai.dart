import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'ai.dart';
import 'chess_game.dart';
import 'hex_board.dart';
import 'three_player_game.dart';

/// Büyük tahtada her seviyenin Klasik'teki arama derinliğine ulaşması için düşünme
/// süresi çarpanı. Ölçüm (her boyutta açılış ve çarpışma evresinden 40 konum):
/// ordular uzakta olduğu için büyük tahtalarda taş alma zincirleri azdır ve aynı
/// derinlik Klasik'ten hızlı ya da eşit sürede biter; yalnızca Dev'in en ağır %10'luk
/// konumları ~1,2 kat sürer. Süre üst sınırdır: derinlik erken biterse YZ hemen oynar.
double thinkTimeScale3P(BoardSize size) => switch (size) {
      BoardSize.classic => 1.0,
      BoardSize.wide => 1.0,
      BoardSize.large => 1.0,
      BoardSize.giant => 1.2,
    };

/// 3 kişilik altıgen amfi satrancı için ayrı arka plan isolate yapay zekâsı.
/// [repetitionHashes]: oyunda zaten iki kez görülmüş konumların özetleri; bunlara
/// giden hamle üç kez tekrar beraberliği demektir.
Future<int?> aiThinkThreePlayer(
  ThreePlayerPosition position,
  AiLevel level, {
  List<int> repetitionHashes = const [],
}) {
  final payload = <int>[
    ...position.serialize(),
    level.depth3p,
    (level.time3p * thinkTimeScale3P(position.size)).round(),
    level.noise,
    (level.blunderChance * 1000).toInt(),
    DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
    repetitionHashes.length,
    ...repetitionHashes,
  ];
  return compute(_aiThreeEntry, payload);
}

int? _aiThreeEntry(List<int> payload) {
  final n = ThreePlayerPosition.serializedLength(BoardSize.values[payload[0]]);
  final pos = ThreePlayerPosition.deserialize(payload.sublist(0, n));
  final repCount = payload[n + 5];
  final engine = ThreePlayerHexAi(
    maxDepth: payload[n],
    timeMs: payload[n + 1],
    noise: payload[n + 2],
    blunderChance: payload[n + 3] / 1000.0,
    seed: payload[n + 4],
    repetitionHashes: payload.sublist(n + 6, n + 6 + repCount).toSet(),
  );
  return engine.bestMove(pos);
}

/// Bir tahta boyutu için ön-hesaplı konum tabloları (taş değeri + yerleşim bonusu).
/// Merkez ve piyon ilerleme bonusları Klasik ölçeğe normalize edilir: Klasik'te
/// eski değerlerle birebir aynıdır, büyük tahtada toplam bonus aralığı korunur.
class _EvalTables {
  _EvalTables(Hex3Geometry g) : n = g.cellsTotal {
    pst = Int16List(3 * 7 * n);
    final rad = g.radius;
    final norm = HexBoard.radius / rad;
    for (final i in g.boardCells) {
      final c5 = (rad - g.ring(i)) * norm; // 0 (kenar) .. 5 (merkez)
      for (var t = 0; t < 3; t++) {
        final fwd = g.pawnFwd[t];
        var steps = 0;
        var cur = i;
        while (g.contains(g.cellOf(cur + fwd))) {
          cur += fwd;
          steps++;
        }
        final progress = (2 * rad - steps) * norm;
        final advance =
            (progress * 6).round() + (steps <= 2 ? (3 - steps) * 28 : 0);
        void put(int kind, int v) => pst[(t * 7 + kind) * n + i] = v;
        put(1, ThreePlayerHexAi.value[1] + advance + (c5 * 3).round());
        put(2, ThreePlayerHexAi.value[2] + (c5 * 9).round() - 10);
        put(3, ThreePlayerHexAi.value[3] + (c5 * 6).round());
        put(4, ThreePlayerHexAi.value[4] + (c5 * 4).round());
        put(5, ThreePlayerHexAi.value[5] + (c5 * 5).round());
        // 3 kişilik kaosta şah yüksek amfi tahtında kalmalı, erken merkeze inmemeli!
        put(6, -(c5 * 14).round());
      }
    }
  }

  static final List<_EvalTables?> _cache = List.filled(BoardSize.values.length, null);
  static _EvalTables of(Hex3Geometry g) =>
      _cache[g.size.index] ??= _EvalTables(g)._withTropism(g);

  final int n;
  late final Int16List pst;

  /// Şaha yaklaşma (tropizm) için sıkıştırılmış hücre indeksi ve hücreler arası mesafe tablosu.
  late final Int16List compact;
  late final Uint8List dist;
  late final int cells;

  /// Taş türüne göre şaha yaklaşma ağırlığı × (R - 5): Klasik'te 0 (davranış birebir
  /// aynı kalır), Dev'de en yüksek. Toplam [tropismDiv]'e bölünür.
  late final Int32List tropism;
  static const int tropismDiv = 3;
  late final int reach;

  _EvalTables _withTropism(Hex3Geometry g) {
    cells = g.boardCells.length;
    compact = Int16List(n)..fillRange(0, n, -1);
    for (var k = 0; k < cells; k++) {
      compact[g.boardCells[k]] = k;
    }
    dist = Uint8List(cells * cells);
    for (var a = 0; a < cells; a++) {
      for (var b = 0; b < cells; b++) {
        dist[a * cells + b] = g.distance(g.boardCells[a], g.boardCells[b]);
      }
    }
    final grow = g.radius - HexBoard.radius;
    //                      -, piyon, at, fil, kale, vezir, şah
    tropism = Int32List.fromList([0, 0, 3 * grow, 2 * grow, 2 * grow, 4 * grow, 0]);
    reach = 2 * g.radius;
    return this;
  }
}

/// 3 cepheli altıgen satranç için koalisyon-farkındalıklı Paranoid Alfa-Beta + Lider Dengeleme Yapay Zekâsı.
/// - İki rakibin de ardışık hamlelerini (`A -> B -> C -> A`) simüle ederek üçüncü ordunun tuzaklarını görür.
/// - Eşit taş takaslarının üçüncü oyuncuya yaradığını bilir ve yalnızca kârlı ya da lideri durduran hamleleri seçer.
/// - Amfi yüksekliği ve merkez hakimiyeti avantajını değerlendirmeye katar.
/// - Oyun sonunda üstün taraf rakip şahı kenara sıkıştırır, kendi şahını yaklaştırır
///   (geniş tahtada da maçı bitirir) ve kazanırken üç kez tekrar beraberliğine düşmez.
class ThreePlayerHexAi {
  ThreePlayerHexAi({
    required this.maxDepth,
    required this.timeMs,
    this.noise = 0,
    this.blunderChance = 0.0,
    int seed = 11,
    this.repetitionHashes = const {},
  }) : _rng = math.Random(seed);

  final int maxDepth;
  final int timeMs;
  final int noise;
  final double blunderChance;
  final Set<int> repetitionHashes;
  final math.Random _rng;

  static const int winScore = 120000;
  static const List<int> value = [0, 100, 310, 345, 515, 960, 0];

  /// Oyun sonu sıkıştırma: zayıf tarafın taş gücü bunu aşmıyorsa ve fark
  /// en az [_mopUpLead] ise devreye girer.
  static const int _mopUpWeakMax = 1300;
  static const int _mopUpLead = 250;

  /// Yalnızca testler için: yeniden düzenlemenin eski aramayla birebir aynı
  /// olduğunu doğrularken oyun sonu sıkıştırması kapatılabilir.
  @visibleForTesting
  static bool endgameSqueeze = true;

  final Stopwatch _clock = Stopwatch();
  bool _abort = false;
  int _nodes = 0;
  Int32List _history = Int32List(0);
  int _historySpan = 0;
  final List<List<int>> _killers = List.generate(48, (_) => [0, 0]);
  final List<List<int>> _movePool = List.generate(64, (_) => <int>[]);
  final List<List<int>> _scorePool = List.generate(64, (_) => <int>[]);
  final Map<int, int> _rootNoise = {};

  int get nodes => _nodes;

  int? bestMove(ThreePlayerPosition pos) {
    final rootTeam = pos.side;
    final root = pos.legalMovesFor(rootTeam);
    if (root.isEmpty) return null;
    if (root.length == 1) return root.first;

    // Harbi Kolay kademeler için acemi gafı (blunder) olasılığı:
    if (blunderChance > 0.0 && _rng.nextDouble() < blunderChance) {
      return root[_rng.nextInt(root.length)];
    }

    final cells = pos.geo.cellsTotal;
    if (_historySpan != cells) {
      _history = Int32List(cells * cells);
      _historySpan = cells;
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
      final (move, score) = _searchRoot(pos, rootTeam, root, depth, best);
      if (_abort) break;
      best = move;
      if (score.abs() > winScore - 500) break;
      if (_clock.elapsedMilliseconds > timeMs * 0.50) break;
    }
    return best;
  }

  (int, int) _searchRoot(
    ThreePlayerPosition pos,
    int rootTeam,
    List<int> moves,
    int depth,
    int pvMove,
  ) {
    moves.sort((a, b) {
      if (a == pvMove) return -1;
      if (b == pvMove) return 1;
      return _orderScore(pos, b, 0) - _orderScore(pos, a, 0);
    });
    var alpha = -winScore - 1;
    const beta = winScore + 1;
    var bestMove = moves.first;

    for (final m in moves) {
      pos.makeMove(m);
      // Üç kez tekrar: bu hamle oyunu berabere bitirir (0 = eşitlik).
      final repeats = repetitionHashes.isNotEmpty &&
          repetitionHashes.contains(pos.repetitionHash);
      final score = (repeats
              ? 0
              : _search(pos, rootTeam, depth - 1, alpha, beta, 1)) +
          (_rootNoise[m] ?? 0);
      pos.unmakeMove();
      if (_abort) break;
      if (score > alpha) {
        alpha = score;
        bestMove = m;
      }
    }
    return (bestMove, alpha);
  }

  int _search(
    ThreePlayerPosition pos,
    int rootTeam,
    int depth,
    int alpha,
    int beta,
    int ply,
  ) {
    if ((++_nodes & 255) == 0 && _clock.elapsedMilliseconds > timeMs) {
      _abort = true;
    }
    if (_abort) return 0;

    if (!pos.isAlive(rootTeam)) return -winScore + ply;
    final survivor = pos.soleSurvivor;
    if (survivor != null) {
      return survivor == rootTeam ? winScore - ply : -winScore + ply;
    }
    if (pos.halfmove >= pos.geo.halfmoveDrawLimit) return 0;

    final actor = pos.side;
    final inChk = pos.inCheck(actor);
    if (inChk && ply < 12) depth++;
    if (depth <= 0 || ply >= 52) {
      return _quiesce(pos, rootTeam, alpha, beta, ply);
    }

    final moves = _movePool[ply]..clear();
    pos.pseudoMovesFor(actor, moves);
    final scores = _scorePool[ply]..clear();
    for (var i = 0; i < moves.length; i++) {
      scores.add(_orderScore(pos, moves[i], ply));
    }

    final isMax = actor == rootTeam;
    var legal = 0;
    var best = isMax ? (-winScore - 1) : (winScore + 1);

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
      if (!_fastLegalCheck(pos, m, actor)) continue;
      legal++;

      final captured = pos.makeMove(m);
      final score = _search(pos, rootTeam, depth - 1, alpha, beta, ply + 1);
      pos.unmakeMove();
      if (_abort) return 0;

      if (isMax) {
        if (score > best) best = score;
        if (score > alpha) {
          alpha = score;
          if (alpha >= beta) {
            _recordCutoff(m, captured, ply, depth);
            break;
          }
        }
      } else {
        if (score < best) best = score;
        if (score < beta) {
          beta = score;
          if (beta <= alpha) {
            _recordCutoff(m, captured, ply, depth);
            break;
          }
        }
      }
    }

    if (legal == 0) {
      return actor == rootTeam ? (-winScore + ply) : evaluateFor(pos, rootTeam);
    }
    return best;
  }

  int _quiesce(
    ThreePlayerPosition pos,
    int rootTeam,
    int alpha,
    int beta,
    int ply,
  ) {
    if ((++_nodes & 255) == 0 && _clock.elapsedMilliseconds > timeMs) {
      _abort = true;
    }
    if (_abort) return 0;
    if (!pos.isAlive(rootTeam)) return -winScore + ply;
    final survivor = pos.soleSurvivor;
    if (survivor != null) {
      return survivor == rootTeam ? winScore - ply : -winScore + ply;
    }

    final stand = evaluateFor(pos, rootTeam);
    final actor = pos.side;
    final isMax = actor == rootTeam;

    if (isMax) {
      if (stand >= beta) return stand;
      if (stand > alpha) alpha = stand;
    } else {
      if (stand <= alpha) return stand;
      if (stand < beta) beta = stand;
    }
    if (ply >= 56) return stand;

    final moves = _movePool[ply]..clear();
    pos.pseudoMovesFor(actor, moves, capturesOnly: true);
    final scores = _scorePool[ply]..clear();
    for (var i = 0; i < moves.length; i++) {
      scores.add(_orderScore(pos, moves[i], 47));
    }

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
      if (!_fastLegalCheck(pos, m, actor)) continue;
      pos.makeMove(m);
      final score = _quiesce(pos, rootTeam, alpha, beta, ply + 1);
      pos.unmakeMove();
      if (_abort) return 0;

      if (isMax) {
        if (score >= beta) return score;
        if (score > alpha) alpha = score;
      } else {
        if (score <= alpha) return score;
        if (score < beta) beta = score;
      }
    }
    return isMax ? alpha : beta;
  }

  bool _fastLegalCheck(ThreePlayerPosition pos, int m, int actor) {
    // `legalMovesFor` ile birebir aynı hızlı şah güvenliği kontrolü
    final from = Mv.from(m), to = Mv.to(m);
    final piece = pos.sq[from];
    var capSq = to;
    var captured = pos.sq[to];
    if (Mv.isEp(m) && pos.epPawnSq >= 0) {
      capSq = pos.epPawnSq;
      captured = pos.sq[capSq];
      pos.sq[capSq] = 0;
    }
    final prevTo = pos.sq[to];
    pos.sq[to] = Mv.isPromo(m)
        ? ThreePlayerPosition.encodePiece(actor, Mv.promoCode(m))
        : piece;
    pos.sq[from] = 0;
    final prevKing = pos.kings[actor];
    if (ThreePlayerPosition.kindCodeOfByte(piece) == 6) pos.kings[actor] = to;

    final prevAlive = pos.aliveMask;
    if (captured != 0 &&
        captured != Position.off &&
        ThreePlayerPosition.kindCodeOfByte(captured) == 6) {
      pos.aliveMask &= ~(1 << ThreePlayerPosition.teamOfByte(captured));
    }

    final kingSq = pos.kings[actor];
    final ok = kingSq >= 0 && !pos.attackedByAnyEnemy(kingSq, actor);

    pos.aliveMask = prevAlive;
    pos.kings[actor] = prevKing;
    pos.sq[from] = piece;
    pos.sq[to] = prevTo;
    if (capSq != to) pos.sq[capSq] = captured;
    return ok;
  }

  void _recordCutoff(int m, int captured, int ply, int depth) {
    if (captured == 0 && ply < 48) {
      final k = _killers[ply];
      if (k[0] != m) {
        k[1] = k[0];
        k[0] = m;
      }
      _history[Mv.from(m) * _historySpan + Mv.to(m)] += depth * depth;
    }
  }

  int _orderScore(ThreePlayerPosition pos, int m, int ply) {
    final to = Mv.to(m), from = Mv.from(m);
    final victimByte = pos.sq[to];
    final victimKind = Mv.isEp(m)
        ? 1
        : (victimByte != 0 && victimByte != Position.off
            ? ThreePlayerPosition.kindCodeOfByte(victimByte)
            : 0);
    var s = 0;
    if (victimKind != 0) {
      final attackerKind = ThreePlayerPosition.kindCodeOfByte(pos.sq[from]);
      s = 100000 +
          (victimKind == 6 ? 50000 : value[victimKind] * 10) -
          value[attackerKind] ~/ 10;
    }
    if (Mv.isPromo(m)) s += 90000;
    if (victimKind == 0 && ply < 48) {
      final k = _killers[ply];
      if (k[0] == m) {
        s += 80000;
      } else if (k[1] == m) {
        s += 70000;
      }
      s += _history[from * _historySpan + to].clamp(0, 60000);
    }
    return s;
  }

  /// Kök oyuncu `rootTeam` açısından 3 cepheli tahta değerlendirmesi:
  /// - Kendi ordusunun gücü - 0.68 * en güçlü rakip - 0.36 * ikinci rakip
  ///   (Böylece iki oyuncunun körü körüne taş takas edip 3. oyuncuyu şampiyon yapmasını engeller!)
  /// - Son iki ordu kaldığında üstün taraf rakip şahı kenara sıkıştırır.
  int evaluateFor(ThreePlayerPosition pos, int rootTeam) {
    if (!pos.isAlive(rootTeam)) return -winScore;
    final g = pos.geo;
    final tables = _EvalTables.of(g);
    final pst = tables.pst;
    final n = tables.n;
    final strengths = [0, 0, 0];
    final material = [0, 0, 0];
    final kingPst = [0, 0, 0];
    final dragons = [0, 0, 0];

    // Büyük tahtada şaha yaklaşma: her ordunun iki rakip şahının sıkıştırılmış indeksi.
    final trop = tables.tropism;
    final useTropism = trop[5] != 0;
    final tropSum = [0, 0, 0];
    final foeKingA = [-1, -1, -1], foeKingB = [-1, -1, -1];
    if (useTropism) {
      for (var t = 0; t < 3; t++) {
        for (var e = 0; e < 3; e++) {
          if (e == t || !pos.isAlive(e) || pos.kings[e] < 0) continue;
          final c = tables.compact[pos.kings[e]];
          if (foeKingA[t] < 0) {
            foeKingA[t] = c;
          } else {
            foeKingB[t] = c;
          }
        }
      }
    }
    final cells = tables.cells;
    final dist = tables.dist;
    final reach = tables.reach;

    for (final i in g.boardCells) {
      final b = pos.sq[i];
      if (b == 0 || b == Position.off) continue;
      final t = ThreePlayerPosition.teamOfByte(b);
      if (!pos.isAlive(t)) continue;
      final k = ThreePlayerPosition.kindCodeOfByte(b);
      final v = pst[(t * 7 + k) * n + i];
      strengths[t] += v;
      if (k == 6) {
        kingPst[t] = v;
      } else {
        material[t] += value[k];
        if (k == 3) dragons[t]++;
        if (useTropism && trop[k] != 0 && foeKingA[t] >= 0) {
          final row = tables.compact[i] * cells;
          var d = dist[row + foeKingA[t]];
          if (foeKingB[t] >= 0) {
            final d2 = dist[row + foeKingB[t]];
            if (d2 < d) d = d2;
          }
          tropSum[t] += trop[k] * (reach - d);
        }
      }
    }
    if (useTropism) {
      for (var t = 0; t < 3; t++) {
        strengths[t] += tropSum[t] ~/ _EvalTables.tropismDiv;
      }
    }

    for (var t = 0; t < 3; t++) {
      if (!pos.isAlive(t)) {
        strengths[t] = -15000;
        continue;
      }
      if (dragons[t] >= 3) {
        strengths[t] += 55;
      } else if (dragons[t] == 2) {
        strengths[t] += 22;
      }
      if (pos.inCheck(t)) {
        strengths[t] -= 65;
      }
    }

    final myStrength = strengths[rootTeam];
    var enemyA = -1, enemyB = -1;
    for (var t = 0; t < 3; t++) {
      if (t != rootTeam && pos.isAlive(t)) {
        if (enemyA < 0) {
          enemyA = t;
        } else {
          enemyB = t;
        }
      }
    }
    if (enemyA < 0) return winScore;
    if (enemyB < 0) {
      // Yalnızca 1 rakip kaldıysa doğrudan düello + elenen rakipten gelen üstünlük bonusu!
      var score = myStrength - strengths[enemyA] + 850;
      final lead = material[rootTeam] - material[enemyA];
      final weak = lead >= 0 ? enemyA : rootTeam;
      if (endgameSqueeze &&
          lead.abs() >= _mopUpLead &&
          material[weak] <= _mopUpWeakMax) {
        final strong = weak == rootTeam ? enemyA : rootTeam;
        final wk = pos.kings[weak], sk = pos.kings[strong];
        if (wk >= 0 && sk >= 0) {
          // Oyun sonunda "taht" kuralı geçersiz: iki şahın yerleşim cezası kaldırılır.
          score += (kingPst[enemyA] - kingPst[rootTeam]);
          final squeeze = 10 * g.ring(wk) + 4 * (2 * g.radius - g.distance(sk, wk));
          score += strong == rootTeam ? squeeze : -squeeze;
        }
      }
      return score;
    }
    final leader = math.max(strengths[enemyA], strengths[enemyB]);
    final trailer = math.min(strengths[enemyA], strengths[enemyB]);
    return myStrength - ((leader * 68 + trailer * 36) ~/ 100);
  }
}
