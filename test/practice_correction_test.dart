import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenchang/app_scope.dart';
import 'package:wenchang/models/models.dart';
import 'package:wenchang/screens/practice/practice_screen.dart';
import 'package:wenchang/services/app_data.dart';
import 'package:wenchang/services/content_overrides.dart';
import 'package:wenchang/services/custom_questions.dart';
import 'package:wenchang/services/favorites.dart';
import 'package:wenchang/services/srs_service.dart';

/// 习题答题页的 ✎ 纠错入口 —— 必须与复习页**同一套**交互：
/// 打开共用的「纠错 · 题目」弹层（题干 + 答案两栏，多空答案原样），
/// 保存走 `ContentOverrides.saveQuestion` 题级覆盖（当前卡立即刷新、
/// 持久化到 `content_overrides`），点遮罩关闭则不落任何数据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 数据装配放 setUp（真实 zone）：rootBundle 首次读资产若发生在
  // testWidgets 的 fake-async zone 里，引擎回包的续体永远不会被冲洗，
  // 测试会挂到 10 分钟超时（见 flutter_test 关于 runAsync 的约定）。
  late AppData data;
  late SrsService srs;
  late ContentOverrides overrides;
  late CustomQuestions customQuestions;
  late Favorites favorites;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    data = await AppData.load();
    srs = await SrsService.load();
    overrides = await ContentOverrides.load();
    customQuestions = await CustomQuestions.load();
    favorites = await Favorites.load();
    overrides.attach(data, customQuestions: customQuestions.questions);
    expect(data.questions, isNotEmpty, reason: '题库资产应能从测试资产包加载');
  });

  /// 挑一个带题目的板块（板块必须能在 sectionIndex 里找到）。
  Section sectionWithQuestions(AppData d) {
    for (final entry in d.questionsBySec.entries) {
      if (entry.value.isEmpty) continue;
      final loc = d.sectionIndex[entry.key];
      if (loc != null) return loc.section;
    }
    throw StateError('题库中找不到带题目的板块');
  }

  Future<void> pumpPractice(WidgetTester tester) async {
    // 与 main.dart 同款装配：AppScope 包在 MaterialApp 外面 —— 纠错弹层是
    // Navigator 上的新路由，只有这样才能向上找到 AppScope（保存依赖它）。
    await tester.pumpWidget(
      AppScope(
        data: data,
        srs: srs,
        overrides: overrides,
        customQuestions: customQuestions,
        favorites: favorites,
        child: MaterialApp(
          home: PracticeScreen(sections: [sectionWithQuestions(data)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('答题页 ✎ 打开同款纠错弹层，保存后当前题立即刷新并写入覆盖',
      (tester) async {
    await pumpPractice(tester);

    // 入口：与复习页一致 —— AppBar 右侧、Icons.edit_outlined、tooltip「纠错」。
    await tester.tap(find.byTooltip('纠错'));
    await tester.pumpAndSettle();

    // 同款弹层：标题「纠错 · 题目」+ 题干/答案两栏（与复习页共用一个组件）。
    expect(find.text('纠错 · 题目'), findsOneWidget);
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, hasLength(2), reason: '题干 + 答案恰好两栏');
    final origQ = fields.first.controller!.text;
    expect(origQ, isNotEmpty);

    await tester.enterText(find.byType(TextField).first, '新题干·习题纠错');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    // 保存轻提示（与复习页同文案）。
    expect(find.text('已保存'), findsOneWidget);

    // 当前题立即刷新：卡片正面题干已是新文本。
    expect(find.text('新题干·习题纠错'), findsOneWidget);

    // 题级覆盖全局生效：数据树里该题已就地改写，并持久化到 content_overrides。
    expect(data.questions.any((q) => q.q == '新题干·习题纠错'), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('content_overrides'), contains('新题干·习题纠错'));

    // 清掉 SnackBar 的 4s 计时器，避免测试收尾时挂起 Timer。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('点弹层外关闭：不保存，题目与持久层原样', (tester) async {
    await pumpPractice(tester);

    await tester.tap(find.byTooltip('纠错'));
    await tester.pumpAndSettle();
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    final origQ = fields.first.controller!.text;

    await tester.enterText(find.byType(TextField).first, '不该被保存的文本');
    await tester.tapAt(const Offset(5, 5)); // 点遮罩 = 取消
    await tester.pumpAndSettle();

    expect(find.text('已保存'), findsNothing, reason: '取消不该出现保存提示');
    expect(
      data.questions.any((q) => q.q == '不该被保存的文本'),
      isFalse,
      reason: '取消不该改写数据树',
    );
    if (origQ.isNotEmpty) {
      expect(find.text(origQ), findsOneWidget, reason: '卡片应仍是原文');
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('content_overrides'), isNull, reason: '取消不落盘');
  });
}
