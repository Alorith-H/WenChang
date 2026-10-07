import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/models.dart';
import '../services/srs_service.dart';
import '../widgets/progress_ring.dart';
import 'learn/chapter_list_screen.dart';
import 'learn/section_list_screen.dart';
import 'learn/study_card_screen.dart';
import 'practice/practice_setup_screen.dart';
import 'review/review_screen.dart';
import 'settings_screen.dart';
import 'source/source_screen.dart';
import 'stats_screen.dart';

/// 首页："文学笔记本"式的版面 —
/// 顶部大标题 + 一张主入口大卡（今日待复习 / 继续学习）+ 三张轻量次级
/// 行卡（学习 / 资料 / 习题）+ 杂志式统计数字行（带已标熟进度环与连续打卡
/// 天数）。朱红只出现
/// 在数字与主行动上，底色全部走纸墨色阶，行与行之间靠留白和发丝线分隔，
/// 没有三张同款 tile。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final srs = scope.srs;
    final data = scope.data;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: srs,
          builder: (context, _) {
            // 首页数字必须与复习页进度一致：存在未完成会话时直接显示
            // 会话剩余数，否则用（修复后的）buildReviewQueue —— 答完归零。
            final session = srs.reviewSession;
            final dueCount = session != null
                ? session.ids.length - session.index
                : buildReviewQueue(data, srs).length;
            final learned = srs.learnedToday().length;
            final total = data.totalSections;
            // 口径与统计页一致：按当前题库 id 划分 已标熟/复习中/未见面。
            final dist = srs.distributionOf(
              data.questions.map((q) => q.id),
            );
            final streak = srs.streak();

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '文常卡片',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 6,
                                      height: 1.2,
                                    ),
                              ),
                              const SizedBox(width: 8),
                              const _Seal(),
                            ],
                          ),
                          if (data.doc.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              data.doc.subtitle.join(' · '),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontSize: 13,
                                    height: 1.6,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.insights_rounded),
                          tooltip: '成就统计',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _push(context, const StatsScreen()),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined),
                          tooltip: '设置',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _push(context, const SettingsScreen()),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _MainEntryCard(
                  dueCount: dueCount,
                  canContinue: srs.lastSection != null,
                  onTap: () => _openMainEntry(context),
                ),
                const SizedBox(height: 16),
                _SecondaryRow(
                  icon: Icons.menu_book_rounded,
                  title: '学习模式',
                  subtitle: '章 → 板块 → 卡片翻面记忆',
                  fill: Theme.of(context).colorScheme.surfaceContainerLow,
                  onTap: () => _openStudy(context),
                ),
                const SizedBox(height: 8),
                _SecondaryRow(
                  icon: Icons.library_books_rounded,
                  title: '资料模式',
                  subtitle: '通读全文，随时搜索查阅',
                  fill: null, // 留白纸面，与上一行靠底色区分
                  onTap: () => _push(context, const SourceScreen()),
                ),
                const SizedBox(height: 8),
                _SecondaryRow(
                  icon: Icons.quiz_outlined,
                  title: '习题模式',
                  subtitle: '选章节乱序刷题，左滑不会右滑会',
                  fill: Theme.of(context).colorScheme.surfaceContainerLow,
                  onTap: () =>
                      _push(context, const PracticeSetupScreen()),
                ),
                const SizedBox(height: 24),
                const Divider(height: 1),
                const SizedBox(height: 16),
                _StatsRow(
                  dueCount: dueCount,
                  learned: learned,
                  total: total,
                  mature: dist.mature,
                  questionTotal: data.questions.length,
                  streak: streak,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  /// 主入口大卡的分状态跳转：有到期题进复习；否则直达上次学习的卡片页
  /// （有历史）或章列表（无历史）。
  void _openMainEntry(BuildContext context) {
    final scope = AppScope.of(context);
    final srs = scope.srs;
    final session = srs.reviewSession;
    final dueCount = session != null
        ? session.ids.length - session.index
        : buildReviewQueue(scope.data, srs).length;
    if (dueCount > 0) {
      _push(context, const ReviewScreen());
      return;
    }
    final study = srs.lastStudy;
    if (study != null) {
      final loc = scope.data.sectionIndex[study.sectionId];
      if (loc != null && _pushStudyAt(context, loc, study.page)) return;
    }
    final lastId = srs.lastSection;
    if (lastId != null) {
      final loc = scope.data.sectionIndex[lastId];
      if (loc != null && _pushStudyAt(context, loc, 0)) return;
    }
    _push(context, const ChapterListScreen());
  }

  /// 进入「学习模式」：有上次位置 → 直达那张卡片（返回键依次退回
  /// 板块列表、章列表）；没有历史 → 章列表。
  void _openStudy(BuildContext context) {
    final scope = AppScope.of(context);
    final study = scope.srs.lastStudy;
    if (study != null) {
      final loc = scope.data.sectionIndex[study.sectionId];
      if (loc != null && _pushStudyAt(context, loc, study.page)) return;
    }
    _push(context, const ChapterListScreen());
  }

  /// 依次压入 章列表 → 板块列表 → 卡片页（停在 [page]），让卡片页的
  /// AppBar 返回能一路退到板块 / 章列表。找不到板块时返回 false。
  bool _pushStudyAt(BuildContext context, SectionLocation loc, int page) {
    final sectionIndex = loc.chapter.sections.indexOf(loc.section);
    if (sectionIndex < 0) return false;
    final nav = Navigator.of(context);
    nav.push(
      MaterialPageRoute<void>(builder: (_) => const ChapterListScreen()),
    );
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => SectionListScreen(chapter: loc.chapter),
      ),
    );
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => StudyCardScreen(
          chapter: loc.chapter,
          initialIndex: sectionIndex,
          initialPage: page,
        ),
      ),
    );
    return true;
  }
}

