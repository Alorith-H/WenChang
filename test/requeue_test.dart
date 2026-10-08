import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenchang/services/srs_logic.dart';
import 'package:wenchang/services/srs_service.dart';

/// 议题 #2（忘记重排）+ #7（标熟按钮）的数据层与纯函数测试：
/// - 忘记 → 入队尾、sessionRequeues=3 上限、超限正常结束；
/// - 完成口径（顶部计数 / 结束页分子）：忘记不加分、队尾重排答熟后才
///   +1、重复不叠加、恢复会话延续、旧存档缺字段降级；
/// - 已答去重 / 今日待复习剩余（首页口径，与完成口径分开）；
/// - forceMature / removeFromQueue：标熟的纯逻辑；
/// - SrsService：requeueInSession 持久化、grade(countStats:false) 不进
///   每日统计、markMature 落库并把题移出会话队列。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('忘记重排 requeueForgotten（纯函数）', () {
    test('忘记 → 追加到队尾，计数 +1，入参不被修改', () {
      final ids = ['q1', 'q2', 'q3'];
      final counts = <String, int>{};
      final out = requeueForgotten(ids, 'q2', counts);

      expect(out.appended, isTrue);
      expect(out.ids, ['q1', 'q2', 'q3', 'q2']);
      expect(out.requeues, {'q2': 1});
      expect(ids, ['q1', 'q2', 'q3'], reason: '纯函数不得改写入参');
      expect(counts, isEmpty);
    });

    test('再次忘记 → 再次追加；每题最多重排 kSessionRequeues=3 次', () {
      expect(kSessionRequeues, 3, reason: '上限 = 每题最多重排 3 次');

      var ids = ['q1', 'q2'];
      var counts = <String, int>{};
      var appended = 0;
      for (var i = 0; i < 5; i++) {
        final out = requeueForgotten(ids, 'q1', counts);
        ids = out.ids;
        counts = out.requeues;
        if (out.appended) appended++;
      }

      expect(appended, 3, reason: '第 4、5 次超限不再追加');
      expect(ids.where((e) => e == 'q1').length, 4, reason: '原始 1 次 + 重排 3 次');
      expect(ids.length, 5);
      expect(counts['q1'], 3);
    });

    test('超限 → 队列原样返回、appended=false（正常结束，不死循环）', () {
      final ids = ['a', 'b', 'a'];
      final out = requeueForgotten(ids, 'a', {'a': 3});
      expect(out.appended, isFalse);
      expect(out.ids, ['a', 'b', 'a']);
      expect(out.requeues, {'a': 3});
    });

    test('各题计数互不影响；空 id 不入队', () {
      final out = requeueForgotten(['x', 'y'], 'x', {'y': 3});
      expect(out.appended, isTrue, reason: 'y 到上限不影响 x');
      expect(out.requeues, {'y': 3, 'x': 1});

      final empty = requeueForgotten(['x'], '', {});
      expect(empty.appended, isFalse);
      expect(empty.ids, ['x']);
    });
  });

  group('完成口径（顶部计数 / 结束页分子）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('忘记不加分：重排 + 推进后 completed 仍为空', () async {
      final srs = await SrsService.load();
      await srs.startReviewSession(['q1', 'q2']);

      expect(await srs.requeueInSession('q1'), isTrue);
      await srs.advanceReviewSession();

      final session = srs.reviewSession!;
      expect(session.completed, isEmpty, reason: '忘记不计入完成 —— 分子不动');
      expect(session.ids.toSet().length, 2, reason: '分母也不因重排变化');
    });

    test('重排答熟后才加分；重复不叠加；分母不出现 11', () async {
      final srs = await SrsService.load();
      final ids = [for (var i = 1; i <= 10; i++) 'q$i'];
      await srs.startReviewSession(ids);

      // 首轮：q3 忘记重排，其余 9 题答成 生疏/熟练。
      for (final id in ids) {
        if (id == 'q3') {
          expect(await srs.requeueInSession(id), isTrue);
        } else {
          await srs.completeInSession(id);
        }
        await srs.advanceReviewSession();
      }
      var session = srs.reviewSession!;
      expect(
        '${session.completed.length} / ${session.ids.toSet().length}',
        '9 / 10',
        reason: '忘 1 → 完成 9/10；重排副本不推高分母',
      );
      expect(session.ids.length, 11, reason: '队列里确有 1 个重排副本');

      // 队尾的重排副本后来答熟 → 那时才 +1（同一题只 +1 一次）。
      await srs.completeInSession('q3');
      session = srs.reviewSession!;
      expect(session.completed.length, 10);
      expect(session.ids.toSet().length, 10, reason: '显示 10 就是 10');

      // 重复记入不叠加（幂等）。
      await srs.completeInSession('q3');
      expect(srs.reviewSession!.completed.length, 10, reason: '重复 +0');

      await srs.advanceReviewSession();
      expect(srs.reviewSession, isNull, reason: '队列走完 → 会话结束');
    });

    test('恢复会话：completed 随存档往返，重排 / 标熟移除都不丢', () async {
      final srs = await SrsService.load();
      await srs.startReviewSession(['q1', 'q2', 'q3']);
      await srs.completeInSession('q1');
      await srs.advanceReviewSession();
      expect(await srs.requeueInSession('q2'), isTrue); // q2 忘记追加副本
      await srs.markMature('q3'); // q3 标熟移出队列

      final back = (await SrsService.load()).reviewSession!;
      expect(back.completed, {'q1'}, reason: '恢复后分子延续，不回零');
      expect(back.completed.contains('q2'), isFalse, reason: '忘记过的 q2 仍未完成');
      expect(back.ids.toSet(), {'q1', 'q2'}, reason: 'q3 已移除、q2 副本保留');
    });

    test('旧存档缺 completed 字段 → 按已答前缀降级播种', () async {
      SharedPreferences.setMockInitialValues({
        'review_session': jsonEncode({
          'ids': ['q1', 'q2', 'q3'],
          'index': 2,
          'requeues': <String, int>{},
        }),
      });
      final srs = await SrsService.load();
      expect(
        srs.reviewSession!.completed,
        {'q1', 'q2'},
        reason: '缺字段 → 已答前缀播种，升级不丢已显示的进度',
      );

      // 之后继续按完成口径走：q3 答熟 +1，落盘为新格式。
      await srs.completeInSession('q3');
      final back = (await SrsService.load()).reviewSession!;
      expect(back.completed, {'q1', 'q2', 'q3'}, reason: '新格式持久化往返');
    });
  });

  group('已答去重 / 今日待复习剩余（首页口径）', () {
    test('distinctAnswered：已答口径（任何评级含忘记），前缀按题去重', () {
      expect(distinctAnswered(['q1', 'q2', 'q3'], 3), 3);
      expect(distinctAnswered(['q1', 'q2', 'q3'], 0), 0);

      // q2 忘记重排到队尾后又答了一遍：
      final ids = ['q1', 'q2', 'q3', 'q2'];
      expect(distinctAnswered(ids, 4), 3, reason: '重复作答不推高已答量');
      expect(distinctAnswered(ids, 99), 3, reason: '越界 clamp 到队尾');
    });

    test('distinctRemaining：首轮走完 + 1 题重排 → 剩余 0（首页口径）', () {
      // 10 题，q3 忘记重排在队尾；下标走完首轮（index=10）。
      // 这是首页「今日待复习」口径；顶部计数的完成口径见上一组
      // （忘 1 → 完成 9/10，两者互不替代）。
      final ids = [
        for (var i = 1; i <= 10; i++) 'q$i',
        'q3',
      ];
      expect(distinctRemaining(ids, 10), 0);
      // 旧口径 ids.length - index = 11 - 10 = 1 会把剩余虚增一天。
    });

    test('distinctRemaining：进行中只剩未答的题，重排副本不虚增', () {
      // 5 题答完 q1（忘记，重排在队尾）：剩余 = q2..q5 共 4 题。
      final ids = ['q1', 'q2', 'q3', 'q4', 'q5', 'q1'];
      expect(distinctRemaining(ids, 1), 4);
      expect(distinctAnswered(ids, 1) + distinctRemaining(ids, 1), 5,
          reason: '已答 + 剩余 = 去重总题数');
    });
  });

  group('标熟纯逻辑', () {
    test('forceMature：goodCount 至少补到 3、mature=true、due 清空', () {
      final fresh = forceMature(SrsState.initial());
      expect(fresh.goodCount, 3, reason: '与「累计 3 次毕业」同口径');
      expect(fresh.mature, isTrue);
      expect(fresh.due, isNull);

      final seasoned = forceMature(const SrsState(
        interval: 5,
        streak: 2,
        goodCount: 5,
        due: '2026-10-07',
      ));
      expect(seasoned.goodCount, 5, reason: '已有进度不回退');
      expect(seasoned.interval, 5);
      expect(seasoned.mature, isTrue);
      expect(seasoned.due, isNull, reason: '成熟态不再排期');
    });

    test('removeFromQueue：中间项移除，下标指向下一题', () {
      final r = removeFromQueue(['a', 'b', 'c'], 1, 'b');
      expect(r.ids, ['a', 'c']);
      expect(r.index, 1);
      expect(r.done, isFalse);
    });

    test('removeFromQueue：删空 → done（会话就此结束）', () {
      final r = removeFromQueue(['a'], 0, 'a');
      expect(r.ids, isEmpty);
      expect(r.done, isTrue);
    });

    test('removeFromQueue：全部副本（含队尾重排）一起移除、下标校正', () {
      // a 已答(0)、b 已答(1)、a 重排在 2；在 2 标熟 a → 只剩已答的 b。
      final r = removeFromQueue(['a', 'b', 'a'], 2, 'a');
      expect(r.ids, ['b']);
      expect(r.index, 1);
      expect(r.done, isTrue, reason: 'b 早已答过 → 队列走完');

      // 开局就在当前题标熟：下一题顶上来，进度不动。
      final head = removeFromQueue(['a', 'b', 'c'], 0, 'a');
      expect(head.ids, ['b', 'c']);
      expect(head.index, 0);
      expect(head.done, isFalse);
    });

    test('removeFromQueue：队列没有该题 → 原样', () {
      final r = removeFromQueue(['a', 'b'], 1, 'zz');
      expect(r.ids, ['a', 'b']);
      expect(r.index, 1);
      expect(r.done, isFalse);
    });
  });

  group('SrsService 通道（持久化）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('requeueInSession：入队 + 计数 + 3 次上限 + reload 往返', () async {
      final srs = await SrsService.load();
      await srs.startReviewSession(['q1', 'q2']);

      expect(await srs.requeueInSession('q1'), isTrue);
      expect(await srs.requeueInSession('q1'), isTrue);
      expect(await srs.requeueInSession('q1'), isTrue);
      expect(
        await srs.requeueInSession('q1'),
        isFalse,
        reason: '第 4 次超限：队列原样、正常结束',
      );

      final session = srs.reviewSession!;
      expect(session.ids, ['q1', 'q2', 'q1', 'q1', 'q1']);
      expect(session.requeues['q1'], 3);
      expect(session.index, 0, reason: '重排只追加队尾，不推进进度');

      // reload 往返：队列与计数都不丢，超限状态延续。
      final reloaded = await SrsService.load();
      final back = reloaded.reviewSession!;
      expect(back.ids, session.ids);
      expect(back.requeues['q1'], 3);
      expect(await reloaded.requeueInSession('q1'), isFalse);
    });

    test('grade(countStats:false)：重排重复作答不进每日统计，间隔照常', () async {
      final srs = await SrsService.load();
      final day = DateTime(2026, 10, 6);

      await srs.grade('q1', Grade.good, now: day);
      var total = srs.dailyTotals(1, day).single;
      expect(total.answers, 1);
      expect(total.good, 1);

      // 重排后的重复作答：SRS 状态照常推进，但 n/g 不再 +1。
      await srs.grade('q1', Grade.again, now: day, countStats: false);
      total = srs.dailyTotals(1, day).single;
      expect(total.answers, 1, reason: '重复作答不计入每日统计');
      expect(total.good, 1);
      expect(srs.stateOf('q1').due, '2026-10-07', reason: '忘记 → 间隔拉长逻辑不变');
      expect(srs.streak(day), 1, reason: '连续打卡按日期集合，天然幂等');
    });

    test('markMature：成熟态落库 + 移出会话队列 + reload 往返', () async {
      final srs = await SrsService.load();
      await srs.startReviewSession(['q1', 'q2', 'q3']);

      await srs.markMature('q2');
      final state = srs.stateOf('q2');
      expect(state.mature, isTrue);
      expect(state.goodCount, greaterThanOrEqualTo(3));
      expect(state.due, isNull);
      expect(srs.reviewSession!.ids, ['q1', 'q3']);
      expect(srs.reviewSession!.index, 0, reason: '当前项移除后下标指向下一题');

      final reloaded = await SrsService.load();
      expect(reloaded.stateOf('q2').mature, isTrue, reason: '成熟态持久化');
      expect(reloaded.reviewSession!.ids, ['q1', 'q3'], reason: '会话移除持久化');
    });

    test('markMature 重排副本：移除全部出现，走完即结束会话', () async {
      final srs = await SrsService.load();
      await srs.startReviewSession(['a', 'b']);
      expect(await srs.requeueInSession('a'), isTrue); // [a, b, a]
      await srs.advanceReviewSession(); // index 1（b 已答）
      await srs.advanceReviewSession(); // index 2（重排的 a）

      await srs.markMature('a');
      expect(srs.reviewSession, isNull, reason: '只剩已答的 b → 会话完成');
      expect(srs.stateOf('a').mature, isTrue);

      final reloaded = await SrsService.load();
      expect(reloaded.reviewSession, isNull, reason: '会话存档已删除');
    });

    test('markMature：无会话 / 空 id 也安全（只写成熟态）', () async {
      final srs = await SrsService.load();
      await srs.markMature('lonely');
      expect(srs.stateOf('lonely').mature, isTrue);
      expect(srs.reviewSession, isNull);

      await srs.markMature('');
      expect(srs.stateOf('').mature, isFalse, reason: '空 id 直接忽略');
    });
  });
}
