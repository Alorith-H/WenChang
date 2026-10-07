/// 用户自建题（习题模式 · 添加习题）：SharedPreferences `custom_questions`
/// JSON 数组持久化，加载 / 容错风格对齐 [ContentOverrides]。
///
/// 存储格式：
/// ```json
/// [{"id":"cq-1712345678901","sec":"s01-01","q":"题干","a":"答案"}]
/// ```
/// 要点：
/// - `sec` = 板块 id（与原生题同字段），命中该板块即并入习题候选池
///   （见 [buildPracticeQueue]），与原生题同等参与打乱 / 作答 / 历史；
/// - 出题用的 [Question] 实例启动时交给 `ContentOverrides.attach` 登记，
///   纠错覆盖按 qid 天然生效 —— 存储里永远是原文，覆盖单独存放；
/// - **v1 不进复习队列**：只被习题候选池 / 收藏夹引用，复习、打卡与
///   熟练度逻辑完全感知不到本存储。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'content_overrides.dart';
import 'favorites.dart';

const kCustomQuestionsKey = 'custom_questions';

/// 一道自建题的存储行：**原文快照**（纠错覆盖不回写这里，见
/// [ContentOverrides]）。
class CustomQuestion {
  final String id;
  final String sec;
  final String q;
  final String a;

  const CustomQuestion({
    required this.id,
    required this.sec,
    required this.q,
    required this.a,
  });

  /// 防御式解析：结构不对返回空 id 行（加载时直接丢弃）。
  factory CustomQuestion.fromJson(Object? json) {
    final m = json is Map<String, dynamic> ? json : null;
    if (m == null) return const CustomQuestion(id: '', sec: '', q: '', a: '');
    final id = m['id'];
    final sec = m['sec'];
    final q = m['q'];
    final a = m['a'];
    return CustomQuestion(
      id: id is String ? id : '',
      sec: sec is String ? sec : '',
      q: q is String ? q : '',
      a: a is String ? a : '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'sec': sec,
        'q': q,
        'a': a,
      };

  /// 出题实例：`src` 留空（自建题无出处），题干 / 答案可被纠错就地改写。
  Question toQuestion() => Question(id: id, sec: sec, q: q, a: a, src: '');
}

class CustomQuestions extends ChangeNotifier {
  final SharedPreferences _prefs;

  /// 存储原文（持久化来源；纠错覆盖不回写）。
  final List<CustomQuestion> _items;

  /// 出题实例，与 [_items] 一一对应 —— attach 时登记进 [ContentOverrides]，
  /// 纠错按 qid 就地生效，队列 / 详情读到的都是覆盖后的文本。
  final List<Question> _questions;

  CustomQuestions._(this._prefs, this._items, this._questions);

  static Future<CustomQuestions> load() async {
    final prefs = await SharedPreferences.getInstance();
    final items = <CustomQuestion>[];
    try {
      final raw = prefs.getString(kCustomQuestionsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            final item = CustomQuestion.fromJson(entry);
            // 无 id 无法引用、无题干不成题 → 丢弃该条，绝不崩溃。
            if (item.id.isEmpty || item.q.isEmpty) continue;
            items.add(item);
          }
        }
      }
    } catch (_) {
      // 损坏的存储 → 从空开始，绝不崩溃。
    }
    return CustomQuestions._(
      prefs,
      items,
      <Question>[for (final e in items) e.toQuestion()],
    );
  }

  /// 全部自建题（存储原文，按添加序）。
  List<CustomQuestion> get items => List<CustomQuestion>.unmodifiable(_items);

  /// 出题实例（按添加序；供候选池合并 / 收藏夹 / attach 登记）。
  List<Question> get questions => List<Question>.unmodifiable(_questions);

  /// 某板块下的自建题数（选题页计数并入）。
  int countFor(String secId) {
    if (secId.isEmpty) return 0;
    var n = 0;
    for (final item in _items) {
      if (item.sec == secId) n++;
    }
    return n;
  }

  /// 添加一题：板块 / 题干 / 答案任一为空一律不落库（调用方负责提示）。
  /// id = `cq-<毫秒时间戳>`，同毫秒连加兜底不撞。
  Future<void> add({
    required String sec,
    required String q,
    required String a,
  }) async {
    final trimmedQ = q.trim();
    final trimmedA = a.trim();
    if (sec.isEmpty || trimmedQ.isEmpty || trimmedA.isEmpty) return;

    var ts = DateTime.now().millisecondsSinceEpoch;
    var id = 'cq-$ts';
    while (_items.any((e) => e.id == id)) {
      ts += 1;
      id = 'cq-$ts';
    }

    final item = CustomQuestion(id: id, sec: sec, q: trimmedQ, a: trimmedA);
    _items.add(item);
    _questions.add(item.toQuestion());
    await _persist();
    notifyListeners();
  }

  /// 删除一题（纠错覆盖与收藏标记的联动清理请走 [deleteCustomQuestion]）。
  Future<void> remove(String id) async {
    final index = _items.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _items.removeAt(index);
    _questions.removeAt(index);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _prefs.setString(
        kCustomQuestionsKey,
        jsonEncode([for (final e in _items) e.toJson()]),
      );
    } catch (_) {
      // Best effort: 自建题丢失也绝不能让界面崩溃。
    }
  }
}

/// 习题候选池：按小节勾选顺序收集原生题，再把**命中板块**的自定义题
/// 并入 —— 与原生题同等参与后续打乱 / 作答 / 历史。按 qid 去重（与旧
/// 实现一致：空 id 照旧不去重），自定义题排在原生题之后。
List<Question> buildPracticeQueue({
  required Iterable<Section> sections,
  required Map<String, List<Question>> questionsBySec,
  Iterable<Question> customQuestions = const <Question>[],
}) {
  final seen = <String>{};
  final queue = <Question>[];

  void enqueue(Question q) {
    if (q.id.isNotEmpty && !seen.add(q.id)) return;
    queue.add(q);
  }

  final secIds = <String>{};
  for (final section in sections) {
    secIds.add(section.id);
    for (final q in questionsBySec[section.id] ?? const <Question>[]) {
      enqueue(q);
    }
  }
  for (final q in customQuestions) {
    if (secIds.contains(q.sec)) enqueue(q);
  }
  return queue;
}

/// 删除一道自定义题的**同一 helper**：题库条目、其纠错覆盖与收藏标记
/// 一并清掉 —— 三者联动，绝不留下指向已删题的孤儿数据。
Future<void> deleteCustomQuestion(
  CustomQuestions store,
  ContentOverrides overrides,
  Favorites favorites,
  String id,
) async {
  await store.remove(id);
  await overrides.removeQuestion(id);
  await favorites.remove(id);
}
