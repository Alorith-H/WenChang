import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/models.dart';
import '../../services/srs_service.dart';
import '../source/question_detail_screen.dart';

/// 练习记录第三层：某一次练习的错题明细。
///
/// 每行 = 题干 + 答案 + 所属板块；点按进现有的 [QuestionDetailScreen]。
class PracticeRecordDetailScreen extends StatelessWidget {
  final PracticeRecord record;

  const PracticeRecordDetailScreen({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scope = AppScope.of(context);

    // qid → Question（错题回查；找不到的 id 跳过，数据不会因此崩）。
    final byId = <String, Question>{
      for (final q in scope.data.questions)
        if (q.id.isNotEmpty) q.id: q,
    };
    final wrongs = <Question>[
      for (final id in record.wrongQids)
        if (byId.containsKey(id)) byId[id]!,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('错题明细')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // 头部：日期 + 成绩摘要。
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    record.date,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${record.right}/${record.total} · 正确率 '
                  '${(record.accuracy * 100).round()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (wrongs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                  '本次没有错题',
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else ...[
            Text(
              '错题 ${wrongs.length}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            for (final q in wrongs) _WrongTile(question: q),
          ],
        ],
      ),
    );
  }
}

/// 一行错题：题干 + 答案（红）+ 所属板块，整行可点进题目详情。
class _WrongTile extends StatelessWidget {
  final Question question;

  const _WrongTile({required this.question});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scope = AppScope.of(context);
    final sectionTitle =
        scope.data.sectionIndex[question.sec]?.section.title ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => QuestionDetailScreen(question: question),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question.q.isEmpty ? '（题目缺失）' : question.q,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 6),
              Text(
                '答案：${question.a.isEmpty ? '？' : question.a}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.error,
                ),
              ),
              if (sectionTitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        sectionTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: scheme.outline,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
