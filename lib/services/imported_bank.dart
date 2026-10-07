/// 导入题库 / 资料的 SharedPreferences 持久层（议题 #3）：
/// `imported_questions` / `imported_source` 存整份生效数据，[AppData.load]
/// 「有导入版用导入版，否则回退 assets」—— **绝不写 assets/**；导出永远
/// 导生效版（见 settings 页的导出入口）。
///
/// 纠错 / 自建题 / 收藏不搬新家，仍写各自的原 key（`content_overrides` /
/// `custom_questions` / `favorite_qids`）—— 覆盖模式文件缺段时这些 key
/// 完全不碰（保留现状），差异模式写合并结果。
///
/// **进度红线**：本文件只碰上述五个 key + 信息用的 `imported_at`，
/// SRS 进度、打卡、练习历史的 key 全程不碰 —— 板块与题目 id 体系不变，
/// 进度自然保留。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'backup_transfer.dart';
import 'content_overrides.dart';
import 'custom_questions.dart';
import 'favorites.dart';

const kImportedQuestionsKey = 'imported_questions';
const kImportedSourceKey = 'imported_source';

/// 最近一次导入时间（纯信息，便于排查；不影响加载优先级）。
const kImportedAtKey = 'imported_at';

/// 导入版数据的读取结果：任一段缺失 / 损坏 → 该段为 null（回退 assets）。
class ImportedBank {
  /// 导入版题库；null = 没有（或损坏）→ 用 assets。
  final List<Question>? questions;

  /// 导入版资料；null = 没有（或损坏）→ 用 assets。
  final SourceDoc? source;

  const ImportedBank({this.questions, this.source});

  bool get isEmpty => questions == null && source == null;

  /// 防御式读取，与 [ContentOverrides] / [CustomQuestions] 同款容错：
  /// 损坏的存储 → 该段回退 assets，绝不抛、绝不崩。
  static Future<ImportedBank> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<Question>? questions;
      SourceDoc? source;

      final rawQuestions = prefs.getString(kImportedQuestionsKey);
      if (rawQuestions != null) {
        try {
          final decoded = jsonDecode(rawQuestions);
          if (decoded is List && decoded.isNotEmpty) {
            questions = decoded.map(Question.fromJson).toList();
          }
        } catch (_) {
          // 损坏的导入题库 → 回退 assets。
        }
      }

      final rawSource = prefs.getString(kImportedSourceKey);
      if (rawSource != null) {
        try {
          final decoded = jsonDecode(rawSource);
          if (decoded is Map<String, dynamic>) {
            final doc = SourceDoc.fromJson(decoded);
            if (doc.chapters.isNotEmpty) source = doc;
          }
        } catch (_) {
          // 损坏的导入资料 → 回退 assets。
        }
      }

      return ImportedBank(questions: questions, source: source);
    } catch (_) {
      // SharedPreferences 不可用（测试环境没 mock 等）→ 全部回退 assets。
      return const ImportedBank();
    }
  }
}

/// 把导入结果落库：生效题库 / 资料写 `imported_*`；纠错 / 自建题 /
/// 收藏按 [BackupData] 里是否携带（非 null）决定写不写 —— 覆盖模式
/// 文件缺段时传的是本地保留值（或 null → 不碰原 key）。写入的都是
/// 校验通过后的数据（见 [parseBackup]），失败由调用方接住提示。
Future<void> persistImportedBackup(BackupData data) async {
  final prefs = await SharedPreferences.getInstance();

  // 先写三个「可缺省」段（覆盖模式文件缺段 → data 里就是本地现状，
  // 写回等价于不变），最后写决定加载优先级的两个 imported_* 键。
  final overrides = data.overrides;
  if (overrides != null) {
    await prefs.setString(kContentOverridesKey, jsonEncode(overrides));
  }
  final custom = data.custom;
  if (custom != null) {
    await prefs.setString(
      kCustomQuestionsKey,
      jsonEncode([for (final c in custom) c.toJson()]),
    );
  }
  final favoriteQids = data.favoriteQids;
  if (favoriteQids != null) {
    await prefs.setString(kFavoriteQidsKey, jsonEncode(favoriteQids));
  }

  await prefs.setString(
    kImportedQuestionsKey,
    jsonEncode([for (final q in data.questions) q.toJson()]),
  );
  await prefs.setString(kImportedSourceKey, jsonEncode(data.source.toJson()));
  await prefs.setString(kImportedAtKey, DateTime.now().toIso8601String());
}
