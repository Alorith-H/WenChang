/// Data models for the bundled JSON assets (`source.json`, `questions.json`).
///
/// All parsers are defensive: missing keys, nulls and malformed entries are
/// tolerated so a partially filled data file can never crash the app.
library;

Map<String, dynamic>? _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

List<Object?> _asList(Object? value) =>
    value is List ? List<Object?>.from(value) : <Object?>[];

String _asStr(Object? value) => value is String ? value : '';

/// One inline run of a bullet's text: [red] matches the red pen marks
/// (C00000) of the original Word document, false keeps the normal color.
class BulletSeg {
  final String text;
  final bool red;

  const BulletSeg({required this.text, this.red = false});
}

/// A single bullet point. [key] marks an important bullet (kept for
/// compatibility, no longer used for coloring); [segs] carries the Word
/// original's black/red runs when the bullet contains inline red text.
///
/// [t] and [segs] are deliberately mutable: a user correction
/// ([ContentOverrides] under `content_overrides`) is merged straight into
/// the loaded tree, so every screen already holding this bullet renders the
/// corrected text on its next rebuild. An overridden bullet drops its red
/// runs (segs → null, plain text); the untouched originals are restored
/// from the snapshot when the override is removed.
class Bullet {
  String t;
  final bool key;
  List<BulletSeg>? segs;

  Bullet({required this.t, this.key = false, this.segs});

  factory Bullet.fromJson(Object? json) {
    final m = _asMap(json);
    if (m == null) return Bullet(t: '');
    return Bullet(
      t: _asStr(m['t']),
      key: m['key'] == true,
      segs: _parseSegs(m['segs']),
    );
  }
}

/// Tolerant `segs` parser: missing key, wrong type, empty array or broken
/// entries all degrade to `null` (renderers then fall back to [Bullet.t]).
List<BulletSeg>? _parseSegs(Object? raw) {
  if (raw is! List || raw.isEmpty) return null;
  final segs = <BulletSeg>[];
  for (final entry in raw) {
    if (entry is! List || entry.length < 2) continue;
    final text = entry[0];
    if (text is! String || text.isEmpty) continue;
    final flag = entry[1];
    segs.add(BulletSeg(
      text: text,
      red: flag == 1 || flag == true || flag == 1.0,
    ));
  }
  return segs.isEmpty ? null : segs;
}

/// An entry inside a section, e.g. "1. 《淮南子》" with its bullets.
class Item {
  final String title;
  final List<Bullet> bullets;

  const Item({required this.title, required this.bullets});

  factory Item.fromJson(Object? json) {
    final m = _asMap(json);
    if (m == null) return const Item(title: '', bullets: []);
    return Item(
      title: _asStr(m['title']),
      bullets: _asList(m['bullets']).map(Bullet.fromJson).toList(),
    );
  }
}

/// A section (板块) — the unit of study cards.
class Section {
  final String id;
  final String title;
  final List<Item> items;
  final List<Bullet> bullets;

  const Section({
    required this.id,
    required this.title,
    required this.items,
    required this.bullets,
  });

  factory Section.fromJson(Object? json) {
    final m = _asMap(json);
    if (m == null) return const Section(id: '', title: '', items: [], bullets: []);
    return Section(
      id: _asStr(m['id']),
      title: _asStr(m['title']),
      items: _asList(m['items']).map(Item.fromJson).toList(),
      bullets: _asList(m['bullets']).map(Bullet.fromJson).toList(),
    );
  }

  bool get isEmpty => items.isEmpty && bullets.isEmpty;
}

/// A chapter (章) grouping sections.
class Chapter {
  final String id;
  final String title;
  final List<Section> sections;

  const Chapter({required this.id, required this.title, required this.sections});

  factory Chapter.fromJson(Object? json) {
    final m = _asMap(json);
    if (m == null) return const Chapter(id: '', title: '', sections: []);
    return Chapter(
      id: _asStr(m['id']),
      title: _asStr(m['title']),
      sections: _asList(m['sections']).map(Section.fromJson).toList(),
    );
  }
}

/// The whole `source.json` document.
class SourceDoc {
  final String title;
  final List<String> subtitle;
  final List<Chapter> chapters;

  const SourceDoc({
    required this.title,
    required this.subtitle,
    required this.chapters,
  });

  factory SourceDoc.empty() =>
      const SourceDoc(title: '文学常识提纲', subtitle: [], chapters: []);

  factory SourceDoc.fromJson(Object? json) {
    final m = _asMap(json);
    if (m == null) return SourceDoc.empty();
    return SourceDoc(
      title: _asStr(m['title']).isEmpty
          ? '文学常识提纲'
          : _asStr(m['title']),
      subtitle: _asList(m['subtitle'])
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList(),
      chapters: _asList(m['chapters']).map(Chapter.fromJson).toList(),
    );
  }
}

/// One review question from `questions.json`.
///
/// [q] / [a] are deliberately mutable for the same reason as [Bullet.t]:
/// a user correction merged by ContentOverrides takes effect in place on
/// every screen already holding this question.
class Question {
  final String id;
  final String sec;
  String q;
  String a;
  final String src;

  Question({
    required this.id,
    required this.sec,
    required this.q,
    required this.a,
    required this.src,
  });

  factory Question.fromJson(Object? json) {
    final m = _asMap(json);
    if (m == null) {
      return Question(id: '', sec: '', q: '', a: '', src: '');
    }
    return Question(
      id: _asStr(m['id']),
      sec: _asStr(m['sec']),
      q: _asStr(m['q']),
      a: _asStr(m['a']),
      src: _asStr(m['src']),
    );
  }
}

/// Where a section lives in the chapter tree.
class SectionLocation {
  final Chapter chapter;
  final Section section;

  const SectionLocation({required this.chapter, required this.section});
}
