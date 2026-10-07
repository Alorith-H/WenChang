import 'package:flutter/material.dart';

import '../services/srs_service.dart';

/// 「纸墨」主题的深浅两套 ColorScheme / ThemeData 构造（议题 #6 深色模式）。
///
/// - 浅色：与旧版逐字一致 —— 暖白纸底、近黑墨字，朱红只做点睛（视觉零回归）。
/// - 深色：`ColorScheme.fromSeed` + 自定义**纸感深色底**（深灰褐 `#1C1A17`
///   一族，不是纯黑）；主色换成 [ThemePreset.seedDark] 的提亮变体，
///   保证 6 色主题在深底上的文字/图标对比度。
///
/// 同文件提供两组「深浅双值」辅助：
/// - [SemanticPalette]：评价按钮、统计三色、红字考点、火焰等硬编码色的
///   语义化归集（浅色沿用原值，深色提亮）。
/// - [paperShadowOf]：纸片卡片的浮起阴影（深色加深才能压出层次）。

/// 由持久化的 `theme_mode` id 得到 MaterialApp 的 [ThemeMode]（非法值按
/// 跟随系统）。
ThemeMode themeModeFromId(String id) {
  switch (id) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

/// 构建某一主题色在 [brightness] 下的 ColorScheme。
///
/// 浅色分支与议题 #6 之前的内联构造完全一致；深色分支先用
/// [ColorScheme.fromSeed]（深色亮度）铺底，再覆写为纸感深色表面。
ColorScheme buildColorScheme(ThemePreset preset, Brightness brightness) {
  if (brightness == Brightness.light) {
    final seed = preset.seed;
    return ColorScheme.fromSeed(
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
  }

  final seed = preset.seedDark;
  return ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  ).copyWith(
    // 深底可读：主色按钮上的字用深灰褐墨（对提亮主色对比度充足）。
    primary: seed,
    onPrimary: const Color(0xFF1C1A17),
    primaryContainer: Color.lerp(seed, const Color(0xFF262219), 0.78)!,
    onPrimaryContainer: seed,
    secondary: const Color(0xFFC4B491),
    secondaryContainer: const Color(0xFF3A3427),
    onSecondaryContainer: const Color(0xFFEDE2CB),
    // 纸感深色底 —— 深灰褐一族，刻意避开纯黑。
    surface: const Color(0xFF1C1A17), // 深灰褐纸
    onSurface: const Color(0xFFEDE6D8), // 暖白墨
    onSurfaceVariant: const Color(0xFFA99C86),
    outline: const Color(0xFF6E6353),
    outlineVariant: const Color(0xFF3A352C), // 1px hairline
    surfaceDim: const Color(0xFF141210),
    surfaceBright: const Color(0xFF262320),
    surfaceContainerLowest: const Color(0xFF242018), // 卡片纸
    surfaceContainerLow: const Color(0xFF2A261E), // 次级行卡
    surfaceContainer: const Color(0xFF2E2A22),
    surfaceContainerHigh: const Color(0xFF332E26),
    surfaceContainerHighest: const Color(0xFF3A352C), // 进度槽
    inverseSurface: const Color(0xFFEDE6D8),
    onInverseSurface: const Color(0xFF1C1A17),
    surfaceTint: Colors.transparent,
  );
}

/// 构建由 [scheme] 驱动的 ThemeData（深浅共用一套结构，颜色全部走
/// scheme 语义位，divider 发丝线随亮度取 outlineVariant）。
///
/// [textScale] 的总控在 MaterialApp 的 builder 上，不在此处。
ThemeData buildThemeData(ColorScheme scheme) {
  return ThemeData(
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
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
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
  );
}

/// 深浅双值的语义点睛色 —— 原散落在各页的硬编码 `0xFF…` 归集到这里：
/// 浅色一律沿用原值（视觉零回归），深色统一提亮，保证深底可读。
///
/// 注意 [good] / [hard] / [again] 是**填充色**（评价药丸、滑动提示徽标，
/// 白字压在上面），深浅同值 —— 白字对比度在两种模式下都达标；
/// 需要落在页面底色上的绿字用 [goodText]。
class SemanticPalette {
  /// 熟练 / 会（绿）填充。
  final Color good;

  /// 绿作**文字**（正确率等）时的深色提亮变体。
  final Color goodText;

  /// 生疏（琥珀）填充。
  final Color hard;

  /// 忘记 / 不会（红）填充。
  final Color again;

  /// 红笔考点文字（Word 原文 C00000；深色换更亮的朱红变体）。
  final Color wordRed;

  /// 连续打卡的火焰图标。
  final Color fire;

  /// 统计：已标熟 / 复习中 / 未见面。
  final Color mature;
  final Color reviewing;
  final Color unseen;

  const SemanticPalette({
    required this.good,
    required this.goodText,
    required this.hard,
    required this.again,
    required this.wordRed,
    required this.fire,
    required this.mature,
    required this.reviewing,
    required this.unseen,
  });
}

const kLightSemanticPalette = SemanticPalette(
  good: Color(0xFF3E7A52),
  goodText: Color(0xFF3E7A52),
  hard: Color(0xFF9A6B12),
  again: Color(0xFFB03A2E),
  wordRed: Color(0xFFC00000), // Word 原文红
  fire: Color(0xFFC2662B),
  mature: Color(0xFF9B3A2C),
  reviewing: Color(0xFF9A6B12),
  unseen: Color(0xFFB4A992),
);

const kDarkSemanticPalette = SemanticPalette(
  good: Color(0xFF3E7A52), // 填充同浅色：白字压面始终可读
  goodText: Color(0xFF6DBF8E),
  hard: Color(0xFF9A6B12), // 填充同浅色
  again: Color(0xFFB03A2E), // 填充同浅色
  wordRed: Color(0xFFF4685C), // 提亮朱红变体（深底对比 ≈ 5.9:1）
  fire: Color(0xFFE8925A),
  mature: Color(0xFFD2604F),
  reviewing: Color(0xFFD9A63F),
  unseen: Color(0xFFA69B85),
);

/// 当前主题亮度下的语义点睛色。
SemanticPalette semanticPaletteOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? kDarkSemanticPalette
    : kLightSemanticPalette;

/// 纸片卡片的浮起阴影：浅色是一层几乎看不见的黑纱（与旧版一致），
/// 深色加深到能从深底上压出层次。
List<BoxShadow> paperShadowOf(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: dark ? 0.4 : 0.05),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}
