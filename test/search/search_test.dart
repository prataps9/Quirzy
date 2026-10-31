import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/providers/feed_providers.dart';
import 'package:quirzy/features/feed/services/feed_bookmark_service.dart';
import 'package:quirzy/features/feed/services/mistakes_service.dart';
import 'package:quirzy/features/feed/services/question_notes_service.dart';
import 'package:quirzy/features/search/models/search_index.dart';
import 'package:quirzy/features/search/screens/search_screen.dart';
import 'package:quirzy/features/search/services/search_service.dart';
import 'package:quirzy/features/search/widgets/search_preview_sheet.dart';
import 'package:quirzy/shared/providers/providers.dart';
import 'package:quirzy/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/side_effect_fakes.dart';

PracticeQuestion _q(
  String id,
  String text, {
  String topic = 'History',
  List<String> options = const ['Yes', 'No'],
  String explanation = '',
}) => PracticeQuestion(
  id: id,
  questionText: text,
  options: options,
  correctIndex: 0,
  explanation: explanation,
  topic: topic,
);

const _card = FeedFlashcard(
  setId: 's1',
  index: 0,
  front: 'Mitochondria',
  back: 'Powerhouse of the cell',
  setTitle: 'Cells',
);

List<String> _ids(List<SearchHit> hits) => [for (final h in hits) h.item.id.split('|').last];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SearchIndex', () {
    test('ignores case and accents, and needs every word', () {
      final index = SearchService.build(
        pool: [
          _q('a', 'Who painted the Café Terrace at Night?'),
          _q('b', 'Which café opened first in Paris?'),
          _q('c', 'Name a famous TERRACE garden'),
        ],
      );
      expect(_ids(index.search('cafe')), unorderedEquals(['a', 'b']));
      expect(_ids(index.search('CAFÉ terrace')), ['a']);
      expect(_ids(index.search('terrace')), unorderedEquals(['a', 'c']));
      expect(index.search('cafe moon'), isEmpty);
      expect(index.search('  ,, '), isEmpty);
    });

    test('a phrase in the question ranks first, then its words, then matches elsewhere', () {
      final index = SearchService.build(
        pool: [
          _q('elsewhere', 'Which river is longest?', options: const ['The Nile delta', 'Amazon']),
          _q('words', 'The delta of which river is the Nile known for?'),
          _q('phrase', 'Where does the Nile delta meet the sea?'),
        ],
      );
      final hits = index.search('nile delta');
      expect(_ids(hits), ['phrase', 'words', 'elsewhere']);
      expect(hits.map((h) => h.strength), [
        MatchStrength.phraseInTitle,
        MatchStrength.allWordsInTitle,
        MatchStrength.elsewhere,
      ]);
    });

    test('looks in options, explanations, notes, topics and cards', () {
      final index = SearchService.build(
        pool: [
          _q('opt', 'Pick one', options: const ['Photosynthesis', 'Osmosis']),
          _q('exp', 'Why is the sky blue?', explanation: 'Rayleigh scattering'),
          _q('topic', 'Who wrote it?', topic: 'Literature'),
          _q('note', 'Capital of Australia?'),
        ],
        notes: {'History|note': 'Not Sydney! Canberra'},
        cards: const [_card],
      );
      expect(_ids(index.search('osmosis')), ['opt']);
      expect(_ids(index.search('rayleigh')), ['exp']);
      expect(_ids(index.search('literature')), ['topic']);
      expect(_ids(index.search('canberra')), ['note']);
      expect(index.search('powerhouse').single.item.isCard, isTrue);
      expect(index.search('cells').single.item.card, _card);
    });

    test('one result per question, with saved, mistake and note folded in', () {
      final shared = _q('x', 'Battle of Plassey year?');
      final old = _q('gone', 'Battle of Buxar year?');
      final index = SearchService.build(
        pool: [shared, _q('y', 'Battle of Panipat year?')],
        saved: [shared, old],
        mistakes: [shared],
        notes: {'History|x': '1757', 'History|unknown': 'lost note'},
        cards: const [_card, _card],
      );
      expect(index.items, hasLength(4), reason: 'x, y, the saved one no longer in the pool, and the card');
      final x = index.search('plassey').single.item;
      expect((x.saved, x.mistake, x.note), (true, true, '1757'));

      expect(_ids(index.search('battle', filter: SearchFilter.saved)), unorderedEquals(['x', 'gone']));
      expect(_ids(index.search('battle', filter: SearchFilter.mistakes)), ['x']);
      expect(_ids(index.search('battle', filter: SearchFilter.notes)), ['x']);
      expect(index.search('battle', filter: SearchFilter.cards), isEmpty);
      expect(index.search('battle', filter: SearchFilter.questions), hasLength(3));
      expect(index.search('lost note'), isEmpty);
    });

    test('the topic filter narrows results, and lists every topic', () {
      final index = SearchService.build(
        pool: [
          _q('h', 'Year of the first war?', topic: 'History'),
          _q('g', 'Longest war river?', topic: 'Geography'),
        ],
        cards: const [_card],
      );
      expect(index.topics, ['Cells', 'Geography', 'History']);
      expect(_ids(index.search('war', topic: 'Geography')), ['g']);
      expect(index.search('war', topic: 'Cells'), isEmpty);
    });

    test('finds where the words are, for highlighting', () {
      expect(SearchIndex.matches('Café au lait, CAFE noir', ['cafe']), [(0, 4), (14, 18)]);
      expect(SearchIndex.matches('nilenile delta', ['nile', 'nilen']), [(0, 8)]);
      expect(SearchIndex.normalize('Ünïcödé'), 'unicode');
    });

    test('a snippet shows the line that matched', () {
      final item = SearchItem.question(
        _q('s', 'Pick one', options: const ['Alpha', 'Beta'], explanation: 'Beta decay'),
        note: 'Remember beta',
      );
      expect(SearchIndex.snippet(item, ['alpha']), 'Alpha');
      expect(SearchIndex.snippet(item, ['beta']), 'Remember beta');
      expect(SearchIndex.snippet(item, ['gamma']), isNull);
    });
  });

  group('Recent searches', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('newest first, once each, at most eight', () async {
      final service = SearchService();
      await service.addRecent('Polity');
      await service.addRecent(' x ');
      for (var i = 0; i < 9; i++) {
        await service.addRecent('topic $i');
      }
      expect(await service.addRecent('POLITY'), hasLength(SearchService.maxRecent));
      final recent = await service.recent();
      expect(recent.first, 'POLITY');
      expect(recent.where((r) => r.toLowerCase() == 'polity'), hasLength(1));
      expect(recent, isNot(contains('x')), reason: 'too short to keep');
      await service.clearRecent();
      expect(await service.recent(), isEmpty);
    });
  });

  group('SearchScreen', () {
    final pool = [
      _q('p1', 'Who wrote the Preamble of the Constitution?', topic: 'Polity', explanation: 'Nehru moved it.'),
      _q('p2', 'How many schedules does the Constitution have?', topic: 'Polity'),
      _q('h1', 'When did the Mughal empire begin?', topic: 'History'),
      for (var i = 0; i < 10; i++) _q('f$i', 'Filler question $i?', topic: 'Economy'),
    ];

    setUp(() {
      SharedPreferences.setMockInitialValues({'selected_exam': 'jee'});
      GoogleFonts.config.allowRuntimeFetching = false;
    });

    Future<ProviderContainer> pumpSearch(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [feedQuestionPoolProvider.overrideWith((ref) async => pool), ...sideEffectOverrides()],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
                    child: const Text('Open search'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final container = ProviderScope.containerOf(tester.element(find.text('Open search')));
      container.listen(feedControllerProvider, (_, _) {});
      for (var i = 0; i < 20 && container.read(feedControllerProvider).loading; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Open search'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return container;
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(SearchScreen.debounce);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    }

    testWidgets('finds as you type, filters, and remembers the search', (tester) async {
      await pumpSearch(tester);
      expect(find.text('Find anything you have studied'), findsOneWidget);

      await type(tester, 'constitution');
      expect(find.text('2 results'), findsOneWidget);
      expect(find.textContaining('Preamble', findRichText: true), findsOneWidget);

      await type(tester, 'constitution xyz');
      expect(find.text('No matches for "constitution xyz"'), findsOneWidget);

      await type(tester, 'the');
      expect(find.text('3 results'), findsOneWidget);
      await tester.tap(find.text('Topic'));
      await frames(tester);
      await tester.tap(find.text('History').last);
      await frames(tester);
      expect(find.text('1 result'), findsOneWidget);

      await tester.tap(find.text('Saved'));
      await frames(tester);
      expect(find.textContaining('No matches'), findsOneWidget);
      expect(find.text('Try fewer words, or clear the filters.'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await frames(tester);
      expect(await SearchService().recent(), ['the']);

      await tester.tap(find.byTooltip('Clear'));
      await frames(tester);
      expect(find.text('Recent searches'), findsOneWidget);
      await tester.tap(find.text('the'));
      await frames(tester);
      expect(find.textContaining('No matches'), findsOneWidget, reason: 'filters are kept');
      await settle(tester);
    });

    testWidgets('a result opens a preview: answer, note, save and practise', (tester) async {
      final container = await pumpSearch(tester);
      await type(tester, 'preamble');
      await tester.tap(find.textContaining('Preamble', findRichText: true));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SearchPreviewSheet), findsOneWidget);

      expect(find.textContaining('Nehru', findRichText: true), findsNothing);
      await tester.tap(find.text('Show answer'));
      await frames(tester);
      expect(find.textContaining('Nehru', findRichText: true), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      await tester.tap(find.text('Save'));
      await frames(tester);
      expect(find.text('Saved'), findsWidgets);
      expect((await FeedBookmarkService().getBookmarks()).single.id, 'p1');

      await tester.tap(find.text('Add note'));
      await frames(tester);
      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Objectives',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await frames(tester);
      expect(await QuestionNotesService().noteFor(pool.first), 'Objectives');
      expect(find.textContaining('Objectives', findRichText: true), findsOneWidget);

      await tester.tap(find.text('Practise this topic'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SearchScreen), findsNothing);
      expect(container.read(feedControllerProvider).lane.label, 'Polity');
      expect(container.read(tabIndexProvider), 0);
      await settle(tester);
    });

    testWidgets('mistakes are found and tagged', (tester) async {
      await MistakesService().recordAnswer(pool[2], correct: false);
      await pumpSearch(tester);
      await type(tester, 'mughal');
      expect(find.text('Mistake'), findsWidgets);
      await tester.tap(find.text('Mistakes'));
      await frames(tester);
      expect(find.text('1 result'), findsOneWidget);
      await settle(tester);
    });
  });
}
