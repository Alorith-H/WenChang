/// 题库 / 资料 备份的**纯函数**层（议题 #3）：导出结构、导入校验与两种
/// 导入模式（覆盖 / 差异）的合并语义 —— 一行不碰 IO 与 SharedPreferences，
/// 全部可脱离 Flutter 环境单测。落库见 `imported_bank.dart`，入口见设置页。
///
/// 导出文件（一个 JSON，结构自定但要完整可还原）：
/// ```json
/// {
///   "formatVersion": 1,
///   "exportedAt": "2026-10-07T12:00:00.000",
///   "stats": {"questionCount": 100, "chapterCount": 12, ...},
///   "questions": [...],         // 生效题库（导入版或 assets 版）
///   "source": {...},            // 生效资料
///   "overrides": {...},         // 用户纠错（content_overrides 原样）
///   "custom_questions": [...],  // 自建题
///   "favorite_qids": [...]      // 收藏
/// }
/// ```
///
/// 两种导入模式（对应 issue #3 原文）：
/// - **覆盖**：题库 + 资料整体替换为文件内容；纠错 / 自建题 / 收藏也用
///   文件里的替换，**文件缺这些段则保留现状**；
/// - **差异**：逐条对比 —— id 相同但内容不同 → 替换为文件版；文件里有而
///   本地没有 → 新增；本地有而文件没有 → 保留；纠错 / 自建题 / 收藏按
///   同规则合并（id 相同以文件为准）。
///
/// 红线：任何模式都不产出 SRS 进度 / 打卡 / 练习历史相关键 —— 板块 id 与
/// 题 id 体系不变，导入后进度自然保留。
library;

import 'dart:convert';

import '../models/models.dart';
import 'custom_questions.dart';

/// 当前支持的备份格式版本；导入遇到更高版本直接拒绝。
const kBackupFormatVersion = 1;

/// 一份备份数据：解析后的导入文件，或导入时的本地现状快照。
///
/// [overrides] / [custom] / [favoriteQids] 可空 —— 导出文件允许缺这几段
/// （覆盖模式下缺段 = 保留本地现状，见 [applyReplace]）；[questions] 与
/// [source] 必填（[parseBackup] 已校验）。
class BackupData {
  final List<Question> questions;
  final SourceDoc source;

  /// 纠错覆盖，结构同 `content_overrides`：`{bullet: {...}, question: {...}}`。
  final Map<String, dynamic>? overrides;

  /// 自建题（存储原文，同 `custom_questions`）。
  final List<CustomQuestion>? custom;

  /// 收藏 qid（同 `favorite_qids`）。
  final List<String>? favoriteQids;

  /// 元数据：`formatVersion` / `exportedAt` / `stats`（本地现状快照为空）。
  final Map<String, dynamic> meta;

  const BackupData({
    required this.questions,
    required this.source,
    this.overrides,
    this.custom,
    this.favoriteQids,
    this.meta = const {},
  });
}

/// [parseBackup] 的结果：成功携带 [backup]，失败携带可直接进 SnackBar
/// 的中文错误文案（`backup == null` 即失败）。
class BackupParseResult {
  final BackupData? backup;
  final String? error;

  const BackupParseResult.success(this.backup) : error = null;
  const BackupParseResult.failure(this.error) : backup = null;

  bool get ok => backup != null;
}

