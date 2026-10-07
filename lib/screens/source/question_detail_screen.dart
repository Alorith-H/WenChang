import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/models.dart';
import '../../widgets/answer_spans.dart';
import 'section_detail_screen.dart';

/// 搜索结果里的题目详情：题干 / 答案 / 出处，可跳转所属板块。
///
/// 多空题（见 [answerSegments]）的答案按序逐段列出（1. 2. 3. …），
/// 与题干里的空位一一对应；存量单空题仍是整段原文显示。
class QuestionDetailScreen extends StatelessWidget {
  final Question question;

  const QuestionDetailScreen({super.key, required this.question});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scope = AppScope.of(context);
    final location = scope.data.sectionIndex[question.sec];
    final segments = answerSegments(question);
    final answerStyle = TextStyle(
      fontSize: 18,
      height: 1.7,
      fontWeight: FontWeight.w800,
      color: scheme.error,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('题目')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '题干',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  question.q,
                  style: const TextStyle(fontSize: 17, height: 1.8),
                ),
                const SizedBox(height: 16),
                Divider(color: scheme.outlineVariant),
                const SizedBox(height: 12),
                Text(
                  '答案',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                if (segments != null)
                  // 多空：按序列出每个空的答案，1. ↔ 第一个 ____、2. ↔ 第二个……
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < segments.length; i++) ...[
                        if (i > 0) const SizedBox(height: 4),
                        Text('${i + 1}. ${segments[i]}', style: answerStyle),
                      ],
                    ],
                  )
                else
                  Text(question.a, style: answerStyle),
                if (question.src.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '出处：${question.src}',
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
          if (location != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SectionDetailScreen(location: location),
                ),
              ),
              icon: const Icon(Icons.article_outlined, size: 18),
              label: Text('查看所属板块：${location.section.title}'),
            ),
          ],
        ],
      ),
    );
  }
}
