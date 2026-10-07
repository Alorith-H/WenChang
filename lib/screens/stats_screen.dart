import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../services/srs_service.dart';
import '../widgets/font_scale_sheet.dart';
import '../widgets/progress_ring.dart';

/// 成就统计页 —— 首页右上角入口。纸墨风格：
/// 进度环大图 + 已标熟/复习中/未见面分布 → 近 7 天复习量与熟练率 →
/// 连续打卡天数 + 最近 7 天每日作答柱状图（CustomPaint，无依赖）。
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final srs = scope.srs;
    final data = scope.data;

    return Scaffold(
      appBar: AppBar(
        title: const Text('成就统计'),
        actions: [
          IconButton(
            icon: const Icon(Icons.format_size_rounded),
            tooltip: '字号',
            onPressed: () => showFontScaleSheet(context, srs),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: srs,
          builder: (context, _) {
            final dist = srs.distributionOf(
              data.questions.map((q) => q.id),
            );
            final week = srs.dailyTotals(7);
            var weekAnswers = 0;
            var weekGood = 0;
            for (final d in week) {
              weekAnswers += d.answers;
              weekGood += d.good;
            }
            final streak = srs.streak();

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _DistributionCard(dist: dist, total: data.questions.length),
                const SizedBox(height: 16),
                _WeekCard(answers: weekAnswers, good: weekGood),
                const SizedBox(height: 16),
                _StreakCard(streak: streak, week: week),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 纸片卡片：与首页主入口卡同款的纸色 + 一层浮起。
class _PaperCard extends StatelessWidget {
  final Widget child;

  const _PaperCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String text;

  const _CardTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 3,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// 进度环大图 + 三色分布（已标熟 / 复习中 / 未见面）。
class _DistributionCard extends StatelessWidget {
  final SrsDistribution dist;
  final int total;

  const _DistributionCard({required this.dist, required this.total});

  static const matureColor = Color(0xFF9B3A2C);
  static const reviewingColor = Color(0xFF9A6B12);
  static const unseenColor = Color(0xFFB4A992);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = total > 0 ? (dist.mature / total).clamp(0.0, 1.0) : 0.0;
    final percent = total > 0 ? '${(progress * 100).round()}%' : '—';

    return _PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('题库掌握'),
          const SizedBox(height: 16),
          Row(
            children: [
              ProgressRing(
                progress: progress,
                size: 116,
                strokeWidth: 10,
                color: matureColor,
                track: scheme.surfaceContainerHighest,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      percent,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        color: matureColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '已标熟',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DistRow(
                      color: matureColor,
                      label: '已标熟',
                      count: dist.mature,
                      total: total,
                    ),
                    const SizedBox(height: 10),
                    _DistRow(
                      color: reviewingColor,
                      label: '复习中',
                      count: dist.reviewing,
                      total: total,
                    ),
                    const SizedBox(height: 10),
                    _DistRow(
                      color: unseenColor,
                      label: '未见面',
                      count: dist.unseen,
                      total: total,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 三色比例条：与上面的数字同一口径。
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (dist.mature > 0)
                    Expanded(flex: dist.mature, child: _BarFill(matureColor)),
                  if (dist.reviewing > 0)
                    Expanded(
                      flex: dist.reviewing,
                      child: _BarFill(reviewingColor),
                    ),
                  if (dist.unseen > 0)
                    Expanded(flex: dist.unseen, child: _BarFill(unseenColor)),
                  if (dist.total == 0)
                    Expanded(child: _BarFill(scheme.surfaceContainerHighest)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarFill extends StatelessWidget {
  final Color color;

  const _BarFill(this.color);

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: color, child: const SizedBox.expand());
}

class _DistRow extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  final int total;

  const _DistRow({
    required this.color,
    required this.label,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = total > 0 ? '${(count * 100 / total).round()}%' : '0%';
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
        Text(
          '$count',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 4),
        Text(
          pct,
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 本周（近 7 天，含今天）的复习量与熟练率。
class _WeekCard extends StatelessWidget {
  final int answers;
  final int good;

  const _WeekCard({required this.answers, required this.good});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rate = answers > 0 ? '${(good * 100 / answers).round()}%' : '—';
    return _PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('本周战绩'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _BigStat(value: '$answers', unit: '题', label: '本周复习量'),
              ),
              Container(
                width: 1,
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: scheme.outlineVariant,
              ),
              Expanded(
                child: _BigStat(value: rate, unit: '', label: '本周熟练率'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '口径：近 7 天（含今天）作答 $answers 题，其中熟练 $good 题',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  final String value;
  final String unit;
  final String label;

  const _BigStat({
    required this.value,
    required this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: scheme.primary,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 连续打卡天数 + 最近 7 天的每日作答小柱状图。
class _StreakCard extends StatelessWidget {
  final int streak;
  final List<DailyTotal> week;

  const _StreakCard({required this.streak, required this.week});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const fire = Color(0xFFC2662B);
    return _PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('连续打卡'),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                size: 26,
                color: fire,
              ),
              const SizedBox(width: 8),
              Text(
                '连续 $streak 天',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  streak > 0
                      ? '每天答一题或翻一张卡片，就不间断'
                      : '今天还没打卡，去翻一张卡片吧',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '最近 7 天作答',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            width: double.infinity,
            child: CustomPaint(
              painter: _WeekBarPainter(
                values: [for (final d in week) d.answers],
                todayIndex: week.length - 1,
                barColor: scheme.primary,
                trackColor: scheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final d in week)
                Expanded(
                  child: Center(
                    child: Text(
                      _shortDay(d.day),
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// `2026-10-07` → `10/7`
  static String _shortDay(String day) {
    final parts = day.split('-');
    if (parts.length != 3) return day;
    final month = parts[1].startsWith('0') ? parts[1].substring(1) : parts[1];
    final dom = parts[2].startsWith('0') ? parts[2].substring(1) : parts[2];
    return '$month/$dom';
  }
}

/// 最近 N 天的作答柱状图：圆角柱、今天实色，零值留一个矮底座。
class _WeekBarPainter extends CustomPainter {
  final List<int> values;
  final int todayIndex;
  final Color barColor;
  final Color trackColor;

  const _WeekBarPainter({
    required this.values,
    required this.todayIndex,
    required this.barColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final slot = size.width / values.length;
    final barWidth = slot * 0.52;
    final baseline = size.height - 2;
    final maxBar = size.height - 20; // 柱顶上方留给数字
    var max = 1;
    for (final v in values) {
      if (v > max) max = v;
    }

    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final center = slot * i + slot / 2;
      final height = v > 0 ? (v / max * maxBar).clamp(6.0, maxBar) : 4.0;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          center - barWidth / 2,
          baseline - height,
          center + barWidth / 2,
          baseline,
        ),
        Radius.circular(v > 0 ? 3 : 2),
      );
      final paint = Paint()
        ..color = v > 0
            ? (i == todayIndex ? barColor : barColor.withValues(alpha: 0.45))
            : trackColor;
      canvas.drawRRect(rect, paint);

      if (v > 0) {
        // 柱顶上方的小数字。
        final tp = TextPainter(
          text: TextSpan(
            text: '$v',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: i == todayIndex
                  ? barColor
                  : barColor.withValues(alpha: 0.65),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(center - tp.width / 2, baseline - height - tp.height - 3),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WeekBarPainter oldDelegate) =>
      oldDelegate.values.length != values.length ||
      oldDelegate.todayIndex != todayIndex ||
      oldDelegate.barColor != barColor ||
      oldDelegate.trackColor != trackColor ||
      !_listEquals(oldDelegate.values, values);

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
