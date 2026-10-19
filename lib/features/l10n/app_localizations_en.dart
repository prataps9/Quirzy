// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get welcomeTitle => 'Crack your exam\nwith AI';

  @override
  String get welcomeSubtitle =>
      'Practice questions, flashcards and study sets for JEE, NEET, CAT, GRE and more.';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get acceptPrivacy =>
      'Please accept the Privacy Policy and Terms to continue';

  @override
  String get required => 'Required';

  @override
  String get iAgreeToThe => 'I agree to the';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get and => ' &';

  @override
  String get terms => 'Terms';

  @override
  String get navCards => 'Cards';

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get greetingAfternoon => 'Good afternoon';

  @override
  String get greetingEvening => 'Good evening';

  @override
  String get enterTopicHint => 'Enter a topic, e.g. Photosynthesis';

  @override
  String get generateQuizButton => 'Add practice topic';

  @override
  String get listening => 'Listening…';

  @override
  String get sayYourTopic => 'Say your topic';

  @override
  String get speechNotAvailable => 'Voice input isn\'t available on this phone';

  @override
  String get pleaseEnterTopic => 'Type a topic first';

  @override
  String get configureQuizTitle => 'Set up your topic';

  @override
  String get topicLabel => 'Topic';

  @override
  String get difficultyLabel => 'Difficulty';

  @override
  String get questionCountLabel => 'Number of questions';

  @override
  String get startGeneratingButton => 'Generate questions';

  @override
  String get difficultyEasy => 'Easy';

  @override
  String get difficultyMedium => 'Medium';

  @override
  String get difficultyHard => 'Hard';

  @override
  String get studySmarter1 => 'Study smarter';

  @override
  String get studySmarter2 => 'with AI';

  @override
  String get studySmarterSubtitle =>
      'Turn any topic into a flashcard set, then review what\'s due.';

  @override
  String get whatsTheTopic => 'What\'s the topic?';
}
