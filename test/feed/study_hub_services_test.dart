import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/services/explain_service.dart';
import 'package:quirzy/features/feed/services/question_notes_service.dart';
import 'package:quirzy/features/flashcards/services/saved_cards_service.dart';
import 'package:quirzy/features/flashcards/services/srs_service.dart';
import 'package:quirzy/shared/utils/user_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

PracticeQuestion _q(int n, {String explanation = 'Because A is the capital.'}) => PracticeQuestion(
  id: 'q$n',
  questionText: 'What is the capital of country $n?',
  options: const ['City A', 'City B', 'City C', 'City D'],
  correctIndex: 0,
  explanation: explanation,
  topic: 'Geography',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ExplainService', () {
    test('sends the question and mode, and returns the answer', () async {
      final calls = <Map<String, dynamic>>[];
      final service = ExplainService(call: (payload) async {
        calls.add(payload);
        return 'Think of it like this.';
      });

      final result = await service.explain(_q(1), ExplainMode.simpler);

      expect(result.answer, 'Think of it like this.');
      expect(result.fromCache, isFalse);
      expect(calls.single['mode'], 'simpler');
      expect(calls.single['question'], 'What is the capital of country 1?');
      expect(calls.single['correctIndex'], 0);
      expect(calls.single.containsKey('followUp'), isFalse);
    });

    test('asking the same thing again comes from the device, not the AI', () async {
      var calls = 0;
      final service = ExplainService(call: (_) async => 'Answer ${++calls}');

      await service.explain(_q(1), ExplainMode.example);
      final again = await service.explain(_q(1), ExplainMode.example);
      final otherMode = await service.explain(_q(1), ExplainMode.memory);

      expect(again.fromCache, isTrue);
      expect(again.answer, 'Answer 1');
      expect(otherMode.fromCache, isFalse);
      expect(calls, 2);
    });

    test('follow-up questions always go to the AI and are not cached', () async {
      var calls = 0;
      final service = ExplainService(call: (_) async => 'Reply ${++calls}');

      final first = await service.explain(_q(1), ExplainMode.followUp, followUp: 'Why not B?');
      final second = await service.explain(_q(1), ExplainMode.followUp, followUp: 'Why not B?');

      expect(first.fromCache, isFalse);
      expect(second.fromCache, isFalse);
      expect(calls, 2);
    });

    test('an empty follow-up is refused without calling the AI', () async {
      var calls = 0;
      final service = ExplainService(call: (_) async => 'x${++calls}');
      await expectLater(
        service.explain(_q(1), ExplainMode.followUp, followUp: '   '),
        throwsA(isA<UserFacingException>()),
      );
      expect(calls, 0);
    });

    test('a failed call is not cached, so retrying asks again', () async {
      var calls = 0;
      final service = ExplainService(call: (_) async {
        if (++calls == 1) throw const UserFacingException('nope');
        return 'Second time lucky';
      });

      await expectLater(service.explain(_q(1), ExplainMode.simpler), throwsA(isA<UserFacingException>()));
      final retry = await service.explain(_q(1), ExplainMode.simpler);
      expect(retry.answer, 'Second time lucky');
    });

    test('keeps only the most recent answers', () async {
      final service = ExplainService(call: (p) async => 'A for ${p['question']}');
      for (var i = 0; i < ExplainService.maxCached + 5; i++) {
        await service.explain(_q(i), ExplainMode.simpler);
      }
      expect(await service.cached(_q(0), ExplainMode.simpler), isNull);
      expect(await service.cached(_q(ExplainService.maxCached + 4), ExplainMode.simpler), isNotNull);
    });
  });

  group('QuestionNotesService', () {
    test('saves, reads back and clears a note per question', () async {
      final notes = QuestionNotesService();
      expect(await notes.noteFor(_q(1)), '');

      await notes.setNote(_q(1), '  Remember: A  ');
      await notes.setNote(_q(2), 'Other');
      expect(await notes.noteFor(_q(1)), 'Remember: A');
      expect(await notes.noteFor(_q(2)), 'Other');

      await notes.setNote(_q(1), '   ');
      expect(await notes.noteFor(_q(1)), '');
      expect(await notes.noteFor(_q(2)), 'Other');
    });

    test('caps note length and the number of notes', () async {
      final notes = QuestionNotesService();
      await notes.setNote(_q(1), 'x' * 900);
      expect((await notes.noteFor(_q(1))).length, QuestionNotesService.maxLength);

      for (var i = 0; i < QuestionNotesService.maxNotes + 3; i++) {
        await notes.setNote(_q(100 + i), 'note $i');
      }
      expect(await notes.noteFor(_q(1)), '');
      expect(await notes.noteFor(_q(100 + QuestionNotesService.maxNotes + 2)), isNotEmpty);
    });
  });

  group('SavedCardsService', () {
    test('saving a question makes a card that is due straight away', () async {
      final saved = SavedCardsService();
      expect(await saved.asSet(), isNull);

      expect(await saved.save(_q(1)), isTrue);

      final set = (await saved.asSet(withCards: true))!;
      expect(set['id'], SavedCardsService.setId);
      expect(set['cardCount'], 1);
      final card = (set['cards'] as List).single as Map;
      expect(card['front'], 'What is the capital of country 1?');
      expect(card['back'], 'City A\n\nBecause A is the capital.');
      expect(await SrsService().dueStartedKeys(), ['local_saved_0']);
      expect((await saved.cardsByKey())['local_saved_0']!.front, card['front']);
    });

    test('the same question is only saved once', () async {
      final saved = SavedCardsService();
      expect(await saved.save(_q(1)), isTrue);
      expect(await saved.save(_q(1)), isFalse);
      expect(await saved.isSaved(_q(1)), isTrue);
      expect(await saved.isSaved(_q(2)), isFalse);
      expect(await saved.count(), 1);
    });

    test('a question without an explanation still saves with just the answer', () async {
      final saved = SavedCardsService();
      await saved.save(_q(1, explanation: ''));
      expect((await saved.cardsByKey())['local_saved_0']!.back, 'City A');
    });

    test('later cards keep their own index and schedule', () async {
      final saved = SavedCardsService();
      await saved.save(_q(1));
      await saved.save(_q(2));
      await SrsService().rateCard(SavedCardsService.setId, 0, SrsRating.good);

      final keys = await SrsService().dueStartedKeys();
      expect(keys, ['local_saved_1']);
    });

    test('clearing removes the cards and their schedule', () async {
      final saved = SavedCardsService();
      await saved.save(_q(1));
      await saved.clear();
      expect(await saved.asSet(), isNull);
      expect(await SrsService().dueStartedKeys(), isEmpty);
    });
  });
}
