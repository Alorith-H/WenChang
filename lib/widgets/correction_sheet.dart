import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/models.dart';
import '../services/content_overrides.dart';

/// 纠错底部弹层（学习模式 + 复习模式共用）：
///
/// - 学习模式：编辑**当前板块**的全部要点 —— 每条一个可编辑 TextField，
///   按原顺序（板块提要在前，条目标题分组），底部「保存」。
/// - 复习模式：编辑**当前题目**的题干 + 答案，底部「保存」。
///
/// 保存写入 SharedPreferences `content_overrides` 并就地合并进已加载的
/// 数据树（见 [ContentOverrides]），返回 true 表示已保存 —— 调用方据此
/// 给出「已保存」轻提示。文本改回原文时自动删除覆盖、恢复红字。
Future<bool> showBulletCorrectionSheet(BuildContext context, Section section) {
  return _showSheet<bool>(context, _BulletCorrectionSheet(section: section));
}

Future<bool> showQuestionCorrectionSheet(
  BuildContext context,
  Question question,
) {
  return _showSheet<bool>(context, _QuestionCorrectionSheet(question: question));
}

Future<bool> _showSheet<T>(BuildContext context, Widget sheet) async {
  final result = await showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => sheet,
  );
  return result == true;
}

/// 弹层公共外壳：拖拽把手 + 标题 + 可选副标题。
class _SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SheetHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, color: scheme.onSurface),
          ),
        ],
      ],
    );
  }
}

/// 小节分组标题（条目名），纸墨风小号字距标签。
class _GroupHeader extends StatelessWidget {
  final String text;

  const _GroupHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: scheme.primary,
        ),
      ),
    );
  }
}

/// 统一样式的编辑框：纸色填充、无描边、圆角 12，长文本自动增高。
class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _EditField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      minLines: 1,
      maxLines: null,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// 底部「保存」按钮条（含安全区与键盘上方留白）。
class _SaveBar extends StatelessWidget {
  final bool enabled;
  final VoidCallback onSave;

  const _SaveBar({required this.enabled, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: enabled ? onSave : null,
          child: const Text('保存'),
        ),
      ),
    );
  }
}

/// 板块要点编辑器：一条要点一个 TextField，按原顺序。
class _BulletCorrectionSheet extends StatefulWidget {
  final Section section;

  const _BulletCorrectionSheet({required this.section});

  @override
  State<_BulletCorrectionSheet> createState() => _BulletCorrectionSheetState();
}

/// 一条可编辑要点：覆盖 key + 所属分组标题（同组首条显示）+ 初始文本。
class _FieldSpec {
  final String key;
  final String? header;
  final String initial;

  const _FieldSpec(this.key, this.header, this.initial);
}

class _BulletCorrectionSheetState extends State<_BulletCorrectionSheet> {
  late final List<_FieldSpec> _specs;
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final section = widget.section;
    final specs = <_FieldSpec>[];
    final controllers = <String, TextEditingController>{};

    // 板块顶层提要（key 的 itemIndex = -1），随后逐条目按原顺序。
    for (var i = 0; i < section.bullets.length; i++) {
      final key = ContentOverrides.bulletKey(section.id, -1, i);
      specs.add(_FieldSpec(key, null, section.bullets[i].t));
      controllers[key] = TextEditingController(text: section.bullets[i].t);
    }
    for (var itemIndex = 0; itemIndex < section.items.length; itemIndex++) {
      final item = section.items[itemIndex];
      for (var i = 0; i < item.bullets.length; i++) {
        final key = ContentOverrides.bulletKey(section.id, itemIndex, i);
        specs.add(_FieldSpec(key, i == 0 ? item.title : null, item.bullets[i].t));
        controllers[key] = TextEditingController(text: item.bullets[i].t);
      }
    }
    _specs = specs;
    _controllers = controllers;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final overrides = AppScope.of(context).overrides;
    final edits = {
      for (final spec in _specs) spec.key: _controllers[spec.key]!.text,
    };
    await overrides.saveBullets(edits);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    // 弹层高度：占屏 75%，键盘弹起时让出（只在上方留出可视编辑区）。
    final height =
        (media.size.height * 0.75 - media.viewInsets.bottom).clamp(260.0, media.size.height);

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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: _SheetHeader(title: '纠错 · 板块要点', subtitle: widget.section.title),
            ),
            Divider(color: scheme.outlineVariant),
            Expanded(
              child: _specs.isEmpty
                  ? Center(
                      child: Text(
                        '该板块暂无要点',
                        style: TextStyle(
                          fontSize: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      itemCount: _specs.length,
                      itemBuilder: (context, i) {
                        final spec = _specs[i];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (spec.header != null) _GroupHeader(spec.header!),
                            _EditField(
                              controller: _controllers[spec.key]!,
                              hint: '要点内容',
                            ),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),
            ),
            _SaveBar(enabled: _specs.isNotEmpty, onSave: _save),
          ],
        ),
      ),
    );
  }
}

/// 题目编辑器：题干 + 答案两个 TextField。
class _QuestionCorrectionSheet extends StatefulWidget {
  final Question question;

  const _QuestionCorrectionSheet({required this.question});

  @override
  State<_QuestionCorrectionSheet> createState() => _QuestionCorrectionSheetState();
}

class _QuestionCorrectionSheetState extends State<_QuestionCorrectionSheet> {
  late final TextEditingController _q;
  late final TextEditingController _a;

  @override
  void initState() {
    super.initState();
    _q = TextEditingController(text: widget.question.q);
    _a = TextEditingController(text: widget.question.a);
  }

  @override
  void dispose() {
    _q.dispose();
    _a.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final overrides = AppScope.of(context).overrides;
    await overrides.saveQuestion(widget.question.id, q: _q.text, a: _a.text);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + media.padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHeader(title: '纠错 · 题目'),
            const SizedBox(height: 14),
            Text(
              '题干',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            _EditField(controller: _q, hint: '题目文本（____ 保留为空位）'),
            const SizedBox(height: 16),
            Text(
              '答案',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            _EditField(controller: _a, hint: '答案文本'),
            const SizedBox(height: 6),
            Text(
              '多空答案用 | 分隔，段数与题干 ____ 的个数一致、顺序一一对应'
              '（例：张若虚|贺知章|张旭|包融）',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            _SaveBar(enabled: true, onSave: _save),
          ],
        ),
      ),
    );
  }
}
