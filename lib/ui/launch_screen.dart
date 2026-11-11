import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/game_database.dart';
import '../game/chess_game.dart';
import '../game/hex_board.dart';

/// Oyun genelinde kullanılan yüksek kaliteli arma/logo bileşeni.
class BrandCrestLogo extends StatelessWidget {
  const BrandCrestLogo({
    super.key,
    required this.size,
    this.glow = true,
  });

  final double size;
  final bool glow;

  static const String assetPath = 'assets/branding/game_logo.png';

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
    );
    if (!glow) return img;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0x4448B4FF),
            blurRadius: size * 0.22,
            spreadRadius: size * 0.01,
          ),
          BoxShadow(
            color: const Color(0x38C81838),
            blurRadius: size * 0.28,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: img,
    );
  }
}

/// Oyunun resmi açılış (splash + başlangıç lobisi) ekranı.
class WizardLaunchScreen extends StatefulWidget {
  const WizardLaunchScreen({
    super.key,
    required this.bootReady,
    required this.bootStatus,
    required this.bootProgress,
    required this.profile,
    required this.activeMatch,
    required this.diagnostics,
    required this.onResumeSavedMatch,
    required this.onStartVariant,
    required this.onOpenArchive,
    required this.onOpenSettings,
    this.initialBoardSize3P = BoardSize.classic,
  });

  final bool bootReady;
  final String bootStatus;
  final double bootProgress;
  final PlayerProfileStats profile;
  final SavedMatchSummary? activeMatch;
  final SqliteDiagnostics? diagnostics;
  final VoidCallback onResumeSavedMatch;
  /// [size] yalnızca 3 kişilik masada anlamlıdır (2 kişilik düello her zaman Klasik).
  final void Function(BoardVariant variant, BoardSize size) onStartVariant;
  final VoidCallback onOpenArchive;
  final VoidCallback onOpenSettings;

  /// 3 kişilik masa için son seçilen tahta boyutu.
  final BoardSize initialBoardSize3P;

  @override
  State<WizardLaunchScreen> createState() => _WizardLaunchScreenState();
}

