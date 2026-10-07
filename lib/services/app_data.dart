/// Loads and indexes the bundled JSON assets.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';
import 'imported_bank.dart';

class AppData {
  final SourceDoc doc;
  final List<Question> questions;

  /// section id → where it lives in the chapter tree.
  final Map<String, SectionLocation> sectionIndex;

  /// section id → its questions (used when marking a section learned).
  final Map<String, List<Question>> questionsBySec;

  AppData._({
    required this.doc,
    required this.questions,
    required this.sectionIndex,
    required this.questionsBySec,
  });

  List<Chapter> get chapters => doc.chapters;

  int get totalSections =>
      chapters.fold(0, (sum, c) => sum + c.sections.length);

  /// Never throws: unreadable / malformed files degrade to empty data.
  ///
  /// 生效数据的优先级（议题 #3 导入）：SharedPreferences 里有导入版
  /// （`imported_questions` / `imported_source`）就用导入版，**按段回退**
  /// —— 哪段缺 / 损坏就哪段用 assets，绝不写 assets。
  static Future<AppData> load() async {
    final imported = await ImportedBank.load();
    final doc = imported.source ?? await _loadSource();
    final questions = imported.questions ?? await _loadQuestions();

    final sectionIndex = <String, SectionLocation>{};
    for (final chapter in doc.chapters) {
      for (final section in chapter.sections) {
        if (section.id.isEmpty) continue;
        sectionIndex.putIfAbsent(
          section.id,
          () => SectionLocation(chapter: chapter, section: section),
        );
      }
    }

    final questionsBySec = <String, List<Question>>{};
    for (final q in questions) {
      if (q.sec.isEmpty) continue;
      questionsBySec.putIfAbsent(q.sec, () => <Question>[]).add(q);
    }

    return AppData._(
      doc: doc,
      questions: questions,
      sectionIndex: sectionIndex,
      questionsBySec: questionsBySec,
    );
  }

  static Future<SourceDoc> _loadSource() async {
    try {
      final raw = await rootBundle.loadString('assets/data/source.json');
      return SourceDoc.fromJson(jsonDecode(raw));
    } catch (_) {
      return SourceDoc.empty();
    }
  }

  static Future<List<Question>> _loadQuestions() async {
    try {
      final raw = await rootBundle.loadString('assets/data/questions.json');
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.map(Question.fromJson).toList();
    } catch (_) {
      return [];
    }
  }
}
