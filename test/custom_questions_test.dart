import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenchang/models/models.dart';
import 'package:wenchang/services/app_data.dart';
import 'package:wenchang/services/content_overrides.dart';
import 'package:wenchang/services/custom_questions.dart';
import 'package:wenchang/services/favorites.dart';

/// 功能 A（添加习题）数据层：
/// - `custom_questions` 存储：cq- 毫秒 id、空值不落库、损坏容错、reload 往返；
/// - [buildPracticeQueue] 合并：命中板块并入、按 qid 去重、未命中不并入；
/// - 纠错覆盖按 qid 对自建题天然生效；
/// - [deleteCustomQuestion] 同一 helper 联动清条目 / 纠错覆盖 / 收藏标记。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Section sec(String id) =>
      Section(id: id, title: id, items: const [], bullets: const []);
  Question question(String id, String sectionId) => Question(
        id: id,
        sec: sectionId,
        q: '题-$id',
        a: '答-$id',
        src: '',
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CustomQuestions 存储', () {
    test('add：cq- 毫秒 id、trim、空值不落库、持久化 + reload 往返', () async {
      final store = await CustomQuestions.load();
      await store.add(sec: 's01-01', q: '  题干一 ', a: ' 答案一');
      await store.add(sec: 's01-02', q: '题干二', a: '答案二');

      expect(store.items, hasLength(2));
      expect(store.items.first.id, startsWith('cq-'));
      expect(
        int.parse(store.items.first.id.substring(3)),
        greaterThan(0),
        reason: 'id = cq-<毫秒时间戳>',
      );
      expect(store.items.first.q, '题干一', reason: '入库前 trim');
      expect(store.items.first.sec, 's01-01');

      // 题干 / 答案 / 板块任一为空 → 一律不落库。
      await store.add(sec: 's01-01', q: '   ', a: 'x');
      await store.add(sec: '', q: 'x', a: 'y');
      await store.add(sec: 's01-01', q: 'x', a: '  ');
      expect(store.items, hasLength(2));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kCustomQuestionsKey);
      expect(raw, isNotNull, reason: '已成功添加 → 必须持久化');
      expect(raw, contains('题干一'));

      // reload 往返：原文不丢，出题实例同步生成。
      final reloaded = await CustomQuestions.load();
      expect(reloaded.items.map((e) => e.q), ['题干一', '题干二']);
      expect(reloaded.questions, hasLength(2));
      expect(reloaded.questions.first.id, store.items.first.id);
      expect(reloaded.questions.first.src, '', reason: '自建题无出处');
      expect(reloaded.countFor('s01-01'), 1);
      expect(reloaded.countFor('s99-99'), 0);
    });

    test('损坏的存储 → 空列表不崩溃；无 id 的行被丢弃', () async {
      SharedPreferences.setMockInitialValues({
        kCustomQuestionsKey: 'not-json{{',
      });
      final broken = await CustomQuestions.load();
      expect(broken.items, isEmpty);

      SharedPreferences.setMockInitialValues({
        kCustomQuestionsKey:
            '[{"id":"","sec":"s01-01","q":"没 id","a":"a"},'
            '{"id":"cq-1","sec":"s01-01","q":"","a":"没题干"}]',
      });
      final partial = await CustomQuestions.load();
      expect(partial.items, isEmpty, reason: '无 id / 无题干的行都丢弃');
    });

    test('remove：删条目（含出题实例）并落盘', () async {
      final store = await CustomQuestions.load();
      await store.add(sec: 's01-01', q: '留下的题', a: 'a');
      await store.add(sec: 's01-01', q: '删掉的题', a: 'b');
      final doomed = store.items.last.id;

      await store.remove(doomed);
      expect(store.items.map((e) => e.q), ['留下的题']);
      expect(store.questions.map((e) => e.q), ['留下的题']);
      expect(store.countFor('s01-01'), 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kCustomQuestionsKey), isNot(contains('删掉的题')));
      // reload 一致。
      expect((await CustomQuestions.load()).items, hasLength(1));
    });
  });

  group('buildPracticeQueue 合并候选池', () {
    test('命中板块的自定义题并入、未命中不并入、按 qid 去重', () {
      final sections = [sec('s1'), sec('s2')];
      final bySec = {
        's1': [question('n1', 's1'), question('n2', 's1')],
        's2': [question('n3', 's2')],
        's9': [question('n9', 's9')],
      };
      final custom = [
        question('cq-1', 's1'),
        question('cq-2', 's2'),
        question('cq-3', 's9'), // 板块未勾选 → 不进池
      ];

      final queue = buildPracticeQueue(
        sections: sections,
        questionsBySec: bySec,
        customQuestions: custom,
      );
      expect(
        queue.map((e) => e.id).toList(),
        ['n1', 'n2', 'n3', 'cq-1', 'cq-2'],
        reason: '原生按勾选顺序在前，自建题随后；未命中的 s9 不进池',
      );

      // 同 qid 冲突（自建题 id 撞原生）→ 只留首个。
      final deduped = buildPracticeQueue(
        sections: sections,
        questionsBySec: bySec,
        customQuestions: [question('n1', 's1')],
      );
      expect(deduped.map((e) => e.id).toList(), ['n1', 'n2', 'n3']);
    });

    test('空 id 照旧不去重（与旧实现逐字一致）', () {
      final noId = Question(id: '', sec: 's1', q: 'q', a: 'a', src: '');
      final queue = buildPracticeQueue(
        sections: [sec('s1')],
        questionsBySec: {
          's1': [noId, noId],
        },
      );
      expect(queue, hasLength(2));
    });

    test('没选小节 / 没有自建题 → 空池', () {
      expect(
        buildPracticeQueue(
          sections: const [],
          questionsBySec: {'s1': [question('n1', 's1')]},
        ),
        isEmpty,
      );
      expect(
        buildPracticeQueue(
          sections: [sec('s1')],
          questionsBySec: const {},
          customQuestions: [question('cq-1', 's2')],
        ),
        isEmpty,
      );
    });
  });

  group('纠错覆盖 + 删除联动', () {
    test('attach 登记自建题：覆盖按 qid 就地生效，改回原文即删覆盖', () async {
      final store = await CustomQuestions.load();
      await store.add(sec: 's01-01', q: '自建题干', a: '自建答案');
      final overrides = await ContentOverrides.load();
      final data = await AppData.load();
      overrides.attach(data, customQuestions: store.questions);

      final target = store.questions.single;
      await overrides.saveQuestion(target.id, q: '改过的题干', a: '改过的答案');
      expect(target.q, '改过的题干', reason: '自建题实例被就地改写');
      expect(target.a, '改过的答案');

      // 改回原文 = 删除覆盖（同一套「纠错」语义）。
      await overrides.saveQuestion(target.id, q: '自建题干', a: '自建答案');
      expect(target.q, '自建题干');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('content_overrides') ?? '',
        isNot(contains(target.id)),
        reason: '覆盖已删除',
      );
    });

    test('deleteCustomQuestion：条目 + 纠错覆盖 + 收藏标记一并清掉', () async {
      final store = await CustomQuestions.load();
      await store.add(sec: 's01-01', q: '将被删除', a: '答案');
      final overrides = await ContentOverrides.load();
      final data = await AppData.load();
      overrides.attach(data, customQuestions: store.questions);
      final favorites = await Favorites.load();

      final target = store.questions.single;
      await overrides.saveQuestion(target.id, q: '纠错后的题干', a: '纠错答案');
      await favorites.toggle(target.id);
      expect(favorites.isFavorite(target.id), isTrue);

      await deleteCustomQuestion(store, overrides, favorites, target.id);

      expect(store.items, isEmpty);
      expect(store.questions, isEmpty);
      expect(favorites.isFavorite(target.id), isFalse);
      expect(target.q, '将被删除', reason: '覆盖被清掉后恢复原文');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kCustomQuestionsKey), contains('[]'));
      expect(
        prefs.getString(kFavoriteQidsKey) ?? '',
        isNot(contains(target.id)),
      );
      expect(
        prefs.getString('content_overrides') ?? '',
        isNot(contains(target.id)),
      );
    });

    test('没收藏 / 没覆盖的题删除同样不炸', () async {
      final store = await CustomQuestions.load();
      await store.add(sec: 's01-01', q: '干净的题', a: 'a');
      final overrides = await ContentOverrides.load();
      final favorites = await Favorites.load();

      await deleteCustomQuestion(
        store,
        overrides,
        favorites,
        store.items.single.id,
      );
      expect(store.items, isEmpty);
      expect(favorites.qids, isEmpty);
    });
  });
}
