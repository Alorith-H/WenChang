import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// The red used for inline 红笔考点 runs — exactly the C00000 red of the
/// original Word document on light card surfaces. 深色模式下换
/// [SemanticPalette.wordRed] 的提亮朱红变体（见 [semanticPaletteOf]），
/// 深灰褐底上的对比度依旧充足。
const Color kWordRed = Color(0xFFC00000);

/// One bullet line. When the bullet carries Word-original [Bullet.segs],
/// segments render with their exact colors (red = C00000); otherwise plain
/// text. The `key` flag no longer affects rendering — the visual marker of
/// an important point is the Word red text itself.
class BulletRow extends StatelessWidget {
  final Bullet bullet;

  const BulletRow({super.key, required this.bullet});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wordRed = semanticPaletteOf(context).wordRed;
    final style = TextStyle(
      fontSize: 15,
      height: 1.7,
      color: scheme.onSurface,
    );
    final segs = bullet.segs;
    final Widget text;
    if (segs == null) {
      text = Text(bullet.t, style: style);
    } else {
      text = Text.rich(
        TextSpan(
          style: style,
          children: [
            for (final seg in segs)
              TextSpan(
                text: seg.text,
                style: seg.red ? TextStyle(color: wordRed) : null,
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text('·', style: style.copyWith(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: text),
        ],
      ),
    );
  }
}

/// The full content of a section in list form (non-collapsible), used on the
/// back of study cards. Callers wrap it in a scroll view.
///
/// Bullets with Word-original red runs (see [BulletRow]) render those runs
/// in the document's C00000 red.
///
/// [accent] tightens the title-vs-points hierarchy for study cards (bolder,
/// larger item titles with a vermillion marker); source screens keep the
/// neutral default.
class SectionBody extends StatelessWidget {
  final Section section;
  final bool accent;

  const SectionBody({
    super.key,
    required this.section,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];

    if (section.bullets.isNotEmpty) {
      for (final b in section.bullets) {
        children.add(BulletRow(bullet: b));
      }
      if (section.items.isNotEmpty) children.add(const SizedBox(height: 8));
    }

    for (final item in section.items) {
      final titleStyle = TextStyle(
        fontSize: accent ? 17 : 16,
        height: accent ? 1.5 : 1.6,
        fontWeight: accent ? FontWeight.w800 : FontWeight.w700,
        color: scheme.onSurface,
      );
      children.add(
        Padding(
          padding: EdgeInsets.only(top: accent ? 14 : 8, bottom: accent ? 4 : 2),
          child: accent
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 8),
                      child: Container(
                        width: 3.5,
                        height: 17,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(item.title, style: titleStyle),
                    ),
                  ],
                )
              : Text(item.title, style: titleStyle),
        ),
      );
      for (final b in item.bullets) {
        children.add(BulletRow(bullet: b));
      }
    }

    if (children.isEmpty) {
      children.add(
        Text(
          '该板块暂无内容',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// A small learned-state chip — a vermillion-tinted accent on paper.
/// [label] carries the wording: 「今日已学」by default, or a date label
/// like 「10月4日已学」when the section was learned on an earlier day.
class LearnedBadge extends StatelessWidget {
  final String label;

  const LearnedBadge({super.key, this.label = '今日已学'});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 14, color: scheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
