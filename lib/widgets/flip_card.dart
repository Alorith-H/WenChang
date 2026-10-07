import 'package:flutter/material.dart';

/// A cross-fade card (400ms, easeInOut): tapping swaps the faces with a
/// visible Fade + a slight 10px slide — the outgoing face drifts aside while
/// the incoming one settles into place — and no 3D rotation.
///
/// Direction follows the flip: going to the back, the front fades out toward
/// the left (-10px) while the back fades in from the right (+10px); flipping
/// back reverses both (front returns from the left, back exits to the right).
///
/// Both faces stay laid out in the tree for the whole animation (and for
/// the card's whole life), so the back face keeps its scroll position
/// across flips and swapping opacity can never flicker or jump the layout.
/// Each face is only hit-testable while it is the dominant one, so hidden
/// buttons can never be pressed through the other side.
class FlipCard extends StatefulWidget {
  final bool flipped;
  final Widget front;
  final Widget back;
  final Duration duration;
  final VoidCallback? onTap;

  /// How far (in px) a face slides while fading — kept small so the motion
  /// reads as part of the fade, not as a push.
  static const double slideDistance = 10;

  const FlipCard({
    super.key,
    required this.flipped,
    required this.front,
    required this.back,
    this.duration = const Duration(milliseconds: 400),
    this.onTap,
  });

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.flipped ? 1 : 0,
  );

  @override
  void didUpdateWidget(FlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new duration (e.g. study mode's short auto-open fade) only takes
    // effect while idle, so a running animation is never jerked around.
    if (widget.duration != oldWidget.duration && !_controller.isAnimating) {
      _controller.duration = widget.duration;
    }
    if (widget.flipped == oldWidget.flipped) return;
    final target = widget.flipped ? 1.0 : 0.0;
    // Scale by the remaining distance so tapping mid-animation keeps a
    // constant perceived speed instead of restarting the full duration.
    final remaining = (target - _controller.value).abs();
    final ms = (widget.duration.inMilliseconds * remaining).round();
    if (ms <= 0) {
      _controller.value = target;
    } else {
      _controller.animateTo(
        target,
        duration: Duration(milliseconds: ms),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        // builder 只读 _controller.value 并重建 Opacity/Transform 这几个
        // 纯 RenderObject 属性节点；widget.front/back 引用逐帧不变，
        // face 子树不 rebuild、不 relayout。
        builder: (context, _) {
          final t = _controller.value;
          // Past the midpoint the incoming face owns the interaction.
          final showBack = t >= 0.5;
          final slide = FlipCard.slideDistance;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Incoming face underneath: fades in from the right while it
              // settles (from the left when the flip is undone).
              // RepaintBoundary 在动画节点（Opacity/Transform）内侧、face
              // 外侧：face 的位图只栅格化一次，动画每帧只对缓存纹理做
              // 透明度混合——满文字面不再逐帧重绘（掉帧修复）。
              IgnorePointer(
                ignoring: !showBack,
                child: Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(slide * (1 - t), 0),
                    child: RepaintBoundary(
                      key: const ValueKey<String>('flip-back-boundary'),
                      child: widget.back,
                    ),
                  ),
                ),
              ),
              // Outgoing face: fades out drifting left (right on the way
              // back), so the swap is visible in both directions.
              IgnorePointer(
                ignoring: showBack,
                child: Opacity(
                  opacity: 1 - t,
                  child: Transform.translate(
                    offset: Offset(-slide * t, 0),
                    child: RepaintBoundary(
                      key: const ValueKey<String>('flip-front-boundary'),
                      child: widget.front,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
