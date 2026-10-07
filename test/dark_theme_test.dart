import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenchang/services/srs_service.dart';
import 'package:wenchang/theme/app_theme.dart';

/// 议题 #6 深色模式的可读性单测：对 [buildColorScheme] 深浅两版 + 语义色
/// 调色板计算 WCAG 对比度 ——
/// 深色下正文/次级文字/红字考点/主色点睛全部达标（正文类 ≥4.5、点睛 ≥3），
/// 浅色关键对保持达标（视觉无回归的量化护栏），评价药丸的白字在两版
/// 调色板下都可读。
void main() {
  /// WCAG 相对亮度。
  double luminance(Color c) {
    double channel(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  /// WCAG 对比度：(L1 + 0.05) / (L2 + 0.05)。
  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// 主题色 → 深浅两版 ColorScheme。
  ColorScheme light(ThemePreset p) => buildColorScheme(p, Brightness.light);
  ColorScheme dark(ThemePreset p) => buildColorScheme(p, Brightness.dark);

  group('深色模式对比度（六页文字可读的量化底线）', () {
    test('正文 / 次级文字 / 卡片上的正文 vs 深灰褐纸底 ≥ 4.5', () {
      final s = dark(kThemePresets[0]);
      expect(contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(s.onSurfaceVariant, s.surface), greaterThanOrEqualTo(4.5));
      expect(
        contrast(s.onSurface, s.surfaceContainerLowest),
        greaterThanOrEqualTo(4.5),
      );
      // 深色底不是纯黑，是纸感深灰褐。
      expect(s.surface, const Color(0xFF1C1A17));
      expect(s.surface, isNot(const Color(0xFF000000)));
    });

    test('红字考点（提亮朱红）落在深色卡片纸上 ≥ 4.5', () {
      final s = dark(kThemePresets[0]);
      expect(
        contrast(kDarkSemanticPalette.wordRed, s.surfaceContainerLowest),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('绿字（正确率 goodText）落在深色卡片纸上 ≥ 4.5', () {
      final s = dark(kThemePresets[0]);
      expect(
        contrast(kDarkSemanticPalette.goodText, s.surfaceContainerLowest),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('答案红（colorScheme.error）vs 深色纸底 ≥ 4.5', () {
      for (final preset in kThemePresets) {
        final s = dark(preset);
        expect(
          contrast(s.error, s.surface),
          greaterThanOrEqualTo(4.5),
          reason: '${preset.name} 深色模式的答案红可读性',
        );
      }
    });

    test('6 色的深色版主色：深底上 ≥ 3（点睛/大字），按钮字压面 ≥ 4.5', () {
      for (final preset in kThemePresets) {
        final s = dark(preset);
        expect(
          preset.seedDark,
          isNot(preset.seed),
          reason: '${preset.name} 有独立深色版',
        );
        expect(
          contrast(s.primary, s.surface),
          greaterThanOrEqualTo(3.0),
          reason: '${preset.name} 深色主色点睛',
        );
        expect(
          contrast(s.onPrimary, s.primary),
          greaterThanOrEqualTo(4.5),
          reason: '${preset.name} 主色按钮上的字',
        );
      }
    });
  });

  group('浅色模式无回归（关键对比度仍达标 + 关键色值不动）', () {
    test('正文 / 次级文字 / 红字考点 vs 暖白纸底 ≥ 4.5', () {
      final s = light(kThemePresets[0]);
      expect(s.surface, const Color(0xFFF7F2E6), reason: '暖白纸底色值不动');
      expect(s.onSurface, const Color(0xFF221E17), reason: '近黑墨色值不动');
      expect(contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(s.onSurfaceVariant, s.surface), greaterThanOrEqualTo(4.5));
      expect(
        contrast(kLightSemanticPalette.wordRed, s.surfaceContainerLowest),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('评价药丸的白字：两版调色板下对填充色都 ≥ 4.5', () {
      for (final palette in [kLightSemanticPalette, kDarkSemanticPalette]) {
        const white = Color(0xFFFFFFFF);
        expect(
          contrast(palette.good, white),
          greaterThanOrEqualTo(4.5),
          reason: '熟练/会 药丸白字',
        );
        expect(
          contrast(palette.again, white),
          greaterThanOrEqualTo(4.5),
          reason: '忘记/不会 药丸白字',
        );
        expect(
          contrast(palette.hard, white),
          greaterThanOrEqualTo(4.5),
          reason: '生疏 药丸白字',
        );
      }
    });
  });

  group('themeModeFromId：theme_mode 持久化值 → MaterialApp ThemeMode', () {
    test('system / light / dark 与非法值', () {
      expect(themeModeFromId('system'), ThemeMode.system);
      expect(themeModeFromId('light'), ThemeMode.light);
      expect(themeModeFromId('dark'), ThemeMode.dark);
      expect(themeModeFromId('whatever'), ThemeMode.system);
    });

    test('持久化 id 集合与默认值', () {
      expect(kThemeModeIds, ['system', 'light', 'dark']);
      expect(kThemeModeDefault, 'system');
      expect(kThemeModeKey, 'theme_mode');
    });
  });
}
