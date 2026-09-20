import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Renders the scrolling spectrogram as a single triangle mesh
/// (`Canvas.drawVertices`) instead of one `drawRect`/pixel per cell — a
/// `historyRows` x `numBins` grid is thousands of cells, and a mesh is one
/// GPU draw call regardless of grid size, which is what keeps this smooth
/// at the spectrum controller's ~25fps default.
///
/// [rows] holds the most recent row first (`rows[0]` is newest); rows
/// beyond what's been collected yet are treated as background-colored, so
/// the waterfall visibly "fills in" from the top on first use, same as
/// gqrx/SDR#.
class WaterfallPainter extends CustomPainter {
  WaterfallPainter({
    required this.rows,
    required this.historyRows,
    required this.minDb,
    required this.maxDb,
    required this.colormap,
    required this.background,
    this.cursorFraction,
    this.passbandFraction,
    this.cursorColor,
  });

  final List<List<double>> rows;
  final int historyRows;
  final double minDb;
  final double maxDb;
  final Color Function(double t) colormap;
  final Color background;

  /// Horizontal position (0..1) of the tuned frequency, matching
  /// [SpectrumPainter]'s cursor — drawn as a thin vertical line down
  /// through the waterfall, same as gqrx.
  final double? cursorFraction;

  /// Width (0..1, fraction of the visible span) of the shaded passband
  /// band around [cursorFraction], matching `SpectrumScope.passbandHz`.
  final double? passbandFraction;
  final Color? cursorColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    if (rows.isEmpty) return;

    final numBins = rows.first.length;
    if (numBins < 2) return;

    final cols = numBins;
    final rowCount = historyRows;
    final vertsPerRow = cols + 1;
    final positions = Float32List((rowCount + 1) * vertsPerRow * 2);
    final colors = Int32List((rowCount + 1) * vertsPerRow);
    final cellW = size.width / cols;
    final cellH = size.height / rowCount;

    var p = 0;
    var c = 0;
    for (var r = 0; r <= rowCount; r++) {
      final dataRow = r < rows.length ? rows[r] : null;
      final y = r * cellH;
      for (var col = 0; col <= cols; col++) {
        positions[p++] = col * cellW;
        positions[p++] = y;
        final value = dataRow == null
            ? minDb
            : dataRow[col < cols ? col : cols - 1];
        final t = ((value - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
        colors[c++] = (dataRow == null ? background : colormap(t)).toARGB32();
      }
    }

    final indices = Uint16List(rowCount * cols * 6);
    var ii = 0;
    for (var r = 0; r < rowCount; r++) {
      for (var col = 0; col < cols; col++) {
        final topLeft = r * vertsPerRow + col;
        final topRight = topLeft + 1;
        final bottomLeft = (r + 1) * vertsPerRow + col;
        final bottomRight = bottomLeft + 1;
        indices[ii++] = topLeft;
        indices[ii++] = bottomLeft;
        indices[ii++] = topRight;
        indices[ii++] = topRight;
        indices[ii++] = bottomLeft;
        indices[ii++] = bottomRight;
      }
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
      indices: indices,
    );
    canvas.drawVertices(vertices, BlendMode.src, Paint());

    _paintCursorAndPassband(canvas, size);
  }

  void _paintCursorAndPassband(Canvas canvas, Size size) {
    final center = cursorFraction;
    if (center == null) return;

    if (passbandFraction case final width? when width > 0) {
      final left = ((center - width / 2).clamp(0.0, 1.0)) * size.width;
      final right = ((center + width / 2).clamp(0.0, 1.0)) * size.width;
      if (right > left) {
        canvas.drawRect(
          Rect.fromLTRB(left, 0, right, size.height),
          Paint()
            ..color = (cursorColor ?? const Color(0xFFFFC13B)).withValues(
              alpha: 0.10,
            ),
        );
      }
    }

    final x = center.clamp(0.0, 1.0) * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = (cursorColor ?? const Color(0xFFFFC13B)).withValues(
          alpha: 0.8,
        )
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant WaterfallPainter oldDelegate) {
    return !identical(oldDelegate.rows, rows) ||
        oldDelegate.minDb != minDb ||
        oldDelegate.maxDb != maxDb ||
        oldDelegate.cursorFraction != cursorFraction ||
        oldDelegate.passbandFraction != passbandFraction;
  }
}