/// 解析 + 校验备份文件（纯函数，失败绝不落库）：
/// - 不是 JSON / 根节点不是对象 → 明确报错；
/// - `questions` 缺失、不是数组、题数为 0、任一条缺 id/q/a → 报错并指出第几题；
/// - `source` 缺失、不是对象、没有章节 → 报错；
/// - `overrides` / `custom_questions` / `favorite_qids` 结构不对 → 报错；
/// - `formatVersion` 高于当前支持 → 提示升级 App。
BackupParseResult parseBackup(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const BackupParseResult.failure('文件不是有效的 JSON');
  }
  if (decoded is! Map<String, dynamic>) {
    return const BackupParseResult.failure('文件格式错误：根节点应为 JSON 对象');
  }
  final m = decoded;

  final version = m['formatVersion'];
  if (version is num && version > kBackupFormatVersion) {
    return BackupParseResult.failure(
      '备份版本过新（v${version.toInt()}），请升级 App 后再导入',
    );
  }

  final rawQuestions = m['questions'];
  if (rawQuestions is! List) {
    return const BackupParseResult.failure('文件缺少题库（questions 段）');
  }
  if (rawQuestions.isEmpty) {
    return const BackupParseResult.failure('题库为空：文件里没有任何题目');
  }
  for (var i = 0; i < rawQuestions.length; i++) {
    final entry = rawQuestions[i];
    final ok = entry is Map &&
        entry['id'] is String &&
        (entry['id'] as String).isNotEmpty &&
        entry['q'] is String &&
        (entry['q'] as String).isNotEmpty &&
        entry['a'] is String &&
        (entry['a'] as String).isNotEmpty;
    if (!ok) {
      return BackupParseResult.failure(
        '第 ${i + 1} 题格式非法：缺少 id / q / a',
      );
    }
  }

  final rawSource = m['source'];
  if (rawSource == null) {
    return const BackupParseResult.failure('文件缺少资料（source 段）');
  }
  if (rawSource is! Map) {
    return const BackupParseResult.failure('资料（source）格式错误');
  }
  final chapters = rawSource['chapters'];
  if (chapters is! List || chapters.isEmpty) {
    return const BackupParseResult.failure('资料（source）没有章节，无法导入');
  }

  final rawOverrides = m['overrides'];
  if (rawOverrides != null && rawOverrides is! Map) {
    return const BackupParseResult.failure('纠错（overrides）格式错误');
  }

  final rawCustom = m['custom_questions'];
  if (rawCustom != null) {
    if (rawCustom is! List) {
      return const BackupParseResult.failure('自建题（custom_questions）格式错误');
    }
    for (var i = 0; i < rawCustom.length; i++) {
      final entry = rawCustom[i];
      final ok = entry is Map &&
          entry['id'] is String &&
          (entry['id'] as String).isNotEmpty &&
          entry['q'] is String &&
          (entry['q'] as String).isNotEmpty;
      if (!ok) {
        return BackupParseResult.failure(
          '自建题第 ${i + 1} 条格式非法：缺少 id / q',
        );
      }
    }
  }

  final rawFavorites = m['favorite_qids'];
  if (rawFavorites != null && rawFavorites is! List) {
    return const BackupParseResult.failure('收藏（favorite_qids）格式错误');
  }

  return BackupParseResult.success(
    BackupData(
      questions: [for (final e in rawQuestions) Question.fromJson(e)],
      source: SourceDoc.fromJson(rawSource),
      overrides: rawOverrides == null
          ? null
          : Map<String, dynamic>.from(rawOverrides as Map),
      custom: rawCustom == null
          ? null
          : [for (final e in rawCustom as List) CustomQuestion.fromJson(e)],
      favoriteQids: rawFavorites == null
          ? null
          : [
              for (final e in rawFavorites as List)
                if (e is String && e.isNotEmpty) e,
            ],
      meta: <String, dynamic>{
        'formatVersion': ?version,
        if (m['exportedAt'] != null) 'exportedAt': m['exportedAt'],
        if (m['stats'] != null) 'stats': m['stats'],
      },
    ),
  );
}

/// 构建导出 JSON（纯函数；编码失败由 [encodeBackup] 向上抛，调用方
/// SnackBar 兜底）。[exportedAt] 可注入，便于测试往返。
Map<String, dynamic> buildBackupJson({
  required List<Question> questions,
  required SourceDoc source,
  required Map<String, dynamic> overrides,
  required List<CustomQuestion> customQuestions,
  required Iterable<String> favoriteQids,
  DateTime? exportedAt,
}) {
  final at = exportedAt ?? DateTime.now();
  final sectionCount = source.chapters.fold(
    0,
    (sum, c) => sum + c.sections.length,
  );
  final favorites = favoriteQids.toList();
  final bulletOverrides = overrides['bullet'];
  final questionOverrides = overrides['question'];
  return <String, dynamic>{
    'formatVersion': kBackupFormatVersion,
    'exportedAt': at.toIso8601String(),
    'stats': <String, dynamic>{
      'questionCount': questions.length,
      'chapterCount': source.chapters.length,
      'sectionCount': sectionCount,
      'customCount': customQuestions.length,
      'favoriteCount': favorites.length,
      'overrideCount': (bulletOverrides is Map ? bulletOverrides.length : 0) +
          (questionOverrides is Map ? questionOverrides.length : 0),
    },
    'questions': [for (final q in questions) q.toJson()],
    'source': source.toJson(),
    'overrides': overrides,
    'custom_questions': [for (final c in customQuestions) c.toJson()],
    'favorite_qids': favorites,
  };
}

