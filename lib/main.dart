import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'screens/home_screen.dart';
import 'services/app_data.dart';
import 'services/content_overrides.dart';
import 'services/srs_service.dart';

void main() {
  runApp(const WenchangApp());
}

class WenchangApp extends StatelessWidget {
  const WenchangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const _Bootstrap();
  }
}

/// Loads data + persisted SRS state once, then hands them to [AppScope].
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

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
    final data = await AppData.load();
    overrides.attach(data);
    final srs = await SrsService.load();
    return _Boot(data, srs, overrides);
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
  /// [seed] is the selected 主题色 accent (default 朱红): it drives only the
  /// accent roles — paper surfaces, ink text and the hairlines stay fixed,
  /// and the launcher icon is never touched.
  ///
  /// The visual direction is "文学笔记本": a warm paper ground, near-black
  /// ink text and the accent used only as point color (key numbers,
  /// highlights, primary actions) — deliberately away from stock M3's
  /// tinted-surface look.
  Widget _app({
    required Widget home,
    double? textScale,
    Color seed = const Color(0xFF9B3A2C), // 朱红（默认主题色）
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(
      // 点睛色 — used at full strength only for accents / primary actions.
      primary: seed,
      onPrimary: const Color(0xFFFFF7F1),
      primaryContainer: Color.lerp(seed, const Color(0xFFFFFDF7), 0.82)!,
      onPrimaryContainer: Color.lerp(seed, const Color(0xFF000000), 0.45)!,
      secondary: const Color(0xFF7A6A4F),
      secondaryContainer: const Color(0xFFEDE2CB),
      onSecondaryContainer: const Color(0xFF4A3D26),
      // 纸墨 palette: warm paper surfaces, ink text, no purple M3 tint.
      surface: const Color(0xFFF7F2E6), // 暖白纸
      onSurface: const Color(0xFF221E17), // 近黑墨
      onSurfaceVariant: const Color(0xFF6E6455),
      outline: const Color(0xFFB4A992),
      outlineVariant: const Color(0xFFE3DAC7), // 1px hairline
      surfaceDim: const Color(0xFFEDE6D6),
      surfaceBright: const Color(0xFFFFFDF7),
      surfaceContainerLowest: const Color(0xFFFFFDF7), // 卡片纸
      surfaceContainerLow: const Color(0xFFF2ECDE), // 次级行卡
      surfaceContainer: const Color(0xFFEDE6D6),
      surfaceContainerHigh: const Color(0xFFE7DFCD),
      surfaceContainerHighest: const Color(0xFFE1D8C4), // 进度槽
      inverseSurface: const Color(0xFF2C271F),
      onInverseSurface: const Color(0xFFF7F2E6),
      // Elevation must never wash the paper purple.
      surfaceTint: Colors.transparent,
    );
    return MaterialApp(
      title: '文常卡片',
      debugShowCheckedModeBanner: false,
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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: scheme.onSurface,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE3DAC7),
          thickness: 1,
          space: 1,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: scheme.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          hintStyle: TextStyle(fontSize: 15),
        ),
        textTheme: Typography.blackMountainView.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        ),
      ),
      home: home,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Boot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _app(
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _app(
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
        final boot = snapshot.data!;
        // Rebuild (and re-apply the text scale / theme color) only when the
        // 字号 or 主题色 changes, not on every grade.
        return AppScope(
          data: boot.data,
          srs: boot.srs,
          overrides: boot.overrides,
          child: ListenableBuilder(
            listenable: Listenable.merge([
              boot.srs.fontScaleListenable,
              boot.srs.themeListenable,
            ]),
            builder: (context, _) => _app(
              home: const HomeScreen(),
              textScale: boot.srs.fontScale,
              seed: boot.srs.themePreset.seed,
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

  const _Boot(this.data, this.srs, this.overrides);
}
