import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/models.dart';
import '../services/app_data.dart';
import '../services/custom_questions.dart';
import 'correction_sheet.dart';

/// 添加习题底部弹层（习题 · 选题页「+ 添加习题」入口）：
///
/// 1. **选择板块**：级联**单选** —— 先选章，再在该章下点选板块
///    （行样式与选题页一致：缩进通栏行 + 圆形单选图标 + 发丝分隔线）；
/// 2. **题干** TextField（必填）；
/// 3. **答案** TextField（必填，hint 注明多空题用 `|` 分隔）；
///
/// 校验不过只在弹层内红字提示、绝不落库；保存写 SharedPreferences
/// `custom_questions`（见 [CustomQuestions]），返回 true 表示已添加 ——
/// 调用方据此给出「已添加」轻提示。
///
/// 同一弹层底部是**管理区**：列出全部自建题（板块名 + 题干摘要 +
/// 删除按钮，二次确认），删除经 [deleteCustomQuestion] 同一 helper
/// 一并清掉纠错覆盖与收藏标记。
Future<bool> showAddQuestionSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AddQuestionSheet(),
  );
  return result == true;
}

class _AddQuestionSheet extends StatefulWidget {
  const _AddQuestionSheet();

  @override
  State<_AddQuestionSheet> createState() => _AddQuestionSheetState();
}

class _AddQuestionSheetState extends State<_AddQuestionSheet> {
  /// 级联选择：先选章（null = 还停在章列表），再单选该章下的板块。
  Chapter? _chapter;
  Section? _section;

  late final TextEditingController _q;
  late final TextEditingController _a;

  /// 最近一次保存的校验错误（null = 无提示）。
  String? _error;

  @override
  void initState() {
    super.initState();
    _q = TextEditingController();
    _a = TextEditingController();
  }

  @override
  void dispose() {
    _q.dispose();
    _a.dispose();
    super.dispose();
  }

  /// 校验：板块 / 题干 / 答案缺一不可 —— 不过只提示，绝不落库。
  Future<void> _save() async {
    final scope = AppScope.of(context);
    final sec = _section?.id ?? '';
    final q = _q.text.trim();
    final a = _a.text.trim();
    String? error;
    if (sec.isEmpty) {
      error = '请先选择板块';
    } else if (q.isEmpty) {
      error = '题干不能为空';
    } else if (a.isEmpty) {
      error = '答案不能为空';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    await scope.customQuestions.add(sec: sec, q: q, a: a);
    if (mounted) Navigator.of(context).pop(true);
  }

  /// 删除二次确认：确认后经同一 helper 清条目 + 纠错覆盖 + 收藏标记。
  Future<void> _confirmDelete(CustomQuestion item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这道题？'),
        content: const Text('删除后会同时清掉它的纠错与收藏记录，且不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final scope = AppScope.of(context);
    await deleteCustomQuestion(
      scope.customQuestions,
      scope.overrides,
      scope.favorites,
      item.id,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final data = AppScope.of(context).data;
    final custom = AppScope.of(context).customQuestions;
    // 弹层高度：占屏大半，键盘弹起时让出（与纠错弹层同款处理）。
    final height =
        (media.size.height * 0.85 - media.viewInsets.bottom).clamp(320.0, media.size.height);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: SheetHeader(
                title: '添加习题',
                subtitle: '自建题与原生题同等参与刷题、评级与纠错',
              ),
            ),
            Divider(color: scheme.outlineVariant),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                children: [
                  // ------------------------------------------------ 1. 板块
                  const GroupHeader('选择板块'),
                  _picker(data),
                  // ------------------------------------------------ 2. 题干
                  const GroupHeader('题干'),
                  EditField(controller: _q, hint: '题目文本（____ 保留为空位）'),
                  const SizedBox(height: 16),
                  // ------------------------------------------------ 3. 答案
                  const GroupHeader('答案'),
                  EditField(controller: _a, hint: '答案文本'),
                  const SizedBox(height: 6),
                  Text(
                    '多空题用 | 分隔，段数与题干 ____ 的个数一致、顺序一一对应'
                    '（例：张若虚|贺知章|张旭|包融）',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  // ------------------------------------------------ 管理区
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Divider(color: scheme.outlineVariant),
                  ),
                  GroupHeader('已添加 · ${custom.items.length} 道'),
                  if (custom.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '还没有自建题',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < custom.items.length; i++) ...[
                      if (i > 0) Divider(color: scheme.outlineVariant),
                      _managedRow(data, custom.items[i]),
                    ],
                ],
              ),
            ),
            // 校验提示固定在保存条上方（不随列表滚动，永远可见）。
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.error,
                  ),
                ),
              ),
            SaveBar(enabled: true, onSave: _save),
          ],
        ),
      ),
    );
  }

  /// 级联选择器：未选章 = 章列表（点按下钻）；已选章 = 该章板块单选 +
  /// 「更换」返回章列表。
  Widget _picker(AppData data) {
    final scheme = Theme.of(context).colorScheme;
    final chapters = data.chapters;

    // 阶段一：选章。
    if (_chapter == null) {
      if (chapters.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '暂无章节',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
        );
      }
      return Column(
        children: [
          for (var i = 0; i < chapters.length; i++) ...[
            if (i > 0) Divider(color: scheme.outlineVariant),
            _chapterRow(chapters[i]),
          ],
        ],
      );
    }

    // 阶段二：选板块（单选）。
    final chapter = _chapter!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() {
              _chapter = null;
              _section = null;
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '更换',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  Icon(
                    Icons.swap_horiz_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (chapter.sections.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              '该章暂无板块',
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
          )
        else
          for (var i = 0; i < chapter.sections.length; i++) ...[
            if (i > 0) Divider(color: scheme.outlineVariant),
            _sectionRow(chapter.sections[i]),
          ],
      ],
    );
  }

  /// 章列表行（阶段一）：点按 = 选中该章并下钻到它的板块。
  Widget _chapterRow(Chapter chapter) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        highlightColor: scheme.primary.withValues(alpha: 0.04),
        splashColor: scheme.primary.withValues(alpha: 0.06),
        onTap: () => setState(() {
          _chapter = chapter;
          _section = null;
        }),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(8, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, height: 1.4),
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

  /// 板块行（阶段二）：与选题页同款缩进行 + 圆形单选图标，点按单选。
  Widget _sectionRow(Section section) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _section == section;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        highlightColor: scheme.primary.withValues(alpha: 0.04),
        splashColor: scheme.primary.withValues(alpha: 0.06),
        onTap: () => setState(() => _section = section),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(24, 11, 4, 11),
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

  /// 管理区一行：板块名 + 题干摘要 + 删除按钮。
  Widget _managedRow(AppData data, CustomQuestion item) {
    final scheme = Theme.of(context).colorScheme;
    final sectionTitle =
        data.sectionIndex[item.sec]?.section.title ?? item.sec;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sectionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.q.isEmpty ? '（题目缺失）' : item.q,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, height: 1.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            onPressed: () => _confirmDelete(item),
          ),
        ],
      ),
    );
  }
}
