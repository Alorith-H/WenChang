import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/models.dart';
import '../../services/content_overrides.dart';
import '../../services/srs_logic.dart';
import '../../services/srs_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/answer_spans.dart';
import '../../widgets/correction_sheet.dart';
import '../../widgets/flip_card.dart';
import '../learn/chapter_list_screen.dart';

/// 复习模式：填空卡片 + 遗忘曲线队列。
///
/// 进入时若存在未完成的复习会话 → 原样恢复（同一份乱序队列、同一进度）；
/// 否则取今天到期的题目生成新会话 —— 是否随机打乱由设置里的「复习随机」
/// 决定（开=打乱，关=按到期顺序）。会话持久化在 [SrsService]
/// （SharedPreferences `{ids, index}`），答题推进进度，答完最后一题自动
/// 完成并删除存档；中途退出（返回键/杀进程）再进都接上一次的状态。
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen>
    with TickerProviderStateMixin {
  List<Question> _queue = const [];
  int _index = 0;

  /// 本会话已答过的题 id（去重口径）：完成度与结束页统计都按它汇报 ——
  /// 队尾重排的重复作答每题只算一次。恢复会话时用前缀（已答部分）播种。
  final Set<String> _answeredIds = <String>{};

  /// 开局时队列非空 —— 标熟可能把队列删空，那也算一轮结束（小结页），
  /// 不能落到「今天没有要复习的卡片」的空队列页。
  bool _startedWithCards = false;

  bool _flipped = false;
  bool _initialized = false;
  bool _grading = false;

  // ------------------------------------------------------------ 手势评级
  //
  // 状态机：翻开（过半）→ 跟手拖动 `_drag` → 松手：过 120px 阈值就
  // 沿滑动方向飞出并淡出（约 250ms）再评级换题，新卡淡入 + 轻微上移
  // 归位；不过阈值则弹性回位（不淡出）。按钮评级 = 原地淡出换卡。
  // `_releasing` 期间新手势一律不接管，手势还记录起始题 id
  // （`_swipeId`），换题后旧手指的事件直接作废 —— 连续滑动不会串到下一题。

  /// 评级阈值（px），三个方向共用。
  static const double _swipeThreshold = 120;

  /// FlipCard 翻面 400ms 动画的中点：过半后答案面才可交互，手势同步等过半。
  static const Duration _flipHalf = Duration(milliseconds: 200);

  /// 手势评级出场：当前卡沿滑动方向飞出 + 淡出的时长。
  static const Duration _flyDuration = Duration(milliseconds: 250);

  /// 按钮评级出场：原地淡出（不飞远）的时长。
  static const Duration _buttonFadeDuration = Duration(milliseconds: 200);

  /// 下一张卡片进场：淡入 + 轻微上移归位的时长。
  static const Duration _enterDuration = Duration(milliseconds: 250);

  /// 进场时卡片从下方多少 px 归位（轻微上移）。
  static const double _enterRise = 14;

  late final AnimationController _releaseAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// 进场动画（0 = 刚换题、完全透明；1 = 归位）。
  late final AnimationController _enterAnim = AnimationController(
    vsync: this,
    duration: _enterDuration,
    value: 1,
  );
  final ScrollController _answerScroll = ScrollController();
  Timer? _flipGateTimer;

  /// 手指拖动的实时位移（跟手，无动画）。
  Offset _drag = Offset.zero;

  /// 回弹 / 飞出动画的起止与曲线。
  Offset _releaseFrom = Offset.zero;
  Offset _releaseTo = Offset.zero;
  Curve _releaseCurve = Curves.easeOutBack;

  /// 飞出 / 回弹进行中（此时不接受新手势）。
  bool _releasing = false;

  /// 出场阶段是否同时淡出（手势飞出与按钮原地淡出都为 true，回弹为 false）。
  bool _fadingOut = false;

  /// 一根手指正由本手势接管。
  bool _swiping = false;

  /// 本次手势起始的题 id —— 中途换题则作废，防串题。
  String? _swipeId;

  /// 上一次指针位置，用来拼出完整的 2D delta。
  Offset _lastPointer = Offset.zero;

  /// 翻面动画已过半（答案可见）。
  bool _flipGateOpen = false;

  /// 纠错覆盖服务（didChangeDependencies 里取，dispose 时摘掉监听）。
  ContentOverrides? _overrides;

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
    _answerScroll.dispose();
    super.dispose();
  }

  /// 纠错保存后立即重建：当前卡片的题干/答案已是覆盖后的新文本。
  void _onOverridesChanged() {
    if (mounted) setState(() {});
  }

  /// ✎ 纠错：编辑**当前题目**的题干 + 答案，保存后当前页立即生效。
  Future<void> _openCorrection() async {
    if (_index >= _queue.length) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showQuestionCorrectionSheet(
      context,
      _queue[_index],
    );
    if (saved && mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  /// 标熟按钮：二次确认后把**当前题**直接置为成熟态（走 SrsService
  /// 的正规通道 [SrsService.markMature]，持久化，从此不进复习队列），
  /// 并把该题从会话队列移除 —— 不闪退，原地下标直接跳到下一题。
  Future<void> _markMature() async {
    if (_grading || _releasing || _index >= _queue.length) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('标熟'),
        content: const Text('标记为已熟？之后不再进入复习'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('标熟'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final id = _queue[_index].id;
    // 正规通道：置成熟态 + 从会话队列移除，一起持久化。
    await AppScope.of(context).srs.markMature(id);
    if (!mounted) return;

    // 本地队列镜像同一套移除逻辑（纯函数，含重排副本与下标校正），
    // 再按同顺序把 id 映射回题目对象。
    final idRemoval = removeFromQueue(
      [for (final q in _queue) q.id],
      _index,
      id,
    );
    final byId = <String, Question>{for (final q in _queue) q.id: q};
    _flipGateTimer?.cancel();
    _flipGateTimer = null;
    if (_releaseAnim.value != 0) _releaseAnim.value = 0;
    setState(() {
      _queue = [for (final rid in idRemoval.ids) byId[rid]!];
      _index = idRemoval.index;
      _flipped = false;
      _flipGateOpen = false;
      _releasing = false;
      _fadingOut = false;
      _swiping = false;
      _swipeId = null;
      _drag = Offset.zero;
    });
    // 下一张：淡入 + 轻微上移归位（队列删空则自然落入小结页）。
    _enterAnim.forward(from: 0);
  }

  /// 轻点翻面；翻到背面时先关手势闸门，400ms 动画过半（答案显形）再开。
  /// 出场 / 评级进行中不接受翻面，避免出场卡中途翻转跳变。
  void _toggleFlip() {
    if (_releasing || _grading) return;
    if (_flipGateTimer != null) {
      _flipGateTimer!.cancel();
      _flipGateTimer = null;
    }
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
      // 中途翻面 / 被按钮抢先评分：丢弃这次手势。
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

  /// 松手：主轴位移过 120px 才评级（右=熟练、左=忘记、上=生疏），
  /// 其余（含下拉）一律弹性回位。
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

    Grade? grade;
    if (drag.dx.abs() >= drag.dy.abs()) {
      if (drag.dx.abs() >= _swipeThreshold) {
        grade = drag.dx > 0 ? Grade.good : Grade.again;
      }
    } else if (drag.dy < 0 && -drag.dy >= _swipeThreshold) {
      grade = Grade.hard;
    }

    if (grade == null) {
      unawaited(_springBack());
    } else {
      unawaited(_flyOut(grade));
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

  /// 过阈值：当前卡沿滑动方向飞出并同步淡出（约 250ms）→ 评级换题 →
  /// 下一张卡片淡入 + 轻微上移归位。
  Future<void> _flyOut(Grade grade) async {
    final size = MediaQuery.sizeOf(context);
    final drag = _drag;
    _releaseCurve = Curves.easeIn;
    _releaseAnim.duration = _flyDuration;
    setState(() {
      _releasing = true;
      _fadingOut = true;
      _releaseFrom = drag;
      _releaseTo = drag.dx.abs() >= drag.dy.abs()
          ? Offset(drag.dx > 0 ? size.width * 1.3 : -size.width * 1.3, drag.dy)
          : Offset(drag.dx, -size.height * 1.3);
    });
    await _releaseAnim.forward(from: 0);
    if (!mounted) return;
    await _commitGrade(grade);
  }

  /// 按钮评级：当前卡原地淡出（不必飞远）→ 换题 → 新卡淡入归位。
  Future<void> _gradeByButton(Grade grade) async {
    if (_grading || _releasing || _index >= _queue.length) return;
    _grading = true;
    _releaseCurve = Curves.easeIn;
    _releaseAnim.duration = _buttonFadeDuration;
    setState(() {
      _releasing = true;
      _fadingOut = true;
      _releaseFrom = Offset.zero;
      _releaseTo = Offset.zero;
    });
    await _releaseAnim.forward(from: 0);
    if (!mounted) return;
    await _commitGrade(grade);
    if (!mounted) return;
    setState(() => _grading = false);
  }

  /// 答案区（Scrollable 内容）中的竖向拖拽该不该由滑动接管：还能往该
  /// 方向滚动就交给滚动视图，滚不动了（或内容一屏放得下）才评级。
  bool _shouldStealVertical(double deltaY) {
    if (!_canSwipe) return false;
    final controller = _answerScroll;
    if (!controller.hasClients || !controller.position.hasContentDimensions) {
      return true;
    }
    final position = controller.position;
    return deltaY < 0
        ? position.extentAfter <= 0.5
        : position.extentBefore <= 0.5;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final scope = AppScope.of(context);
    final srs = scope.srs;
    _overrides = scope.overrides;
    _overrides!.addListener(_onOverridesChanged);
    final session = srs.reviewSession;

    if (session != null) {
      // 未完成的会话：恢复同一份乱序队列与进度，总量不变。
      // （bundled 题库是静态的；万一遇到未知 id，位置 clamp 兜底。）
      final byId = <String, Question>{
        for (final q in scope.data.questions) q.id: q,
      };
      _queue = [
        for (final id in session.ids)
          if (byId[id] != null) byId[id]!,
      ];
      _index = session.index.clamp(0, _queue.length).toInt();
      // 前缀 = 上次已答部分：播种去重口径，重排副本的重复作答继续按
      // 「每题只算一次」处理（不重复计入每日统计）。
      _answeredIds.addAll(_queue.sublist(0, _index).map((q) => q.id));
    } else {
      // 无会话：今天到期（due ≤ 今天、未标熟）的题目开局。
      // 「复习随机」设置决定开局是否打乱（关 = 按到期顺序）。
      final due = buildReviewQueue(scope.data, srs);
      if (srs.reviewShuffle) due.shuffle();
      _queue = due;
      _index = 0;
      if (due.isNotEmpty) {
        // didChangeDependencies 处于 build 阶段，会话开局不广播
        // （首页统计与会话无关，无需重建）。
        unawaited(srs.startReviewSession([for (final q in due) q.id]));
      }
    }
    _startedWithCards = _queue.isNotEmpty;
  }

  /// 写成绩 + 忘记重排 + 推进会话，然后清干净状态换到下一题，并启动新卡的
  /// 淡入进场动画（由 [_flyOut] / [_gradeByButton] 在出场完成后调用）。
  Future<void> _commitGrade(Grade grade) async {
    if (_index >= _queue.length) return;
    final srs = AppScope.of(context).srs;
    final id = _queue[_index].id;
    // 去重口径：重排副本的重复作答不进每日统计（SRS 间隔照常更新）。
    final repeat = _answeredIds.contains(id);
    await srs.grade(id, grade, countStats: !repeat);
    // 忘记 → 追加到队尾，同一次会话内稍后再次出现（每题最多
    // kSessionRequeues 次，超限不再追加、正常往下走）。
    if (grade == Grade.again && await srs.requeueInSession(id)) {
      _queue = <Question>[..._queue, _queue[_index]];
    }
    _answeredIds.add(id);
    // 推进会话进度；答完最后一题时存档自动删除。
    await srs.advanceReviewSession();
    if (!mounted) return;
    // 换题同时清干净手势状态：出场落位、新卡片原点待命。
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
    // 下一张：淡入 + 轻微上移归位。
    _enterAnim.forward(from: 0);
  }

  /// 一轮结束：正常答完（下标顶到末尾），或标熟把队列删空（开局时非空）。
  bool get _finished =>
      _queue.isNotEmpty ? _index >= _queue.length : _startedWithCards;

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      // 结束页按**去重后的题**汇报 —— 队尾重排的重复作答每题只算一次。
      return _SummaryView(count: _answeredIds.length);
    }
    if (_queue.isEmpty) return const _EmptyQueueView();

    final scheme = Theme.of(context).colorScheme;
    // 完成度走去重口径：重排副本不推高分母、也不算新的完成量。
    final ids = [for (final q in _queue) q.id];
    final total = ids.toSet().length;
    final answered = distinctAnswered(ids, _index);
    final progress = total > 0 ? answered / total : 0.0;
    final position = distinctAnswered(ids, _index + 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('复习模式'),
        actions: [
          // 标熟在纠错 ✎ 左边：图标用勋章（区别于收藏的星标）。
          IconButton(
            icon: const Icon(Icons.workspace_premium_outlined),
            tooltip: '标熟',
            visualDensity: VisualDensity.compact,
            onPressed: !_grading && !_releasing && _index < _queue.length
                ? _markMature
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '纠错',
            visualDensity: VisualDensity.compact,
            onPressed: !_grading && !_releasing && _index < _queue.length
                ? _openCorrection
                : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 进度：右上角数字 + 一条细线（不再用粗条 + 左侧序号）。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$position / $total',
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
                    // 进场：淡入 + 从下方 14px 轻微上移归位。
                    final enterT = _enterAnim.value;
                    final enterOffset = Offset(0, _enterRise * (1 - enterT));
                    // 出场：飞出 / 原地淡出时 opacity → 0（回弹不淡出）。
                    final exitT = _releasing && _fadingOut
                        ? _releaseAnim.value
                        : 0.0;
                    final opacity = (enterT * (1 - exitT)).clamp(0.0, 1.0);
                    // 跟手旋转，最多 6°。
                    final angle =
                        (offset.dx / 320).clamp(-1.0, 1.0) *
                        (6 * 3.141592653589793 / 180);
                    return Opacity(
                      opacity: opacity,
                      child: Transform.translate(
                        offset: offset + enterOffset,
                        child: Transform.rotate(
                          angle: angle,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // 横向手势整卡可用（右=熟练、左=忘记）；
                              // 竖向手势在答案内容里，见 _ReviewBack。
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
                                    front:
                                        _ReviewFront(question: _queue[_index]),
                                    back: _ReviewBack(
                                      question: _queue[_index],
                                      onGrade: _gradeByButton,
                                      enabled: !_grading && !_releasing,
                                      scrollController: _answerScroll,
                                      drag: _VerticalDragCallbacks(
                                        onStart: _onSwipeStart,
                                        onUpdate: _onSwipeUpdate,
                                        onEnd: _onSwipeEnd,
                                        onCancel: _onSwipeCancel,
                                        shouldAccept: _shouldStealVertical,
                                      ),
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
    );
  }
}

/// 竖向手势回调包：答案区内层识别器要用的一组回调 + 接管策略。
class _VerticalDragCallbacks {
  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;
  final VoidCallback onCancel;

  /// 拖拽刚过触摸阈值时决定这次竖向手势归谁：true = 滑动评级接管，
  /// false = 保持 pending 让滚动视图赢。参数是最近一段的竖向 delta。
  final bool Function(double deltaY) shouldAccept;

  const _VerticalDragCallbacks({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required this.shouldAccept,
  });
}

/// 竖向拖拽识别器：普通 VerticalDragGestureRecognizer 多问一步 ——
/// 位移刚过触摸阈值时调用 [shouldSteal]，只有「这次该评级」才 accept；
/// 否则保持 pending，让更外层的滚动视图在自己的阈值上正常接管。
/// 它位于滚动视图**内层**，竞技场里先到，所以 accept 总能赢。
class _ScrollAwareVerticalDrag extends VerticalDragGestureRecognizer {
  /// 最近一段事件的竖向 delta，供 [shouldSteal] 判断方向。
  double _lastDeltaY = 0;

  bool Function(double deltaY)? shouldSteal;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _lastDeltaY = event.localDelta.dy;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    if (!super.hasSufficientGlobalDistanceToAccept(
      pointerDeviceKind,
      deviceTouchSlop,
    )) {
      return false;
    }
    return shouldSteal?.call(_lastDeltaY) ?? true;
  }
}

/// 跟手浮出的评级提示层：随位移在对应方向浮现半透明色层与徽标 ——
/// 右滑绿色 ✓ 熟练、左滑红色 ✗ 忘记、上滑琥珀色 ！ 生疏。
/// 透明度由位移距离（对齐 120px 阈值）驱动，回位时自动淡出。
class _SwipeHintLayer extends StatelessWidget {
  final Offset offset;

  const _SwipeHintLayer({required this.offset});

  @override
  Widget build(BuildContext context) {
    // 评价三色是语义填充色（深浅同值，白字徽标压面始终可读）。
    final pal = semanticPaletteOf(context);
    final dx = offset.dx;
    final dy = offset.dy;
    final horizontal = dx.abs() >= dy.abs();

    final IconData icon;
    final Color color;
    final String label;
    final Alignment badgeAlign;
    final EdgeInsets badgePadding;
    final Alignment gradientBegin;
    final Alignment gradientEnd;

    if (horizontal && dx.abs() > 8) {
      color = dx > 0 ? pal.good : pal.again;
      icon = dx > 0 ? Icons.check_rounded : Icons.close_rounded;
      label = dx > 0 ? '熟练' : '忘记';
      badgeAlign = dx > 0 ? Alignment.centerRight : Alignment.centerLeft;
      badgePadding = EdgeInsets.only(
        left: dx > 0 ? 0 : 26,
        right: dx > 0 ? 26 : 0,
      );
      // 色层压在手指推进的那一侧。
      gradientBegin = dx > 0 ? Alignment.centerLeft : Alignment.centerRight;
      gradientEnd = dx > 0 ? Alignment.centerRight : Alignment.centerLeft;
    } else if (!horizontal && dy < -8) {
      color = pal.hard;
      icon = Icons.priority_high_rounded;
      label = '生疏';
      badgeAlign = Alignment.topCenter;
      badgePadding = const EdgeInsets.only(top: 34);
      gradientBegin = Alignment.bottomCenter;
      gradientEnd = Alignment.topCenter;
    } else {
      return const SizedBox.shrink();
    }

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

/// 卡片正面：题干（含 ____）大号居中偏上。
class _ReviewFront extends StatelessWidget {
  final Question question;

  const _ReviewFront({required this.question});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: paperShadowOf(context),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text(
            '填 空',
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
          // 底部预留更高，题干整体居中偏上。
          SizedBox(
            height: 64,
            child: Center(
              child: Text(
                '轻点翻面查看答案 · 翻开后可滑动评级',
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片背面：完整句子 + 高亮答案 + 三个评分按钮。
///
/// 答案内容包在**滚动视图之内**的竖向手势识别器里：它比滚动视图更内层，
/// 在手势竞技场里先到，于是能自己决定「这次上滑评级 / 交给滚动」（见
/// [_ScrollAwareVerticalDrag]）；横向上滚动视图不参与竞争，整卡由外层
/// GestureDetector 负责。
class _ReviewBack extends StatelessWidget {
  final Question question;
  final Future<void> Function(Grade) onGrade;
  final bool enabled;
  final ScrollController? scrollController;
  final _VerticalDragCallbacks drag;

  const _ReviewBack({
    required this.question,
    required this.onGrade,
    required this.enabled,
    required this.drag,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pal = semanticPaletteOf(context);
    final baseStyle = const TextStyle(fontSize: 18, height: 1.8);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: paperShadowOf(context),
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
              controller: scrollController,
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: {
                  _ScrollAwareVerticalDrag:
                      GestureRecognizerFactoryWithHandlers<
                        _ScrollAwareVerticalDrag
                      >(_ScrollAwareVerticalDrag.new, (instance) {
                        instance.shouldSteal = drag.shouldAccept;
                        instance.onStart = drag.onStart;
                        instance.onUpdate = drag.onUpdate;
                        instance.onEnd = drag.onEnd;
                        instance.onCancel = drag.onCancel;
                      }),
                },
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
          ),
          const SizedBox(height: 16),
          // 三个带色药丸：熟练=绿、生疏=琥珀、忘记=红，取代通用按钮。
          // 语义填充色（SemanticPalette），深浅两版白字都可读。
          Row(
            children: [
              Expanded(
                child: _GradePill(
                  icon: Icons.check_rounded,
                  label: '熟练',
                  color: pal.good,
                  onPressed: enabled ? () => onGrade(Grade.good) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GradePill(
                  icon: Icons.help_outline_rounded,
                  label: '生疏',
                  color: pal.hard,
                  onPressed: enabled ? () => onGrade(Grade.hard) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GradePill(
                  icon: Icons.close_rounded,
                  label: '忘记',
                  color: pal.again,
                  onPressed: enabled ? () => onGrade(Grade.again) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

/// 评分药丸：整颗带色 + 图标，评分进行中降透明度禁用。
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

/// 无到期题。
class _EmptyQueueView extends StatelessWidget {
  const _EmptyQueueView();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final nextDue = scope.srs.nextDueDay();

    return Scaffold(
      appBar: AppBar(title: const Text('复习模式')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.done_all_rounded, size: 56, color: scheme.outline),
                const SizedBox(height: 16),
                const Text(
                  '今天没有要复习的卡片',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  nextDue != null ? '最近到期时间：$nextDue' : '已学板块的题目到期后会出现在这里',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '去学习模式打开板块，它的题目会自动加入今天的复习队列',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ChapterListScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  label: const Text('去学习'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一轮结束的小结。
class _SummaryView extends StatelessWidget {
  final int count;

  const _SummaryView({required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('复习完成')),
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
                  '本次复习 $count 题',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '做得好，按遗忘曲线继续坚持',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('返回首页'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
