import 'package:flutter/material.dart';

/// Text with every case-insensitive occurrence of [needle] highlighted.
class HighlightText extends StatelessWidget {
  final String text;
  final String needle;
  final TextStyle? style;

  const HighlightText({
    super.key,
    required this.text,
    required this.needle,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (needle.isEmpty) return Text(text, style: style);

    final lowerText = text.toLowerCase();
    final lowerNeedle = needle.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerNeedle, start);
      if (idx < 0) break;
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + lowerNeedle.length),
          style: TextStyle(
            color: scheme.error,
            fontWeight: FontWeight.w700,
            backgroundColor: scheme.errorContainer,
          ),
        ),
      );
      start = idx + lowerNeedle.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
