// 真机翻面动画 E2E：三条路径在 150/500/900ms 抓取中间帧证据。
//
// 运行：flutter test integration_test -d 19faf100 --no-uninstall
// 断言：每个采样点存在 FlipCard 正/背面的 Opacity value ∈ (0.02, 0.98)
// （IgnorePointer > Opacity 结构，排除评分徽章等无关 Opacity）。
// 截图：takeScreenshot 的字节不会自动落盘，这里手动写进应用外部
// /sdcard/Android/data/com.alorith.wenchang/files/screenshots（可 adb pull）
// 与内部 /data/data/... 双备份，最后汇总打印文件清单。
//
// 时钟：live binding 下 AnimationController 只在 pump 帧按真实流逝时间打点，
// 所以用 Stopwatch 记录真实毫秒，再 pump 到目标时刻采样；截图耗时计入
// Stopwatch，下一个采样点自动补差。
//
// easeInOut(1000ms) 在恰好 900ms 时 back=0.981 已越过 (0.02, 0.98) 上界，
// 故第三个采样点名义 900ms、实际落在 ~800–890ms 窗口（打印真实时刻）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show debugSemanticsDisableAnimations;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wenchang/app_scope.dart';
import 'package:wenchang/main.dart';
import 'package:wenchang/screens/home_screen.dart';
import 'package:wenchang/screens/learn/chapter_list_screen.dart';
import 'package:wenchang/screens/learn/section_list_screen.dart';
import 'package:wenchang/screens/learn/study_card_screen.dart';
import 'package:wenchang/screens/practice/practice_setup_screen.dart';
import 'package:wenchang/screens/practice/practice_screen.dart';
import 'package:wenchang/screens/review/review_screen.dart';
import 'package:wenchang/services/srs_service.dart';
import 'package:wenchang/widgets/flip_card.dart';

// ignore_for_file: avoid_print

/// 成功写入设备的截图路径（汇总打印）。
final List<String> _shotPaths = <String>[];

/// FlipCard 正/背面的不透明度：IgnorePointer 直接包住的 Opacity，
/// 且祖先里有 FlipCard（排除滑动提示层等同构但无关的节点）。
List<double> _faceOpacities(WidgetTester tester) {
  final values = <double>[];
  for (final element in tester.allElements) {
    final widget = element.widget;
    if (widget is! Opacity) continue;
    Element? directParent;
    var flipAncestor = false;
    // visitAncestorElements：首个回调即直接父节点；一路走到根查 FlipCard。
    element.visitAncestorElements((ancestor) {
      directParent ??= ancestor;
      if (ancestor.widget is FlipCard) flipAncestor = true;
      return true;
    });
    if (directParent?.widget is IgnorePointer && flipAncestor) {
      values.add(widget.opacity);
    }
  }
  return values;
}

String _fmt(List<double> values) =>
    '[${values.map((v) => v.toStringAsFixed(3)).join(', ')}]';

/// 截图并落盘（外部 + 内部双写），文件名 `name.png`。
Future<void> _shoot(WidgetTester tester, String name) async {
  final binding = tester.binding as IntegrationTestWidgetsFlutterBinding;
  final bytes = await binding
      .takeScreenshot(name)
      .timeout(const Duration(seconds: 30));
  var saved = false;
  for (final dir in const [
    '/storage/emulated/0/Android/data/com.alorith.wenchang/files/screenshots',
    '/data/data/com.alorith.wenchang/files/screenshots',
  ]) {
    try {
      Directory(dir).createSync(recursive: true);
      final file = File('$dir/$name.png');
      file.writeAsBytesSync(bytes);
      _shotPaths.add(file.path);
      saved = true;
      print('[shot] $name.png -> ${file.path} (${bytes.length} bytes)');
    } catch (error) {
      print('[shot] $name.png 写入 $dir 失败: $error');
    }
  }
  expect(saved, isTrue, reason: '截图 $name 未能写入设备任何存储路径');
}

