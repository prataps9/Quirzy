/// A single practice question in the feed's local content pool.
class PracticeQuestion {
  final String id;
  final String questionText;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String? sourceTopicId;
  final String? topic;

  const PracticeQuestion({
    required this.id,
    required this.questionText,
    required this.options,
    required this.correctIndex,
    this.explanation = '',
    this.sourceTopicId,
    this.topic,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'questionText': questionText,
      'options': options,
      'correctIndex': correctIndex,
      'explanation': explanation,
      'sourceTopicId': sourceTopicId,
      'topic': topic,
    };
  }

  factory PracticeQuestion.fromJson(Map<String, dynamic> json) {
    return PracticeQuestion(
      id: json['id'] as String,
      questionText: json['questionText'] as String,
      options: List<String>.from(json['options'] as List),
      correctIndex: json['correctIndex'] as int,
      explanation: json['explanation'] as String? ?? '',
      sourceTopicId: json['sourceTopicId'] as String? ?? json['originalQuizId'] as String?,
      topic: json['topic'] as String?,
    );
  }
}

extension PracticeQuestionKeys on PracticeQuestion {
  /// Topic name with the store's "General" fallback for untagged questions.
  String get topicName =>
      (topic == null || topic!.trim().isEmpty) ? 'General' : topic!;

  /// Ids alone can collide across topics (generated ids fall back to
  /// `null_0`-style values), so engagement data is keyed by topic too.
  String get engagementKey => '$topicName|$id';
}

/// When a question was last shown and how many times, for recycling.
class SeenRecord {
  final int lastSeenMs;
  final int count;

  const SeenRecord({required this.lastSeenMs, required this.count});
}

/// One topic bucket in the local content store — the data behind a
/// per-topic lane, including whether it's protected from eviction
/// ("downloaded").
class TopicSummary {
  final String topic;
  final int count;
  final bool downloaded;
  final DateTime lastUpdated;

  const TopicSummary({
    required this.topic,
    required this.count,
    required this.downloaded,
    required this.lastUpdated,
  });
}

/// The kind of lane a [FeedLane] represents: the adaptive For You feed,
/// one topic, weak topics, the revision vault, or saved questions.
enum FeedLaneType { forYou, topic, weakTopics, revision, bookmarks }

/// One entry in the Lane Switcher (swipe-right / lane-chip tap).
class FeedLane {
  final FeedLaneType type;
  final String id;
  final String label;
  final int count;
  final bool downloaded;

  const FeedLane({
    required this.type,
    required this.id,
    required this.label,
    this.count = 0,
    this.downloaded = false,
  });

  static const forYou = FeedLane(
    type: FeedLaneType.forYou,
    id: 'for_you',
    label: 'For You',
  );

  bool get isInfinite => type == FeedLaneType.forYou;

  FeedLane copyWith({int? count, bool? downloaded}) => FeedLane(
    type: type,
    id: id,
    label: label,
    count: count ?? this.count,
    downloaded: downloaded ?? this.downloaded,
  );
}

/// What a card in the feed is. Everything except [question] is mixed into
/// For You from content already on the device.
enum FeedCardKind {
  /// A multiple-choice question.
  question,

  /// "Is this the answer?" — the stem with one shown option.
  trueFalse,

  /// "Remember this?" — a question you missed, with its answer and
  /// explanation, read like a story.
  fact,

  /// A due flashcard from Cards, flipped and rated in the feed.
  flashcard,

  /// "Your session so far" — answered, accuracy, XP, topics — every few
  /// answers, and the gentle take-a-break moment in long sessions.
  recap,

  /// "You've seen everything new" — offers to generate more of a topic.
  caughtUp,
}

/// One session-recap card's numbers, frozen when the card is created.
class FeedRecap {
  final int answered;
  final int correct;
  final int xp;
  final int bestCombo;

  /// Topics practised this session, most-practised first.
  final List<String> topTopics;

  /// The topic with the lowest accuracy this session (2+ attempts), if any.
  final String? weakTopic;

  /// Shown in a long session: the headline suggests a break.
  final bool suggestBreak;

  const FeedRecap({
    required this.answered,
    required this.correct,
    required this.xp,
    required this.bestCombo,
    required this.topTopics,
    required this.weakTopic,
    required this.suggestBreak,
  });

  int get accuracyPercent => answered == 0 ? 0 : (correct * 100 / answered).round();

