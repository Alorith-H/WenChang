import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenchang/widgets/flip_card.dart';

/// FlipCard 的渐入渐出必须是**可证伪**的：翻面后 50ms 正面已经开始淡出、
/// 背面已经开始淡入（而不是瞬间硬切），400ms 后动画到达终态。
///
/// 定位方式：只在 FlipCard 子树里找「包含指定文案的 Opacity」，双面常驻
/// （正反面一直挂在树里，只有 opacity 在动），所以两个面各自对应唯一一枚
/// Opacity。
void main() {
  Finder opacityOf(String text) => find.descendant(
        of: find.byType(FlipCard),
        matching: find.byElementPredicate(
          (e) => e.widget is Opacity && _containsText(e, text),
        ),
      );

  double opacity(WidgetTester tester, String text) =>
      tester.widget<Opacity>(opacityOf(text)).opacity;

  testWidgets('翻面 50ms 时正面淡出中、背面淡入中，400ms 后到达终态',
      (WidgetTester tester) async {
    var flipped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 480,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return FlipCard(
                    flipped: flipped,
                    front: const Text('FRONT'),
                    back: const Text('BACK'),
                    onTap: () => setState(() => flipped = !flipped),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    // 初始：正面全显、背面完全隐藏。
    expect(opacity(tester, 'FRONT'), 1.0);
    expect(opacity(tester, 'BACK'), 0.0);

    // 触发翻面（等价于外部把 flipped 切到 true）。
    await tester.tap(find.byType(FlipCard));
    await tester.pump(); // 这一帧：flipped 变化，动画启动（value = 0）。

    // 50ms 后：正面 Opacity < 1、背面 Opacity > 0 —— 渐变确实在进行。
    await tester.pump(const Duration(milliseconds: 50));
    expect(opacity(tester, 'FRONT'), lessThan(1.0),
        reason: '50ms 时正面应已开始淡出（硬切 = bug）');
    expect(opacity(tester, 'BACK'), greaterThan(0.0),
        reason: '50ms 时背面应已开始淡入（硬切 = bug）');

    // 泵过 400ms 动画时长（1s 充足）：正面不可见、背面完全显示，状态完成。
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(opacity(tester, 'FRONT'), moreOrLessEquals(0.0));
    expect(opacity(tester, 'BACK'), moreOrLessEquals(1.0));

    // 反向翻回同样走渐变，且回到终态。
    await tester.tap(find.byType(FlipCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(opacity(tester, 'FRONT'), greaterThan(0.0));
    expect(opacity(tester, 'BACK'), lessThan(1.0));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(opacity(tester, 'FRONT'), moreOrLessEquals(1.0));
    expect(opacity(tester, 'BACK'), moreOrLessEquals(0.0));
  });
}

/// 深度优先检查 [e] 的子树里是否挂着文案为 [text] 的 Text。
bool _containsText(Element e, String text) {
  final w = e.widget;
  if (w is Text && w.data == text) return true;
  var found = false;
  e.visitChildren((child) {
    if (!found && _containsText(child, text)) found = true;
  });
  return found;
}
