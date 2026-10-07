import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_scope.dart';
import '../services/srs_service.dart';
import '../services/update_check.dart';
import '../theme/app_theme.dart';
import '../widgets/font_scale_sheet.dart';
import '../widgets/update_dialog.dart';

/// 设置页：主题色 / 深色模式 / 复习随机 / 字号 / 检查更新 / 清空学习记录。
///
/// 全部设置即时生效并持久化在 SharedPreferences（主题色、深色模式、复习
/// 随机、字号由 [SrsService] 持有；清空记录只动学习数据，不动这些设置）。
/// 版面延续「纸墨」风：小节标题字距拉开，行卡圆角 14、纸色底。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _shuffle;
  late int _themeIndex;
  late String _themeMode;
  late Future<PackageInfo> _packageInfo;
  bool _initialized = false;

  /// 手动「检查更新」进行中（≤8s；期间行不可再点，转圈不出 8 秒）。
  bool _checkingUpdate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final srs = AppScope.of(context).srs;
    _shuffle = srs.reviewShuffle;
    _themeIndex = srs.themeIndex;
    _themeMode = srs.themeMode;
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
          // 深色模式（议题 #6）：分段三选，紧挨色调选择；持久化
          // `theme_mode`，冷启动生效。
          _sectionTitle(context, '深色模式'),
          _card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'system',
                        label: Text('跟随系统'),
                      ),
                      ButtonSegment(value: 'light', label: Text('浅色')),
                      ButtonSegment(value: 'dark', label: Text('深色')),
                    ],
                    selected: {_themeMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) async {
                      setState(() => _themeMode = selection.first);
                      await srs.setThemeMode(selection.first);
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return scheme.primary;
                        }
                        return scheme.surfaceContainerLow;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return scheme.onPrimary;
                        }
                        return scheme.onSurfaceVariant;
                      }),
                      side: WidgetStatePropertyAll(
                        BorderSide(color: scheme.outlineVariant),
                      ),
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '跟随系统将随手机的深浅色设置自动切换；深色为纸感深灰褐底',
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
                final vTag = info == null
                    ? '…'
                    : 'v${info.version}'
                          '${info.buildNumber.isEmpty ? '' : '+${info.buildNumber}'}';
                return Column(
                  children: [
                    ListTile(
                      title: const Text(
                        '版本',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Text(
                        version,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                    // 检查更新（议题 #5）：显示当前版本，点击手动检查。
                    ListTile(
                      onTap: _checkingUpdate
                          ? null
                          : () => _checkUpdate(context),
                      enabled: !_checkingUpdate,
                      title: const Text(
                        '检查更新',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_checkingUpdate)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          else
                            Text(
                              vTag,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: scheme.outline,
                          ),
                        ],
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                  ],
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

  /// 手动检查更新（议题 #5）：≤8s 内三选一 ——
  /// 有更新 → 更新对话框（新版本号 + Release body 原文 + 去下载）；
  /// 已是最新 → SnackBar；网络失败 → SnackBar（静默容错，绝不崩）。
  Future<void> _checkUpdate(BuildContext context) async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    final messenger = ScaffoldMessenger.of(context);
    final release = await fetchLatestRelease(); // ≤8s，失败 → null
    PackageInfo? info;
    try {
      info = await _packageInfo;
    } catch (_) {
      info = null;
    }
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    if (release == null || info == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('检查失败，请稍后重试')),
      );
      return;
    }
    if (!isNewer(release.version, info.version)) {
      messenger.showSnackBar(const SnackBar(content: Text('已是最新版本')));
      return;
    }
    if (!context.mounted) return;
    await showUpdateDialog(context, release);
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
        boxShadow: paperShadowOf(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  /// 单选色块：主题色圆点，选中态加主色描边圈 + 勾。
  /// 圆点显示当前模式的种子色（深色模式下是 seedDark 提亮变体），
  /// 勾的颜色随模式走：浅色压白、深色压深灰褐墨。
  Widget _colorSwatch({
    required ThemePreset preset,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final swatchColor = dark ? preset.seedDark : preset.seed;
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
                  color: swatchColor,
                  boxShadow: selected
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: dark ? 0.35 : 0.08,
                            ),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: dark ? scheme.surface : Colors.white,
                      )
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