/// 编码导出 JSON 文本（结构非法时 jsonEncode 向上抛，调用方捕获提示）。
String encodeBackup({
  required List<Question> questions,
  required SourceDoc source,
  required Map<String, dynamic> overrides,
  required List<CustomQuestion> customQuestions,
  required Iterable<String> favoriteQids,
  DateTime? exportedAt,
}) =>
    jsonEncode(
      buildBackupJson(
        questions: questions,
        source: source,
        overrides: overrides,
        customQuestions: customQuestions,
        favoriteQids: favoriteQids,
        exportedAt: exportedAt,
      ),
    );

/// 备份文件名：`wenchang-backup-YYYYMMDD.json`。
String backupFileName(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'wenchang-backup-${at.year}${two(at.month)}${two(at.day)}.json';
}

bool _sameQuestion(Question a, Question b) =>
    a.sec == b.sec && a.q == b.q && a.a == b.a && a.src == b.src;

/// 深比较（导入时一次性调用，jsonEncode 足够快且显然正确）。
bool _sameJson(Object? a, Object? b) =>
    jsonEncode(a) == jsonEncode(b);

/// [mergeQuestionsById] 的结果：合并后的列表 + 三分支计数。
class QuestionMergeResult {
  /// 本地序在前（同 id 的被文件版原地替换），文件独有追加在尾部。
  final List<Question> merged;

  /// 文件里有而本地没有 → 新增。
  final int added;

  /// id 相同但内容不同 → 替换为文件版。
  final int replaced;

  /// 本地独有（文件没有）或内容相同 → 保留。
  final int kept;

  const QuestionMergeResult({
    required this.merged,
    required this.added,
    required this.replaced,
    required this.kept,
  });
}

/// 题库差异合并（issue #3「差异」语义的逐条实现）。
///
/// 空 id 无法引用：本地空 id 条目原样保留；文件空 id 条目跳过（导入校验
/// 已在入口挡住）。文件内重复 id 只取首个。
QuestionMergeResult mergeQuestionsById({
  required List<Question> local,
  required List<Question> incoming,
}) {
  final incomingById = <String, Question>{};
  for (final q in incoming) {
    if (q.id.isNotEmpty) incomingById.putIfAbsent(q.id, () => q);
  }

  final matched = <String>{};
  final merged = <Question>[];
  var added = 0, replaced = 0, kept = 0;
  for (final q in local) {
    final match = q.id.isEmpty ? null : incomingById[q.id];
    if (match == null) {
      merged.add(q);
      kept++;
      continue;
    }
    matched.add(q.id);
    if (_sameQuestion(q, match)) {
      merged.add(q);
      kept++;
    } else {
      merged.add(match);
      replaced++;
    }
  }

  final appended = <String>{};
  for (final q in incoming) {
    if (q.id.isEmpty || matched.contains(q.id)) continue;
    if (!appended.add(q.id)) continue; // 文件内重复 id → 只收首个。
    merged.add(q);
    added++;
  }
  return QuestionMergeResult(
    merged: merged,
    added: added,
    replaced: replaced,
    kept: kept,
  );
}

/// [mergeSourceById] 的结果。
class SourceMergeResult {
  final SourceDoc merged;
  final int chaptersAdded;
  final int sectionsAdded;
  final int sectionsReplaced;

  const SourceMergeResult({
    required this.merged,
    required this.chaptersAdded,
    required this.sectionsAdded,
    required this.sectionsReplaced,
  });
}

