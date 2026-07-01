import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/usage_stats.dart';
import '../settings_shared.dart';

/// A longer, GitHub-style contribution heatmap that replaces the old 30-day
/// dot strip. It spans as many weeks as fit the available width (min 8, max
/// 26 — roughly 2 to 6 months) so the user can "see more of the past" while
/// scales stay aligned to calendar weeks (Monday-start, matching the weekly
/// bar chart).
///
/// Everything renders inside one [CustomPainter], exactly like
/// `_WeeklyBarPainter`: ink fills (`beeText`) scaled by daily intensity, with
/// empty days as faint ceramic squares. Month + weekday labels are painted by
/// the same record using [TextPainter], so alignment is pixel-perfect.
class HomeActivityHeatmap extends StatelessWidget {
  final UsageStats stats;

  const HomeActivityHeatmap({super.key, required this.stats});

  // Geometry constants shared between widget sizing and the painter.
  static const double _cell = 12.0;
  static const double _gap = 4.0;
  static const double _stride = _cell + _gap; // 16
  static const double _leftGutter = 24.0; // room for M/W/F weekday labels
  static const double _topLabelH = 15.0; // room for month labels

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The heatmap paints inside a Container with 14px horizontal padding,
        // so size the week columns to the *inner* width to avoid right-edge
        // clipping of the last columns and the legend.
        final avail = constraints.maxWidth - 28;
        final weeks = ((avail - _leftGutter) / _stride).floor().clamp(8, 26);

        // ── Build the week×day grid of word counts (null = future day) ──
        final today = DateTime.now();
        final mondayThisWeek = today.subtract(
          Duration(days: today.weekday - 1),
        );
        // Each past cell is remembered so the interactive overlay can show a
        // per-cell tooltip — the signature pointer interaction for a heatmap.
        final pastCells = <_Cell>[];
        final grid = List<List<int?>>.generate(weeks, (col) {
          // Monday of this column's week.
          final weekMonday = mondayThisWeek.subtract(
            Duration(days: (weeks - 1 - col) * 7),
          );
          return List<int?>.generate(7, (row) {
            final date = weekMonday.add(Duration(days: row));
            if (_dateOnly(date).isAfter(_dateOnly(today))) return null;
            final words = stats.dailyWordCount[_dateKey(date)] ?? 0;
            pastCells.add(_Cell(col, row, date, words));
            return words;
          });
        });

        // ── Intensity ceiling across the visible range ──
        int maxVal = 0;
        int activeDays = 0;
        for (final col in grid) {
          for (final w in col) {
            if (w != null) {
              if (w > 0) activeDays++;
              if (w > maxVal) maxVal = w;
            }
          }
        }

        // ── Month labels at column boundaries ──
        final monthLabels = <_ColLabel>[];
        int? lastMonth;
        for (int col = 0; col < weeks; col++) {
          final weekMonday = mondayThisWeek.subtract(
            Duration(days: (weeks - 1 - col) * 7),
          );
          if (weekMonday.month != lastMonth) {
            monthLabels.add(_ColLabel(col, _monthAbbr[weekMonday.month - 1]));
            lastMonth = weekMonday.month;
          }
        }