  /// Builds the recap from per-topic (attempts, correct) counts.
  factory FeedRecap.fromSession({
    required Map<String, ({int attempts, int correct})> topics,
    required int xp,
    required int bestCombo,
    required bool suggestBreak,
  }) {
    final answered = topics.values.fold<int>(0, (sum, t) => sum + t.attempts);
    final correct = topics.values.fold<int>(0, (sum, t) => sum + t.correct);
    final ranked = topics.keys.toList()
      ..sort((a, b) => topics[b]!.attempts.compareTo(topics[a]!.attempts));
    String? weak;
    var weakest = 2.0;
    for (final entry in topics.entries) {
      final t = entry.value;
      if (t.attempts < 2) continue;
      final accuracy = t.correct / t.attempts;
      if (accuracy < weakest && accuracy < 0.7) {
        weakest = accuracy;
        weak = entry.key;
      }
    }
    return FeedRecap(
      answered: answered,
      correct: correct,
      xp: xp,
      bestCombo: bestCombo,
      topTopics: ranked.take(3).toList(),
      weakTopic: weak,
      suggestBreak: suggestBreak,
    );
  }
}

/// A flashcard shown in the feed, from a set cached on the device.
class FeedFlashcard {
  final String setId;
  final int index;
  final String front;
  final String back;
  final String setTitle;

  const FeedFlashcard({
    required this.setId,
    required this.index,
    required this.front,
    required this.back,
    required this.setTitle,
  });

  /// The key [SrsService] stores this card's schedule under.
  String get srsKey => '${setId}_$index';

  /// A stand-in question so topic chips, sharing and dwell tracking work
  /// the same for every card.
  PracticeQuestion toQuestion() => PracticeQuestion(
    id: 'flashcard:$srsKey',
    questionText: front,
    options: [back],
    correctIndex: 0,
    topic: setTitle,
  );
}

/// Per-card state within the currently loaded lane.
///
/// [uid] is unique per card instance (the same question can appear twice
/// in an endless feed) and is what the page view keys on.
class FeedCardState {
  final int uid;
  final FeedCardKind kind;
  final PracticeQuestion question;
  final int? selectedOption;
  final bool skipped;
  final bool bookmarked;
  final bool liked;

  /// Why the feed picked this card, e.g. "Because you liked Physics".
  final String? reason;

  /// Inserted on request (Deep Dive "Similar"), so re-ranking keeps it.
  final bool pinned;

  /// True/False: the option shown, and what the user answered.
  final int? tfShownOption;
  final bool? tfChoice;

  /// Fact: read to the end (or tapped through).
  final bool acknowledged;

  /// Flashcard: the card, whether it was flipped, and whether it was rated.
  final FeedFlashcard? flashcard;
  final bool flipped;
  final bool rated;

  /// Recap: the session numbers it shows.
  final FeedRecap? recap;

  const FeedCardState({
    required this.uid,
    required this.question,
    this.kind = FeedCardKind.question,
    this.selectedOption,
    this.skipped = false,
    this.bookmarked = false,
    this.liked = false,
    this.reason,
    this.pinned = false,
    this.tfShownOption,
    this.tfChoice,
    this.acknowledged = false,
    this.flashcard,
    this.flipped = false,
    this.rated = false,
    this.recap,
  });

  /// Whether the shown True/False option is the right answer.
  bool get tfStatementTrue => tfShownOption == question.correctIndex;

  bool get isResolved => switch (kind) {
    FeedCardKind.question => selectedOption != null || skipped,
    FeedCardKind.trueFalse => tfChoice != null || skipped,
    FeedCardKind.fact || FeedCardKind.recap || FeedCardKind.caughtUp => acknowledged,
    FeedCardKind.flashcard => rated,
  };

  bool get isCorrect => switch (kind) {
    FeedCardKind.question => selectedOption != null && selectedOption == question.correctIndex,
    FeedCardKind.trueFalse => tfChoice != null && tfChoice == tfStatementTrue,
    _ => false,
  };

  /// Cards the ranker queued (and must release when they are dropped).
  bool get fromRanker => kind == FeedCardKind.question || kind == FeedCardKind.trueFalse;

  /// Cards that are answered for stats, XP and the daily goal.
  bool get isQuiz => fromRanker;

  /// Cards whose [question] is a stand-in, not a question from the pool:
  /// they must not touch engagement, bookmarks or the revision vault.
  bool get isSynthetic =>
      kind == FeedCardKind.flashcard || kind == FeedCardKind.recap || kind == FeedCardKind.caughtUp;

  FeedCardState copyWith({
    int? selectedOption,
    bool? skipped,
    bool? bookmarked,
    bool? liked,
    bool? tfChoice,
    bool? acknowledged,
    bool? flipped,
    bool? rated,
  }) {
    return FeedCardState(
      uid: uid,
      kind: kind,
      question: question,
      selectedOption: selectedOption ?? this.selectedOption,
      skipped: skipped ?? this.skipped,
      bookmarked: bookmarked ?? this.bookmarked,
      liked: liked ?? this.liked,
      reason: reason,
      pinned: pinned,
      tfShownOption: tfShownOption,
      tfChoice: tfChoice ?? this.tfChoice,
      acknowledged: acknowledged ?? this.acknowledged,
      flashcard: flashcard,
      flipped: flipped ?? this.flipped,
      rated: rated ?? this.rated,
      recap: recap,
    );
  }
}

