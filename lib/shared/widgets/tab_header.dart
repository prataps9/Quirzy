import 'package:flutter/material.dart';

/// The big title at the top of a main tab (My Prep, Cards, Profile), so
/// every tab opens the same way: title, an optional one-line subtitle and
/// optional actions on the right.
class TabHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  const TabHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 8),
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(title, style: text.headlineMedium)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
