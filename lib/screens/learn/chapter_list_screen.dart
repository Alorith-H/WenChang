import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/models.dart';
import 'section_list_screen.dart';

/// 学习模式第一层：章列表（11 章）。
///
/// 版面走"通栏行 + 1px 发丝分隔线"，不再是一行一张带阴影的圆角卡；
/// 章序号做成小号朱红角标，按压态是水彩式的暖色晕染。
class ChapterListScreen extends StatelessWidget {
  const ChapterListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context).data;
    final chapters = data.chapters;

    return Scaffold(
      appBar: AppBar(title: const Text('学习模式')),
      body: chapters.isEmpty
          ? const _EmptyHint(
              icon: Icons.auto_stories_outlined,
              text: '书页还空着，稍后再来看看吧',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
              itemCount: chapters.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) => _ChapterRow(
                ordinal: i + 1,
                chapter: chapters[i],
              ),
            ),
    );
  }
}

/// 中文章序号（一、二、…、十一、…），用作小号朱红角标。
String _cnOrdinal(int n) {
  const digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
  if (n <= 0) return '$n';
  if (n < 10) return digits[n];
  if (n == 10) return '十';
  if (n < 20) return '十${digits[n % 10]}';
  final tens = digits[n ~/ 10];
  final rest = n % 10;
  return '$tens十${rest == 0 ? '' : digits[rest]}';
}

class _ChapterRow extends StatelessWidget {
  final int ordinal;
  final Chapter chapter;

  const _ChapterRow({required this.ordinal, required this.chapter});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        highlightColor: scheme.primary.withValues(alpha: 0.05),
        splashColor: scheme.primary.withValues(alpha: 0.07),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SectionListScreen(chapter: chapter),
          ),
        ),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _cnOrdinal(ordinal),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
              const SizedBox(width: 8),
              Text(
                '${chapter.sections.length} 板块',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
