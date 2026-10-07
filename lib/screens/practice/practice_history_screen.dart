import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/srs_service.dart';
import 'practice_record_detail_screen.dart';

/// 练习记录列表：每行 = 日期 + 正确率 + 题数（最新在前），
/// 点按进错题明细。清空学习记录时与学习进度一起被清掉
/// （记录存在 SrsService.practiceHistory，见 clearAllRecords）。
class PracticeHistoryScreen extends StatelessWidget {
  const PracticeHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final srs = AppScope.of(context).srs;

    return Scaffold(
      appBar: AppBar(title: const Text('练习记录')),
      body: ListenableBuilder(
        listenable: srs,
        builder: (context, _) {
          // 存储顺序为追加序（旧 → 新），列表反转成新 → 旧。
          final records = srs.practiceHistory.reversed.toList();
          if (records.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 56,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '还没有练习记录',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '去「习题模式」刷一组，成绩会记在这里',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: records.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = records[i];
              final percent = (r.accuracy * 100).round();
              return _HistoryTile(
                record: r,
                percent: percent,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PracticeRecordDetailScreen(record: r),
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

/// 一行记录：日期（主）+ 正确率 / 题数（副），右侧箭头。
class _HistoryTile extends StatelessWidget {
  final PracticeRecord record;
  final int percent;
  final VoidCallback onTap;

  const _HistoryTile({
    required this.record,
    required this.percent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  record.date,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '正确率 $percent%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: percent >= 80
                      ? const Color(0xFF3E7A52)
                      : (percent >= 60
                          ? scheme.onSurfaceVariant
                          : scheme.error),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${record.total} 题',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
