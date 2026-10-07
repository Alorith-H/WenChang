import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/models.dart';
import '../../services/app_data.dart';
import 'practice_history_screen.dart';
import 'practice_screen.dart';

/// 习题模式第一层 · 选题页：11 个章节多选（色块 + 复选勾），
/// 顶部「全选 / 清空」，底部「开始刷题」（至少选 1 章才能开始）。
/// 右上角 🕘 进「练习记录」（入口旁的记录入口）。
class PracticeSetupScreen extends StatefulWidget {
  const PracticeSetupScreen({super.key});

  @override
  State<PracticeSetupScreen> createState() => _PracticeSetupScreenState();
}

class _PracticeSetupScreenState extends State<PracticeSetupScreen> {
  /// 选中的章下标（数据静态，下标即稳定 id）。
  final Set<int> _selected = <int>{};

  /// 一章里可刷的题数：各板块题目按 section id 归组求和（板块 id 去重）。
  int _questionCount(AppData data, Chapter chapter) {
    var count = 0;
    final seen = <String>{};
    for (final section in chapter.sections) {
      if (section.id.isEmpty || !seen.add(section.id)) continue;
      count += data.questionsBySec[section.id]?.length ?? 0;
    }
    return count;
  }

  void _start() {
    if (_selected.isEmpty) return;
    final data = AppScope.of(context).data;
    final chapters = [
      for (final i in _selected.toList()..sort())
        if (i >= 0 && i < data.chapters.length) data.chapters[i],
    ];
    if (chapters.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PracticeScreen(chapters: chapters)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = AppScope.of(context).data;
    final chapters = data.chapters;

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
                    '已选 ${_selected.length}/${chapters.length} 章',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _selected.addAll(List.generate(chapters.length, (i) => i));
                    }),
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
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
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _chapterBlock(
                        data,
                        chapters[i],
                        i,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty ? null : _start,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(_selected.isEmpty ? '至少选 1 章' : '开始刷题'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一章一块的可选色块：选中 = 主色淡底 + 主色描边 + 实心勾。
  Widget _chapterBlock(AppData data, Chapter chapter, int index) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selected.contains(index);
    final count = _questionCount(data, chapter);

    return Container(
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          highlightColor: scheme.primary.withValues(alpha: 0.05),
          splashColor: scheme.primary.withValues(alpha: 0.07),
          onTap: () => setState(() {
            if (!_selected.remove(index)) _selected.add(index);
          }),
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
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
