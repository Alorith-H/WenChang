/// 用户纠错覆盖：SharedPreferences `content_overrides` 持久化，加载后
/// 合并进已加载的 [AppData] 数据树（就地改写，见 [Bullet.t] / [Question.q]）。
///
/// 存储格式：
/// ```json
/// {
///   "bullet":  {"{sectionId}:{itemIndex}:{bulletIndex}": "新文本"},
///   "question": {"{qid}": {"q": "新题干", "a": "新答案"}}
/// }
/// ```
/// 要点 key 的 itemIndex = -1 表示板块顶层 bullets，≥0 表示 items 下第
/// 几个条目的 bullets —— key 只依赖当前数据结构的下标，结构不变则稳定。
///
/// 合并语义：**未编辑**的条目原样保留（含红字 segs）；被覆盖的要点
/// 置 segs = null 按纯文本渲染（红字标记让位，可接受）；保存时若文本
/// 与原文一致则删除覆盖、恢复红字。保存后 notifyListeners —— 订阅了
/// 本对象的页面立即重建，后续导航读到的也都是覆盖后的内容。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'app_data.dart';

const _kOverridesKey = 'content_overrides';

/// 某条要点被覆盖前的原文与红字分段 —— 保存回原文时用来恢复 segs。
class _OrigBullet {
  final String t;
  final List<BulletSeg>? segs;

  const _OrigBullet(this.t, this.segs);
}

/// 某题被覆盖前的原文。
class _OrigQuestion {
  final String q;
  final String a;

  const _OrigQuestion(this.q, this.a);
}

class ContentOverrides extends ChangeNotifier {
  final SharedPreferences _prefs;

  /// bullet key → 覆盖文本。
  final Map<String, String> _bullets;

  /// qid → `{q, a}` 覆盖（至少含一个字段）。
  final Map<String, Map<String, String>> _questions;

  /// section id → 数据树里的 Section（首个为准）。
  final Map<String, Section> _sections = {};

  /// qid → 数据树里的 Question。
  final Map<String, Question> _questionById = {};

  /// 覆盖前的原文快照（attach 时采集），用于「改回原文 = 删除覆盖」。
  final Map<String, _OrigBullet> _origBullets = {};
  final Map<String, _OrigQuestion> _origQuestions = {};

  ContentOverrides._(this._prefs, this._bullets, this._questions);

  /// 覆盖存储的要点 key：`{sectionId}:{itemIndex}:{bulletIndex}`，
  /// itemIndex = -1 为板块顶层 bullets。
  static String bulletKey(String sectionId, int itemIndex, int bulletIndex) =>
      '$sectionId:$itemIndex:$bulletIndex';

