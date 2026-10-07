import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'section_detail_screen.dart';

/// 资料模式第二层：某章的板块目录。
class ChapterSectionsScreen extends StatelessWidget {
  final Chapter chapter;

  const ChapterSectionsScreen({super.key, required this.chapter});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sections = chapter.sections;

    return Scaffold(
      appBar: AppBar(title: Text(chapter.title)),
      body: sections.isEmpty
          ? Center(
              child: Text(
                '本章暂无内容',
                style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: sections.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final location = SectionLocation(
                  chapter: chapter,
                  section: sections[i],
                );
                return Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SectionDetailScreen(location: location),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              sections[i].title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: scheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