class _WizardLaunchScreenState extends State<WizardLaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  late BoardSize _size3P = widget.initialBoardSize3P;

  @override
  void didUpdateWidget(covariant WizardLaunchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Kayıtlı tercih açılış ekranı çizildikten sonra yüklenebilir.
    if (oldWidget.initialBoardSize3P != widget.initialBoardSize3P) {
      _size3P = widget.initialBoardSize3P;
    }
  }

  static String _sizeHint(BoardSize s) => switch (s) {
        BoardSize.classic => 'Klasik amfi • 91 hücre • hızlı ve sıkışık savaş',
        BoardSize.wide => 'Geniş meydan • 127 hücre • ordular 6 adım uzakta',
        BoardSize.large => 'Büyük meydan • 169 hücre • ordular 8 adım uzakta',
        BoardSize.giant => 'Dev meydan • 217 hücre • ordular 10 adım uzakta, uzun savaş',
      };

  Widget _sizePicker() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TAHTA BOYUTU (yalnızca 3 kişilik masa)',
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 1.1,
              color: Color(0xFF8FD9BB),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in BoardSize.values)
                ChoiceChip(
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '${s.label} • ${s.cellCount}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          _size3P == s ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  selected: _size3P == s,
                  selectedColor: const Color(0xFF1F5A47),
                  backgroundColor: const Color(0xFF0E1E1A),
                  side: BorderSide(
                    color: _size3P == s
                        ? const Color(0xFF34D399)
                        : const Color(0xFF24443A),
                  ),
                  onSelected: (_) => setState(() => _size3P = s),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _sizeHint(_size3P),
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF98A8C2)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final sh = mq.size.height;
    final sw = mq.size.width;
    final compact = sh < 720 || sw < 390;
    final crestSize = math.min(
      sw * (compact ? 0.60 : 0.68),
      sh * (compact ? 0.34 : 0.41),
    ).clamp(185.0, 390.0);

    final saved = widget.activeMatch;
    final hasResume = widget.bootReady && saved != null && saved.isActive;

    return Material(
      color: const Color(0xFF03050B),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Arka plan: saf obsidyen + ay mavisi ve kızıl kanat parıltısı + hafif rün kıvılcımları
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, _) => CustomPaint(
                painter: _ArcaneBackdropPainter(phase: _pulseCtrl.value),
              ),
            ),
          ),

          // 2. Ana açılış içeriği
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: compact ? 10 : 18,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Üst Sefer Rozeti
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC0A1120),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xAA9E7A38)),
                          boxShadow: const [
                            BoxShadow(color: Color(0x44000000), blurRadius: 10),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_moon_rounded,
                                size: 12.5, color: Color(0xFFFFD166)),
                            SizedBox(width: 6),
                            Text(
                              'ANTİK AMFİ SEFERİ • ÇAĞ I',
                              style: TextStyle(
                                fontSize: 10.5,
                                letterSpacing: 1.2,
                                color: Color(0xFFFFE599),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: compact ? 8 : 14),

                      // Resmi Oyun Arması / Logosu (Nefes alan hafif sinematik hareket)
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (context, child) {
                          final breath =
                              math.sin(_pulseCtrl.value * math.pi * 2);
                          final scale = 1.0 + breath * 0.016;
                          return Transform.scale(
                            scale: scale,
                            child: child,
                          );
                        },
                        child: BrandCrestLogo(size: crestSize),
                      ),

                      SizedBox(height: compact ? 8 : 12),

                      // Oyun Başlığı
                      ShaderMask(
                        shaderCallback: (rect) => const LinearGradient(
                          colors: [
                            Color(0xFFD8E9FF),
                            Color(0xFFFFD98E),
                            Color(0xFFFF6B7A),
                          ],
                        ).createShader(rect),
                        child: Text(
                          'WIZARD HEX CHESS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: compact ? 23 : 27,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.4,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '3B AMFİ SÜTUNLAR • KARANLIK FANTEZİ SATRANÇ',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8EA4C8),
                        ),
                      ),

                      SizedBox(height: compact ? 14 : 18),

                      // Başlangıç Yükleme Çubuğu VEYA Canlı Giriş Menü Düğmeleri
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        child: !widget.bootReady
                            ? _buildLoadingBox()
                            : _buildMenuControls(hasResume, saved, compact),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBox() {
    return Container(
      key: const ValueKey('splash-loading'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xD80B1222),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF243858)),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: widget.bootProgress > 0.05 ? widget.bootProgress : null,
              minHeight: 6,
              backgroundColor: const Color(0xFF162238),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF5CE1FF)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.bootStatus,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFC4D4EC),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuControls(
    bool hasResume,
    SavedMatchSummary? saved,
    bool compact,
  ) {
    final p = widget.profile;
    return Column(
      key: const ValueKey('splash-menu'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Komutan Kariyer & ELO Özeti (SQLite'tan canlı)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xDD0D1629), Color(0xDD1A1022)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2B3B58)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statPill('2P ELO', '${p.elo2P}', const Color(0xFF5CE1FF)),
              _vDivider(),
              _statPill('3P ELO', '${p.elo3P}', const Color(0xFF34D399)),
              _vDivider(),
              _statPill('Zafer', '${p.wins}/${p.gamesPlayed}',
                  const Color(0xFFFFD166)),
              _vDivider(),
              _statPill('Avlanan', '${p.totalCaptures}',
                  const Color(0xFFFF6B7A)),
            ],
          ),
        ),
        SizedBox(height: compact ? 10 : 14),

        // Yarım kalmış aktif maç varsa tek dokunuşla kaldığı yerden devam et!
        if (hasResume && saved != null) ...[
          _primaryLaunchButton(
            icon: Icons.play_circle_fill_rounded,
            title: 'SAVAŞA DEVAM ET',
            subtitle:
                '${saved.boardLabel} • ${saved.humanTeam.legion} • ${saved.plyCount} Yarı-Hamle Kayıtlı',
            gradient: const [Color(0xFF9E1B34), Color(0xFF5A1228)],
            borderColor: const Color(0xFFFF6B7A),
            onTap: widget.onResumeSavedMatch,
          ),
          const SizedBox(height: 10),
        ],

        // 2 Kişilik Amfi Düellosu Başlat
        _primaryLaunchButton(
          icon: Icons.shield_rounded,
          title: '2 KİŞİLİK AMFİ DÜELLOSU',
          subtitle: 'Kral & Kraliçe Zirvede • 36 Savaşçı • Gliński Kuralları',
          gradient: const [Color(0xFF1B355C), Color(0xFF10203A)],
          borderColor: const Color(0xFF5CE1FF),
          onTap: () => widget.onStartVariant(
            BoardVariant.twoPlayer,
            BoardSize.classic,
          ),
        ),
        const SizedBox(height: 10),

        // 3 Kişilik Altıgen Amfi Masası Başlat
        _primaryLaunchButton(
          icon: Icons.hexagon_rounded,
          title: '3 KİŞİLİK AMFİ MASASI',
          subtitle:
              '${_size3P.label} Tahta • Beyaz • Siyah • Zümrüt Ordu • Özel 3\'lü Koalisyon YZ',
          gradient: const [Color(0xFF144236), Color(0xFF0C2620)],
          borderColor: const Color(0xFF34D399),
          onTap: () => widget.onStartVariant(BoardVariant.threePlayer, _size3P),
        ),
        _sizePicker(),
        const SizedBox(height: 12),

        // Alt ikincil düğmeler: Savaş Arşivi (SQLite) & Ayarlar
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE2ECF8),
                  side: const BorderSide(color: Color(0xFF2D4060)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                onPressed: widget.onOpenArchive,
                icon: const Icon(
                  Icons.military_tech_rounded,
                  size: 17,
                  color: Color(0xFFD4A854),
                ),
                label: const Text(
                  'Sefer & Zaferler',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE2ECF8),
                  side: const BorderSide(color: Color(0xFF2D4060)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                onPressed: widget.onOpenSettings,
                icon: const Icon(
                  Icons.tune_rounded,
                  size: 17,
                  color: Color(0xFF5CE1FF),
                ),
                label: const Text(
                  'Savaş Ayarları',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statPill(String label, String value, Color accent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF94A4BE),
          ),
        ),
      ],
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 24,
        color: const Color(0xFF253550),
      );

  Widget _primaryLaunchButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.25),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x33000000),
                  border: Border.all(color: borderColor.withValues(alpha: 0.65)),
                ),
                child: Icon(icon, color: borderColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFC6D4EA),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: borderColor, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArcaneBackdropPainter extends CustomPainter {
  const _ArcaneBackdropPainter({required this.phase});
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final cx = size.width * 0.5;
    final cy = size.height * 0.30;
    final pulse = 0.88 + 0.12 * math.sin(phase * math.pi * 2);

    // Üst buz-mavisi hilal / ejderha halesi
    final moonPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.fromRGBO(56, 165, 255, 0.22 * pulse),
          const Color.fromRGBO(18, 42, 88, 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: Offset(cx, cy - size.height * 0.06),
          radius: size.shortestSide * 0.52,
        ),
      );
    canvas.drawRect(rect, moonPaint);

    // Kanat arkası kızıl kor halesi
    final crimsonPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.fromRGBO(196, 24, 58, 0.19 * pulse),
          const Color.fromRGBO(72, 10, 26, 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: Offset(cx, cy + size.height * 0.05),
          radius: size.shortestSide * 0.56,
        ),
      );
    canvas.drawRect(rect, crimsonPaint);

    // Hafif yüzen rün kıvılcımları (sabit 18 parçacık, sıfır bellek tahsisi)
    final sparkPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 18; i++) {
      final seed = i * 1.6180339;
      final px = ((seed * 0.37) % 1.0) * size.width;
      final py = (((seed * 0.73) - phase * (0.35 + (i % 3) * 0.15)) % 1.0) *
          size.height;
      final y = py < 0 ? py + size.height : py;
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase * math.pi * 2 + i));
      sparkPaint.color = i.isEven
          ? Color.fromRGBO(110, 205, 255, 0.38 * twinkle)
          : Color.fromRGBO(255, 92, 118, 0.34 * twinkle);
      canvas.drawCircle(Offset(px, y), 1.2 + (i % 3) * 0.55, sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcaneBackdropPainter oldDelegate) =>
      oldDelegate.phase != phase;
}

