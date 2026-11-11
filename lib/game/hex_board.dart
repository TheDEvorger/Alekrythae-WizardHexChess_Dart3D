import 'dart:math' as math;
import 'dart:typed_data';

/// Masa düzeni: klasik 2 kişilik düello veya 3 kişilik altıgen amfi masası.
enum BoardVariant {
  twoPlayer('2 Kişilik Düello'),
  threePlayer('3 Kişilik Masa');

  const BoardVariant(this.label);
  final String label;
}

/// 3 kişilik masanın tahta boyutu. Ordular her boyutta kendi köşesinden aynı
/// dizilimle başlar; tahta büyüdükçe aradaki meydan genişler ve savaş yavaşlar.
/// 2 kişilik düello her zaman [classic] boyuttadır.
enum BoardSize {
  classic('Klasik', 5),
  wide('Geniş', 6),
  large('Büyük', 7),
  giant('Dev', 8);

  const BoardSize(this.label, this.radius);
  final String label;

  /// Merkezden kenara halka sayısı.
  final int radius;

  /// Tahtadaki altıgen hücre sayısı (91 / 127 / 169 / 217).
  int get cellCount => 3 * radius * (radius + 1) + 1;

  static BoardSize fromName(String? raw) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return BoardSize.classic;
  }
}

/// Eksenel (axial) altıgen koordinat; üçüncü küp koordinatı -q-r olur.
class HexCell {
  const HexCell(this.q, this.r);

  final int q;
  final int r;
  int get s => -q - r;

  HexCell operator +(HexCell other) => HexCell(q + other.q, r + other.r);

  @override
  bool operator ==(Object other) =>
      other is HexCell && q == other.q && r == other.r;

  @override
  int get hashCode => Object.hash(q, r);

  @override
  String toString() => '($q, $r)';
}

/// Bir masa düzeninin (2/3 kişilik + boyut) hücreleri, kare gösterimi ve amfi
/// sütun yükseklikleri. Örnekler önbelleklidir: [BoardShape.of] her çağrıda
/// aynı nesneyi döndürür.
class BoardShape {
  BoardShape._(this.variant, this.size)
      : radius = size.radius,
        _gridSide = size.radius * 2 + 1 {
    cells = List<HexCell>.unmodifiable([
      for (var q = -radius; q <= radius; q++)
        for (var r = -radius; r <= radius; r++)
          if (contains(HexCell(q, r))) HexCell(q, r),
    ]);
    _heights = Float64List(_gridSide * _gridSide);
    for (final c in cells) {
      _heights[_lutIdx(c)] = _computeColumnHeight(c);
    }
  }

  static final Map<(BoardVariant, BoardSize), BoardShape> _cache = {};

  /// 2 kişilik düello için boyut her zaman Klasik'tir.
  static BoardShape of(BoardVariant variant, [BoardSize size = BoardSize.classic]) {
    final s = variant == BoardVariant.twoPlayer ? BoardSize.classic : size;
    return _cache[(variant, s)] ??= BoardShape._(variant, s);
  }

  final BoardVariant variant;
  final BoardSize size;
  final int radius;
  final int _gridSide;
  late final List<HexCell> cells;
  late final Float64List _heights;

  /// Gliński yazımında j harfi yoktur; Dev tahtada 17 dosya (a..r) gerekir.
  static const String _allFiles = 'abcdefghiklmnopqr';
  String get files => _allFiles.substring(0, _gridSide);

  bool contains(HexCell cell) =>
      math.max(cell.q.abs(), math.max(cell.r.abs(), (cell.q + cell.r).abs())) <=
      radius;

  int _rankMin(int q) => math.max(-radius, -radius - q);

  String name(HexCell cell) {
    if (!contains(cell)) throw ArgumentError('Tahta dışında: $cell');
    return '${files[cell.q + radius]}${cell.r - _rankMin(cell.q) + 1}';
  }

