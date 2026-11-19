import 'dart:math';

import 'package:flutter/material.dart';

import 'controller.dart';

/// Portrait animé de Sarra : respiration, clignements, bouche qui bouge quand elle parle.
class SarraAvatar extends StatefulWidget {
  const SarraAvatar({super.key, required this.mode});
  final SarraMode mode;

  @override
  State<SarraAvatar> createState() => _SarraAvatarState();
}

class _SarraAvatarState extends State<SarraAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(painter: _Painter(t: _c.value * 600, mode: widget.mode)),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter({required this.t, required this.mode});
  final double t;
  final SarraMode mode;

  static const _hair = Color(0xFF2B1A14);
  static const _skin = Color(0xFFEFC4A0);

  Paint _fill(Color c) => Paint()..color = c;
  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final center = Offset(w / 2, w / 2);
    final r = w / 2 * 0.84;

    if (mode == SarraMode.listening) {
      final ph = (t % 1.6) / 1.6;
      canvas.drawCircle(
        center,
        r * (1 + 0.14 * ph),
        _stroke(const Color(0xFF7CC4FF).withOpacity((1 - ph) * 0.85), 3),
      );
    }

    canvas.save();
    canvas.translate(center.dx - r, center.dy - r);
    canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, 2 * r, 2 * r)));
    canvas.scale(2 * r / 300);

    const bg = Rect.fromLTWH(0, 0, 300, 300);
    canvas.drawRect(
      bg,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.3),
          radius: 0.9,
          colors: [Color(0xFF3A5A96), Color(0xFF22386A)],
        ).createShader(bg),
    );

    canvas.translate(0, sin(t * 1.5) * 3);
    if (mode == SarraMode.listening) {
      canvas.translate(150, 150);
      canvas.rotate(-0.035);
      canvas.translate(-150, -150);
    }

    // cheveux (arrière)
    canvas.drawPath(
      Path()
        ..moveTo(82, 125)
        ..cubicTo(70, 60, 120, 36, 150, 36)
        ..cubicTo(190, 36, 232, 62, 218, 135)
        ..cubicTo(226, 190, 232, 225, 238, 262)
        ..lineTo(62, 262)
        ..cubicTo(68, 225, 74, 190, 82, 125)
        ..close(),
      _fill(_hair),
    );
    // haut
    canvas.drawPath(
      Path()
        ..moveTo(30, 300)
        ..cubicTo(36, 246, 92, 226, 150, 226)
        ..cubicTo(208, 226, 264, 246, 270, 300)
        ..close(),
      _fill(const Color(0xFFE8735A)),
    );
    // cou
    canvas.drawPath(
      Path()
        ..moveTo(130, 176)
        ..lineTo(130, 222)
        ..quadraticBezierTo(150, 238, 170, 222)
        ..lineTo(170, 176)
        ..close(),
      _fill(const Color(0xFFDFAE88)),
    );
    // visage
    canvas.drawOval(const Rect.fromLTRB(94, 56, 206, 188), _fill(_skin));
    // boucles d'oreilles
    canvas.drawCircle(const Offset(94, 142), 3.6, _fill(const Color(0xFFF2C94C)));
    canvas.drawCircle(const Offset(206, 142), 3.6, _fill(const Color(0xFFF2C94C)));
    // frange
    canvas.drawPath(
      Path()
        ..moveTo(92, 128)
        ..cubicTo(86, 70, 126, 50, 152, 52)
        ..cubicTo(194, 54, 214, 88, 208, 128)
        ..cubicTo(198, 98, 176, 82, 146, 82)
        ..cubicTo(116, 84, 98, 102, 92, 128)
        ..close(),
      _fill(_hair),
    );

    // yeux (clignement toutes les 5,5 s)
    final ph = t % 5.5;
    final blink = (ph > 5.2 && ph < 5.4) ? 0.1 : 1.0;
    for (final cx in [128.0, 172.0]) {
      canvas.save();
      canvas.translate(cx, 128);
      canvas.scale(1, blink);
      canvas.translate(-cx, -128);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, 128), width: 18, height: 14), _fill(Colors.white));
      canvas.drawCircle(Offset(cx, 128), 5, _fill(const Color(0xFF2A1C16)));
      canvas.drawCircle(Offset(cx - 1.5, 126.5), 1.6, _fill(Colors.white));
      canvas.restore();
    }

    // sourcils, nez, joues
    final brows = _stroke(_hair, 3);
    canvas.drawPath(Path()..moveTo(118, 112)..quadraticBezierTo(128, 106, 138, 111), brows);
    canvas.drawPath(Path()..moveTo(162, 111)..quadraticBezierTo(172, 106, 182, 112), brows);
    canvas.drawPath(
        Path()..moveTo(150, 132)..quadraticBezierTo(146, 150, 151, 152), _stroke(const Color(0xFFD29B78), 2));
    final blush = _fill(const Color(0xFFF08A7A).withOpacity(0.3));
    canvas.drawCircle(const Offset(120, 153), 9, blush);
    canvas.drawCircle(const Offset(180, 153), 9, blush);

    // bouche
    if (mode == SarraMode.speaking) {
      final open = max(0.15, (0.5 + 0.5 * sin(t * 17)) * (0.55 + 0.45 * sin(t * 7.3).abs()));
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(150, 173), width: 24, height: 16 * open),
        _fill(const Color(0xFF7A2B2B)),
      );
    } else {
      canvas.drawPath(
          Path()..moveTo(135, 170)..quadraticBezierTo(150, 182, 165, 170), _stroke(const Color(0xFFB5473F), 4));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}
