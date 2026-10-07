import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/models.dart';
import '../../services/section_split.dart';
import '../../theme/app_theme.dart';
import '../../widgets/content_views.dart';
import '../../widgets/correction_sheet.dart';
import '../../widgets/flip_card.dart';

/// 学习模式第三层：淡入淡出切换正/背面的卡片。
///
/// 长板块被拆成多张子卡（见 [splitSection]），整章的子卡连成一个
/// PageView：左右滑动吸附翻页切换，轻点卡片让正面淡出、背面淡入。
/// 只有真正翻到背面的子卡才计入阅读进度；一个板块**所有**子卡都看过，
/// 才通过 `srs.markLearned` 标记「今日已学」并把题目拉进今天的复习。
/// 每张子卡的翻面状态独立记住——滑走再滑回来仍是翻开的。
///
/// 位置记忆：每次翻页 / 切板块都会把 `{章, 板块, 板块内页}` 存进
/// [SrsService.setLastStudy]，再进学习模式可直达这张卡。
///
/// 自动翻开：板块**第一张**子卡被手动翻开后（「开始学习」的信号），
/// 后续子卡滑到时自动呈翻开态（短暂渐显），滑回已看过的保持翻开；
/// 计数逻辑不变 —— 看过 = 翻到背面。
class StudyCardScreen extends StatefulWidget {
  final Chapter chapter;

  /// Index of the section (板块) to start at.
  final int initialIndex;

  /// Page within the starting section's sub-cards to restore
  /// (0-based; clamped — see [SrsService.lastStudy]).
  final int initialPage;

  const StudyCardScreen({
    super.key,
    required this.chapter,
    this.initialIndex = 0,
    this.initialPage = 0,
  });

  @override
  State<StudyCardScreen> createState() => _StudyCardScreenState();
}

class _StudyCardScreenState extends State<StudyCardScreen> {
  /// All sub-cards of the chapter, flattened in section order.
  late final List<SubCard> _cards;

  /// Flip state per page — never reset when swiping between cards.
  late final List<bool> _flipped;

  /// Sections whose first sub-card has been manually flipped open — the
  /// rest of the section's sub-cards then auto-open when swiped to.
  final Set<String> _autoArmed = <String>{};

