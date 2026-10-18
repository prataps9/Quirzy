import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/models/feed_models.dart';
import 'package:quirzy/features/feed/services/feed_mixer.dart';
import 'package:quirzy/features/feed/services/feed_ranker.dart';

PracticeQuestion _q(int n, {List<String>? options, String explanation = '', String? text}) =>
    PracticeQuestion(
      id: 'q$n',
      questionText: text ?? 'Question $n?',
      options: options ?? const ['Alpha', 'Beta', 'Gamma', 'Delta'],
      correctIndex: 1,
      explanation: explanation,
      topic: 'Physics',
    );

List<RankedPick> _picks(int count) => [for (var i = 0; i < count; i++) RankedPick(_q(i), 'Because you like Physics')];

const _longWhy = 'Because the second option follows directly from the first law of motion.';

FeedFlashcard _card(int i) =>
    FeedFlashcard(setId: 'set', index: i, front: 'Front $i', back: 'Back $i', setTitle: 'Optics');

void main() {
  group('eligibility', () {
    test('composite and negative questions never become True/False', () {
      expect(FeedMixer.trueFalseEligible(_q(1)), isTrue);
      expect(FeedMixer.trueFalseEligible(_q(2, options: ['A', 'B', 'All of the above', 'C'])), isFalse);
      expect(FeedMixer.trueFalseEligible(_q(3, options: ['A', 'Both A and B', 'C', 'D'])), isFalse);
      expect(FeedMixer.trueFalseEligible(_q(4, text: 'Which is NOT a vector?')), isFalse);
      expect(FeedMixer.trueFalseEligible(_q(5, text: 'All are metals EXCEPT')), isFalse);
      expect(FeedMixer.trueFalseEligible(_q(6, options: ['A', 'x' * 120])), isFalse);
    });

    test('facts need a real explanation', () {
      expect(FeedMixer.factEligible(_q(1, explanation: 'Short.')), isFalse);
      expect(FeedMixer.factEligible(_q(1, explanation: _longWhy)), isTrue);
    });
  });

  group('mix', () {
    test('keeps every pick in order and shares about a fifth as True/False', () {
      final mixer = FeedMixer(random: math.Random(7));
      final slots = mixer.mix(_picks(1000));
      expect(slots.map((s) => s.question.id), [for (var i = 0; i < 1000; i++) 'q$i']);
      final tf = slots.where((s) => s.kind == FeedCardKind.trueFalse).length;
      expect(tf, inInclusiveRange(120, 230));
    });

    test('never puts two True/False cards in a row', () {
      final slots = FeedMixer(random: math.Random(3), trueFalseShare: 0.9).mix(_picks(300));
      for (var i = 1; i < slots.length; i++) {
        expect(
          slots[i].kind == FeedCardKind.trueFalse && slots[i - 1].kind == FeedCardKind.trueFalse,
          isFalse,
        );
      }
    });

    test('the shown True/False option is right about half the time and always valid', () {
      final slots = FeedMixer(random: math.Random(11), trueFalseShare: 0.5)
          .mix(_picks(2000))
          .where((s) => s.kind == FeedCardKind.trueFalse)
          .toList();
      final right = slots.where((s) => s.tfShownOption == 1).length;
      expect(right / slots.length, closeTo(0.5, 0.06));
      expect(slots.every((s) => s.tfShownOption! >= 0 && s.tfShownOption! < 4), isTrue);
    });

    test('flashcards and facts are spaced out and each used once', () {
      final mixer = FeedMixer(random: math.Random(1), trueFalseShare: 0);
      final slots = mixer.mix(
        _picks(40),
        facts: [for (var i = 100; i < 110; i++) _q(i, explanation: _longWhy)],
        flashcards: [for (var i = 0; i < 10; i++) _card(i)],
      );

      final kinds = slots.map((s) => s.kind).toList();
      final inserts = [
        for (var i = 0; i < kinds.length; i++)
          if (kinds[i] == FeedCardKind.fact || kinds[i] == FeedCardKind.flashcard) i,
      ];
      expect(inserts, isNotEmpty);
      for (var i = 1; i < inserts.length; i++) {
        expect(inserts[i] - inserts[i - 1], greaterThan(FeedMixer.minQuizBetween));
      }
      final flashIdx = [for (var i = 0; i < kinds.length; i++) if (kinds[i] == FeedCardKind.flashcard) i];
      for (var i = 1; i < flashIdx.length; i++) {
        expect(flashIdx[i] - flashIdx[i - 1], greaterThanOrEqualTo(FeedMixer.flashcardEvery));
      }
      final cardKeys = slots.where((s) => s.flashcard != null).map((s) => s.flashcard!.srsKey);
      expect(cardKeys.toSet().length, cardKeys.length);
      expect(kinds.take(FeedMixer.minQuizBetween), everyElement(FeedCardKind.question));
    });

    test('respects the cards already in the feed', () {
      final mixer = FeedMixer(random: math.Random(1), trueFalseShare: 0);
      final slots = mixer.mix(
        _picks(3),
        history: const [FeedCardKind.question, FeedCardKind.flashcard],
        flashcards: [_card(0)],
      );
      expect(slots.any((s) => s.kind == FeedCardKind.flashcard), isFalse);
    });

    test('ineligible facts are ignored', () {
      final slots = FeedMixer(random: math.Random(1), trueFalseShare: 0)
          .mix(_picks(30), facts: [_q(100)], history: List.filled(10, FeedCardKind.question));
      expect(slots.any((s) => s.kind == FeedCardKind.fact), isFalse);
    });
  });

  group('adapts to recent accuracy', () {
    List<MixedSlot> run(double? accuracy) => FeedMixer(random: math.Random(9)).mix(
      _picks(600),
      facts: [for (var i = 1000; i < 1300; i++) _q(i, explanation: _longWhy)],
      recentAccuracy: accuracy,
    );
    int count(List<MixedSlot> slots, FeedCardKind kind) => slots.where((s) => s.kind == kind).length;

    test('struggling: more facts and more True/False than usual', () {
      final usual = run(0.7);
      final struggling = run(0.3);
      expect(count(struggling, FeedCardKind.fact), greaterThan(count(usual, FeedCardKind.fact)));
      expect(count(struggling, FeedCardKind.trueFalse), greaterThan(count(usual, FeedCardKind.trueFalse)));
    });

    test('cruising: fewer facts and fewer True/False than usual', () {
      final usual = run(0.7);
      final cruising = run(0.95);
      expect(count(cruising, FeedCardKind.fact), lessThan(count(usual, FeedCardKind.fact)));
      expect(count(cruising, FeedCardKind.trueFalse), lessThan(count(usual, FeedCardKind.trueFalse)));
    });

    test('unknown accuracy keeps the defaults', () {
      expect(FeedMixer.factEveryFor(null), FeedMixer.factEvery);
      expect(FeedMixer().trueFalseShareFor(null), 0.2);
    });
  });

  test('a due flashcard can come early, so short feeds still get one', () {
    final slots = FeedMixer(random: math.Random(1), trueFalseShare: 0).mix(_picks(4), flashcards: [_card(0)]);
    final index = slots.indexWhere((s) => s.kind == FeedCardKind.flashcard);
    expect(index, FeedMixer.minQuizBetween);
  });
}