/// 标题旁的小朱红"文"字印章 —— 一枚点睛的主题记号。
class _Seal extends StatelessWidget {
  const _Seal();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: primary, width: 1.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '文',
        style: TextStyle(
          fontSize: 13,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
      ),
    );
  }
}

/// 主入口大卡：今日待复习 N + 分状态的主行动文案。
class _MainEntryCard extends StatelessWidget {
  final int dueCount;
  final bool canContinue;
  final VoidCallback onTap;

  const _MainEntryCard({
    required this.dueCount,
    required this.canContinue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasDue = dueCount > 0;
    final status = hasDue
        ? '按遗忘曲线排好了队，答完这一轮就归零'
        : (canContinue
            ? '今天没有到期的题，去上次学到的地方坐坐'
            : '今天没有到期的题，先开一节板块读读');
    final cta = hasDue ? '开始复习' : (canContinue ? '继续学习' : '开始学习');

    return Container(
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          highlightColor: scheme.primary.withValues(alpha: 0.05),
          splashColor: scheme.primary.withValues(alpha: 0.07),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日待复习',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$dueCount',
                      style: TextStyle(
                        fontSize: 44,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: hasDue ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '题',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      cta,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 17,
                      color: scheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 次级入口：轻量通栏行卡 —— 无描边，靠底色 / 留白区分。
class _SecondaryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? fill;
  final VoidCallback onTap;

  const _SecondaryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.fill,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: fill ?? Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        highlightColor: scheme.primary.withValues(alpha: 0.05),
        splashColor: scheme.primary.withValues(alpha: 0.07),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 杂志式统计行："进度环 + 数据（大）/ 小灰标签"，发丝线分隔，底下再挂
/// 一条连续打卡。没有等权卡片。
class _StatsRow extends StatelessWidget {
  final int dueCount;
  final int learned;
  final int total;
  final int mature;
  final int questionTotal;
  final int streak;

  const _StatsRow({
    required this.dueCount,
    required this.learned,
    required this.total,
    required this.mature,
    required this.questionTotal,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _MatureRing(mature: mature, total: questionTotal),
            _Hairline(color: scheme.outlineVariant),
            Expanded(
              child: _Stat(
                value: '$learned/$total',
                label: '已学板块',
                highlight: false,
              ),
            ),
            _Hairline(color: scheme.outlineVariant),
            Expanded(
              child: _Stat(
                value: '$dueCount',
                label: '今日待复习',
                highlight: dueCount > 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _StreakLine(streak: streak),
      ],
    );
  }
}

/// 已标熟进度环：朱红圆环（mature / 题库总数），中心显示百分比。
class _MatureRing extends StatelessWidget {
  final int mature;
  final int total;

  const _MatureRing({required this.mature, required this.total});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = total > 0 ? (mature / total).clamp(0.0, 1.0) : 0.0;
    final center = total > 0 ? '${(progress * 100).round()}%' : '—';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProgressRing(
          progress: progress,
          size: 60,
          strokeWidth: 6,
          color: scheme.primary,
          track: scheme.surfaceContainerHighest,
          child: Text(
            center,
            style: TextStyle(
              fontSize: 13,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '已标熟',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 连续打卡：火焰图标 + 「连续 N 天」，0 天时补一句开工提示。
class _StreakLine extends StatelessWidget {
  final int streak;

  const _StreakLine({required this.streak});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const fire = Color(0xFFC2662B);
    return Row(
      children: [
        const Icon(Icons.local_fire_department_rounded, size: 18, color: fire),
        const SizedBox(width: 6),
        Text(
          '连续 $streak 天',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        if (streak == 0) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '今天翻开一张卡片或答一题，就算打卡',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final bool highlight;

  const _Stat({
    required this.value,
    required this.label,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 21,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: highlight ? scheme.primary : scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Hairline extends StatelessWidget {
  final Color color;

  const _Hairline({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: color,
    );
  }
}
