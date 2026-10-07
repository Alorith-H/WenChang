import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenchang/app_scope.dart';
import 'package:wenchang/models/models.dart';
import 'package:wenchang/screens/source/section_detail_screen.dart';
import 'package:wenchang/services/app_data.dart';
import 'package:wenchang/services/content_overrides.dart';
import 'package:wenchang/services/custom_questions.dart';
import 'package:wenchang/services/favorites.dart';
import 'package:wenchang/services/srs_service.dart';

/// 资料板块详情页的 ✎ 纠错入口（议题 #8）—— 必须与学习模式**同一套**：
/// 打开共用的「纠错 · 板块要点」整板块弹层，保存走 `content_overrides`
/// 板块级覆盖（本页 ListenableBuilder 即刻刷新、持久化全局生效），
/// 点遮罩关闭则不落任何数据。
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
    expect(data.sectionIndex, isNotEmpty, reason: '资料资产应能从测试资产包加载');
  });

  /// 挑一个有顶层要点的板块（要点列表才有内容可改）。
  SectionLocation locationWithBullets(AppData d) {
    for (final loc in d.sectionIndex.values) {
      if (loc.section.bullets.isNotEmpty) return loc;
    }
    throw StateError('资料中找不到带顶层要点的板块');
  }

  Future<void> pumpDetail(
    WidgetTester tester,
    SectionLocation location,
  ) async {
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
          home: SectionDetailScreen(location: location),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('资料详情页 ✎ 打开学习模式同款要点弹层，保存后本页立即刷新并写入覆盖',
      (tester) async {
    final location = locationWithBullets(data);
    await pumpDetail(tester, location);

    // 入口：与学习模式一致 —— AppBar 右侧、Icons.edit_outlined、tooltip「纠错」。
    await tester.tap(find.byTooltip('纠错'));
    await tester.pumpAndSettle();

    // 同款弹层：标题「纠错 · 板块要点」，首栏 = 顶层第一条要点
    //（字段列表是懒加载 ListView，只断言可见部分）。
    expect(find.text('纠错 · 板块要点'), findsOneWidget);
    final section = location.section;
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, isNotEmpty, reason: '整板块每条要点一个编辑框');
    expect(fields.first.controller!.text, section.bullets.first.t);

    await tester.enterText(find.byType(TextField).first, '新要点·资料纠错');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    // 保存轻提示（与学习模式同文案）。
    expect(find.text('已保存'), findsOneWidget);

    // 本页即刻刷新：ListenableBuilder 监听 overrides，第一枪要点已是新文本
    // （覆盖后 segs = null → 纯文本渲染，find.text 可命中）。
    expect(find.text('新要点·资料纠错'), findsOneWidget);

    // 同一份覆盖全局生效：数据树里该要点已就地改写，并持久化到 content_overrides。
    expect(section.bullets.first.t, '新要点·资料纠错');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('content_overrides'), contains('新要点·资料纠错'));

    // 清掉 SnackBar 的 4s 计时器，避免测试收尾时挂起 Timer。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('点弹层外关闭：不保存，要点与持久层原样', (tester) async {
    final location = locationWithBullets(data);
    await pumpDetail(tester, location);
    final orig = location.section.bullets.first.t;

    await tester.tap(find.byTooltip('纠错'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '不该被保存的文本');
    await tester.tapAt(const Offset(5, 5)); // 点遮罩 = 取消
    await tester.pumpAndSettle();

    expect(find.text('已保存'), findsNothing, reason: '取消不该出现保存提示');
    expect(location.section.bullets.first.t, orig, reason: '取消不该改写数据树');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('content_overrides'), isNull, reason: '取消不落盘');
  });
}
