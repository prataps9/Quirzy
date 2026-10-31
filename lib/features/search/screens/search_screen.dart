import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_motion.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/motion.dart';
import '../models/search_index.dart';
import '../providers/search_providers.dart';
import '../widgets/highlight_text.dart';
import '../widgets/search_preview_sheet.dart';

/// Search across the question pool, saved questions, mistakes, notes and
/// flashcards, narrowed by kind and topic.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  static const debounce = Duration(milliseconds: 150);

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  SearchFilter _filter = SearchFilter.all;
  String? _topic;
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    ref.read(searchServiceProvider).recent().then((r) {
      if (mounted) setState(() => _recent = r);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(SearchScreen.debounce, () {
      if (mounted) setState(() => _query = text);
    });
  }

  void _setQuery(String text) {
    _debounce?.cancel();
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _query = text);
  }

  Future<void> _remember() async {
    final recent = await ref.read(searchServiceProvider).addRecent(_controller.text);
    if (mounted) setState(() => _recent = recent);
  }

  Future<void> _clearRecent() async {
    await ref.read(searchServiceProvider).clearRecent();
    if (mounted) setState(() => _recent = const []);
  }

  Future<void> _open(SearchItem item) async {
    HapticFeedback.selectionClick();
    _focus.unfocus();
    unawaited(_remember());
    final changed = await SearchPreviewSheet.show(context, item, SearchIndex.terms(_query));
    if (changed && mounted) ref.invalidate(searchIndexProvider);
  }

  Future<void> _pickTopic(List<String> topics) async {
    final p = context.palette;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
            children: [
              for (final t in ['', ...topics])
                ListTile(
                  title: Text(t.isEmpty ? 'Any topic' : t),
                  trailing: (t.isEmpty ? _topic == null : _topic == t)
                      ? Icon(Icons.check_rounded, color: p.accentText)
                      : null,
                  onTap: () => Navigator.of(context).pop(t),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _topic = picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final index = ref.watch(searchIndexProvider);
    final value = index.value;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (t) {
            _setQuery(t);
            unawaited(_remember());
          },
          style: text.bodyLarge,
          decoration: const InputDecoration(
            hintText: 'Search questions, notes and cards',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            isDense: true,
          ),
        ),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, v, _) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _setQuery('');
                      _focus.requestFocus();
                    },
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.sm),
                  child: ActionChip(
                    avatar: Icon(
                      Icons.filter_list_rounded,
                      size: 18,
                      color: _topic == null ? p.textMuted : p.accentText,
                    ),
                    label: Text(_topic ?? 'Topic'),
                    onPressed: value == null ? null : () => _pickTopic(value.topics),
                  ),
                ),
                for (final f in SearchFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpace.sm),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _filter = f);
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: value == null
                ? (index.hasError
                      ? const _Message(
                          icon: Icons.cloud_off_rounded,
                          title: "Search isn't ready",
                          body: 'Your questions could not be loaded. Try again in a moment.',
                        )
                      : const SkeletonList(count: 6, itemHeight: 76, padding: EdgeInsets.all(AppSpace.lg)))
                : _body(value),
          ),
        ],
      ),
    );
  }

  Widget _body(SearchIndex index) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final words = SearchIndex.terms(_query);

    if (words.isEmpty) {
      if (_recent.isEmpty) {
        return const _Message(
          icon: Icons.search_rounded,
          title: 'Find anything you have studied',
          body: 'Questions, your saved ones and mistakes, notes and flashcards.',
        );
      }
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.sm, 0),
            child: Row(
              children: [
                Expanded(child: Text('Recent searches', style: text.titleSmall)),
                TextButton(onPressed: _clearRecent, child: const Text('Clear')),
              ],
            ),
          ),
          for (final (i, r) in _recent.indexed)
            Stagger(
              key: ValueKey('recent:$r'),
              index: i,
              child: ListTile(
                leading: Icon(Icons.history_rounded, color: p.textMuted),
                title: Text(r),
                trailing: Icon(Icons.north_west_rounded, size: 18, color: p.textMuted),
                onTap: () => _setQuery(r),
              ),
            ),
        ],
      );
    }

    final hits = index.search(_query, filter: _filter, topic: _topic);
    if (hits.isEmpty) {
      return _Message(
        icon: Icons.search_off_rounded,
        title: 'No matches for "${_query.trim()}"',
        body: _filter != SearchFilter.all || _topic != null
            ? 'Try fewer words, or clear the filters.'
            : 'Try fewer words, or a different spelling.',
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xl),
      itemCount: hits.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text(
              hits.length == 1 ? '1 result' : '${hits.length}${hits.length >= 100 ? '+' : ''} results',
              style: text.bodySmall,
            ),
          );
        }
        final item = hits[i - 1].item;
        return Stagger(
          key: ValueKey(item.id),
          index: i - 1,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: _ResultTile(item: item, words: words, onTap: () => _open(item)),
          ),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  final SearchItem item;
  final List<String> words;
  final VoidCallback onTap;

  const _ResultTile({required this.item, required this.words, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final snippet = SearchIndex.snippet(item, words);
    final tags = [
      if (item.isCard) 'Card',
      if (item.saved) 'Saved',
      if (item.mistake) 'Mistake',
      if (item.hasNote) 'Note',
    ];
    return Semantics(
      button: true,
      label: '${item.isCard ? 'Flashcard' : 'Question'}: ${item.title}. ${item.topic}',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.topic,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium!.copyWith(color: p.textMuted),
                  ),
                ),
                for (final t in tags) ...[const SizedBox(width: AppSpace.xs), _Tag(t)],
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            HighlightText(item.title, words: words, style: text.bodyLarge!, maxLines: 3),
            if (snippet != null) ...[
              const SizedBox(height: AppSpace.xs),
              HighlightText(snippet, words: words, style: text.bodySmall!, maxLines: 2),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;

  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
      decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Message({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: FadeRise(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: p.accentText),
              const SizedBox(height: 14),
              Text(title, textAlign: TextAlign.center, style: text.titleLarge),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: text.bodyMedium!.copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
