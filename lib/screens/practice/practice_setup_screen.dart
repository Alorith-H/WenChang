import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/models.dart';
import '../../services/app_data.dart';
import '../../widgets/custom_question_sheet.dart';
import 'practice_history_screen.dart';
import 'practice_screen.dart';

/// 习题模式第一层 · 选题页（两级选择）：
///
/// - 每章一行：复选框 = 全选 / 取消该章所有小节，支持**半选态**显示
///   （章内只勾了一部分时显示横杠）；
/// - 章行下面常驻**小节列表**（缩进、独立复选框），点按单独勾选；
/// - 开始刷题 = 所有**已勾选小节**的题；至少 1 个小节才能开始
///   （按钮置灰 + 提示）；
/// - 默认**全不选**（避免误开始全量），顶部可一键全选 / 清空；
/// - 底部另有两个入口：「添加习题」（自建题弹层，含管理区）与
///   「收藏夹」（按收藏 qid 组队刷题）—— 自建题计入各层题数，
///   并在开局时并入候选池（见 `buildPracticeQueue`）。
///
/// 版面沿用纸墨 UI（章 = 圆角色块，小节 = 卡内缩进行 + 发丝分隔线）。
/// 右上角 🕘 仍是「练习记录」入口。
class PracticeSetupScreen extends StatefulWidget {
  const PracticeSetupScreen({super.key});

  @override
  State<PracticeSetupScreen> createState() => _PracticeSetupScreenState();
}

class _PracticeSetupScreenState extends State<PracticeSetupScreen> {
  /// 已勾选的小节 key：`'${章下标}/${小节下标}'`（数据静态，下标即稳定 id）。
  final Set<String> _selected = <String>{};

  static String _key(int chapterIndex, int sectionIndex) =>
      '$chapterIndex/$sectionIndex';

  /// 一个小节里的可刷题数：原生题 + 该板块的自建题。
  int _sectionQuestionCount(AppData data, Section section) {
    if (section.id.isEmpty) return 0;
    final custom = AppScope.of(context).customQuestions;
    return (data.questionsBySec[section.id]?.length ?? 0) +
        custom.countFor(section.id);
  }

  /// 一章里可刷的题数：各板块（原生 + 自建）按 section id 归组求和
  /// （板块 id 去重）。
  int _chapterQuestionCount(AppData data, Chapter chapter) {
    var count = 0;
    final seen = <String>{};
    final custom = AppScope.of(context).customQuestions;
    for (final section in chapter.sections) {
      if (section.id.isEmpty || !seen.add(section.id)) continue;
      count += (data.questionsBySec[section.id]?.length ?? 0) +
          custom.countFor(section.id);
    }
    return count;
  }

  int _selectedInSection(Chapter chapter, int chapterIndex) {
    var n = 0;
    for (var si = 0; si < chapter.sections.length; si++) {
      if (_selected.contains(_key(chapterIndex, si))) n++;
    }
    return n;
  }

  /// 章的三态：true = 全选、false = 全不选、null = 半选（部分勾选）。
  bool? _chapterState(Chapter chapter, int chapterIndex) {
    if (chapter.sections.isEmpty) return false;
    final n = _selectedInSection(chapter, chapterIndex);
    if (n == 0) return false;
    if (n == chapter.sections.length) return true;
    return null; // 半选态
  }

  void _toggleChapter(int chapterIndex, Chapter chapter) {
    setState(() {
      final allSelected = _chapterState(chapter, chapterIndex) == true;
      for (var si = 0; si < chapter.sections.length; si++) {
        final key = _key(chapterIndex, si);
        if (allSelected) {
          _selected.remove(key);
        } else {
          _selected.add(key);
        }
      }
    });
  }

  void _toggleSection(int chapterIndex, int sectionIndex) {
    setState(() {
      final key = _key(chapterIndex, sectionIndex);
      if (!_selected.remove(key)) _selected.add(key);
    });
  }