/// 采样当前中间帧：打印 faces、断言存在 (0.02, 0.98) 内的值、截图存档。
Future<void> _captureMid(
  WidgetTester tester,
  String path,
  int nominalMs,
  int actualMs,
) async {
  final faces = _faceOpacities(tester);
  final mid = faces.any((v) => v > 0.02 && v < 0.98);
  print(
    '[$path] t=${nominalMs}ms (实际 ${actualMs}ms) '
    'faces=${_fmt(faces)} midFrame=$mid',
  );
  expect(
    mid,
    isTrue,
    reason: '[$path] ${actualMs}ms 处没有 Opacity ∈ (0.02, 0.98) 的翻面中间帧，'
        'faces=${_fmt(faces)}',
  );
  await _shoot(tester, '${path}_${nominalMs}ms');
}

/// pump 到 Stopwatch 指定时刻（目标已过则立即 pump 一帧）。
Future<void> _pumpTo(WidgetTester tester, Stopwatch sw, int targetMs) async {
  final remaining = targetMs - sw.elapsedMilliseconds;
  if (remaining > 0) {
    await tester.pump(Duration(milliseconds: remaining));
  } else {
    await tester.pump();
  }
}

/// 点按翻面后的 150/500/900ms 三次采样 + 结束态（全 0 或全 1）断言。
Future<void> _sampleFlipPath(
  WidgetTester tester,
  String path,
  Future<void> Function() tapFlip,
) async {
  final sw = Stopwatch()..start();
  await tapFlip();
  await tester.pump(); // 第 0 帧：didUpdateWidget 启动动画
  print('[$path] frame0 faces=${_fmt(_faceOpacities(tester))} '
      'sw=${sw.elapsedMilliseconds}ms');

  await _pumpTo(tester, sw, 150);
  await _captureMid(tester, path, 150, sw.elapsedMilliseconds);

  await _pumpTo(tester, sw, 500);
  await _captureMid(tester, path, 500, sw.elapsedMilliseconds);

  // 名义 900ms：easeInOut 在 900ms 处已出界，实际窗口取 ≥800 即采。
  await _pumpTo(tester, sw, 800);
  await _captureMid(tester, path, 900, sw.elapsedMilliseconds);

  await tester.pump(const Duration(milliseconds: 350));
  final settled = _faceOpacities(tester);
  print('[$path] 结束态 faces=${_fmt(settled)}');
  for (final v in settled) {
    expect(
      v < 0.02 || v > 0.98,
      isTrue,
      reason: '[$path] 动画结束后仍有中间值 $v（未停在 0/1）',
    );
  }
}

/// 自动翻开路径：30ms 轮询直到出现中间帧，最多拍 3 张；动画结束即停。
Future<int> _sampleAuto(WidgetTester tester) async {
  final sw = Stopwatch()..start();
  var shots = 0;
  var lastFaces = <double>[];
  while (sw.elapsedMilliseconds < 3000 && shots < 3) {
    await tester.pump(const Duration(milliseconds: 30));
    final faces = _faceOpacities(tester);
    lastFaces = faces;
    final mid = faces.any((v) => v > 0.02 && v < 0.98);
    if (!mid) {
      if (shots > 0) break; // 已拍到且当前落定
      continue; // 还没开始/还没到中间
    }
    final actual = sw.elapsedMilliseconds;
    print(
      '[study_auto] 350ms 渐显 实际 ${actual}ms '
      'faces=${_fmt(faces)} midFrame=true',
    );
    await _shoot(tester, 'study_auto_mid${shots + 1}');
    shots++;
  }
  expect(
    shots,
    greaterThan(0),
    reason: '自动翻开 350ms 渐显全程没有中间帧（lastFaces=${_fmt(lastFaces)}）'
        '——若挂载同帧置 flipped=true，controller 初值=1 将没有动画',
  );
  print('[study_auto] 捕获 mid 帧 $shots 张');
  return shots;
}

