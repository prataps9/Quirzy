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

/// Per-question state within the currently loaded lane.
///
/// [uid] is unique per card instance (the same question can appear twice
/// in an endless feed) and is what the page view keys on.
class FeedCardState {
  final int uid;
  final PracticeQuestion question;
  final int? selectedOption;
  final bool skipped;
  final bool bookmarked;
  final bool liked;

  /// Why the feed picked this card, e.g. "Because you liked Physics".
  final String? reason;

  /// Inserted on request (Deep Dive "Similar"), so re-ranking keeps it.
  final bool pinned;

  const FeedCardState({
    required this.uid,
    required this.question,
    this.selectedOption,
    this.skipped = false,
    this.bookmarked = false,
    this.liked = false,
    this.reason,
    this.pinned = false,
  });

  bool get isResolved => selectedOption != null || skipped;
  bool get isCorrect =>
      selectedOption != null && selectedOption == question.correctIndex;

  FeedCardState copyWith({
    int? selectedOption,
    bool? skipped,
    bool? bookmarked,
    bool? liked,
  }) {
    return FeedCardState(
      uid: uid,
      question: question,
      selectedOption: selectedOption ?? this.selectedOption,
      skipped: skipped ?? this.skipped,
      bookmarked: bookmarked ?? this.bookmarked,
      liked: liked ?? this.liked,
      reason: reason,
      pinned: pinned,
    );
  }
}

/// XP for a correct answer, and the bonus for each combo milestone.
const int kFeedXpPerCorrect = 10;
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
  final bool breakNudgeShown;
  final bool pendingBreakNudge;
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
  final bool pendingCaughtUpNotice;

  /// Correct answers in a row this session; wrong answers reset it.
  final int combo;

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
    this.pendingBreakNudge = false,
    this.dailyTargetCelebrated = false,
    this.showHints = true,
    this.startIndex = 0,
    this.laneEpoch = 0,
    this.hasMore = false,
    this.allTopicsHidden = false,
    this.pendingCaughtUpNotice = false,
    this.combo = 0,
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
    bool? pendingBreakNudge,
    bool? dailyTargetCelebrated,
    bool? showHints,
    int? startIndex,
    int? laneEpoch,
    bool? hasMore,
    bool? allTopicsHidden,
    bool? pendingCaughtUpNotice,
    int? combo,
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
      pendingBreakNudge: pendingBreakNudge ?? this.pendingBreakNudge,
      dailyTargetCelebrated:
          dailyTargetCelebrated ?? this.dailyTargetCelebrated,
      showHints: showHints ?? this.showHints,
      startIndex: startIndex ?? this.startIndex,
      laneEpoch: laneEpoch ?? this.laneEpoch,
      hasMore: hasMore ?? this.hasMore,
      allTopicsHidden: allTopicsHidden ?? this.allTopicsHidden,
      pendingCaughtUpNotice:
          pendingCaughtUpNotice ?? this.pendingCaughtUpNotice,
      combo: combo ?? this.combo,
      todayAnswered: todayAnswered ?? this.todayAnswered,
      reward: reward ?? this.reward,
    );
  }
}
