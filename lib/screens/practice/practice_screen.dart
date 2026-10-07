import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/models.dart';
import '../../services/content_overrides.dart';
import '../../services/srs_logic.dart';
import '../../services/srs_service.dart';
import '../../widgets/answer_spans.dart';
import '../../widgets/flip_card.dart';
import 'practice_history_screen.dart';

/// 习题模式 · 答题页：所选**小节**（选题页勾选的那些板块）的全部题目
/// 随机打乱，顶部进度 n/N。
///
/// 每题点按翻面看答案，然后**左滑 = 不会、右滑 = 会**（只有这两个方向，
/// 背面另有两个按钮备选）。出场/入场沿用复习页 6a 的衔接：过阈值后当前
/// 卡沿滑动方向飞出 + 淡出（250ms），下一张淡入 + 轻微上移归位（250ms）。
/// 中途退出（返回键）与答完都会把成绩写进 SharedPreferences
/// `practice_history`（见 [PracticeRecord]）。
///
/// **完全独立于 SRS**：只统计会/不会，不写复习队列、不动每日统计与
/// 打卡，也不影响学习/复习的到期计算。
class PracticeScreen extends StatefulWidget {
  /// 本次刷题的小节（选题页勾选的那些板块，跨章保持勾选顺序）。
  final List<Section> sections;

