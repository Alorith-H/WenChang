import 'package:flutter/material.dart';

import '../models/models.dart';

/// 多空答案解析：题干至少含 2 个 `____`、且答案 `a` 用 `|` 恰好分成与
/// 空位数相同的段时，返回逐空答案 —— 顺序与题干空位一一对应。
///
/// 其余一律返回 null：存量单空题（答案无 `|`）、无空位题、空答案、以及
/// 「`|` 段数 ≠ `____` 数」的数据，都按**单段原文整体显示**（见
/// [answerSpans]）—— 不拆分、不裁剪、不抛错，与旧行为完全一致。
List<String>? answerSegments(Question question) {
  final blanks = question.q.split('____').length - 1;
  if (blanks < 2 || question.a.isEmpty) return null;
  final segments = question.a.split('|');
  if (segments.length != blanks) return null;
  return segments;
}

/// 把题干按 `____` 切开，答案空位用红色加粗填入 —— 复习与刷题共用。
///
/// - 存量单空题（无 `|`）：整段答案填进空位，与旧版逐字一致。
/// - 多空且 `|` 段数吻合：逐段按序填入对应空位（见 [answerSegments]）。
/// - 题干没有空位 / 段数不符（容错）：正常显示题干；无空位时另起一行
///   给出「答案：…」，有空位时把原文整体当作单段填入，不炸不裁。
List<TextSpan> answerSpans(BuildContext context, Question question) {
  final scheme = Theme.of(context).colorScheme;
  final answerStyle = TextStyle(
    fontSize: 18,
    height: 1.8,
    fontWeight: FontWeight.w800,
    color: scheme.error,
  );
  final q = question.q;
  final a = question.a.isEmpty ? '？' : question.a;

  if (!q.contains('____')) {
    return [
      TextSpan(text: q),
      TextSpan(text: '\n答案：', style: answerStyle),
      TextSpan(text: a, style: answerStyle),
    ];
  }

  final parts = q.split('____');
  // 多空匹配 → 逐段填空；否则把 a 当作单段原文，整体填进每个空位
  //（与旧版渲染逐字一致 —— 存量单空题行为完全不变）。
  final fills =
      answerSegments(question) ?? List<String>.filled(parts.length - 1, a);
  final spans = <TextSpan>[];
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) {
      spans.add(TextSpan(text: fills[i - 1], style: answerStyle));
    }
    spans.add(TextSpan(text: parts[i]));
  }
  return spans;
}