  static Future<ContentOverrides> load() async {
    final prefs = await SharedPreferences.getInstance();
    final bullets = <String, String>{};
    final questions = <String, Map<String, String>>{};
    try {
      final raw = prefs.getString(_kOverridesKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final b = decoded['bullet'];
          if (b is Map<String, dynamic>) {
            b.forEach((k, v) {
              if (v is String && v.isNotEmpty) bullets[k] = v;
            });
          }
          final q = decoded['question'];
          if (q is Map<String, dynamic>) {
            q.forEach((k, v) {
              if (v is Map<String, dynamic>) {
                final text = <String, String>{
                  if (v['q'] is String && (v['q'] as String).isNotEmpty)
                    'q': v['q'] as String,
                  if (v['a'] is String && (v['a'] as String).isNotEmpty)
                    'a': v['a'] as String,
                };
                if (text.isNotEmpty) questions[k] = text;
              }
            });
          }
        }
      }
    } catch (_) {
      // 损坏的覆盖文件 → 从空开始，绝不崩溃。
    }
    return ContentOverrides._(prefs, bullets, questions);
  }

  /// 把持久化的覆盖合并进 [data] 的数据树，并记住树里各条目的位置 ——
  /// 必须在 AppData 加载后、界面首绘前调用一次。
  ///
  /// [customQuestions] = 自建题的出题实例（`CustomQuestions.questions`）：
  /// 它们不在数据树里，但同样按 qid 登记原文快照并套用覆盖 —— 自建题的
  /// 纠错因此与原生题走同一套存储与生效路径（按 qid 天然生效）。
  void attach(AppData data, {Iterable<Question> customQuestions = const []}) {
    _sections.clear();
    _questionById.clear();
    _origBullets.clear();
    _origQuestions.clear();

    for (final chapter in data.chapters) {
      for (final section in chapter.sections) {
        if (section.id.isEmpty) continue;
        _sections.putIfAbsent(section.id, () => section);
        _snapshotSection(section);
      }
    }
    for (final q in data.questions) {
      if (q.id.isEmpty) continue;
      _questionById.putIfAbsent(q.id, () => q);
      _origQuestions.putIfAbsent(q.id, () => _OrigQuestion(q.q, q.a));
    }
    for (final q in customQuestions) {
      if (q.id.isEmpty) continue;
      _questionById.putIfAbsent(q.id, () => q);
      _origQuestions.putIfAbsent(q.id, () => _OrigQuestion(q.q, q.a));
    }

    for (final key in _bullets.keys) {
      _applyBullet(key);
    }
    for (final key in _questions.keys) {
      _applyQuestion(key);
    }
  }

  void _snapshotSection(Section section) {
    for (var i = 0; i < section.bullets.length; i++) {
      final key = bulletKey(section.id, -1, i);
      _origBullets.putIfAbsent(
        key,
        () => _OrigBullet(section.bullets[i].t, section.bullets[i].segs),
      );
    }
    for (var itemIndex = 0; itemIndex < section.items.length; itemIndex++) {
      final bullets = section.items[itemIndex].bullets;
      for (var i = 0; i < bullets.length; i++) {
        final key = bulletKey(section.id, itemIndex, i);
        _origBullets.putIfAbsent(
          key,
          () => _OrigBullet(bullets[i].t, bullets[i].segs),
        );
      }
    }
  }

  /// 批量保存要点覆盖：文本与原文一致（或清空）= 删除覆盖恢复红字，
  /// 否则写入覆盖并就地改写数据树，一次持久化 + 一次通知。
  Future<void> saveBullets(Map<String, String> edits) async {
    var changed = false;
    edits.forEach((key, text) {
      final trimmed = text.trim();
      final origT = _origBullets[key]?.t;
      var keyChanged = false;
      if (trimmed.isEmpty || trimmed == origT) {
        keyChanged = _bullets.remove(key) != null;
      } else if (_bullets[key] != trimmed) {
        _bullets[key] = trimmed;
        keyChanged = true;
      }
      if (keyChanged) {
        changed = true;
        _applyBullet(key);
      }
    });
    if (!changed) return;
    await _persist();
    notifyListeners();
  }

  /// 保存一道题的题干 + 答案（空输入回落原文；与原文一致 = 删除覆盖）。
  Future<void> saveQuestion(
    String qid, {
    required String q,
    required String a,
  }) async {
    if (qid.isEmpty) return;
    final orig = _origQuestions[qid];
    final trimmedQ = q.trim();
    final trimmedA = a.trim();
    final effQ = trimmedQ.isEmpty ? (orig?.q ?? '') : trimmedQ;
    final effA = trimmedA.isEmpty ? (orig?.a ?? '') : trimmedA;

    var changed = false;
    if (orig != null && effQ == orig.q && effA == orig.a) {
      if (_questions.remove(qid) != null) changed = true;
    } else if (_questions[qid]?['q'] != effQ || _questions[qid]?['a'] != effA) {
      _questions[qid] = {'q': effQ, 'a': effA};
      changed = true;
    }
    if (!changed) return;
    _applyQuestion(qid);
    await _persist();
    notifyListeners();
  }

  /// 删除某题的题级覆盖（删除自建题时的联动清理走这里，见
  /// `deleteCustomQuestion`）。登记过的题会立即恢复原文，随后持久化
  /// 并通知；本来就没有覆盖时不落盘。
  Future<void> removeQuestion(String qid) async {
    if (qid.isEmpty) return;
    final removed = _questions.remove(qid) != null;
    _applyQuestion(qid);
    if (!removed) return;
    await _persist();
    notifyListeners();
  }

  /// 按 key 定位要点并把（覆盖后/恢复后的）文本就地写回数据树。
  void _applyBullet(String key) {
    final parts = key.split(':');
    if (parts.length != 3) return;
    final itemIndex = int.tryParse(parts[1]);
    final bulletIndex = int.tryParse(parts[2]);
    if (itemIndex == null || bulletIndex == null) return;
    final section = _sections[parts[0]];
    if (section == null) return;

    final Bullet? bullet;
    if (itemIndex < 0) {
      bullet = (bulletIndex >= 0 && bulletIndex < section.bullets.length)
          ? section.bullets[bulletIndex]
          : null;
    } else {
      bullet = (itemIndex < section.items.length &&
              bulletIndex >= 0 &&
              bulletIndex < section.items[itemIndex].bullets.length)
          ? section.items[itemIndex].bullets[bulletIndex]
          : null;
    }
    if (bullet == null) return;

    final override = _bullets[key];
    if (override == null) {
      final orig = _origBullets[key];
      if (orig != null) {
        bullet.t = orig.t;
        bullet.segs = orig.segs; // 恢复红字。
      }
    } else {
      bullet.t = override;
      bullet.segs = null; // 覆盖后按纯文本渲染（红字标记让位）。
    }
  }

  /// 按 qid 把（覆盖后/恢复后的）题干与答案就地写回数据树。
  void _applyQuestion(String qid) {
    final question = _questionById[qid];
    if (question == null) return;
    final override = _questions[qid];
    if (override == null) {
      final orig = _origQuestions[qid];
      if (orig != null) {
        question.q = orig.q;
        question.a = orig.a;
      }
      return;
    }
    final q = override['q'];
    final a = override['a'];
    if (q != null) question.q = q;
    if (a != null) question.a = a;
  }

  Future<void> _persist() async {
    try {
      await _prefs.setString(_kOverridesKey, jsonEncode({
        'bullet': _bullets,
        'question': _questions,
      }));
    } catch (_) {
      // Best effort: 纠错内容丢失也绝不能让界面崩溃。
    }
  }
}
