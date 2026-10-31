import 'package:flutter/material.dart';

import '../../../shared/theme/app_palette.dart';
import '../models/search_index.dart';

/// [text] with the searched [words] picked out in the accent colour.
class HighlightText extends StatelessWidget {
  final String text;
  final List<String> words;
  final TextStyle style;
  final int? maxLines;

  const HighlightText(this.text, {super.key, required this.words, required this.style, this.maxLines});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hit = style.copyWith(color: p.accentText, fontWeight: FontWeight.w800);
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in SearchIndex.matches(text, words)) {
      if (start > at) spans.add(TextSpan(text: text.substring(at, start)));
      spans.add(TextSpan(text: text.substring(start, end), style: hit));
      at = end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