  const PracticeScreen({super.key, required this.sections});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen>
    with TickerProviderStateMixin {
  List<Question> _queue = const [];
  int _index = 0;
  int _right = 0;
  final List<String> _wrongIds = <String>[];
  bool _flipped = false;
  bool _initialized = false;
  bool _grading = false;

  /// 本轮成绩是否已落盘（完成时写入；中途退出写「已完成部分」）。
  bool _recorded = false;

  // ------------------------------------------------------------ 手势评级
  //
  // 与复习页同一套状态机（6a），只是方向只有两个、不写 SRS：
  // 翻开（过半）→ 跟手拖动 `_drag` → 松手过 120px 沿滑动方向飞出 +
  // 淡出（250ms）→ 计成绩换题 → 新卡淡入 + 轻微上移归位（250ms）；
  // 不过阈值弹性回位（不淡出）。按钮评级 = 原地淡出换卡（250ms）。

  /// 评级阈值（px）。
  static const double _swipeThreshold = 120;

  /// FlipCard 翻面 400ms 动画的中点：过半后答案面才可交互。
  static const Duration _flipHalf = Duration(milliseconds: 200);

  /// 出场：沿滑动方向飞出 + 淡出的时长。
  static const Duration _exitDuration = Duration(milliseconds: 250);

  /// 下一张卡片进场：淡入 + 轻微上移归位的时长。
  static const Duration _enterDuration = Duration(milliseconds: 250);

  /// 进场时卡片从下方多少 px 归位。
  static const double _enterRise = 14;

  late final AnimationController _releaseAnim = AnimationController(
    vsync: this,
    duration: _exitDuration,
  );

  /// 进场动画（0 = 刚换题、完全透明；1 = 归位）。
  late final AnimationController _enterAnim = AnimationController(
    vsync: this,
    duration: _enterDuration,
    value: 1,
  );
  Timer? _flipGateTimer;

  Offset _drag = Offset.zero;
  Offset _releaseFrom = Offset.zero;
  Offset _releaseTo = Offset.zero;
  Curve _releaseCurve = Curves.easeOutBack;
  bool _releasing = false;
  bool _fadingOut = false;
  bool _swiping = false;
  String? _swipeId;
  Offset _lastPointer = Offset.zero;
  bool _flipGateOpen = false;

  /// 纠错覆盖服务（didChangeDependencies 里取）。
  ContentOverrides? _overrides;

  /// 题库/记录服务（didChangeDependencies 里取，落盘时不再依赖 context）。
  SrsService? _srs;

  /// 手势接管的总开关：翻开看到答案、不在评分、不在飞出/回弹。
  bool get _canSwipe =>
      _flipped &&
      _flipGateOpen &&
      !_grading &&
      !_releasing &&
      _index < _queue.length;

  @override
  void dispose() {
    _overrides?.removeListener(_onOverridesChanged);
    _flipGateTimer?.cancel();
    _releaseAnim.dispose();
    _enterAnim.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final scope = AppScope.of(context);
    _srs = scope.srs;
    _overrides = scope.overrides;
    _overrides!.addListener(_onOverridesChanged);

    // 所选小节的全部题目按勾选顺序收集后随机打乱；按题 id 去重。
    final seen = <String>{};
    final queue = <Question>[];
    for (final section in widget.sections) {
      final qs = scope.data.questionsBySec[section.id] ?? const [];
      for (final q in qs) {
        if (q.id.isNotEmpty && !seen.add(q.id)) continue;
        queue.add(q);
      }
    }
    queue.shuffle();
    _queue = queue;
  }

  /// 纠错保存后立即重建（当前卡显示覆盖后的题干/答案）。
  void _onOverridesChanged() {
    if (mounted) setState(() {});
  }

  /// 中途退出：把「已完成部分」落盘（答完时已写过则跳过）。
  void _savePartialRecord() {
    if (_recorded || _index <= 0) return;
    _recorded = true;
    unawaited(_persistRecord());
  }

  Future<void> _persistRecord() async {
    final srs = _srs;
    if (srs == null) return;
    await srs.addPracticeRecord(
      PracticeRecord(
        date: formatDay(DateTime.now()),
        total: _index,
        right: _right,
        wrongQids: List<String>.of(_wrongIds),
      ),
    );
  }

  /// 轻点翻面；翻到背面时先关手势闸门，400ms 动画过半（答案显形）再开。
  void _toggleFlip() {
    if (_releasing || _grading) return;
    _flipGateTimer?.cancel();
    _flipGateTimer = null;
    setState(() {
      _flipped = !_flipped;
      _flipGateOpen = false;
    });
    if (!_flipped) return;
    _flipGateTimer = Timer(_flipHalf, () {
      if (!mounted) return;
      setState(() => _flipGateOpen = true);
    });
  }

  void _onSwipeStart(DragStartDetails details) {
    if (!_canSwipe) return;
    _swiping = true;
    _swipeId = _queue[_index].id;
    _lastPointer = details.localPosition;
    setState(() => _drag = Offset.zero);
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    if (!_swiping) return;
    if (!_canSwipe || _swipeId != _queue[_index].id) {
      _swiping = false;
      _swipeId = null;
      setState(() => _drag = Offset.zero);
      return;
    }
    final delta = details.localPosition - _lastPointer;
    _lastPointer = details.localPosition;
    if (delta == Offset.zero) return;
    setState(() => _drag += delta);
  }

  void _onSwipeEnd(DragEndDetails details) => _settleGesture();

  void _onSwipeCancel() => _settleGesture();

  /// 松手：主轴水平且过 120px 才评级（右 = 会、左 = 不会），其余回弹。
  void _settleGesture() {
    if (!_swiping) return;
    _swiping = false;
    final stale =
        _swipeId == null ||
        _index >= _queue.length ||
        _queue[_index].id != _swipeId;
    _swipeId = null;
    final drag = _drag;
    if (stale || !_canSwipe) {
      setState(() => _drag = Offset.zero);
      return;
    }

    bool? known;
    if (drag.dx.abs() >= drag.dy.abs() && drag.dx.abs() >= _swipeThreshold) {
      known = drag.dx > 0;
    }
    if (known == null) {
      unawaited(_springBack());
    } else {
      unawaited(_flyOut(known));
    }
  }

  /// 不过阈值：easeOutBack 轻微过冲的弹性回位（不淡出）。
  Future<void> _springBack() async {
    _releaseCurve = Curves.easeOutBack;
    _releaseAnim.duration = const Duration(milliseconds: 300);
    setState(() {
      _releasing = true;
      _fadingOut = false;
      _releaseFrom = _drag;
      _releaseTo = Offset.zero;
    });
    await _releaseAnim.forward(from: 0);
    if (!mounted) return;
    _releaseAnim.value = 0;
    setState(() {
      _releasing = false;
      _drag = Offset.zero;
    });
  }

  /// 过阈值：当前卡沿滑动方向飞出并同步淡出（250ms）→ 计成绩换题 →
  /// 下一张卡片淡入 + 轻微上移归位（250ms）。
  Future<void> _flyOut(bool known) async {
    final size = MediaQuery.sizeOf(context);
    final drag = _drag;
    _releaseCurve = Curves.easeIn;
    _releaseAnim.duration = _exitDuration;
    setState(() {
      _releasing = true;
      _fadingOut = true;
      _releaseFrom = drag;
      _releaseTo = Offset(drag.dx > 0 ? size.width * 1.3 : -size.width * 1.3, drag.dy);
    });
    await _releaseAnim.forward(from: 0);
    if (!mounted) return;
    await _commit(known);
  }

  /// 按钮评级：当前卡原地淡出（250ms）→ 换题 → 新卡淡入归位。
  Future<void> _gradeByButton(bool known) async {
    if (_grading || _releasing || _index >= _queue.length) return;
    _grading = true;
    _releaseCurve = Curves.easeIn;
    _releaseAnim.duration = _exitDuration;
    setState(() {
      _releasing = true;
      _fadingOut = true;
      _releaseFrom = Offset.zero;
      _releaseTo = Offset.zero;
    });
    await _releaseAnim.forward(from: 0);
    if (!mounted) return;
    await _commit(known);
    if (!mounted) return;
    setState(() => _grading = false);
  }

  /// 记一次成绩（右滑/「会」= 答对，左滑/「不会」= 错题），清干净状态
  /// 换到下一题并启动新卡进场；答完最后一题立即把整轮成绩落盘。
  Future<void> _commit(bool known) async {
    if (_index >= _queue.length) return;
    final question = _queue[_index];
    if (known) {
      _right += 1;
    } else if (question.id.isNotEmpty && !_wrongIds.contains(question.id)) {
      _wrongIds.add(question.id);
    }

    _flipGateTimer?.cancel();
    _flipGateTimer = null;
    if (_releaseAnim.value != 0) _releaseAnim.value = 0;
    setState(() {
      _index += 1;
      _flipped = false;
      _flipGateOpen = false;
      _releasing = false;
      _fadingOut = false;
      _swiping = false;
      _swipeId = null;
      _drag = Offset.zero;
    });
    _enterAnim.forward(from: 0);

    if (_index >= _queue.length && !_recorded) {
      _recorded = true;
      unawaited(_persistRecord());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_queue.isEmpty) return const _EmptyQueueView();
    if (_index >= _queue.length) return _buildResult(context);

    final scheme = Theme.of(context).colorScheme;
    final progress = _index / _queue.length;

    return PopScope<void>(
      // 返回键 / 侧滑退出：已完成部分立刻落盘（答完则已写过，跳过）。
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _savePartialRecord();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('习题模式')),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_index + 1} / ${_queue.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 2.5,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_releaseAnim, _enterAnim]),
                    builder: (context, _) {
                      final offset = _releasing
                          ? Offset.lerp(
                              _releaseFrom,
                              _releaseTo,
                              _releaseCurve.transform(_releaseAnim.value),
                            )!
                          : _drag;
                      final enterT = _enterAnim.value;
                      final enterOffset = Offset(0, _enterRise * (1 - enterT));
                      final exitT = _releasing && _fadingOut
                          ? _releaseAnim.value
                          : 0.0;
                      final opacity = (enterT * (1 - exitT)).clamp(0.0, 1.0);
                      final angle =
                          (offset.dx / 320).clamp(-1.0, 1.0) *
                          (6 * math.pi / 180);
                      return Opacity(
                        opacity: opacity,
                        child: Transform.translate(
                          offset: offset + enterOffset,
                          child: Transform.rotate(
                            angle: angle,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // 只有横向两个方向：右 = 会、左 = 不会。
                                // RepaintBoundary 在动画节点（Opacity/Transform）
                                // 内侧、满文本卡外侧：飞出/跟手期间整卡位图只
                                // 栅格化一次，每帧只做变换+透明度合成（掉帧修复）。
                                RepaintBoundary(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onHorizontalDragStart: _onSwipeStart,
                                    onHorizontalDragUpdate: _onSwipeUpdate,
                                    onHorizontalDragEnd: _onSwipeEnd,
                                    onHorizontalDragCancel: _onSwipeCancel,
                                    child: FlipCard(
                                      key: ValueKey<String>(_queue[_index].id),
                                      flipped: _flipped,
                                      onTap: _toggleFlip,
                                      front: _PracticeFront(
                                        question: _queue[_index],
                                      ),
                                      back: _PracticeBack(
                                        question: _queue[_index],
                                        onGrade: _gradeByButton,
                                        enabled: !_grading && !_releasing,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: _SwipeHintLayer(offset: offset),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 结果页：本次题数、答对数与正确率（right/total）、错题数；
  /// 「再练一组」同章重开，「返回」回选题页，另可进「练习记录」。
  Widget _buildResult(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _queue.length;
    final wrong = total - _right;
    final percent = total > 0 ? ((_right / total) * 100).round() : 0;

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _savePartialRecord(); // _recorded 已 true，不会重复写
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('练习完成'),
          actions: [
            IconButton(
              icon: const Icon(Icons.history_rounded),
              tooltip: '练习记录',
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PracticeHistoryScreen(),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 40,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '本次 $total 题',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _ResultStat(value: '$_right', label: '答对', highlight: true),
                      _ResultHairline(color: scheme.outlineVariant),
                      _ResultStat(value: '$percent%', label: '正确率', highlight: false),
                      _ResultHairline(color: scheme.outlineVariant),
                      _ResultStat(value: '$wrong', label: '错题', highlight: false),
                    ],
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 14,
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => PracticeScreen(
                          sections: widget.sections,
                        ),
                      ),
                    ),
                    child: const Text('再练一组'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 14,
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PracticeHistoryScreen(),
                      ),
                    ),
                    child: const Text('练习记录'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 卡片正面：题干（含 ____）大号居中偏上。
class _PracticeFront extends StatelessWidget {
  final Question question;

  const _PracticeFront({required this.question});

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
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text(
            '习 题',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              letterSpacing: 6,
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Text(
                  question.q.isEmpty ? '（题目缺失）' : question.q,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 64,
            child: Center(
              child: Text(
                '轻点翻面查看答案 · 翻开后左滑不会、右滑会',
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片背面：完整句子 + 高亮答案 +「不会 / 会」两个按钮备选。
class _PracticeBack extends StatelessWidget {
  final Question question;
  final Future<void> Function(bool) onGrade;
  final bool enabled;

  const _PracticeBack({
    required this.question,
    required this.onGrade,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseStyle = const TextStyle(fontSize: 18, height: 1.8);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Text(
              '答 案',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
                letterSpacing: 6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: baseStyle.copyWith(color: scheme.onSurface),
                      children: answerSpans(context, question),
                    ),
                  ),
                  if (question.src.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      '—— ${question.src}',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _GradePill(
                  icon: Icons.close_rounded,
                  label: '不会',
                  color: const Color(0xFFB03A2E),
                  onPressed: enabled ? () => onGrade(false) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GradePill(
                  icon: Icons.check_rounded,
                  label: '会',
                  color: const Color(0xFF3E7A52),
                  onPressed: enabled ? () => onGrade(true) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 评级药丸：整颗带色 + 图标，评分进行中降透明度禁用。
class _GradePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _GradePill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: SizedBox(
            height: 46,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 跟手浮出的评级提示层：右滑绿色 ✓ 会、左滑红色 ✗ 不会，透明度随
/// 位移（对齐 120px 阈值）驱动，回位时自动淡出。只有这两个方向。
class _SwipeHintLayer extends StatelessWidget {
  final Offset offset;

  const _SwipeHintLayer({required this.offset});

  static const _know = Color(0xFF3E7A52);
  static const _dontKnow = Color(0xFFB03A2E);

  @override
  Widget build(BuildContext context) {
    final dx = offset.dx;
    final dy = offset.dy;
    if (dx.abs() < dy.abs() || dx.abs() <= 8) return const SizedBox.shrink();

    final color = dx > 0 ? _know : _dontKnow;
    final icon = dx > 0 ? Icons.check_rounded : Icons.close_rounded;
    final label = dx > 0 ? '会' : '不会';
    final badgeAlign = dx > 0 ? Alignment.centerRight : Alignment.centerLeft;
    final badgePadding = EdgeInsets.only(
      left: dx > 0 ? 0 : 26,
      right: dx > 0 ? 26 : 0,
    );
    final gradientBegin = dx > 0 ? Alignment.centerLeft : Alignment.centerRight;
    final gradientEnd = dx > 0 ? Alignment.centerRight : Alignment.centerLeft;

    final t = (offset.distance / 120).clamp(0.0, 1.0);
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: gradientBegin,
              end: gradientEnd,
              colors: [
                color.withValues(alpha: 0.55 * t),
                color.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.72],
            ),
          ),
          alignment: badgeAlign,
          child: Padding(
            padding: badgePadding,
            child: Opacity(
              opacity: (0.2 + 0.8 * t).clamp(0.0, 1.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 30, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 6)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 结果页统计数字：大数 + 小灰标签（答对项用主色点睛）。
class _ResultStat extends StatelessWidget {
  final String value;
  final String label;
  final bool highlight;

  const _ResultStat({
    required this.value,
    required this.label,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: highlight ? scheme.primary : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ResultHairline extends StatelessWidget {
  final Color color;

  const _ResultHairline({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: color,
    );
  }
}

/// 所选章节没有一道题（数据异常时的兜底页）。
class _EmptyQueueView extends StatelessWidget {
  const _EmptyQueueView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('习题模式')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.quiz_outlined, size: 56, color: scheme.outline),
                const SizedBox(height: 16),
                const Text(
                  '所选小节暂无题目',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  '换几个小节再试试',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