/// 资料（章节树）差异合并：章与板块都按 id 走三分支 ——
/// 文件独有 → 新增；同 id 内容不同 → 文件版（章内板块继续逐条合并，
/// 本地独有的板块仍保留）；本地独有 → 保留。文档级 title / subtitle 取
/// 文件版。空 id 的条目不参与匹配（无 id 不可引用）。
SourceMergeResult mergeSourceById({
  required SourceDoc local,
  required SourceDoc incoming,
}) {
  final incomingChapters = <String, Chapter>{};
  for (final c in incoming.chapters) {
    if (c.id.isNotEmpty) incomingChapters.putIfAbsent(c.id, () => c);
  }

  final matched = <String>{};
  final chapters = <Chapter>[];
  var chaptersAdded = 0, sectionsAdded = 0, sectionsReplaced = 0;
  for (final localChapter in local.chapters) {
    final match = localChapter.id.isEmpty
        ? null
        : incomingChapters[localChapter.id];
    if (match == null) {
      chapters.add(localChapter);
      continue;
    }
    matched.add(localChapter.id);
    if (_sameJson(localChapter, match)) {
      chapters.add(localChapter);
      continue;
    }
    final sub = _mergeSections(
      local: localChapter.sections,
      incoming: match.sections,
    );
    sectionsAdded += sub.added;
    sectionsReplaced += sub.replaced;
    chapters.add(
      Chapter(id: localChapter.id, title: match.title, sections: sub.merged),
    );
  }

  final appended = <String>{};
  for (final c in incoming.chapters) {
    if (c.id.isEmpty || matched.contains(c.id)) continue;
    if (!appended.add(c.id)) continue;
    chapters.add(c);
    chaptersAdded++;
    sectionsAdded += c.sections.length;
  }
  return SourceMergeResult(
    merged: SourceDoc(
      title: incoming.title,
      subtitle: incoming.subtitle,
      chapters: chapters,
    ),
    chaptersAdded: chaptersAdded,
    sectionsAdded: sectionsAdded,
    sectionsReplaced: sectionsReplaced,
  );
}

/// 章内板块的三分支合并（同 id 深比较，内容不同 → 文件版整块替换）。
({List<Section> merged, int added, int replaced}) _mergeSections({
  required List<Section> local,
  required List<Section> incoming,
}) {
  final incomingById = <String, Section>{};
  for (final s in incoming) {
    if (s.id.isNotEmpty) incomingById.putIfAbsent(s.id, () => s);
  }
  final matched = <String>{};
  final merged = <Section>[];
  var added = 0, replaced = 0;
  for (final s in local) {
    final match = s.id.isEmpty ? null : incomingById[s.id];
    if (match == null) {
      merged.add(s);
      continue;
    }
    matched.add(s.id);
    if (_sameJson(s, match)) {
      merged.add(s);
    } else {
      merged.add(match);
      replaced++;
    }
  }
  final appended = <String>{};
  for (final s in incoming) {
    if (s.id.isEmpty || matched.contains(s.id)) continue;
    if (!appended.add(s.id)) continue;
    merged.add(s);
    added++;
  }
  return (merged: merged, added: added, replaced: replaced);
}

/// 纠错覆盖差异合并：按 key（bullet key / qid）同规则 ——
/// 文件覆盖同 key（id 相同以文件为准），本地独有的 key 保留。
/// `bullet` / `question` 两个子表分别合并，其余顶层键两份并存（文件优先）。
Map<String, dynamic> mergeOverridesById({
  required Map<String, dynamic> local,
  required Map<String, dynamic> incoming,
}) {
  Map<String, dynamic> mergeSub(String key) {
    final l = local[key];
    final i = incoming[key];
    return <String, dynamic>{
      if (l is Map<String, dynamic>) ...l,
      if (i is Map<String, dynamic>) ...i,
    };
  }

  bool isCore(String key) => key == 'bullet' || key == 'question';
  return <String, dynamic>{
    for (final e in local.entries)
      if (isCore(e.key)) e.key: e.value,
    for (final e in incoming.entries)
      if (isCore(e.key)) e.key: e.value,
    'bullet': mergeSub('bullet'),
    'question': mergeSub('question'),
  };
}

/// [mergeCustomById] 的结果。
class CustomMergeResult {
  final List<CustomQuestion> merged;
  final int added;
  final int replaced;
  final int kept;

  const CustomMergeResult({
    required this.merged,
    required this.added,
    required this.replaced,
    required this.kept,
  });
}

