import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/models.dart';
import '../../widgets/content_views.dart';

/// 资料模式第三层：板块的完整阅读版式（条目可折叠/展开）。
class SectionDetailScreen extends StatelessWidget {
  final SectionLocation location;

  const SectionDetailScreen({super.key, required this.location});

  @override
  Widget build(BuildContext context) {
    final section = location.section;
    final chapter = location.chapter;
    final scheme = Theme.of(context).colorScheme;
    final srs = AppScope.of(context).srs;

    return Scaffold(
      appBar: AppBar(title: Text(section.title)),
      body: ListenableBuilder(
        // srs：今日已学徽标；overrides：纠错保存后要点立即刷新。
        listenable: Listenable.merge([srs, AppScope.of(context).overrides]),
        builder: (context, _) {
          final learned = srs.isLearnedToday(section.id);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chapter.title,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  if (learned) const LearnedBadge(),
                ],
              ),
              const SizedBox(height: 8),
              Divider(color: scheme.outlineVariant),
              const SizedBox(height: 4),
              if (section.bullets.isNotEmpty) ...[
                for (final b in section.bullets) BulletRow(bullet: b),
                const SizedBox(height: 8),
              ],
              if (section.items.isEmpty && section.bullets.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Center(
                    child: Text(
                      '该板块暂无内容',
                      style: TextStyle(
                        fontSize: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              for (var i = 0; i < section.items.length; i++)
                _ItemTile(item: section.items[i], key: ValueKey<int>(i)),
            ],
          );
        },
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final Item item;

  const _ItemTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(
            item.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          children: [
            if (item.bullets.isEmpty)
              Text(
                '暂无要点',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final b in item.bullets) BulletRow(bullet: b),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
