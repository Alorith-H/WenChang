import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenchang/app_scope.dart';
import 'package:wenchang/models/models.dart';
import 'package:wenchang/screens/practice/practice_screen.dart';
import 'package:wenchang/screens/practice/practice_setup_screen.dart';
import 'package:wenchang/services/app_data.dart';
import 'package:wenchang/services/content_overrides.dart';
import 'package:wenchang/services/custom_questions.dart';
import 'package:wenchang/services/favorites.dart';
import 'package:wenchang/services/srs_service.dart';

/// 任务 10 的两条 UI 链路冒烟（弹层不强求，但入口与校验值得钉住）：
/// - 选题页「添加习题 / 收藏夹」入口；添加弹层级联选板块（先章后板块、
///   可更换）、空值校验不落库、保存成功入库 + 「已添加」轻提示；
/// - 收藏夹空队列 → 空态文案；答题页 ☆/★ 切换写 `favorite_qids`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 数据装配放 setUp（真实 zone），与 practice_correction_test 同款。
  late AppData data;
  late SrsService srs;
  late ContentOverrides overrides;
  late CustomQuestions custom;
  late Favorites favorites;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    data = await AppData.load();
    srs = await SrsService.load();
    overrides = await ContentOverrides.load();
    custom = await CustomQuestions.load();
    favorites = await Favorites.load();
    overrides.attach(data, customQuestions: custom.questions);
    expect(data.questions, isNotEmpty, reason: '题库资产应能从测试资产包加载');
  });

  /// 挑一个带题目的板块（板块必须能在 sectionIndex 里找到）。
  Section sectionWithQuestions() {
    for (final entry in data.questionsBySec.entries) {
      if (entry.value.isEmpty) continue;
      final loc = data.sectionIndex[entry.key];
      if (loc != null) return loc.section;
    }
    throw StateError('题库中找不到带题目的板块');
  }

  /// 与 main.dart 同款装配：AppScope 包在 MaterialApp 外面 —— 弹层与
  /// 新路由都要向上找到 AppScope。
  Widget app(Widget home) => AppScope(
        data: data,
        srs: srs,
        overrides: overrides,
        customQuestions: custom,
        favorites: favorites,
        child: MaterialApp(home: home),
      );

  /// 限定在底部弹层里查找（选题页背后有同名章 / 板块行）。
  Finder inSheet(Finder finder) => find.descendant(
        of: find.byType(BottomSheet),
        matching: finder,
      );

  testWidgets('选题页两个入口；添加弹层：级联单选 + 校验不落库 + 保存入库',
      (tester) async {
    await tester.pumpWidget(app(const PracticeSetupScreen()));
    await tester.pumpAndSettle();

    // 两个入口都在选题页。
    expect(find.text('添加习题'), findsOneWidget);
    expect(find.text('收藏夹'), findsOneWidget);

    await tester.tap(find.text('添加习题'));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('添加习题')), findsOneWidget, reason: '弹层标题');

    // 级联第一段：未选章 = 只有章列表，板块尚未出现。
    expect(inSheet(find.text('一、先秦')), findsOneWidget);
    expect(inSheet(find.text('（一）上古神话')), findsNothing);

    // 校验 1：没选板块 → 提示，且不落库。
    await tester.tap(inSheet(find.widgetWithText(FilledButton, '保存')));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('请先选择板块')), findsOneWidget);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('custom_questions'), isNull, reason: '校验不过绝不落库');

    // 选章 → 该章板块出现（级联第二段）；「更换」回章列表。
    await tester.tap(inSheet(find.text('一、先秦')));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('（一）上古神话')), findsOneWidget);
    await tester.tap(inSheet(find.text('更换')));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('（一）上古神话')), findsNothing, reason: '更换后板块收起');

    // 重新选章 + 单选板块。
    await tester.tap(inSheet(find.text('一、先秦')));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('（一）上古神话')));
    await tester.pumpAndSettle();

    // 校验 2：板块已选、题干空。
    await tester.tap(inSheet(find.widgetWithText(FilledButton, '保存')));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('题干不能为空')), findsOneWidget);

    // 字段在懒加载列表的折叠线以下 —— 先滚出来再找。
    await tester.drag(inSheet(find.byType(ListView)), const Offset(0, -300));
    await tester.pumpAndSettle();

    final fields =
        tester.widgetList<TextField>(inSheet(find.byType(TextField))).toList();
    expect(fields, hasLength(2), reason: '题干 + 答案恰好两栏');

    await tester.ensureVisible(inSheet(find.byType(TextField)).first);
    await tester.pumpAndSettle();
    await tester.enterText(inSheet(find.byType(TextField)).first, '自建题·冒烟');
    await tester.tap(inSheet(find.widgetWithText(FilledButton, '保存')));
    await tester.pumpAndSettle();

    // 校验 3：答案空。
    expect(inSheet(find.text('答案不能为空')), findsOneWidget);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('custom_questions'), isNull);

    // 答案补齐 → 保存成功：关弹层、轻提示、落库。
    await tester.ensureVisible(inSheet(find.byType(TextField)).last);
    await tester.pumpAndSettle();
    await tester.enterText(inSheet(find.byType(TextField)).last, '冒烟答案');
    await tester.tap(inSheet(find.widgetWithText(FilledButton, '保存')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing, reason: '保存后弹层关闭');
    expect(find.text('已添加'), findsOneWidget, reason: '选题页给轻提示');
    expect(custom.items, hasLength(1));
    expect(custom.items.single.q, '自建题·冒烟');
    final tappedSec = data.chapters
        .firstWhere((c) => c.title == '一、先秦')
        .sections
        .firstWhere((s) => s.title == '（一）上古神话')
        .id;
    expect(custom.items.single.sec, tappedSec, reason: '板块 = 级联里点选的那个');
    expect(custom.questions.single.id, startsWith('cq-'));
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('custom_questions'), contains('自建题·冒烟'));

    // 清掉 SnackBar 的 4s 计时器，避免测试收尾时挂起 Timer。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('收藏夹入口：空收藏 → 空态文案，返回回选题页', (tester) async {
    await tester.pumpWidget(app(const PracticeSetupScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('收藏夹'));
    await tester.pumpAndSettle();

    expect(find.text('收藏夹还没有题目'), findsOneWidget);
    expect(find.text('答题时点亮 ☆ 收藏，之后集中重刷'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '返回'));
    await tester.pumpAndSettle();
    expect(find.text('添加习题'), findsOneWidget, reason: '回到选题页');
  });

  testWidgets('答题页 ☆/★：切换写 favorite_qids，星标即时刷新', (tester) async {
    await tester.pumpWidget(app(PracticeScreen(sections: [sectionWithQuestions()])));
    await tester.pumpAndSettle();

    expect(find.byTooltip('收藏'), findsOneWidget, reason: '初始未收藏 = 空心星');
    await tester.tap(find.byTooltip('收藏'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('取消收藏'), findsOneWidget, reason: '已收藏 = 实心星');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('favorite_qids');
    expect(raw, isNotNull, reason: '收藏必须持久化');
    expect(raw, isNot('[]'));

    // 再点取消：星标回落、存储清空（队列不受影响 —— 队列只构建一次）。
    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(prefs.getString('favorite_qids'), contains('[]'));
  });
}
