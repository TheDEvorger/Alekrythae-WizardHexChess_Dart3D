import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/chess_game.dart';

/// Klasik satranç sembolleri yerine her karanlık-fantezi savaşçısı için
/// özel çizilmiş yüksek kontrastlı vektör arma ikonu.
class CreatureBadge extends StatelessWidget {
  const CreatureBadge({
    super.key,
    required this.kind,
    required this.team,
    this.size = 32,
    this.framed = true,
  });

  final PieceType kind;
  final Team team;
  final double size;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final (primary, accent, bg, border) = switch (team) {
      Team.white => (
          const Color(0xFFE8EEF8),
          const Color(0xFF5CE1FF),
          const Color(0xFF192842),
          const Color(0xFFD4A854),
        ),
      Team.black => (
          const Color(0xFFE05262),
          const Color(0xFFFF9248),
          const Color(0xFF2B121B),
          const Color(0xFFB84052),
        ),
      Team.emerald => (
          const Color(0xFF6EF5B8),
          const Color(0xFFFFD166),
          const Color(0xFF102E24),
          const Color(0xFF2ECF8A),
        ),
    };

    final painter = CustomPaint(
      size: Size.square(size * (framed ? 0.68 : 0.92)),
      painter: _EmblemPainter(kind: kind, primary: primary, accent: accent),
    );

    if (!framed) {
      return SizedBox.square(dimension: size, child: Center(child: painter));
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [bg.withValues(alpha: 0.96), const Color(0xFF0A0E18)],
        ),
        border: Border.all(color: border.withValues(alpha: 0.88), width: 1.25),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.20),
            blurRadius: 5,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: painter,
    );
  }
}

class _EmblemPainter extends CustomPainter {
  const _EmblemPainter({
    required this.kind,
    required this.primary,
    required this.accent,
  });