/// 自建题差异合并：与题库同一套三分支语义（按 id，文件版优先）。
CustomMergeResult mergeCustomById({
  required List<CustomQuestion> local,
  required List<CustomQuestion> incoming,
}) {
  final incomingById = <String, CustomQuestion>{};
  for (final c in incoming) {
    if (c.id.isNotEmpty) incomingById.putIfAbsent(c.id, () => c);
  }
  final matched = <String>{};
  final merged = <CustomQuestion>[];
  var added = 0, replaced = 0, kept = 0;
  for (final c in local) {
    final match = c.id.isEmpty ? null : incomingById[c.id];
    if (match == null) {
      merged.add(c);
      kept++;
      continue;
    }
    matched.add(c.id);
    final same = c.sec == match.sec && c.q == match.q && c.a == match.a;
    if (same) {
      merged.add(c);
      kept++;
    } else {
      merged.add(match);
      replaced++;
    }
  }
  final appended = <String>{};
  for (final c in incoming) {
    if (c.id.isEmpty || matched.contains(c.id)) continue;
    if (!appended.add(c.id)) continue;
    merged.add(c);
    added++;
  }
  return CustomMergeResult(
    merged: merged,
    added: added,
    replaced: replaced,
    kept: kept,
  );
}

/// 收藏差异合并：并集去重 —— 本地序在前，文件独有的 qid 追加在尾
/// （id 相同以文件为准对集合无感，本地独有按规则保留）。
List<String> mergeFavoriteIds({
  required List<String> local,
  required List<String> incoming,
}) {
  final merged = <String>[];
  final seen = <String>{};
  for (final id in <String>[...local, ...incoming]) {
    if (id.isEmpty || !seen.add(id)) continue;
    merged.add(id);
  }
  return merged;
}

/// **覆盖**模式（issue #3「覆盖」）：题库 + 资料整体替换为文件内容；
/// 纠错 / 自建题 / 收藏也用文件里的替换，文件缺哪段就保留本地（[local]）
/// 哪段 —— `BackupData` 对应字段为 null 即「文件缺该段」。
BackupData applyReplace({required BackupData file, required BackupData local}) {
  return BackupData(
    questions: file.questions,
    source: file.source,
    overrides: file.overrides ?? local.overrides,
    custom: file.custom ?? local.custom,
    favoriteQids: file.favoriteQids ?? local.favoriteQids,
    meta: file.meta,
  );
}

/// [applyDiff] 的结果：合并后的数据 + 实数统计（进 SnackBar 文案）。
class DiffOutcome {
  final BackupData data;
  final int questionsAdded;
  final int questionsReplaced;
  final int questionsKept;
  final int chaptersAdded;
  final int sectionsAdded;
  final int sectionsReplaced;
  final int customAdded;
  final int customReplaced;

  const DiffOutcome({
    required this.data,
    required this.questionsAdded,
    required this.questionsReplaced,
    required this.questionsKept,
    required this.chaptersAdded,
    required this.sectionsAdded,
    required this.sectionsReplaced,
    required this.customAdded,
    required this.customReplaced,
  });
}

/// **差异**模式（issue #3「差异」）：题库 / 资料 / 纠错 / 自建题 / 收藏
/// 全部按 id 三分支合并（同 id 以文件为准，本地独有的保留）。文件缺的段
/// 等价于「文件版为空」→ 结果即本地现状。
DiffOutcome applyDiff({required BackupData file, required BackupData local}) {
  final questions = mergeQuestionsById(
    local: local.questions,
    incoming: file.questions,
  );
  final source = mergeSourceById(local: local.source, incoming: file.source);
  final overrides = mergeOverridesById(
    local: local.overrides ?? const <String, dynamic>{},
    incoming: file.overrides ?? const <String, dynamic>{},
  );
  final custom = mergeCustomById(
    local: local.custom ?? const <CustomQuestion>[],
    incoming: file.custom ?? const <CustomQuestion>[],
  );
  final favorites = mergeFavoriteIds(
    local: local.favoriteQids ?? const <String>[],
    incoming: file.favoriteQids ?? const <String>[],
  );
  return DiffOutcome(
    data: BackupData(
      questions: questions.merged,
      source: source.merged,
      overrides: overrides,
      custom: custom.merged,
      favoriteQids: favorites,
      meta: file.meta,
    ),
    questionsAdded: questions.added,
    questionsReplaced: questions.replaced,
    questionsKept: questions.kept,
    chaptersAdded: source.chaptersAdded,
    sectionsAdded: source.sectionsAdded,
    sectionsReplaced: source.sectionsReplaced,
    customAdded: custom.added,
    customReplaced: custom.replaced,
  );
}
