import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr/qr.dart';

import '../theme.dart';
import 'swapnio_widgets.dart';

const Color _ink = Color(0xFF17142B);
const Color _paper = Color(0xFFFFFFFF);

/// Swapnio's branded QR: rounded data dots in the orange-to-purple brand
/// gradient, rounded finder "eyes" in ink, and the Swapnio mark in the
/// middle. Readability rules it keeps, so ordinary camera apps still scan it:
///  - highest error correction (H, ~30%), which is what lets the centre
///    carry the logo;
///  - a 4-module quiet zone of plain white around the code;
///  - dark marks on a white background (the gradient's lightest point is
///    still dark enough to binarise as "dark");
///  - finder patterns keep their 1:1:3:1:1 proportions, only with rounded
///    corners.
class SwapnioQrCode extends StatelessWidget {
  final String data;
  final double size;

  const SwapnioQrCode({super.key, required this.data, this.size = 240});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final image = QrImage(
      QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.H),
    );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _QrPainter(image, from: c.give, to: c.get),
          ),
          // Logo: ~18% of the width, well inside what level H can lose.
          Container(
            padding: EdgeInsets.all(size * 0.012),
            decoration: BoxDecoration(
              color: _paper,
              borderRadius: BorderRadius.circular(size * 0.06),
            ),
            child: SwapnioMark(size: size * 0.16),
          ),
        ],
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final QrImage image;
  final Color from;
  final Color to;

  const _QrPainter(this.image, {required this.from, required this.to});

  static const int _quiet = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.width / (n + _quiet * 2);
    final origin = Offset(cell * _quiet, cell * _quiet);
    final codeRect = origin & Size.square(cell * n);

    canvas.drawRect(Offset.zero & size, Paint()..color = _paper);

    // Keep the centre clear for the logo.
    final logoHalf = size.width * 0.1 / cell;
    final mid = n / 2;
    bool inLogo(int r, int col) =>
        (r + 0.5 - mid).abs() < logoHalf && (col + 0.5 - mid).abs() < logoHalf;
    bool inFinder(int r, int col) =>
        (r < 7 && col < 7) ||
        (r < 7 && col >= n - 7) ||
        (r >= n - 7 && col < 7);

    final dots = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [from, Color.lerp(from, to, 0.5)!, to],
      ).createShader(codeRect);
    for (var r = 0; r < n; r++) {
      for (var col = 0; col < n; col++) {
        if (!image.isDark(r, col) || inFinder(r, col) || inLogo(r, col))
          continue;
        final center = origin + Offset((col + 0.5) * cell, (r + 0.5) * cell);
        // Neighbouring dark modules are bridged so runs read as solid
        // strokes - rounder look, same data.
        canvas.drawCircle(center, cell * 0.46, dots);
        if (col + 1 < n &&
            image.isDark(r, col + 1) &&
            !inFinder(r, col + 1) &&
            !inLogo(r, col + 1)) {
          canvas.drawRect(
            Rect.fromLTWH(
              center.dx,
              center.dy - cell * 0.46,
              cell,
              cell * 0.92,
            ),
            dots,
          );
        }
        if (r + 1 < n &&
            image.isDark(r + 1, col) &&
            !inFinder(r + 1, col) &&
            !inLogo(r + 1, col)) {
          canvas.drawRect(
            Rect.fromLTWH(
              center.dx - cell * 0.46,
              center.dy,
              cell * 0.92,
              cell,
            ),
            dots,
          );
        }
      }
    }

    // Finder eyes: 7x7 ring (1 module thick) around a 3x3 core.
    void eye(int r, int col) {
      final outer = Rect.fromLTWH(
        origin.dx + col * cell,
        origin.dy + r * cell,
        cell * 7,
        cell * 7,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          outer.deflate(cell / 2),
          Radius.circular(cell * 1.9),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell
          ..color = _ink,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          outer.deflate(cell * 2),
          Radius.circular(cell * 1.1),
        ),
        Paint()..color = _ink,
      );
    }

    eye(0, 0);
    eye(0, n - 7);
    eye(n - 7, 0);
  }

  @override
  bool shouldRepaint(_QrPainter old) =>
      old.image != image || old.from != from || old.to != to;
}

/// The shareable card around a profile QR: who it belongs to, what they
/// teach and their passport number. Always drawn light, so a screenshot or
/// saved image looks the same in any theme.
class ProfileQrCard extends StatelessWidget {
  final String data;
  final String name;
  final String? photoUrl;
  final String? topSkill;
  final String passportNumber;
  final bool verified;

  const ProfileQrCard({
    super.key,
    required this.data,
    required this.name,
    required this.photoUrl,
    required this.topSkill,
    required this.passportNumber,
    this.verified = false,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.lightTheme,
      child: Builder(
        builder: (context) {
          final c = context.sw;
          return Container(
            width: 320,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.give, c.get],
              ),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(27),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SwapAvatar(
                        name: name,
                        photoUrl: photoUrl,
                        size: 46,
                        radius: 15,
                        verified: verified,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.display(
                                fontSize: 19,
                                color: c.text,
                              ),
                            ),
                            if (topSkill != null && topSkill!.isNotEmpty)
                              Text(
                                'Teaches $topSkill',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.give,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SwapnioQrCode(data: data, size: 260),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.rotate(
                        angle: math.pi / 2,
                        child: Icon(
                          Icons.swap_horiz_rounded,
                          size: 14,
                          color: c.get,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Scan to swap skills · $passportNumber',
                        style: GoogleFonts.manrope(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: c.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
