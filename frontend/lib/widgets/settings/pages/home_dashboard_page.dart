import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/usage_stats.dart';
import '../../../services/usage_stats_service.dart';
import 'home_activity_heatmap.dart';
import 'home_achievements_section.dart';
import '../settings_shared.dart';

/// Home dashboard — the landing page inside settings.
///
/// Layout mirrors the other settings pages: flat `beeSurface` background,
/// `BeeGroupLabel` section headers, consistent padding and spacing.
class HomeDashboardPage extends StatefulWidget {
  final UsageStatsService statsService;

  const HomeDashboardPage({super.key, required this.statsService});

  @override
  State<HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeDashboardPageState extends State<HomeDashboardPage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.statsService,
      builder: (context, _) {
        final stats = widget.statsService.stats;

        return Column(
          children: [
            Expanded(
              child: Container(
                color: beeSurface(context),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!stats.hasAnyRecording)
                        _buildEmptyState(context)
                      else ...[
                        _buildOverviewSection(context, stats),
                        const SizedBox(height: 24),
                        _buildWeeklySection(context),
                        const SizedBox(height: 24),
                        HomeActivityHeatmap(stats: stats),
                        const SizedBox(height: 24),
                        HomeAchievementsSection(stats: stats),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Empty State
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Center(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: beeYellow(context).withValues(alpha: 0.10),
              ),
              child: Icon(
                Icons.mic_rounded,
                size: 24,
                color: beeYellow(context).withValues(alpha: 0.50),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No recordings yet',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: beeTextSub(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Press your hotkey and start speaking.\n'
              'Your stats will appear here automatically.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: beeTextMuted(context),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Overview Section — main hero number + stat rows
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildOverviewSection(BuildContext context, UsageStats stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Hero number ──────────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _formatNumber(stats.totalWords),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: beeText(context),
                letterSpacing: -1.2,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'words spoken',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: beeTextSub(context),
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // Time saved subtitle
        Row(
          children: [
            Icon(
              Icons.bolt_rounded,
              size: 13,
              color: beeYellow(context),
            ),
            const SizedBox(width: 4),
            Text(
              _formatTimeSaved(stats.totalTypingTimeSavedMinutes),
              style: GoogleFonts.inter(
                fontSize: 11,
                color: beeTextMuted(context),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // ── Stat rows (same BeeSettingsRow pattern as every page) ───
        const BeeGroupLabel(label: 'Overview'),

        BeeSettingsRow(
          icon: Icons.local_fire_department_rounded,
          label: 'Current Streak',
          description: _streakDescription(stats),
          trailing: _StatBadge(
            value: '${stats.currentStreak}',
            unit: stats.currentStreak == 1 ? 'day' : 'days',
            isActive: stats.currentStreak >= 3,
          ),
        ),
        BeeSettingsRow(
          icon: Icons.mic_rounded,
          label: 'Total Recordings',
          description:
              'Average ${stats.averageWordsPerRecording.toStringAsFixed(0)} words per recording',
          trailing: _StatBadge(
            value: _formatNumber(stats.totalRecordings),
            unit: '',
          ),
        ),
        BeeSettingsRow(
          icon: Icons.equalizer_rounded,
          label: 'Longest Recording',
          description: _formatDuration(stats.longestRecordingSeconds),
          trailing: _StatBadge(
            value: _formatDuration(stats.longestRecordingSeconds),
            unit: '',
          ),
        ),
        BeeSettingsRow(
          icon: Icons.calendar_today_rounded,
          label: 'Active Days',
          description: stats.totalSessionDays <= 1
              ? 'Keep showing up to grow this'
              : 'Recording across ${stats.totalSessionDays} separate days',
          trailing: _StatBadge(
            value: '${stats.totalSessionDays}',
            unit: stats.totalSessionDays == 1 ? 'day' : 'days',
          ),
        ),
        BeeSettingsRow(
          icon: Icons.star_rounded,
          label: 'Best Day',
          description: _bestDayDescription(stats),
          showDivider: false,
          trailing: _StatBadge(
            value: _formatNumber(_bestDayWords(stats)),
            unit: 'words',
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Weekly Activity Chart
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildWeeklySection(BuildContext context) {
    final weeklyData = widget.statsService.getWeeklyData();
    final total = weeklyData.fold<int>(0, (a, b) => a + b);
    final maxVal = weeklyData.fold<int>(0, (a, b) => math.max(a, b));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: BeeGroupLabel(label: 'This Week')),
            Text(
              '$total words',
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            color: beeSurfaceHighest(context),
            borderRadius: BorderRadius.circular(kBeeRadiusMd),
            border: Border.all(
              color: beeBorder(context).withValues(alpha: 0.5),
            ),
          ),
          child: SizedBox(
            height: 72,
            child: CustomPaint(
              painter: _WeeklyBarPainter(
                data: weeklyData,
                maxValue: maxVal.toDouble(),
                barColor: beeYellow(context),
                dimColor: beeBorder(context),
                labelColor: beeTextMuted(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Formatting Helpers
  // ═════════════════════════════════════════════════════════════════════════

  String _streakDescription(UsageStats stats) {
    if (stats.currentStreak == 0) return 'Record today to start your streak';
    if (stats.currentStreak == 1) return 'Keep going — record again tomorrow';
    if (stats.currentStreak < 7) return 'Your best is ${stats.longestStreak} days';
    return 'Personal best: ${stats.longestStreak} days';
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (m) => ',',
        );
  }

  String _formatTimeSaved(double minutes) {
    if (minutes < 1) return '< 1 min of typing saved';
    if (minutes < 60) return '${minutes.round()} min of typing saved';
    final hours = minutes / 60;
    if (hours < 24) return '${hours.toStringAsFixed(1)}h of typing saved';
    final days = hours / 24;
    return '${days.toStringAsFixed(1)} days of typing saved';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m < 60) return '${m}m ${s}s';
    final h = m ~/ 60;
    final rm = m % 60;
    return '${h}h ${rm}m';
  }

  /// The single highest daily word count across the whole history.
  int _bestDayWords(UsageStats stats) {
    if (stats.dailyWordCount.isEmpty) return 0;
    return stats.dailyWordCount.values.fold<int>(
      0,
      (a, b) => a > b ? a : b,
    );
  }

  /// Human-readable label for the best day (prettiest day so far).
  String _bestDayDescription(UsageStats stats) {
    if (stats.dailyWordCount.isEmpty) return 'No recordings yet';
    String? bestKey;
    int best = -1;
    stats.dailyWordCount.forEach((key, v) {
      if (v > best) {
        best = v;
        bestKey = key;
      }
    });
    if (bestKey == null) return 'No recordings yet';
    try {
      final d = DateTime.parse(bestKey!);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return 'Your most active day';
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Stat Badge — the trailing value pill for BeeSettingsRow
// ═════════════════════════════════════════════════════════════════════════════

class _StatBadge extends StatelessWidget {
  final String value;
  final String unit;
  final bool isActive;

  const _StatBadge({
    required this.value,
    required this.unit,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isActive ? beeYellow(context) : beeText(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kBeeRadiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive) ...[
            Icon(
              Icons.local_fire_department_rounded,
              size: 12,
              color: accent,
            ),
            const SizedBox(width: 3),
          ],
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 3),
            Text(
              unit,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: beeTextMuted(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Weekly Bar Chart Painter
// ═════════════════════════════════════════════════════════════════════════════

class _WeeklyBarPainter extends CustomPainter {
  final List<int> data;
  final double maxValue;
  final Color barColor;
  final Color dimColor;
  final Color labelColor;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  _WeeklyBarPainter({
    required this.data,
    required this.maxValue,
    required this.barColor,
    required this.dimColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gap = 8.0;
    final barWidth = (size.width - gap * 6) / 7;
    final labelHeight = 14.0;
    final chartHeight = size.height - labelHeight;

    for (int i = 0; i < 7; i++) {
      final x = i * (barWidth + gap);
      final value = maxValue == 0 ? 0.0 : data[i] / maxValue;
      final barHeight = math.max(value * (chartHeight - 4), 2.0);
      final y = chartHeight - barHeight;

      // Bar
      final paint = Paint()
        ..color = value > 0
            ? barColor.withValues(alpha: 0.55 + value * 0.45)
            : dimColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(rrect, paint);

      // Day label
      final tp = TextPainter(
        text: TextSpan(
          text: _labels[i],
          style: TextStyle(color: labelColor, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelX = x + (barWidth - tp.width) / 2;
      tp.paint(canvas, Offset(labelX, chartHeight + 1));
    }
  }

  @override
  bool shouldRepaint(covariant _WeeklyBarPainter old) =>
      data != old.data || maxValue != old.maxValue;
}
