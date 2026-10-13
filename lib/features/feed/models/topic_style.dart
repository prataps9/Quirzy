import 'package:flutter/material.dart';

import '../../../shared/theme/app_palette.dart';

/// A stable look per topic: a solid background tint and an icon, so each
/// subject feels like its own channel as you swipe.
class TopicStyle {
  final int tintIndex;
  final IconData icon;

  const TopicStyle._(this.tintIndex, this.icon);

  static const _icons = <String, IconData>{
    'physic': Icons.bolt_rounded,
    'mechanic': Icons.bolt_rounded,
    'electric': Icons.bolt_rounded,
    'optic': Icons.lightbulb_outline_rounded,
    'chem': Icons.science_rounded,
    'organic': Icons.science_rounded,
    'bio': Icons.eco_rounded,
    'botany': Icons.eco_rounded,
    'zoology': Icons.pets_rounded,
    'anatomy': Icons.favorite_border_rounded,
    'math': Icons.calculate_rounded,
    'algebra': Icons.calculate_rounded,
    'calculus': Icons.functions_rounded,
    'geometry': Icons.change_history_rounded,
    'statistic': Icons.bar_chart_rounded,
    'quant': Icons.calculate_rounded,
    'history': Icons.account_balance_rounded,
    'polity': Icons.gavel_rounded,
    'law': Icons.gavel_rounded,
    'geograph': Icons.public_rounded,
    'english': Icons.translate_rounded,
    'grammar': Icons.translate_rounded,
    'vocab': Icons.translate_rounded,
    'verbal': Icons.translate_rounded,
    'reading': Icons.menu_book_rounded,
    'econom': Icons.trending_up_rounded,
    'finance': Icons.trending_up_rounded,
    'account': Icons.receipt_long_rounded,
    'code': Icons.code_rounded,
    'coding': Icons.code_rounded,
    'program': Icons.code_rounded,
    'computer': Icons.computer_rounded,
    'reasoning': Icons.psychology_rounded,
    'logic': Icons.psychology_rounded,
    'aptitude': Icons.psychology_rounded,
    'current': Icons.newspaper_rounded,
    'general': Icons.lightbulb_outline_rounded,
  };

  static TopicStyle of(String topic) {
    final key = topic.trim().toLowerCase();
    var icon = Icons.auto_awesome_rounded;
    for (final entry in _icons.entries) {
      if (key.contains(entry.key)) {
        icon = entry.value;
        break;
      }
    }
    return TopicStyle._(_stableHash(key) % kTopicTintsDark.length, icon);
  }

  /// The card background for this topic in the current brightness.
  Color tint(Brightness brightness) =>
      (brightness == Brightness.dark ? kTopicTintsDark : kTopicTintsLight)[tintIndex];

  /// FNV-1a, so the colour never changes between launches (String.hashCode
  /// is not guaranteed stable across runs).
  static int _stableHash(String s) {
    var hash = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
