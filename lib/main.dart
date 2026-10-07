import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'screens/home_screen.dart';
import 'services/app_data.dart';
import 'services/content_overrides.dart';
import 'services/custom_questions.dart';
import 'services/favorites.dart';
import 'services/srs_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 深色模式设置先于首帧读出（SharedPreferences 已在插件通道就绪），
  // 冷启动第一帧就是用户选的 跟随系统 / 浅色 / 深色，不闪白。
  final themeMode = themeModeFromId(await loadThemeModeId());
  runApp(WenchangApp(initialThemeMode: themeMode));
}

class WenchangApp extends StatelessWidget {
  /// 冷启动时从 SharedPreferences 读到的深色模式（[main] 里 await）。
  /// 直接 pumpWidget 的调用方不传 → 跟随系统。
  final ThemeMode? initialThemeMode;

  const WenchangApp({super.key, this.initialThemeMode});

  @override
  Widget build(BuildContext context) {
    return _Bootstrap(initialThemeMode: initialThemeMode);
  }
}

/// Loads data + persisted SRS state once, then hands them to [AppScope].
class _Bootstrap extends StatefulWidget {
  final ThemeMode? initialThemeMode;

  const _Bootstrap({this.initialThemeMode});

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<_Boot> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Boot> _load() async {
    // 纠错覆盖先于数据加载：attach 时把它合并进题库/资料数据树，
    // 之后所有页面（学习、资料、题目、复习、刷题）读到的都是覆盖后的内容。
    final overrides = await ContentOverrides.load();
    // 自建题与收藏夹同批加载：attach 时把自建题的出题实例一并登记，
    // 纠错覆盖按 qid（含 cq- 自建题）天然生效。
    final customQuestions = await CustomQuestions.load();
    final favorites = await Favorites.load();
    final data = await AppData.load();
    overrides.attach(data, customQuestions: customQuestions.questions);
    final srs = await SrsService.load();
    return _Boot(data, srs, overrides, customQuestions, favorites);
  }

  void _retry() {
    setState(() => _future = _load());
  }

  /// Builds the app's [MaterialApp] with the shared title/theme settings.
  ///
  /// [textScale] (when provided — null keeps the system setting) is applied
  /// through a MediaQuery above the navigator so the 字号 setting reaches
  /// every route: cards, lists, review stems. It is capped at 1.3 anyway,
  /// which keeps AppBar titles from being blown up.
  ///
  /// [preset] is the selected 主题色 (default 朱红): it drives both the
  /// light and dark ColorScheme (its two seeds — see [buildColorScheme]),
  /// and the launcher icon is never touched.
  ///
  /// [themeMode]（跟随系统 / 浅色 / 深色，议题 #6）同时接进 MaterialApp 的
  /// `themeMode`，深色走 [buildThemeData] 的深灰褐纸感底。
  ///
  /// The visual direction is "文学笔记本": a warm paper ground, near-black
  /// ink text and the accent used only as point color (key numbers,
  /// highlights, primary actions) — deliberately away from stock M3's
  /// tinted-surface look. 深色是同一本笔记本的夜间版：深灰褐纸底、
  /// 暖白墨字、提亮点睛。
  Widget _app({
    required Widget home,
    required ThemeMode themeMode,
    double? textScale,
    ThemePreset? preset, // null → 朱红（默认主题色）
  }) {
    final active = preset ?? kThemePresets[0];
    return MaterialApp(
      title: '文常卡片',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: buildThemeData(buildColorScheme(active, Brightness.light)),
      darkTheme: buildThemeData(buildColorScheme(active, Brightness.dark)),
      // 字号设置总控：统一改写 MediaQuery 的 textScaler，全局生效。
      builder: textScale == null
          ? null
          : (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(textScaler: TextScaler.linear(textScale)),
                child: child ?? const SizedBox.shrink(),
              );
            },
      home: home,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 加载期间用冷启动读出的模式；数据就绪后跟随 SrsService 里可改的值。
    final initialMode =
        widget.initialThemeMode == null
            ? ThemeMode.system
            : widget.initialThemeMode!;
    return FutureBuilder<_Boot>(
      future: _future,
      builder: (context, snapshot) {
        // 首次加载：没有旧数据可退 —— 加载中转圈、出错进错误页。
        // 导入后的重载（_retry 换 future）：FutureBuilder 在等待期保留
        // 上一份快照（hasData 为真），这里继续用旧 UI 渲染 —— 树形不变，
        // SnackBar 与路由栈都留在原地；新数据就绪后 AppScope 的新实例
        // 通知依赖方重建（见 updateShouldNotify）。
        if (snapshot.hasError && !snapshot.hasData) {
          return _app(
            themeMode: initialMode,
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('数据加载失败'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _retry,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return _app(
            themeMode: initialMode,
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final boot = snapshot.data!;
        // Rebuild (and re-apply the text scale / theme color / theme mode)
        // only when the 字号、主题色 or 深色模式 changes, not on every grade.
        return AppScope(
          data: boot.data,
          srs: boot.srs,
          overrides: boot.overrides,
          customQuestions: boot.customQuestions,
          favorites: boot.favorites,
          // 设置页导入成功后调用：重载题库 / 资料 / 各存储（议题 #3）。
          reloadData: _retry,
          child: ListenableBuilder(
            listenable: Listenable.merge([
              boot.srs.fontScaleListenable,
              boot.srs.themeListenable,
              boot.srs.themeModeListenable,
            ]),
            builder: (context, _) => _app(
              themeMode: themeModeFromId(boot.srs.themeMode),
              home: const HomeScreen(),
              textScale: boot.srs.fontScale,
              preset: boot.srs.themePreset,
            ),
          ),
        );
      },
    );
  }
}

class _Boot {
  final AppData data;
  final SrsService srs;
  final ContentOverrides overrides;
  final CustomQuestions customQuestions;
  final Favorites favorites;

  const _Boot(
    this.data,
    this.srs,
    this.overrides,
    this.customQuestions,
    this.favorites,
  );
}