  final PieceType kind;
  final Color primary;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fill = Paint()
      ..color = primary
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final glow = Paint()
      ..color = accent
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    switch (kind) {
      case PieceType.pawn:
        // Kalkan Muhafızı: Şövalye Kalkanı + Çapraz Mızrak
        final spear = Path()
          ..moveTo(w * 0.82, h * 0.06)
          ..lineTo(w * 0.92, h * 0.22)
          ..lineTo(w * 0.80, h * 0.28)
          ..lineTo(w * 0.70, h * 0.20)
          ..close();
        canvas.drawPath(spear, glow);
        canvas.drawLine(Offset(w * 0.80, h * 0.24), Offset(w * 0.22, h * 0.92), stroke);

        final shield = Path()
          ..moveTo(w * 0.16, h * 0.20)
          ..quadraticBezierTo(w * 0.45, h * 0.13, w * 0.74, h * 0.20)
          ..quadraticBezierTo(w * 0.74, h * 0.62, w * 0.45, h * 0.90)
          ..quadraticBezierTo(w * 0.16, h * 0.62, w * 0.16, h * 0.20)
          ..close();
        canvas.drawPath(shield, fill);
        canvas.drawCircle(Offset(w * 0.45, h * 0.48), w * 0.095, glow);

      case PieceType.knight:
        // Suikastçi: Çapraz Kıvrık Şam Hançerleri
        for (final flip in const [1.0, -1.0]) {
          canvas.save();
          if (flip < 0) {
            canvas.translate(w, 0);
            canvas.scale(-1, 1);
          }
          final blade = Path()
            ..moveTo(w * 0.20, h * 0.82)
            ..lineTo(w * 0.34, h * 0.68)
            ..quadraticBezierTo(w * 0.56, h * 0.32, w * 0.86, h * 0.12)
            ..quadraticBezierTo(w * 0.72, h * 0.48, w * 0.44, h * 0.76)
            ..close();
          canvas.drawPath(blade, fill);
          canvas.drawLine(Offset(w * 0.15, h * 0.87), Offset(w * 0.34, h * 0.68), stroke);
          canvas.restore();
        }
        canvas.drawCircle(Offset(w * 0.50, h * 0.52), w * 0.08, glow);

      case PieceType.bishop:
        // Ejderha: Boynuzlu Ejder Kafası ve Açık Kanatlar
        final dragon = Path()
          ..moveTo(w * 0.50, h * 0.16)
          ..lineTo(w * 0.34, h * 0.04)
          ..lineTo(w * 0.38, h * 0.26)
          ..lineTo(w * 0.06, h * 0.18)
          ..quadraticBezierTo(w * 0.18, h * 0.48, w * 0.08, h * 0.72)
          ..quadraticBezierTo(w * 0.28, h * 0.62, w * 0.40, h * 0.76)
          ..lineTo(w * 0.50, h * 0.94)
          ..lineTo(w * 0.60, h * 0.76)
          ..quadraticBezierTo(w * 0.72, h * 0.62, w * 0.92, h * 0.72)
          ..quadraticBezierTo(w * 0.82, h * 0.48, w * 0.94, h * 0.18)
          ..lineTo(w * 0.62, h * 0.26)
          ..lineTo(w * 0.66, h * 0.04)
          ..close();
        canvas.drawPath(dragon, fill);
        canvas.drawCircle(Offset(w * 0.43, h * 0.40), w * 0.045, glow);
        canvas.drawCircle(Offset(w * 0.57, h * 0.40), w * 0.045, glow);

      case PieceType.rook:
        // Savaş Titanı: Çapraz Dövme Savaş Çekici (War-Maul) + Kıvrık Boğa Boynuzları (Sıfır kale ikonu!)
        final hornL = Path()
          ..moveTo(w * 0.34, h * 0.28)
          ..quadraticBezierTo(w * 0.08, h * 0.24, w * 0.10, h * 0.05)
          ..quadraticBezierTo(w * 0.20, h * 0.18, w * 0.42, h * 0.20)
          ..close();
        final hornR = Path()
          ..moveTo(w * 0.72, h * 0.66)
          ..quadraticBezierTo(w * 0.76, h * 0.92, w * 0.95, h * 0.90)
          ..quadraticBezierTo(w * 0.82, h * 0.80, w * 0.80, h * 0.58)
          ..close();
        canvas.drawPath(hornL, glow);
        canvas.drawPath(hornR, glow);

        canvas.save();
        canvas.translate(w * 0.50, h * 0.50);
        canvas.rotate(-math.pi / 4);
        // Çekiç sapı
        canvas.drawLine(
          Offset(0, -h * 0.12),
          Offset(0, h * 0.46),
          stroke..strokeWidth = w * 0.115,
        );
        // Pahlı savaş balyozu başı ve zırh delici arka gaga
        final head = Path()
          ..moveTo(-w * 0.34, -h * 0.32)
          ..lineTo(w * 0.18, -h * 0.34)
          ..lineTo(w * 0.38, -h * 0.20)
          ..lineTo(w * 0.18, -h * 0.10)
          ..lineTo(-w * 0.34, -h * 0.12)
          ..lineTo(-w * 0.40, -h * 0.22)
          ..close();
        canvas.drawPath(head, fill);
        canvas.drawCircle(Offset(-w * 0.08, -h * 0.22), w * 0.075, glow);
        canvas.restore();

      case PieceType.queen:
        // Vampir Kraliçe: Yarasa Kanatları + Kan Yakutu Tacı
        final wings = Path()
          ..moveTo(w * 0.50, h * 0.42)
          ..quadraticBezierTo(w * 0.28, h * 0.18, w * 0.05, h * 0.30)
          ..quadraticBezierTo(w * 0.18, h * 0.50, w * 0.12, h * 0.74)
          ..quadraticBezierTo(w * 0.32, h * 0.62, w * 0.50, h * 0.82)
          ..quadraticBezierTo(w * 0.68, h * 0.62, w * 0.88, h * 0.74)
          ..quadraticBezierTo(w * 0.82, h * 0.50, w * 0.95, h * 0.30)
          ..quadraticBezierTo(w * 0.72, h * 0.18, w * 0.50, h * 0.42)
          ..close();
        canvas.drawPath(wings, fill);
        final gem = Path()
          ..moveTo(w * 0.50, h * 0.10)
          ..lineTo(w * 0.63, h * 0.34)
          ..lineTo(w * 0.50, h * 0.58)
          ..lineTo(w * 0.37, h * 0.34)
          ..close();
        canvas.drawPath(gem, glow);

      case PieceType.king:
        // Barbar Kral: Çift Ağızlı Hilal Savaş Baltası
        canvas.drawLine(
          Offset(w * 0.50, h * 0.08),
          Offset(w * 0.50, h * 0.94),
          stroke..strokeWidth = w * 0.095,
        );
        final axe = Path()
          ..moveTo(w * 0.44, h * 0.26)
          ..quadraticBezierTo(w * 0.18, h * 0.12, w * 0.10, h * 0.22)
          ..quadraticBezierTo(w * 0.04, h * 0.44, w * 0.12, h * 0.66)
          ..quadraticBezierTo(w * 0.22, h * 0.74, w * 0.44, h * 0.56)
          ..close();
        final axeR = Path()
          ..moveTo(w * 0.56, h * 0.26)
          ..quadraticBezierTo(w * 0.82, h * 0.12, w * 0.90, h * 0.22)
          ..quadraticBezierTo(w * 0.96, h * 0.44, w * 0.88, h * 0.66)
          ..quadraticBezierTo(w * 0.78, h * 0.74, w * 0.56, h * 0.56)
          ..close();
        canvas.drawPath(axe, fill);
        canvas.drawPath(axeR, fill);
        canvas.drawCircle(Offset(w * 0.50, h * 0.41), w * 0.085, glow);
    }
  }

  @override
  bool shouldRepaint(covariant _EmblemPainter old) =>
      old.kind != kind || old.primary != primary || old.accent != accent;
}
