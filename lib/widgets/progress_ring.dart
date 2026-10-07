import 'package:flutter/material.dart';

/// 朱红进度环：一段圆环跑道 + 从12点开始的进度弧（CustomPaint，无依赖）。
/// 首页统计行的小环与成就统计页的大图共用。
class ProgressRing extends StatelessWidget {
  /// 0.0 – 1.0。
  final double progress;
  final double size;
  final double strokeWidth;

  /// 环弧颜色；null → 跟随主题主色（深浅两版 ColorScheme 自适应）。
  final Color? color;

  /// 环跑道颜色；null → 跟随主题进度槽色。
  final Color? track;

  /// 居中显示在环内的内容（百分比、x/总 等）。
  final Widget? child;

  const ProgressRing({
    super.key,
    required this.progress,
    required this.size,
    required this.child,
    this.strokeWidth = 6,
    this.color,
    this.track,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.clamp(0.0, 1.0),
          color: color ?? scheme.primary,
          track: track ?? scheme.surfaceContainerHighest,
          strokeWidth: strokeWidth,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  final double strokeWidth;

  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(strokeWidth / 2);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arc, 0, 6.283185307179586, false, trackPaint);
    if (progress <= 0) return;
    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      arc,
      -1.5707963267948966,
      6.283185307179586 * progress,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      track != oldDelegate.track ||
      strokeWidth != oldDelegate.strokeWidth;
}
