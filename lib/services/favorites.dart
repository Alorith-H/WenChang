/// 收藏夹：SharedPreferences `favorite_qids`（JSON 字符串数组）持久化，
/// 原生题与自定义题通用 —— 都按 qid 收藏 / 取消。
///
/// 要点：
/// - 内部 [Set] 保持插入序 = 收藏顺序，收藏夹队列按此顺序出题；
/// - 损坏的存储从空开始，绝不崩溃（与 content_overrides 同款容错）；
/// - 取消收藏只动标记：已开局的队列持有题对象照常答完，**下次**进入
///   收藏夹才消失（见 [buildFavoriteQueue]）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

const kFavoriteQidsKey = 'favorite_qids';

class Favorites extends ChangeNotifier {
  final SharedPreferences _prefs;

  /// 已收藏的 qid，插入序即收藏序。
  final Set<String> _qids;

  Favorites._(this._prefs, this._qids);

  static Future<Favorites> load() async {
    final prefs = await SharedPreferences.getInstance();
    final qids = <String>{};
    try {
      final raw = prefs.getString(kFavoriteQidsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is String && entry.isNotEmpty) qids.add(entry);
          }
        }
      }
    } catch (_) {
      // 损坏的收藏文件 → 从空开始，绝不崩溃。
    }
    return Favorites._(prefs, qids);
  }

  /// 全部收藏 qid（不可变副本，收藏序）。
  Set<String> get qids => Set<String>.unmodifiable(_qids);

  int get count => _qids.length;

  bool isFavorite(String qid) => _qids.contains(qid);

  /// 收藏 ⇄ 取消收藏，返回切换后是否处于收藏态（qid 为空时不落库）。
  Future<bool> toggle(String qid) async {
    if (qid.isEmpty) return false;
    final nowFavorite = !_qids.remove(qid);
    if (nowFavorite) _qids.add(qid);
    await _persist();
    notifyListeners();
    return nowFavorite;
  }

  /// 移除收藏标记（删除自定义题的联动清理走这里）。从未收藏则无事发生。
  Future<void> remove(String qid) async {
    if (!_qids.remove(qid)) return;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _prefs.setString(kFavoriteQidsKey, jsonEncode(_qids.toList()));
    } catch (_) {
      // Best effort: 收藏丢失也绝不能让界面崩溃。
    }
  }
}

/// 收藏夹队列：按**收藏顺序**取题（原生 + 自定义），收藏里已不存在的
/// qid（题被删除等）直接跳过、不重复出题。返回的都是共享题对象 ——
/// 中途取消收藏不影响已开局的队列（照常答完，下次进入才消失）。
List<Question> buildFavoriteQueue({
  required Iterable<String> favoriteIds,
  required Iterable<Question> nativeQuestions,
  Iterable<Question> customQuestions = const <Question>[],
}) {
  final byId = <String, Question>{};
  for (final q in nativeQuestions) {
    if (q.id.isNotEmpty) byId.putIfAbsent(q.id, () => q);
  }
  for (final q in customQuestions) {
    if (q.id.isNotEmpty) byId.putIfAbsent(q.id, () => q);
  }
  final queue = <Question>[];
  final emitted = <String>{};
  for (final id in favoriteIds) {
    if (!emitted.add(id)) continue; // 防御：同一 qid 只出一道。
    final q = byId[id];
    if (q != null) queue.add(q);
  }
  return queue;
}