  HexCell parse(String notation) {
    final text = notation.trim().toLowerCase();
    if (text.length < 2) throw FormatException('Geçersiz kare: $notation');
    final file = files.indexOf(text[0]);
    final rank = int.tryParse(text.substring(1));
    if (file < 0 || rank == null) {
      throw FormatException('Geçersiz kare: $notation');
    }
    final q = file - radius;
    final cell = HexCell(q, _rankMin(q) + rank - 1);
    if (!contains(cell) || name(cell) != text) {
      throw FormatException('Tahtada böyle bir kare yok: $notation');
    }
    return cell;
  }

  /// Tahtanın merkezden en uzak köşe hücresinin dış kenarına dünya uzaklığı
  /// (oyun alanı ölçeklenmeden önce).
  double get extent => HexBoard.cornerDistance * radius + HexBoard.tileRadius;

  /// Oyun alanının (sütunlar, taşlar, vurgular, efektler) sahnedeki ölçeği.
  /// Büyük tahtalar Klasik arenanın alanına sığdırılır; fırtına, kuleler, sis
  /// ve kamera düzeni her boyutta aynı kalır. Klasik'te tam 1'dir.
  double get playScale => radius == HexBoard.radius
      ? 1.0
      : BoardShape.of(variant).extent / extent;

  int _lutIdx(HexCell c) => (c.q + radius) * _gridSide + (c.r + radius);

  /// O(1) ön-hesaplı amfi sütun yüksekliği (ölçeklenmemiş yerel birimde).
  double columnHeight(HexCell cell) {
    if (!contains(cell)) return 0.20;
    return _heights[_lutIdx(cell)];
  }

  /// Tek bir ordu cephesinin amfi yüksekliği (yerel küp koordinatlarında ordu
  /// köşesi `(0, -R, +R)`). Büyük tahtada ordu köşeye kaydırıldığı için yerel
  /// koordinatlar Klasik'e geri taşınır: ordunun kendi kademeleri birebir aynı
  /// kalır, aradaki genişleyen meydan alçak düz bir savaş alanına iner.
  static double _wingElevation(int lq, int lr, int ls, int shift) {
    lr += shift;
    ls -= shift;
    final diff = ls - lr;
    // Meydan tabanı: hiçbir ordunun kademesine girmeyen orta alan (Klasik'te
    // her hücrede başka bir cephe ≥ 0.18 verdiği için sonuç değişmez).
    if (diff < 0) return 0.18;

    final forward = diff * 0.5; // 0.0 (orta) .. 5.0 (arka uç), Şah/Vezir = 4.5
    final absQ = lq.abs();

    // Şah ve Vezir sütunları zirvede taçlanır
    if (lq == 1 && lr == -5 && ls == 4) return 1.46; // Barbar Kral zirvesi
    if (lq == -1 && lr == -4 && ls == 5) return 1.42; // Vampir Kraliçe zirvesi
    if (lq == 0 && lr == -5 && ls == 5) return 1.33; // Kraliyet arka burcu

    final cappedForward = math.min(forward, 4.4);
    final flankDrop = math.max(0, absQ - 1) * 0.132 +
        (absQ == 0 && forward > 0.2 ? 0.024 : 0.0) +
        absQ * 0.022;

    final h = 0.30 + cappedForward * 0.248 - flankDrop;
    return h.clamp(0.18, 1.36);
  }

  double _computeColumnHeight(HexCell cell) {
    final q = cell.q, r = cell.r, s = cell.s;
    final shift = radius - HexBoard.radius;
    final double base;
    if (variant == BoardVariant.twoPlayer) {
      base = math.max(
        _wingElevation(q, r, s, shift),
        _wingElevation(-q, -r, -s, shift),
      );
    } else {
      base = math.max(
        _wingElevation(q, r, s, shift),
        math.max(
          _wingElevation(r, s, q, shift),
          _wingElevation(s, q, r, shift),
        ),
      );
    }

    // Kral/Kraliçe zirvelerini koruyarak her altıgen sütuna kendine has ince taş kademesi ver
    if (base >= 1.40) return base;
    final micro = (((q * 11 + r * 19) % 7) - 3) * 0.0055;
    return (base + micro).clamp(0.17, 1.37);
  }

