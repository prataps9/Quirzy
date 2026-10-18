import 'dart:math' as math;

import '../models/feed_models.dart';
import 'feed_ranker.dart';

/// One slot in For You after mixing: a ranked question (possibly shown as
/// True/False) or an inserted fact or flashcard card.
class MixedSlot {
  final FeedCardKind kind;
  final PracticeQuestion question;
  final String? reason;
  final int? tfShownOption;
  final FeedFlashcard? flashcard;

  const MixedSlot._(this.kind, this.question, {this.reason, this.tfShownOption, this.flashcard});

  factory MixedSlot.question(RankedPick pick) =>
      MixedSlot._(FeedCardKind.question, pick.question, reason: pick.reason);

  factory MixedSlot.trueFalse(RankedPick pick, int shownOption) =>
      MixedSlot._(FeedCardKind.trueFalse, pick.question, reason: pick.reason, tfShownOption: shownOption);

  factory MixedSlot.fact(PracticeQuestion question) =>
      MixedSlot._(FeedCardKind.fact, question, reason: 'You missed this one before');

  factory MixedSlot.flashcard(FeedFlashcard card) => MixedSlot._(
    FeedCardKind.flashcard,
    card.toQuestion(),
    reason: 'Due for review in ${card.setTitle}',
    flashcard: card,
  );
}

/// Turns ranked picks into a varied For You stream. Pure and seedable.
///
/// - About [trueFalseShare] of eligible questions become True/False, never
///   two in a row.
/// - A due flashcard is slotted in at most once every [flashcardEvery]
///   cards, and a "Remember this?" fact at most once every [factEvery].
/// - Facts and flashcards always have at least [minQuizBetween] quiz cards
///   (question or True/False) between them, so the feed stays a quiz.
/// - The mix follows how the user is doing ([recentAccuracy]): when they
///   are struggling, more teaching (facts) and the easier True/False
///   format; when they are cruising, fewer facts and more full questions.
class FeedMixer {
  FeedMixer({math.Random? random, this.trueFalseShare = 0.2}) : _random = random ?? math.Random();

  final math.Random _random;

  /// Share of eligible questions shown as True/False.
  final double trueFalseShare;

  static const flashcardEvery = 6;
  static const factEvery = 8;

  /// Below / above these recent accuracies the mix shifts (see [mix]).
  static const strugglingBelow = 0.5;
  static const cruisingAbove = 0.85;
  static const minQuizBetween = 2;
  static const maxTrueFalseOptionLength = 90;
  static const minFactExplanationLength = 40;

  static final _composite = RegExp(
    r'\b(all|none|both|neither)\b.*\b(above|these|of them)\b|\bboth\b.*\band\b',
    caseSensitive: false,
  );

  /// Whether [q] reads sensibly as "Is this the answer?".
  static bool trueFalseEligible(PracticeQuestion q) {
    if (q.options.length < 2) return false;
    if (q.correctIndex < 0 || q.correctIndex >= q.options.length) return false;
    // Negative stems ("Which is NOT…", "…EXCEPT") turn True/False into a
    // double negative.
    if (q.questionText.contains(' NOT ') || q.questionText.contains('EXCEPT')) return false;
    for (final option in q.options) {
      final text = option.trim();
      if (text.isEmpty || text.length > maxTrueFalseOptionLength) return false;
      if (_composite.hasMatch(text)) return false;
    }
    return true;
  }

  /// Whether [q] has enough explanation to stand alone as a fact card.
  static bool factEligible(PracticeQuestion q) =>
      q.explanation.trim().length >= minFactExplanationLength &&
      q.correctIndex >= 0 &&
      q.correctIndex < q.options.length;

  /// How often a fact may appear for a given recent accuracy.
  static int factEveryFor(double? recentAccuracy) {
    if (recentAccuracy == null) return factEvery;
    if (recentAccuracy < strugglingBelow) return 5;
    if (recentAccuracy > cruisingAbove) return 12;
    return factEvery;
  }

  /// The True/False share for a given recent accuracy.
  double trueFalseShareFor(double? recentAccuracy) {
    if (recentAccuracy == null) return trueFalseShare;
    if (recentAccuracy < strugglingBelow) return trueFalseShare * 1.5;
    if (recentAccuracy > cruisingAbove) return trueFalseShare * 0.5;
    return trueFalseShare;
  }

  /// Mixes [picks] after the cards already in the feed, whose kinds are
  /// [history] (oldest first). [facts] and [flashcards] are consumed from
  /// the front; the caller removes the ones returned so they don't repeat.
  /// [recentAccuracy] (0–1, null when unknown) tunes the mix.
  List<MixedSlot> mix(
    List<RankedPick> picks, {
    List<FeedCardKind> history = const [],
    List<PracticeQuestion> facts = const [],
    List<FeedFlashcard> flashcards = const [],
    double? recentAccuracy,
  }) {
    final everyFact = factEveryFor(recentAccuracy);
    final tfShare = trueFalseShareFor(recentAccuracy);
    final kinds = [...history];
    final out = <MixedSlot>[];
    final factQueue = facts.where(factEligible).toList();
    final cardQueue = [...flashcards];

    // Cards since the last one matching; "never" counts as long ago, so
    // the first due flashcard can come as soon as there is room for it.
    int sinceLast(bool Function(FeedCardKind) match, {bool neverIsLongAgo = false}) {
      for (var i = kinds.length - 1; i >= 0; i--) {
        if (match(kinds[i])) return kinds.length - 1 - i;
      }
      return neverIsLongAgo ? 1 << 30 : kinds.length;
    }

    bool isInsert(FeedCardKind k) => k == FeedCardKind.fact || k == FeedCardKind.flashcard;

    void add(MixedSlot slot) {
      out.add(slot);
      kinds.add(slot.kind);
    }

    for (final pick in picks) {
      final roomForInsert = sinceLast(isInsert) >= minQuizBetween;
      if (roomForInsert && cardQueue.isNotEmpty &&
          sinceLast((k) => k == FeedCardKind.flashcard, neverIsLongAgo: true) >= flashcardEvery - 1) {
        add(MixedSlot.flashcard(cardQueue.removeAt(0)));
      } else if (roomForInsert && factQueue.isNotEmpty &&
          sinceLast((k) => k == FeedCardKind.fact) >= everyFact - 1) {
        add(MixedSlot.fact(factQueue.removeAt(0)));
      }

      final q = pick.question;
      final afterTrueFalse = kinds.isNotEmpty && kinds.last == FeedCardKind.trueFalse;
      if (!afterTrueFalse && trueFalseEligible(q) && _random.nextDouble() < tfShare) {
        add(MixedSlot.trueFalse(pick, _shownOption(q)));
      } else {
        add(MixedSlot.question(pick));
      }
    }
    return out;
  }

  /// Half the time the right answer, otherwise a random wrong one.
  int _shownOption(PracticeQuestion q) {
    if (_random.nextBool()) return q.correctIndex;
    final wrong = [for (var i = 0; i < q.options.length; i++) if (i != q.correctIndex) i];
    return wrong[_random.nextInt(wrong.length)];
  }
}
