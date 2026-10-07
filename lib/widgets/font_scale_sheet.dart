import 'package:flutter/material.dart';

import '../services/srs_service.dart';

/// 弹出「字号」BottomSheet：小 / 标准 / 大 / 特大 四档
/// （textScale 0.9 / 1.0 / 1.15 / 1.3），点选即存 SharedPreferences，
/// 由 MaterialApp 的 MediaQuery 总控全局生效。
Future<void> showFontScaleSheet(BuildContext context, SrsService srs) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _FontScaleSheet(srs: srs),
  );
}

class _FontScaleSheet extends StatefulWidget {
  final SrsService srs;

  const _FontScaleSheet({required this.srs});

  @override
  State<_FontScaleSheet> createState() => _FontScaleSheetState();
}

class _FontScaleSheetState extends State<_FontScaleSheet> {
  late double _selected = widget.srs.fontScale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 最接近当前值的档位作为选中态（历史值可能不在四档里）。
    var selectedIndex = 0;
    var best = double.infinity;
    for (var i = 0; i < kFontScaleSteps.length; i++) {
      final diff = (kFontScaleSteps[i] - _selected).abs();
      if (diff < best) {
        best = diff;
        selectedIndex = i;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 16),
          Text(
            '字号',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < kFontScaleSteps.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _ScaleChip(
                    label: kFontScaleLabels[i],
                    selected: i == selectedIndex,
                    onTap: () {
                      setState(() => _selected = kFontScaleSteps[i]);
                      widget.srs.setFontScale(kFontScaleSteps[i]);
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              // 点选档位会立刻写入并经 MaterialApp 的 MediaQuery 生效，
              // 这行预览随全局 textScaler 一起缩放，即所选档位的观感。
              '预览 · 逝者如斯夫，不舍昼夜',
              style: TextStyle(
                fontSize: 16,
                height: 1.7,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScaleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ScaleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
