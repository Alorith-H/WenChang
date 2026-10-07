import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/models.dart';
import '../../services/app_data.dart';
import '../../widgets/highlight_text.dart';
import 'chapter_sections_screen.dart';
import 'question_detail_screen.dart';
import 'section_detail_screen.dart';

/// 资料模式：「资料 | 题目」双页签浏览（章 → 板块 → 详情 / 全部题目分组）
/// + 即时全文搜索。
///
/// 搜索节流 200ms；范围 = 章名 + 板块名 + 条目名 + 要点文本 + 题库 q/a，
/// 结果按「资料」「题目」分组。搜索框两个页签共享：有关键词时一律显示
/// 搜索结果（页签只决定无关键词时的浏览内容）。
class SourceScreen extends StatefulWidget {
  const SourceScreen({super.key});

  @override
  State<SourceScreen> createState() => _SourceScreenState();
}

/// One row of the flattened 「题目」 browse list: a chapter / section
/// header, or a question itself.
class _QListItem {
  final Chapter? chapter;
  final Section? section;
  final Question? question;

  const _QListItem.chapter(this.chapter)
    : section = null,
      question = null;
  const _QListItem.section(this.section)
    : chapter = null,
      question = null;
  const _QListItem.question(this.question)
    : chapter = null,
      section = null;
}