        final gridH = 7 * _stride - _gap; // 108
        const legendH = 20.0;
        final height = _topLabelH + gridH + legendH;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: BeeGroupLabel(label: 'Activity')),
                Text(
                  '$activeDays active day${activeDays == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: beeTextMuted(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                color: beeSurfaceHighest(context),
                borderRadius: BorderRadius.circular(kBeeRadiusMd),
                border: Border.all(
                  color: beeBorder(context).withValues(alpha: 0.5),
                ),
              ),
              child: SizedBox(
                height: height,
                child: _HeatmapGrid(
                  grid: grid,
                  pastCells: pastCells,
                  monthLabels: monthLabels,
                  maxVal: maxVal,
                  inkColor: beeText(context),
                  trackColor: beeBorder(context),
                  labelColor: beeTextMuted(context),
                  cell: _cell,
                  gap: _gap,
                  leftGutter: _leftGutter,
                  topLabelH: _topLabelH,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Pure date helpers (the service keeps these private) ──────────────

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _dateKey(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}'
        '-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}';
  }

  static const _monthAbbr = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

/// Lightweight pairing of a column index to its month label.
class _ColLabel {
  final int col;
  final String text;
  const _ColLabel(this.col, this.text);
}

// ═════════════════════════════════════════════════════════════════════════════
// Heatmap Painter — cells + month labels + weekday labels + legend
// ═════════════════════════════════════════════════════════════════════════════

class _HeatmapPainter extends CustomPainter {
  final List<List<int?>> grid;
  final int maxVal;
  final List<_ColLabel> monthLabels;

  final Color inkColor;
  final Color trackColor;
  final Color labelColor;

  final double cell;
  final double gap;
  final double leftGutter;
  final double topLabelH;

  /// Cell under the pointer, for the live hover outline (null = none).
  final int? hoveredCol;
  final int? hoveredRow;

  /// Columns whose weekday label should be rendered (0=Mon … 6=Sun).
  static const _labelRows = {0: 'M', 2: 'W', 4: 'F'};

  _HeatmapPainter({
    required this.grid,
    required this.maxVal,
    required this.monthLabels,
    required this.inkColor,
    required this.trackColor,
    required this.labelColor,
    required this.cell,
    required this.gap,
    required this.leftGutter,
    required this.topLabelH,
    required this.hoveredCol,
    required this.hoveredRow,
  });

  double _cellAlpha(double intensity) => 0.20 + intensity * 0.80;

  @override
  void paint(Canvas canvas, Size size) {
    final stride = cell + gap;
    final weeks = grid.length;

    // ── Month labels (top) ───────────────────────────────────────────
    final monthStyle = TextStyle(color: labelColor, fontSize: 9, height: 1.0);
    for (final ml in monthLabels) {
      final x = leftGutter + ml.col * stride;
      final tp = TextPainter(
        text: TextSpan(text: ml.text, style: monthStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, 0));
    }

    // ── Weekday labels (left gutter) ─────────────────────────────────
    final dayStyle = TextStyle(color: labelColor, fontSize: 9, height: 1.0);
    for (final entry in _labelRows.entries) {
      final row = entry.key;
      final y = topLabelH + row * stride + (cell / 2);
      final tp = TextPainter(
        text: TextSpan(text: entry.value, style: dayStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      // Vertically center on the cell.
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    // ── Cells ────────────────────────────────────────────────────────
    final empty = Paint()
      ..color = trackColor.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    final radius = Radius.circular(3);

    for (int col = 0; col < weeks; col++) {
      for (int row = 0; row < 7; row++) {
        final words = grid[col][row];
        if (words == null) continue; // future day — leave blank
        final x = leftGutter + col * stride;
        final y = topLabelH + row * stride;

        final Paint paint;
        if (words == 0) {
          paint = empty;
        } else {
          final intensity = maxVal == 0
              ? 0.0
              : (words / maxVal).clamp(0.0, 1.0);
          paint = Paint()
            ..color = inkColor.withValues(alpha: _cellAlpha(intensity))
            ..style = PaintingStyle.fill;
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, cell, cell), radius),
          paint,
        );

        // Live pointer feedback — outline the cell under the cursor. Uses the
        // same ink token as the fills, so it harmonizes with the dashboard's
        // other hover treatments (which tint surfaces ~6% ink).
        if (col == hoveredCol && row == hoveredRow) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, y, cell, cell), radius),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = inkColor.withValues(alpha: 0.6),
          );
        }
      }
    }

    // ── Legend (bottom-right): "Less ▢▢▢▢▢ More" ──────────────────────
    _drawLegend(canvas, size, stride);
  }

  void _drawLegend(Canvas canvas, Size size, double stride) {
    final legendY = topLabelH + 7 * stride - gap + 7;
    final smallStyle = TextStyle(color: labelColor, fontSize: 9, height: 1.0);
    final radius = Radius.circular(3);

    TextPainter layout(String text) => TextPainter(
      text: TextSpan(text: text, style: smallStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final moreTp = layout('More');
    final lessTp = layout('Less');

    // Right-aligned: [Less][gap][5 squares][gap][More]
    const square = 9.0;
    const sqGap = 3.0;
    final squaresWidth = 5 * square + 4 * sqGap;
    final totalWidth = lessTp.width + 8 + squaresWidth + 8 + moreTp.width;

    final startX = size.width - totalWidth;

    lessTp.paint(canvas, Offset(startX, legendY));

    double sx = startX + lessTp.width + 8;
    const intensities = [0.0, 0.3, 0.55, 0.78, 1.0];
    for (final intensity in intensities) {
      final Paint p;
      if (intensity == 0) {
        p = Paint()
          ..color = trackColor.withValues(alpha: 0.45)
          ..style = PaintingStyle.fill;
      } else {
        p = Paint()
          ..color = inkColor.withValues(alpha: _cellAlpha(intensity))
          ..style = PaintingStyle.fill;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(sx, legendY + 1, square, square),
          radius,
        ),
        p,
      );
      sx += square + sqGap;
    }

    moreTp.paint(canvas, Offset(sx + 2, legendY));
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      grid != old.grid ||
      maxVal != old.maxVal ||
      monthLabels != old.monthLabels ||
      inkColor != old.inkColor ||
      hoveredCol != old.hoveredCol ||
      hoveredRow != old.hoveredRow;
}

// ═════════════════════════════════════════════════════════════════════════════
// Interactive grid body — paints the heatmap via [_HeatmapPainter] and layers
// per-cell [Tooltip]s on top, plus a live hovered-cell outline. Mirrors the
// desktop-native pointer feedback used across the rest of the dashboard
// (see `BeeInteractive`): every surface under the pointer reacts to it.
// ═════════════════════════════════════════════════════════════════════════════

class _HeatmapGrid extends StatefulWidget {
  final List<List<int?>> grid;
  final List<_Cell> pastCells;
  final List<_ColLabel> monthLabels;
  final int maxVal;

  final Color inkColor;
  final Color trackColor;
  final Color labelColor;

  final double cell;
  final double gap;
  final double leftGutter;
  final double topLabelH;

  const _HeatmapGrid({
    required this.grid,
    required this.pastCells,
    required this.monthLabels,
    required this.maxVal,
    required this.inkColor,
    required this.trackColor,
    required this.labelColor,
    required this.cell,
    required this.gap,
    required this.leftGutter,
    required this.topLabelH,
  });

  @override
  State<_HeatmapGrid> createState() => _HeatmapGridState();
}

class _HeatmapGridState extends State<_HeatmapGrid> {
  int? _hoveredCol;
  int? _hoveredRow;

  double get _stride => widget.cell + widget.gap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (e) {
        final p = e.localPosition;
        final col = ((p.dx - widget.leftGutter) / _stride).floor();
        final row = ((p.dy - widget.topLabelH) / _stride).floor();
        final valid =
            col >= 0 &&
            col < widget.grid.length &&
            row >= 0 &&
            row < 7 &&
            widget.grid[col][row] != null;
        final nCol = valid ? col : null;
        final nRow = valid ? row : null;
        if (nCol != _hoveredCol || nRow != _hoveredRow) {
          setState(() {
            _hoveredCol = nCol;
            _hoveredRow = nRow;
          });
        }
      },
      onExit: (_) {
        if (_hoveredCol != null || _hoveredRow != null) {
          setState(() {
            _hoveredCol = null;
            _hoveredRow = null;
          });
        }
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _HeatmapPainter(
                grid: widget.grid,
                maxVal: widget.maxVal,
                monthLabels: widget.monthLabels,
                inkColor: widget.inkColor,
                trackColor: widget.trackColor,
                labelColor: widget.labelColor,
                cell: widget.cell,
                gap: widget.gap,
                leftGutter: widget.leftGutter,
                topLabelH: widget.topLabelH,
                hoveredCol: _hoveredCol,
                hoveredRow: _hoveredRow,
              ),
            ),
          ),
          // One invisible hit-target per past cell. Flutter's [Tooltip] shows
          // its message automatically when the pointer hovers the child, so we
          // get a native, per-cell "X words · Mon, Jan 15" affordance.
          for (final c in widget.pastCells)
            Positioned(
              left: widget.leftGutter + c.col * _stride,
              top: widget.topLabelH + c.row * _stride,
              width: widget.cell,
              height: widget.cell,
              child: Tooltip(
                message: _tooltip(c),
                waitDuration: Duration.zero,
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }

  String _tooltip(_Cell c) {
    const weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final label =
        '${weekday[c.date.weekday - 1]}, ${HomeActivityHeatmap._monthAbbr[c.date.month - 1]} '
        '${c.date.day}, ${c.date.year}';
    if (c.words <= 0) return 'No activity · $label';
    final f = c.words.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );
    return '$f words · $label';
  }
}

/// One past day expressed as grid coordinates + its date and word count.
class _Cell {
  final int col;
  final int row;
  final DateTime date;
  final int words;

  const _Cell(this.col, this.row, this.date, this.words);
}