  /// Yerel `(x, z)` noktasındaki amfi sütun yüzey yüksekliğini hesaplar;
  /// yürüyen ve dövüşen savaşçıların sütun basamaklarına tam basmasını sağlar.
  double surfaceHeightAtWorld(double x, double z) {
    final fq = x / (1.5 * HexBoard.tileRadius);
    final fr = -z / (HexBoard._sqrt3 * HexBoard.tileRadius) - fq * 0.5;
    final fs = -fq - fr;
    var rq = fq.round();
    var rr = fr.round();
    final rs = fs.round();
    final dq = (rq - fq).abs();
    final dr = (rr - fr).abs();
    final ds = (rs - fs).abs();
    if (dq > dr && dq > ds) {
      rq = -rr - rs;
    } else if (dr > ds) {
      rr = -rq - rs;
    }
    final cell = HexCell(rq, rr);
    if (!contains(cell)) return 0.20;

    final hCenter = columnHeight(cell);
    final (cx, cz) = HexBoard.worldXZ(cell);
    final dist = math.sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz));
    // Sütun üst tablasının iç %72'lik kısmında tam düz sütun tepesi, kenarda komşu sütuna yumuşak geçiş
    const flatRad = HexBoard.tileRadius * 0.64;
    if (dist <= flatRad) return hCenter;

    var bestNeighbor = hCenter;
    var bestDist = double.infinity;
    const dirs = [
      HexCell(1, 0),
      HexCell(1, -1),
      HexCell(0, -1),
      HexCell(-1, 0),
      HexCell(-1, 1),
      HexCell(0, 1),
    ];
    for (final d in dirs) {
      final nb = cell + d;
      if (!contains(nb)) continue;
      final (nx, nz) = HexBoard.worldXZ(nb);
      final nd = (x - nx) * (x - nx) + (z - nz) * (z - nz);
      if (nd < bestDist) {
        bestDist = nd;
        bestNeighbor = columnHeight(nb);
      }
    }
    final blend = ((dist - flatRad) / (HexBoard.tileRadius * 0.44)).clamp(0.0, 0.5);
    return hCenter + (bestNeighbor - hCenter) * blend;
  }
}

/// Klasik 91 hücreli tahtanın (2 kişilik düello ve Klasik 3 kişilik masa)
/// kısayolları. Boyuta bağlı kod [BoardShape] kullanır.
class HexBoard {
  static const int radius = 5;
  static const String files = 'abcdefghikl'; // Gliński yazımında j yok.
  static const double tileRadius = 0.86;
  static const double _sqrt3 = 1.7320508075688772;

  /// Köşe hücre merkezinin tahta merkezine uzaklığı / halka sayısı.
  static const double cornerDistance = _sqrt3 * tileRadius;

  static final BoardShape _classic2P = BoardShape.of(BoardVariant.twoPlayer);

  static bool contains(HexCell cell) =>
      math.max(cell.q.abs(), math.max(cell.r.abs(), (cell.q + cell.r).abs())) <=
      radius;

  /// Sabit, sıfır-tahsisli (zero-allocation) 91 hücre tablosu.
  static List<HexCell> get cells => _classic2P.cells;

  static String name(HexCell cell) => _classic2P.name(cell);

  static HexCell parse(String notation) => _classic2P.parse(notation);

  /// Altıgenleri XZ düzleminde yerleştiriyoruz; Y, 3D amfi sütun yüksekliği ekseni.
  static (double, double) worldXZ(HexCell cell) {
    return (
      1.5 * tileRadius * cell.q,
      -_sqrt3 * tileRadius * (cell.r + cell.q / 2),
    );
  }

  static int colorIndex(HexCell cell) => (cell.q - cell.r) % 3;

  /// O(1) ön-hesaplı amfi sütun yüksekliği tablosu okuması (Klasik tahta).
  static double columnHeight(HexCell cell, BoardVariant variant) =>
      BoardShape.of(variant).columnHeight(cell);

  /// Dünya `(x, z)` noktasındaki amfi sütun yüzey yüksekliği (Klasik tahta).
  static double surfaceHeightAtWorld(
    double x,
    double z,
    BoardVariant variant,
  ) =>
      BoardShape.of(variant).surfaceHeightAtWorld(x, z);
}