  /// Pages opened by the auto-flip (they use a shorter, "短暂" fade than
  /// the manual 400ms flip) until the user interacts with them.
  final Set<int> _autoOpened = <int>{};

  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    final sections = widget.chapter.sections;
    final target = sections.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, sections.length - 1).toInt();

    _cards = <SubCard>[];
    var start = 0;
    var startCount = 0;
    for (var i = 0; i < sections.length; i++) {
      final before = _cards.length;
      _cards.addAll(splitSection(sections[i]));
      if (i == target) {
        start = before;
        startCount = _cards.length - before;
      }
    }
    _flipped = List<bool>.filled(_cards.length, false);

    // Restore the remembered page inside the target section (clamped so it
    // can never spill into the next section).
    final restored = _cards.isEmpty
        ? 0
        : (start + widget.initialPage)
            .clamp(0, (start + startCount - 1).clamp(0, _cards.length - 1))
            .toInt();
    _index = restored;
    _pageController = PageController(
      initialPage: _index,
      viewportFraction: 0.92,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Remembered as the exact "上次学习的位置" (章/板块/页).
    _recordStudyPosition();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Only the chrome follows the page here — flip state is never touched,
  /// so the previous card can never be visibly "snapped back".
  void _onPageChanged(int i) {
    setState(() {
      _index = i;
      _autoOpenIfArmed(i);
    });
    _recordStudyPosition();
  }

  void _recordStudyPosition() {
    if (_cards.isEmpty) return;
    final card = _cards[_index];
    if (card.section.id.isEmpty) return;
    unawaited(
      AppScope.of(context).srs.setLastStudy(
        chapterId: widget.chapter.id,
        sectionId: card.section.id,
        page: card.index,
      ),
    );
  }

  /// 板块第一张已被手动翻开 → 滑到该板块后续子卡时自动翻开
  /// （短暂渐显），并照常计入阅读进度；第一张永远手动。
  ///
  /// 挂载与翻开必须**错开一帧**：滑页时新页往往本帧才构建，若此刻直接把
  /// `_flipped[page]` 置 true，FlipCard 的 controller 初值就等于 1 ——
  /// 根本没有动画（用户看到的"瞬间切换"）。推迟到 post-frame 再翻，
  /// 卡片已带着 false 挂载，下一帧 didUpdateWidget 才能真正跑 250ms 渐显。
  void _autoOpenIfArmed(int page) {
    final card = _cards[page];
    if (_flipped[page]) return; // 滑回已看过的：保持翻开
    if (card.index == 0) return; // 第一张仍需手动点按
    if (!_autoArmed.contains(card.section.id)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 一帧的间隙里状态可能已变（手动翻过 / 已处理），只翻还没翻的。
      if (!mounted || _flipped[page]) return;
      setState(() {
        _flipped[page] = true;
        _autoOpened.add(page);
      });
      _markSeen(page);
    });
  }

  /// Counts a sub-card as read (manual flip and auto-open share this path —
  /// once every sub-card is read the section becomes 今日已学).
  void _markSeen(int page) {
    final card = _cards[page];
    final scope = AppScope.of(context);
    final questions = scope.data.questionsBySec[card.section.id] ?? const [];
    scope.srs.markCardSeen(card.section.id, card.index, card.total, questions);
  }

  /// Tapping the current card flips it; turning it to its back counts the
  /// sub-card as read for the section's progress. Flipping the section's
  /// first sub-card open arms auto-open for the rest of the section.
  void _toggleFlip(int page) {
    setState(() => _flipped[page] = !_flipped[page]);
    // Manual interaction → use the full 400ms flip, not the auto fade.
    _autoOpened.remove(page);
    if (!_flipped[page]) return;
    final card = _cards[page];
    if (card.index == 0) _autoArmed.add(card.section.id);
    _markSeen(page);
  }

  void _goTo(int next) {
    if (next < 0 || next >= _cards.length || next == _index) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// ✎ 纠错：编辑**当前板块**的全部要点（按原顺序）。保存后覆盖就地
  /// 生效 —— 背面内容订阅了 overrides，弹层一关即见新文本。
  Future<void> _openCorrection() async {
    if (_cards.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showBulletCorrectionSheet(
      context,
      _cards[_index].section,
    );
    if (saved && mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cards.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(title: Text(widget.chapter.title)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 48,
                color: scheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                '这一章还没有可以翻的卡片',
                style: TextStyle(
                  fontSize: 15,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final current = _cards[_index];

    return Scaffold(
      appBar: AppBar(
        title: const Text('学习卡片'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '纠错',
            visualDensity: VisualDensity.compact,
            onPressed: _openCorrection,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${current.section.title} · ${current.index + 1}/${current.total}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _cards.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, i) {
                final card = _cards[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 16,
                  ),
                  child: FlipCard(
                    key: ValueKey<String>('${card.section.id}#${card.index}'),
                    flipped: _flipped[i],
                    // 自动翻开是"短暂渐显"（250ms），手动翻面 400ms。
                    duration: _autoOpened.contains(i)
                        ? const Duration(milliseconds: 250)
                        : const Duration(milliseconds: 400),
                    onTap: () {
                      // Tapping a peeking neighbour slides to it; only the
                      // current card flips in place.
                      if (i != _index) {
                        _goTo(i);
                      } else {
                        _toggleFlip(i);
                      }
                    },
                    front: _CardShell(
                      child: _FrontFace(
                        chapter: widget.chapter,
                        card: card,
                      ),
                    ),
                    back: _CardShell(
                      child: _BackFace(card: card),
                    ),
                  ),
                );
              },
            ),
          ),
          _BottomBar(
            index: _index,
            count: _cards.length,
            onPrev: () => _goTo(_index - 1),
            onNext: () => _goTo(_index + 1),
          ),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;

  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 纸片感：卡片纸色 + 一层几乎看不见的浮起，无描边，统一圆角 14。
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: paperShadowOf(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _FrontFace extends StatelessWidget {
  final Chapter chapter;
  final SubCard card;

  const _FrontFace({required this.chapter, required this.card});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scope = AppScope.of(context);

    return ListenableBuilder(
      listenable: scope.srs,
      builder: (context, _) {
        final srs = scope.srs;
        final learnedDay = srs.lastLearnedDay(card.section.id);
        final seen = srs.seenCount(card.section.id, card.total);
        return Column(
          children: [
            // 序号 → 顶部 n/N 分段细进度条，替代原来的"子卡 n/N"药丸。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _SegmentBar(index: card.index, total: card.total),
            ),
            Expanded(
              child: Center(
                // 底部留白更多，板块名居中偏上。
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chapter.title,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        card.section.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          height: 1.35,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (card.itemTitle != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          card.itemTitle!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (learnedDay != null)
                        LearnedBadge(
                          label: srs.lastLearnedLabel(card.section.id),
                        )
                      else
                        Text(
                          '$seen/${card.total} 已看',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: Center(
                child: Text(
                  '轻点卡片翻面查看内容',
                  style: TextStyle(fontSize: 12.5, color: scheme.outline),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 正面顶部的 n/N 分段细进度条：一段一节子卡，当前段实色朱红。
class _SegmentBar extends StatelessWidget {
  final int index;
  final int total;

  const _SegmentBar({required this.index, required this.total});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (total <= 0) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i < index
                    ? scheme.primary.withValues(alpha: 0.35)
                    : (i == index
                        ? scheme.primary
                        : scheme.surfaceContainerHighest),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BackFace extends StatelessWidget {
  final SubCard card;

  const _BackFace({required this.card});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scope = AppScope.of(context);

    // srs：学习日期徽标；overrides：纠错保存后要点立即刷新。
    return ListenableBuilder(
      listenable: Listenable.merge([scope.srs, scope.overrides]),
      builder: (context, _) {
        final srs = scope.srs;
        final learnedDay = srs.lastLearnedDay(card.section.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      card.section.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${card.index + 1}/${card.total}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (learnedDay != null) ...[
                    const SizedBox(width: 8),
                    LearnedBadge(label: srs.lastLearnedLabel(card.section.id)),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                // accent: 条目标题带朱红角标、比要点更重一级。
                child: SectionBody(section: card.content, accent: true),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '轻点卡片返回正面',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final int count;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _BottomBar({
    required this.index,
    required this.count,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: index > 0 ? onPrev : null,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('上一张'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '${index + 1} / $count',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: FilledButton.icon(
                onPressed: index < count - 1 ? onNext : null,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('下一张'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
