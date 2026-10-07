import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenchang/models/models.dart';
import 'package:wenchang/services/favorites.dart';

/// 功能 B（收藏夹）数据层：
/// - `favorite_qids` 存储：toggle 收藏 / 取消往返、序列化顺序、损坏容错；
/// - [buildFavoriteQueue]：按收藏顺序出题（原生 + 自建）、缺失 qid 跳过。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Question question(String id) =>
      Question(id: id, sec: 's01-01', q: '题-$id', a: '答-$id', src: '');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Favorites 存储', () {
    test('toggle：收藏 ⇄ 取消往返，序列化进 favorite_qids 并可 reload', () async {
      final favorites = await Favorites.load();

      expect(await favorites.toggle('q-1'), isTrue, reason: '首次 = 收藏');
      expect(await favorites.toggle('q-2'), isTrue);
      expect(favorites.qids, ['q-1', 'q-2'], reason: '收藏序保留');
      expect(favorites.count, 2);

      expect(await favorites.toggle('q-1'), isFalse, reason: '再按 = 取消');
      expect(favorites.qids, ['q-2']);
      expect(favorites.isFavorite('q-1'), isFalse);
      expect(favorites.isFavorite('q-2'), isTrue);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kFavoriteQidsKey);
      expect(raw, isNotNull, reason: '每次切换都持久化');
      expect(raw, contains('q-2'));
      expect(raw, isNot(contains('q-1')));

      // reload 往返（JSON 字符串数组）。
      final reloaded = await Favorites.load();
      expect(reloaded.qids, ['q-2']);
      expect(reloaded.isFavorite('q-2'), isTrue);
    });

    test('空 qid 不落库；remove 只在已收藏时写盘', () async {
      final favorites = await Favorites.load();
      expect(await favorites.toggle(''), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kFavoriteQidsKey), isNull);

      await favorites.remove('从未收藏'); // 无事发生
      expect(prefs.getString(kFavoriteQidsKey), isNull);

      await favorites.toggle('q-9');
      await favorites.remove('q-9');
      expect(favorites.qids, isEmpty);
      expect(prefs.getString(kFavoriteQidsKey), contains('[]'));
    });

    test('损坏 / 非数组的存储 → 空收藏不崩溃；重复 id 去重', () async {
      SharedPreferences.setMockInitialValues({kFavoriteQidsKey: '{{{'});
      final broken = await Favorites.load();
      expect(broken.qids, isEmpty);

      SharedPreferences.setMockInitialValues({
        kFavoriteQidsKey: '{"not":"a list"}',
      });
      final notList = await Favorites.load();
      expect(notList.qids, isEmpty);

      SharedPreferences.setMockInitialValues({
        kFavoriteQidsKey: '["q-1","","q-1","q-2"]',
      });
      final dup = await Favorites.load();
      expect(dup.qids, ['q-1', 'q-2'], reason: '空串丢弃、重复去重、顺序保留');
    });
  });

  group('buildFavoriteQueue', () {
    test('按收藏顺序出题，原生 + 自建题都能命中', () {
      final native = [question('n-1'), question('n-2')];
      final custom = [question('cq-1')];

      final queue = buildFavoriteQueue(
        favoriteIds: {'cq-1', 'n-2', 'n-1'},
        nativeQuestions: native,
        customQuestions: custom,
      );
      expect(
        queue.map((e) => e.id).toList(),
        ['cq-1', 'n-2', 'n-1'],
        reason: '按收藏顺序（不按原生/自建分组）',
      );
      expect(queue.first, same(custom.first), reason: '命中的是共享题对象');
    });

    test('收藏里已不存在的 qid 跳过、同一 qid 不重复出题', () {
      final native = [question('n-1'), question('n-2')];
      final queue = buildFavoriteQueue(
        favoriteIds: ['n-1', '已删除的题', 'n-1', 'n-2'],
        nativeQuestions: native,
      );
      expect(queue.map((e) => e.id).toList(), ['n-1', 'n-2']);
    });

    test('空收藏 → 空队列（答题页据此给空态）', () {
      expect(
        buildFavoriteQueue(
          favoriteIds: const {},
          nativeQuestions: [question('n-1')],
        ),
        isEmpty,
      );
    });
  });
}