/// XP for a correct answer, and the bonus for each combo milestone.
const int kFeedXpPerCorrect = 10;

/// True/False is a coin flip to guess, so it is worth half.
const int kFeedXpPerTrueFalse = 5;
const int kFeedComboBonusXp = 10;

/// A combo milestone fires every this many correct answers in a row.
const int kFeedComboMilestone = 5;

enum FeedRewardKind { streak, comboMilestone, dailyGoal, levelUp }

/// A celebration the feed screen should show once. [id] changes for every
/// new reward so the screen can tell a new one from the one it showed.
class FeedReward {
  final int id;
  final FeedRewardKind kind;

  /// Streak days, combo count, goal size or new level, depending on [kind].
  final int value;

  const FeedReward({required this.id, required this.kind, required this.value});
}

/// State owned by [FeedController].
class FeedState {
  final FeedLane lane;
  final List<FeedCardState> cards;
  final bool loading;
  final String? error;
  final bool focusMode;
  final int sessionAnswered;
  final int sessionCorrect;
  final DateTime sessionStart;
  /// A long session's recap has already suggested a break.
  final bool breakNudgeShown;
  final bool dailyTargetCelebrated;
  final bool showHints;
  final int startIndex;

  /// Bumped each time a lane (re)loads; the screen jumps to [startIndex]
  /// only when this changes, so appended or re-ranked cards never move
  /// the user.
  final int laneEpoch;

  /// Whether more cards can still be appended; when false the feed ends
  /// with a closing page.
  final bool hasMore;

  /// Every topic with content is hidden, so the feed is empty by choice.
  final bool allTopicsHidden;

  /// Correct answers in a row this session; wrong answers reset it.
  final int combo;

  /// Best combo and XP earned this session, for the recap card.
  final int bestCombo;
  final int sessionXp;

  /// Questions answered or revealed today, for the daily-goal ring.
  final int todayAnswered;

  /// The latest celebration to show, if any.
  final FeedReward? reward;

  FeedState({
    required this.lane,
    this.cards = const [],
    this.loading = true,
    this.error,
    this.focusMode = false,
    this.sessionAnswered = 0,
    this.sessionCorrect = 0,
    DateTime? sessionStart,
    this.breakNudgeShown = false,
    this.dailyTargetCelebrated = false,
    this.showHints = true,
    this.startIndex = 0,
    this.laneEpoch = 0,
    this.hasMore = false,
    this.allTopicsHidden = false,
    this.combo = 0,
    this.bestCombo = 0,
    this.sessionXp = 0,
    this.todayAnswered = 0,
    this.reward,
  }) : sessionStart = sessionStart ?? DateTime.now();

  factory FeedState.initial() => FeedState(lane: FeedLane.forYou);

  double get sessionAccuracy =>
      sessionAnswered == 0 ? 0 : (sessionCorrect / sessionAnswered) * 100;

  FeedState copyWith({
    FeedLane? lane,
    List<FeedCardState>? cards,
    bool? loading,
    String? error,
    bool? focusMode,
    int? sessionAnswered,
    int? sessionCorrect,
    bool? breakNudgeShown,
    bool? dailyTargetCelebrated,
    bool? showHints,
    int? startIndex,
    int? laneEpoch,
    bool? hasMore,
    bool? allTopicsHidden,
    int? combo,
    int? bestCombo,
    int? sessionXp,
    int? todayAnswered,
    FeedReward? reward,
  }) {
    return FeedState(
      lane: lane ?? this.lane,
      cards: cards ?? this.cards,
      loading: loading ?? this.loading,
      error: error,
      focusMode: focusMode ?? this.focusMode,
      sessionAnswered: sessionAnswered ?? this.sessionAnswered,
      sessionCorrect: sessionCorrect ?? this.sessionCorrect,
      sessionStart: sessionStart,
      breakNudgeShown: breakNudgeShown ?? this.breakNudgeShown,
      dailyTargetCelebrated:
          dailyTargetCelebrated ?? this.dailyTargetCelebrated,
      showHints: showHints ?? this.showHints,
      startIndex: startIndex ?? this.startIndex,
      laneEpoch: laneEpoch ?? this.laneEpoch,
      hasMore: hasMore ?? this.hasMore,
      allTopicsHidden: allTopicsHidden ?? this.allTopicsHidden,
      combo: combo ?? this.combo,
      bestCombo: bestCombo ?? this.bestCombo,
      sessionXp: sessionXp ?? this.sessionXp,
      todayAnswered: todayAnswered ?? this.todayAnswered,
      reward: reward ?? this.reward,
    );
  }
}
