import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_scope.dart';
import '../services/srs_service.dart';
import '../widgets/font_scale_sheet.dart';

/// 设置页：主题色 / 复习随机 / 字号 / 版本号 / 清空学习记录。
///
/// 全部设置即时生效并持久化在 SharedPreferences（主题色、复习随机、
/// 字号由 [SrsService] 持有；清空记录只动学习数据，不动这些设置）。
/// 版面延续「纸墨」风：小节标题字距拉开，行卡圆角 14、纸色底。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _shuffle;
  late int _themeIndex;
  late Future<PackageInfo> _packageInfo;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final srs = AppScope.of(context).srs;
    _shuffle = srs.reviewShuffle;
    _themeIndex = srs.themeIndex;
    _packageInfo = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final srs = AppScope.of(context).srs;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _sectionTitle(context, '主题色'),
          _card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < kThemePresets.length; i++)
                        Expanded(
                          child: Center(
                            child: _colorSwatch(
                              preset: kThemePresets[i],
                              selected: i == _themeIndex,
                              onTap: () async {
                                setState(() => _themeIndex = i);
                                await srs.setThemePreset(i);
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '当前：${kThemePresets[_themeIndex].name} · 选中即全局生效',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _sectionTitle(context, '复习'),
          _card(
            child: SwitchListTile(
              value: _shuffle,
              onChanged: (v) async {
                setState(() => _shuffle = v);
                await srs.setReviewShuffle(v);
              },
              title: const Text(
                '复习随机',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '开 = 开局打乱，关 = 按到期顺序',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
          _sectionTitle(context, '显示'),
          _card(
            child: ListTile(
              onTap: () async {
                await showFontScaleSheet(context, srs);
                if (mounted) setState(() {});
              },
              title: const Text(
                '字号',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fontScaleLabel(srs.fontScale),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: scheme.outline,
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
          _sectionTitle(context, '关于'),
          _card(
            child: FutureBuilder<PackageInfo>(
              future: _packageInfo,
              builder: (context, snapshot) {
                final info = snapshot.data;
                final version = info == null
                    ? '…'
                    : '版本 ${info.version}'
                          '${info.buildNumber.isEmpty ? '' : '+${info.buildNumber}'}';
                return ListTile(
                  title: const Text(
                    '版本',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  trailing: Text(
                    version,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                );
              },
            ),
          ),
          _sectionTitle(context, '数据'),
          _card(
            child: ListTile(
              onTap: () => _confirmClear(context, srs),
              title: Text(
                '清空学习记录',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.error,
                ),
              ),
              subtitle: Text(
                '学习进度、复习安排、已标熟记录、每日统计、打卡与练习记录',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ],
      ),
    );
  }

  /// 当前字号档位的标签（历史值可能不在四档里，取最接近的）。
  String _fontScaleLabel(double scale) {
    var label = kFontScaleLabels[0];
    var best = double.infinity;
    for (var i = 0; i < kFontScaleSteps.length; i++) {
      final diff = (kFontScaleSteps[i] - scale).abs();
      if (diff < best) {
        best = diff;
        label = kFontScaleLabels[i];
      }
    }
    return label;
  }

  /// 二次确认后清空学习记录（学习进度、复习安排、已标熟记录、练习记录），
  /// 不动题库、资料数据、纠错覆盖与设置。
  Future<void> _confirmClear(BuildContext context, SrsService srs) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空学习记录？'),
        content: const Text(
          '将清空：学习进度、复习安排、已标熟记录、\n每日作答统计、连续打卡与练习记录。题库和资料数据不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await srs.clearAllRecords();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空')),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  /// 单选色块：主题色圆点，选中态加主色描边圈 + 白勾。
  Widget _colorSwatch({
    required ThemePreset preset,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      label: preset.name,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: preset.seed,
                  boxShadow: selected
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: selected
                    ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              preset.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