class _SourceScreenState extends State<SourceScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  AppData? _data;

  /// 0 = 资料, 1 = 题目.
  int _tab = 0;

  /// Flattened 「题目」browse rows (chapter → section → questions),
  /// built once from the static bundle — plus any ungrouped questions so
  /// every question in the bank stays reachable.
  List<_QListItem> _questionRows = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = AppScope.of(context).data;
    if (!identical(data, _data)) {
      _data = data;
      _questionRows = _buildQuestionRows(data);
    }
  }

  /// Groups every question by 章 → 板块 (data order). Questions whose
  /// section can't be located in the chapter tree fall into a trailing
  /// 「未归类」group — nothing is ever dropped.
  static List<_QListItem> _buildQuestionRows(AppData data) {
    final rows = <_QListItem>[];
    final placed = <String>{};

    for (final chapter in data.chapters) {
      final chapterSections = <Section>[];
      for (final section in chapter.sections) {
        final qs = data.questionsBySec[section.id];
        if (qs == null || qs.isEmpty) continue;
        // 重复 id 的板块只归一次，避免题目重复列出。
        if (placed.contains(section.id)) continue;
        chapterSections.add(section);
        placed.add(section.id);
      }
      if (chapterSections.isEmpty) continue;
      rows.add(_QListItem.chapter(chapter));
      for (final section in chapterSections) {
        rows.add(_QListItem.section(section));
        for (final q in data.questionsBySec[section.id] ?? const []) {
          rows.add(_QListItem.question(q));
        }
      }
    }

    final orphans = [
      for (final q in data.questions)
        if (q.sec.isEmpty || !placed.contains(q.sec)) q,
    ];
    if (orphans.isNotEmpty) {
      rows.add(const _QListItem.chapter(null));
      rows.add(const _QListItem.section(null));
      for (final q in orphans) {
        rows.add(_QListItem.question(q));
      }
    }
    return rows;
  }

  /// Row title for a question: the stem with the `____` blank removed
  /// (the detail screen keeps the original text).
  static String _stemOf(Question q) {
    final stripped = q.q
        .replaceAll('____', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return stripped.isEmpty ? q.q : stripped;
  }

  // 搜索结果（有界，保证列表流畅）。
  List<Chapter> _chapterHits = const [];
  List<_SectionHit> _sectionHits = const [];
  List<Question> _questionHits = const [];
  bool _truncated = false;

  static const int _maxSectionHits = 80;
  static const int _maxQuestionHits = 80;
  static const int _maxChapterHits = 30;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      final q = raw.trim();
      if (!mounted) return;
      setState(() => _applyQuery(q));
    });
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    setState(() => _applyQuery(''));
  }

  void _applyQuery(String q) {
    _query = q;
    if (q.isEmpty) {
      _chapterHits = const [];
      _sectionHits = const [];
      _questionHits = const [];
      _truncated = false;
      return;
    }
    final data = _data;
    if (data == null) return;
    final needle = q.toLowerCase();

    bool contains(String s) => s.toLowerCase().contains(needle);

    // 章名
    _chapterHits = <Chapter>[];
    for (final c in data.chapters) {
      if (contains(c.title)) _chapterHits.add(c);
      if (_chapterHits.length >= _maxChapterHits) break;
    }

    // 板块 / 条目 / 要点（每个板块只保留第一条命中，按板块 id 去重）
    _sectionHits = <_SectionHit>[];
    final seenSections = <String>{};
    var truncated = false;
    outer:
    for (final chapter in data.chapters) {
      for (final section in chapter.sections) {
        if (section.id.isNotEmpty && seenSections.contains(section.id)) {
          continue;
        }
        String? snippet;
        if (contains(section.title)) {
          snippet = section.title;
        } else {
          for (final item in section.items) {
            if (contains(item.title)) {
              snippet = '${item.title}（条目）';
              break;
            }
            for (final b in item.bullets) {
              if (contains(b.t)) {
                snippet = b.t;
                break;
              }
            }
            if (snippet != null) break;
          }
          if (snippet == null) {
            for (final b in section.bullets) {
              if (contains(b.t)) {
                snippet = b.t;
                break;
              }
            }
          }
        }
        if (snippet != null) {
          if (_sectionHits.length >= _maxSectionHits) {
            truncated = true;
            break outer;
          }
          if (section.id.isNotEmpty) seenSections.add(section.id);
          _sectionHits.add(_SectionHit(
            location: SectionLocation(chapter: chapter, section: section),
            snippet: snippet,
          ));
        }
      }
    }

    // 题库 q / a
    _questionHits = <Question>[];
    for (final question in data.questions) {
      if (contains(question.q) || contains(question.a)) {
        if (_questionHits.length >= _maxQuestionHits) {
          truncated = true;
          break;
        }
        _questionHits.add(question);
      }
    }

    _truncated = truncated;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('资料模式')),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部页签：资料 | 题目（纸墨风：选中 = 主色文字 + 下划线）。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  _SourceTab(
                    label: '资料',
                    selected: _tab == 0,
                    onTap: () => setState(() => _tab = 0),
                  ),
                  const SizedBox(width: 24),
                  _SourceTab(
                    label: _data == null
                        ? '题目'
                        : '题目 ${_data!.questions.length}',
                    selected: _tab == 1,
                    onTap: () => setState(() => _tab = 1),
                  ),
                ],
              ),
            ),
            // 搜索框两个页签共享：有关键词时一律显示搜索结果。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _controller,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _tab == 0
                      ? '搜索章名、板块、要点或题目'
                      : '搜索题干或答案',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _clear,
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _query.isNotEmpty
                  ? _buildResults(context)
                  : (_tab == 0
                      ? _buildBrowse(context)
                      : _buildQuestionList(context)),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------- 题目 browse

  /// 全部题目按 章 → 板块 分组的可滚动列表；点行进详情页。
  Widget _buildQuestionList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_questionRows.isEmpty) {
      return Center(
        child: Text(
          '暂无题目',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _questionRows.length,
      itemBuilder: (context, i) {
        final row = _questionRows[i];
        final chapter = row.chapter;
        if (chapter != null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Row(
              children: [
                Text(
                  chapter.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Divider(color: scheme.outlineVariant)),
              ],
            ),
          );
        }
        final section = row.section;
        if (section != null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
            child: Text(
              section.title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final question = row.question;
        if (question == null) return const SizedBox.shrink();
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => QuestionDetailScreen(question: question),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _stemOf(question),
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.outline,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------- browse

  Widget _buildBrowse(BuildContext context) {
    final data = AppScope.of(context).data;
    final scheme = Theme.of(context).colorScheme;

    if (data.chapters.isEmpty) {
      return Center(
        child: Text(
          '暂无资料内容',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: data.chapters.length + (data.doc.subtitle.isEmpty ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (data.doc.subtitle.isNotEmpty && i == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              data.doc.subtitle.join('\n'),
              style: TextStyle(
                fontSize: 13,
                height: 1.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final offset = data.doc.subtitle.isEmpty ? 0 : 1;
        final chapter = data.chapters[i - offset];
        return Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChapterSectionsScreen(chapter: chapter),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      chapter.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${chapter.sections.length} 板块',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.outline,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ results

  Widget _buildResults(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasAny = _chapterHits.isNotEmpty ||
        _sectionHits.isNotEmpty ||
        _questionHits.isNotEmpty;

    if (!hasAny) {
      return Center(
        child: Text(
          '没有找到与「$_query」相关的内容',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
      );
    }

    final rows = <Widget>[];

    if (_chapterHits.isNotEmpty) {
      rows.add(_groupHeader(context, '资料 · 章'));
      for (final chapter in _chapterHits) {
        rows.add(_resultTile(
          context,
          title: chapter.title,
          snippet: '章 · ${chapter.sections.length} 板块',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChapterSectionsScreen(chapter: chapter),
            ),
          ),
        ));
      }
    }

    if (_sectionHits.isNotEmpty) {
      rows.add(_groupHeader(context, '资料 · 板块 / 要点'));
      for (final hit in _sectionHits) {
        rows.add(_resultTile(
          context,
          title: hit.location.section.title,
          snippet: hit.snippet,
          highlight: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SectionDetailScreen(location: hit.location),
            ),
          ),
        ));
      }
    }

    if (_questionHits.isNotEmpty) {
      rows.add(_groupHeader(context, '题目'));
      for (final question in _questionHits) {
        rows.add(_resultTile(
          context,
          title: question.q,
          snippet: '答案：${question.a}',
          highlight: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => QuestionDetailScreen(question: question),
            ),
          ),
        ));
      }
    }

    if (_truncated) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              '结果较多，仅显示部分匹配，请细化关键词',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: rows,
    );
  }

  Widget _groupHeader(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: scheme.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _resultTile(
    BuildContext context, {
    required String title,
    required String snippet,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                highlight
                    ? HighlightText(
                        text: title,
                        needle: _query,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        ),
                      )
                    : Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        ),
                      ),
                const SizedBox(height: 2),
                highlight
                    ? HighlightText(
                        text: snippet,
                        needle: _query,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : Text(
                        snippet,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHit {
  final SectionLocation location;
  final String snippet;

  const _SectionHit({required this.location, required this.snippet});
}

/// 资料模式顶部的页签：选中态为主色文字 + 2px 下划线，未选中为灰字。
class _SourceTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SourceTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 1,
                color: color,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: selected ? 24 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
