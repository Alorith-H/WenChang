import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/models.dart';
import '../../services/section_split.dart';
import '../../widgets/content_views.dart';
import 'study_card_screen.dart';

/// 学习模式第二层：某章下的板块列表，带阅读进度与「今日已学」标记。
///
/// 与章列表同一套版式：通栏行 + 1px 发丝线 + 水彩式按压态，没有
/// 每行一张的阴影圆角卡。
class SectionListScreen extends StatelessWidget {
  final Chapter chapter;

  const SectionListScreen({super.key, required this.chapter});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final srs = scope.srs;
    final sections = chapter.sections;

    return Scaffold(
      appBar: AppBar(title: Text(chapter.title)),
      body: sections.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '本章还没有整理出板块',
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : ListenableBuilder(
              listenable: srs,
              builder: (context, _) {
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
                  itemCount: sections.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) {
                    final section = sections[i];
                    final learned = srs.isLearnedToday(section.id);
                    final total = splitSection(section).length;
                    final seen = srs.seenCount(section.id, total);
                    final scheme = Theme.of(context).colorScheme;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        highlightColor:
                            scheme.primary.withValues(alpha: 0.05),
                        splashColor: scheme.primary.withValues(alpha: 0.07),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => StudyCardScreen(
                              chapter: chapter,
                              initialIndex: i,
                            ),
                          ),
                        ),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      section.title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      seen >= total && total > 0
                                          ? '已通读'
                                          : '$seen/$total 已看',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (learned) ...[
                                const LearnedBadge(),
                                const SizedBox(width: 8),
                              ],
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
                  },
                );
              },
            ),
    );
  }
}