  /// 开始刷题：收集所有已勾选小节（按章、节顺序），至少 1 个才放行。
  void _start() {
    if (_selected.isEmpty) return;
    final data = AppScope.of(context).data;
    final sections = <Section>[];
    for (var ci = 0; ci < data.chapters.length; ci++) {
      final chapter = data.chapters[ci];
      for (var si = 0; si < chapter.sections.length; si++) {
        if (_selected.contains(_key(ci, si))) sections.add(chapter.sections[si]);
      }
    }
    if (sections.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PracticeScreen(sections: sections)),
    );
  }

  /// 「+ 添加习题」：打开自建题弹层（级联选板块 + 题干 + 答案，底部
  /// 管理区可删）。弹层里可能已增 / 删，返回后**无条件**刷新计数；
  /// 新增成功才给「已添加」轻提示。
  Future<void> _openAddSheet() async {
    final messenger = ScaffoldMessenger.of(context);
    final added = await showAddQuestionSheet(context);
    if (!mounted) return;
    setState(() {}); // 各层题数含自建题，需重建。
    if (added) {
      messenger.showSnackBar(const SnackBar(content: Text('已添加')));
    }
  }

  /// 「⭐ 收藏夹」：按收藏 qid 组队进答题页（队列为空时答题页给空态）。
  void _openFavorites() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PracticeScreen.favorites()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = AppScope.of(context).data;
    final chapters = data.chapters;
    var totalSections = 0;
    for (final chapter in chapters) {
      totalSections += chapter.sections.length;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('习题模式'),
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
        child: Column(
          children: [
            // 已选计数 + 全选 / 清空。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 8, 2),
              child: Row(
                children: [
                  Text(
                    '已选 ${_selected.length}/$totalSections 小节',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: chapters.isEmpty
                        ? null
                        : () => setState(() {
                              for (var ci = 0; ci < chapters.length; ci++) {
                                for (var si = 0;
                                    si < chapters[ci].sections.length;
                                    si++) {
                                  _selected.add(_key(ci, si));
                                }
                              }
                            }),
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(_selected.clear),
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: chapters.isEmpty
                  ? Center(
                      child: Text(
                        '暂无章节',
                        style: TextStyle(
                          fontSize: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                      itemCount: chapters.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) =>
                          _chapterBlock(data, chapters[i], i),
                    ),
            ),
            // 底部两个入口：添加习题（自建题弹层）+ 收藏夹（组队刷题）。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openAddSheet,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('添加习题'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openFavorites,
                      icon: const Icon(Icons.star_rounded, size: 18),
                      label: const Text('收藏夹'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty ? null : _start,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(
                    _selected.isEmpty ? '至少选 1 个小节' : '开始刷题',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一章一块：章行（三态复选）+ 卡内常驻的小节列表（缩进、独立复选）。
  Widget _chapterBlock(AppData data, Chapter chapter, int chapterIndex) {
    final scheme = Theme.of(context).colorScheme;
    final state = _chapterState(chapter, chapterIndex); // true/false/null
    final selected = state == true;
    final partial = state == null;
    final count = _chapterQuestionCount(data, chapter);

    return Container(
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (selected || partial) ? scheme.primary : scheme.outlineVariant,
          width: (selected || partial) ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 章行：整行点按 = 全选 / 取消该章所有小节。
          Material(
            color: Colors.transparent,
            child: InkWell(
              highlightColor: scheme.primary.withValues(alpha: 0.05),
              splashColor: scheme.primary.withValues(alpha: 0.07),
              onTap: () => _toggleChapter(chapterIndex, chapter),
              child: Ink(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chapter.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                    Text(
                      '$count 题',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      // 三态：全选 ✓ / 半选 − / 全不选 ○。
                      selected
                          ? Icons.check_circle_rounded
                          : (partial
                              ? Icons.remove_circle_rounded
                              : Icons.radio_button_unchecked_rounded),
                      size: 22,
                      color: (selected || partial)
                          ? scheme.primary
                          : scheme.outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (chapter.sections.isNotEmpty) Divider(color: scheme.outlineVariant),
          // 小节列表（常驻）：缩进 + 独立复选框。
          for (var si = 0; si < chapter.sections.length; si++) ...[
            if (si > 0) Divider(color: scheme.outlineVariant),
            _sectionRow(data, chapter, chapterIndex, si),
          ],
        ],
      ),
    );
  }

  /// 一个小节：缩进的通栏行，点按单独勾选。
  Widget _sectionRow(
    AppData data,
    Chapter chapter,
    int chapterIndex,
    int sectionIndex,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final section = chapter.sections[sectionIndex];
    final selected = _selected.contains(_key(chapterIndex, sectionIndex));
    final count = _sectionQuestionCount(data, section);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        highlightColor: scheme.primary.withValues(alpha: 0.04),
        splashColor: scheme.primary.withValues(alpha: 0.06),
        onTap: () => _toggleSection(chapterIndex, sectionIndex),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(28, 11, 16, 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  section.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Text(
                '$count 题',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