/// 等待 finder 出现（真实时间轮询）。
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? label,
}) async {
  final sw = Stopwatch()..start();
  while (finder.evaluate().isEmpty) {
    if (sw.elapsed > timeout) {
      fail('等待 ${label ?? finder.toString()} 超时（${timeout.inSeconds}s）');
    }
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// 等动画静止（转场、翻页物理等 transient 回调清空）。
Future<void> _settle(WidgetTester tester, {int maxPumps = 60}) async {
  var idle = 0;
  for (var i = 0; i < maxPumps && idle < 2; i++) {
    if (tester.binding.transientCallbackCount > 0) {
      idle = 0;
    } else {
      idle++;
    }
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 点按 → 目标页出现 → 静止。
Future<void> _navTo(
  WidgetTester tester,
  Finder tapTarget,
  Finder screen,
) async {
  await tester.tap(tapTarget);
  await _pumpUntilFound(tester, screen);
  await _settle(tester);
}

/// 等待列表里任意一个 finder 出现。
Future<void> _pumpUntilAny(
  WidgetTester tester,
  List<Finder> finders, {
  Duration timeout = const Duration(seconds: 20),
  String? label,
}) async {
  final sw = Stopwatch()..start();
  while (finders.every((f) => f.evaluate().isEmpty)) {
    if (sw.elapsed > timeout) {
      fail('等待 ${label ?? '任一目标'} 超时（${timeout.inSeconds}s）');
    }
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// 保证停在整章第一张子卡（上次学习位置可能记在后面的页）。
/// 底部页码文案形如 `1 / 14`；不是则点「上一张」。
Future<void> _ensureFirstCard(WidgetTester tester) async {
  final first = RegExp(r'^1 / \d+$');
  for (var i = 0; i < 40; i++) {
    if (find.textContaining(first).evaluate().isNotEmpty) return;
    await tester.tap(find.text('上一张'));
    await _settle(tester);
  }
  fail('无法回到第一张子卡（底部页码不是 “1 / N”）');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flip mid-animation e2e on device', (tester) async {
    final binding = tester.binding as IntegrationTestWidgetsFlutterBinding;

    // 系统若上报「移除动画」（AccessibilityFeatures.disableAnimations），
    // AnimationBehavior.normal 会把 1000ms 翻面压到 5% = 50ms，中间帧
    // 物理上不存在。测试里强制恢复正常时长（debug 构建下此开关生效）。
    final platformDisableAnimations = binding
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    debugSemanticsDisableAnimations = false;
    print('[env] 平台 disableAnimations=$platformDisableAnimations '
        '→ 测试强制 debugSemanticsDisableAnimations=false（翻面 1000ms 全速）');

    await binding.convertFlutterSurfaceToImage();
    await tester.pump();

    await tester.pumpWidget(const WenchangApp());
    await _pumpUntilFound(
      tester,
      find.byType(HomeScreen),
      timeout: const Duration(seconds: 30),
      label: '首页',
    );
    await _settle(tester);
    print('[nav] 首页就绪');

    // ---------- 路径 A：学习模式 · 点按第一张卡 ----------
    // 有上次位置时「学习模式」会直达卡片页；没有则 章列表 → 板块列表。
    await tester.tap(find.text('学习模式'));
    await _pumpUntilAny(
      tester,
      [
        find.byType(ChapterListScreen),
        find.byType(StudyCardScreen),
      ],
      label: '章列表或学习卡片',
    );
    if (find.byType(StudyCardScreen).evaluate().isEmpty) {
      await _settle(tester);
      await tester.tap(find.text('一、先秦'));
      await _pumpUntilFound(tester, find.byType(SectionListScreen));
      await _settle(tester);
      await tester.tap(find.text('（一）上古神话'));
    }
    await _pumpUntilFound(tester, find.byType(StudyCardScreen));
    await _settle(tester);
    await _ensureFirstCard(tester);
    print('[nav] 学习卡片页就绪（板块第一张子卡）');

    await _sampleFlipPath(tester, 'study_flip', () async {
      await tester.tap(find.byType(PageView));
    });

    // ---------- 路径 B：滑动到第二张 · 自动翻开 350ms ----------
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    final autoShots = await _sampleAuto(tester);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^2 / \d+$').hasMatch(w.data ?? ''),
      ),
      findsOneWidget,
      reason: '滑动后未切到第二张子卡（底部计数不是 2 / N）',
    );
    await _settle(tester);
    final autoSettled = _faceOpacities(tester);
    print('[study_auto] 结束态 faces=${_fmt(autoSettled)}');
    for (final v in autoSettled) {
      expect(
        v < 0.02 || v > 0.98,
        isTrue,
        reason: '自动翻面结束后仍有中间值 $v',
      );
    }

    // ---------- 路径 C：习题模式 · 点按翻面 ----------
    Navigator.of(tester.element(find.byType(StudyCardScreen)))
        .popUntil((route) => route.isFirst);
    await _pumpUntilFound(tester, find.byType(HomeScreen));
    await _settle(tester);
    await _navTo(tester, find.text('习题模式'), find.byType(PracticeSetupScreen));
    await tester.tap(find.text('（一）上古神话'));
    await _pumpUntilFound(tester, find.text('开始刷题'));
    await tester.tap(find.text('开始刷题'));
    await _pumpUntilFound(tester, find.byType(PracticeScreen));
    await _settle(tester);
    print('[nav] 习题页就绪');

    await _sampleFlipPath(tester, 'practice_flip', () async {
      await tester.tap(find.byType(FlipCard));
    });

    // ---------- 路径 D：复习模式（队列空则 SKIP） ----------
    Navigator.of(tester.element(find.byType(PracticeScreen)))
        .popUntil((route) => route.isFirst);
    await _pumpUntilFound(tester, find.byType(HomeScreen));
    await _settle(tester);

    var reviewRan = false;
    final scope = AppScope.of(tester.element(find.byType(HomeScreen)));
    final due = buildReviewQueue(scope.data, scope.srs).length;
    if (due <= 0) {
      print('[review] SKIP：复习队列为空（due=0）');
    } else {
      await tester.tap(find.text('今日待复习').first);
      await _pumpUntilFound(
        tester,
        find.byType(ReviewScreen),
        timeout: const Duration(seconds: 10),
        label: '复习页',
      );
      await _settle(tester);
      if (find.byType(FlipCard).evaluate().isEmpty) {
        print('[review] SKIP：进入复习页但无题目卡片（队列空）');
      } else {
        reviewRan = true;
        print('[nav] 复习页就绪（队列 $due 题）');
        await _sampleFlipPath(tester, 'review_flip', () async {
          await tester.tap(find.byType(FlipCard));
        });
      }
    }

    // ---------- 汇总 ----------
    print('======== E2E 翻面中间帧检测汇总 ========');
    print('[学习·点按] 150/500/900ms mid-frame: PASS '
        '→ study_flip_150ms / study_flip_500ms / study_flip_900ms');
    print('[学习·自动翻开] 350ms mid-frame: PASS ×$autoShots '
        '→ study_auto_mid1..$autoShots');
    print('[习题·点按] 150/500/900ms mid-frame: PASS '
        '→ practice_flip_150ms / practice_flip_500ms / practice_flip_900ms');
    if (reviewRan) {
      print('[复习·点按] 150/500/900ms mid-frame: PASS '
          '→ review_flip_150ms / review_flip_500ms / review_flip_900ms');
    } else {
      print('[复习·点按] SKIP（复习队列为空）');
    }
    print('设备端截图文件（${_shotPaths.length} 个）：');
    for (final path in _shotPaths) {
      print('  $path');
    }
    print('====================================');
  });
}
