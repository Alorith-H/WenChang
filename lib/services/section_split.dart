/// Splits a 板块 (Section) into study-mode sub-cards **by knowledge-point
/// structure only** — never by character, row or width counts.
///
/// Page boundaries recognize exactly two structures:
///
/// 1. **h5 item titles** (`section.items[].title`): the item's title plus
///    all of its bullets form one page.
/// 2. **Top-level numbered headings among the flat bullets**: a line that
///    starts with digits followed by `.`/`、`/`．`, is ≤20 characters in
///    total, and does not end with `：`/`:` (e.g. `1. 大小晏`, `4. 苏轼`,
///    `2. 范仲淹`). The heading and the bullets it leads form one
///    *numbered block*, up to (not including) the next top-level heading.
///    A numbered line ending in a colon (e.g. `1.小说：`) is content of its
///    parent knowledge point, not a boundary.
///
/// ### Short-block merging (细化的拆卡规则)
///
/// A numbered block whose content is **≤3 lines** (the numbered line plus
/// the bullets it leads) is a "短块"; **adjacent short blocks merge into
/// one page** while the page stays ≤10 lines total — the page is cut when
/// the next block is ≥4 lines (a long block, which always keeps its own
/// page) or when adding it would push the total past 10 lines. So 《诗经》
/// 重点作品 1./2./3./4. with one line each become a single card. Long
/// content is never cut apart by any character/line count.
///
/// Bullets matching neither rule join the current page; unnumbered
/// lead-in bullets at the top of a section form the first page. A section
/// with no numbered structure at all stays on **one single page** (read
/// by scrolling) — the same knowledge point is never cut apart, no matter
/// how long it is (e.g. the whole "鲁迅" block).
///
/// The result is pure data: each [SubCard] carries the original section
/// (for learned-state ids), a synthetic content [Section] to render on the
/// back of the card, and the `子卡 x/y` counters.
library;

import '../models/models.dart';

/// Top-level numbered heading: digits + one of `.` `、` `．`.
final RegExp _numberedHeading = RegExp(r'^\d+[.、．]');

/// 短块上限：编号块内容（编号行 + 其要点）≤3 行视为短块。
const int _shortBlockMaxLines = 3;

/// 合并页上限：相邻短块合并累计 ≤10 行，超过则切页。
const int _mergeMaxLines = 10;

/// One sub-card of a section.
class SubCard {
  /// The original section this card belongs to (id/title drive learned state).
  final Section section;

  /// The slice of content to render on the back of the card.
  final Section content;

  /// 0-based index of this sub-card within [section].
  final int index;

  /// Total number of sub-cards of [section].
  final int total;

  /// Knowledge-point title shown on the front (h5 item title, or the
  /// numbered heading this page starts with), when the card carries one.
  final String? itemTitle;

  const SubCard({
    required this.section,
    required this.content,
    required this.index,
    required this.total,
    this.itemTitle,
  });
}

/// Splits [section] into its sub-cards (always at least one).
List<SubCard> splitSection(Section section) {
  final slices = _slices(section);
  final total = slices.length;
  return [
    for (var i = 0; i < total; i++)
      SubCard(
        section: section,
        content: slices[i].content,
        index: i,
        total: total,
        itemTitle: slices[i].itemTitle,
      ),
  ];
}

/// A content slice plus the knowledge-point title (if any) shown on the
/// card front.
class _Slice {
  final Section content;
  final String? itemTitle;

  const _Slice(this.content, this.itemTitle);
}

List<_Slice> _slices(Section section) {
  final slices = <_Slice>[];

  // Flat bullets first: intro page (if any), then one page per numbered
  // knowledge point — or the whole run on a single page when the section
  // has no numbered structure at all.
  slices.addAll(_flatSlices(section, section.bullets));

  // Then one page per h5 item: title + all of its bullets.
  for (final item in section.items) {
    slices.add(_Slice(_content(section, const [], [item]), item.title));
  }

  // Empty section → still one (empty) card.
  if (slices.isEmpty) {
    slices.add(_Slice(_content(section, const [], const []), null));
  }
  return slices;
}

/// Splits a run of flat bullets along top-level numbered headings, merging
/// adjacent 短块 (≤3 lines) into pages of up to 10 lines — see the library
/// docs. Long blocks (≥4 lines) always keep a page to themselves.
List<_Slice> _flatSlices(Section section, List<Bullet> bullets) {
  if (bullets.isEmpty) return const [];

  final headings = <int>[
    for (var i = 0; i < bullets.length; i++)
      if (_isTopHeading(bullets[i])) i,
  ];

  // No numbered structure → the whole section is one page (scrollable).
  if (headings.isEmpty) {
    return [_Slice(_content(section, bullets, const []), null)];
  }

  final slices = <_Slice>[];
  // Unnumbered lead-in bullets at the top of the section = first page.
  if (headings.first > 0) {
    slices.add(
      _Slice(_content(section, bullets.sublist(0, headings.first), const []), null),
    );
  }

  // Accumulated run of adjacent short blocks (pageStart = index of the run's
  // first numbered line; -1 = no page in progress). The run is flushed when
  // a long block arrives, when the next short block would exceed the line
  // budget, or at the end of the section.
  var pageStart = -1;
  var pageLines = 0;
  void flush(int end) {
    if (pageStart < 0) return;
    slices.add(
      _Slice(
        _content(section, bullets.sublist(pageStart, end), const []),
        bullets[pageStart].t,
      ),
    );
    pageStart = -1;
    pageLines = 0;
  }

  for (var k = 0; k < headings.length; k++) {
    final start = headings[k];
    final end = k + 1 < headings.length ? headings[k + 1] : bullets.length;
    final lines = end - start; // 编号行 + 其要点 = 块的行数
    if (lines > _shortBlockMaxLines) {
      // 长块：先结掉累计的短块页，长块独占一页。
      flush(start);
      slices.add(
        _Slice(
          _content(section, bullets.sublist(start, end), const []),
          bullets[start].t,
        ),
      );
      continue;
    }
    // 短块：与相邻连续短块合并；累计将超 10 行就先切页。
    if (pageStart >= 0 && pageLines + lines > _mergeMaxLines) {
      flush(start);
    }
    if (pageStart < 0) pageStart = start;
    pageLines += lines;
  }
  flush(bullets.length);
  return slices;
}

/// A top-level numbered heading: `数字 + (./、/．)` at line start, the whole
/// line ≤20 characters, and not ending with `：`/`:` (`1.小说：` is content
/// of its parent knowledge point, not a split point).
bool _isTopHeading(Bullet bullet) {
  final t = bullet.t.trim();
  if (t.isEmpty || t.length > 20) return false;
  if (!_numberedHeading.hasMatch(t)) return false;
  return !t.endsWith('：') && !t.endsWith(':');
}

Section _content(Section section, List<Bullet> bullets, List<Item> items) =>
    Section(id: section.id, title: section.title, items: items, bullets: bullets);
