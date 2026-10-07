import 'package:flutter/material.dart';

import '../models/models.dart';

/// 把题干按 `____` 切开，答案空位用红色加粗填入 —— 复习与刷题共用。
///
/// 题干没有空位时（容错）正常显示题干，并另起一行给出「答案：…」。
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
  final spans = <TextSpan>[];
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) {
      spans.add(TextSpan(text: a, style: answerStyle));
    }
    spans.add(TextSpan(text: parts[i]));
  }
  return spans;
}
