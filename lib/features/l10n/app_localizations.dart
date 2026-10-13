import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
  ];

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Crack your exam\nwith AI'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Practice questions, flashcards and study sets for JEE, NEET, CAT, GRE and more.'**
  String get welcomeSubtitle;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @acceptPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Please accept the Privacy Policy and Terms to continue'**
  String get acceptPrivacy;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @iAgreeToThe.
  ///
  /// In en, this message translates to:
  /// **'I agree to the '**
  String get iAgreeToThe;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @and.
  ///
  /// In en, this message translates to:
  /// **' & '**
  String get and;

  /// No description provided for @terms.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get terms;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @commonLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get commonLanguage;

  /// No description provided for @commonAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get commonAppearance;

  /// No description provided for @commonNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get commonNotifications;

  /// No description provided for @commonSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get commonSupport;

  /// No description provided for @helpAndFeedback.
  ///
  /// In en, this message translates to:
  /// **'Help & Feedback'**
  String get helpAndFeedback;

  /// No description provided for @settingsDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get settingsDarkMode;

  /// No description provided for @settingsSystemTheme.
  ///
  /// In en, this message translates to:
  /// **'System Theme'**
  String get settingsSystemTheme;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navCards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get navCards;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good Morning 👋'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good Afternoon 👋'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good Evening 👋'**
  String get greetingEvening;

  /// No description provided for @adsLabel.
  ///
  /// In en, this message translates to:
  /// **'Ads'**
  String get adsLabel;

  /// No description provided for @freeLabel.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get freeLabel;

  /// No description provided for @homeTitle1.
  ///
  /// In en, this message translates to:
  /// **'Prepare smarter,\n'**
  String get homeTitle1;

  /// No description provided for @homeTitle2.
  ///
  /// In en, this message translates to:
  /// **'score higher.'**
  String get homeTitle2;

  /// No description provided for @actionAIGen.
  ///
  /// In en, this message translates to:
  /// **'AI Gen'**
  String get actionAIGen;

  /// No description provided for @actionQuick.
  ///
  /// In en, this message translates to:
  /// **'Quick'**
  String get actionQuick;

  /// No description provided for @actionDeep.
  ///
  /// In en, this message translates to:
  /// **'Deep'**
  String get actionDeep;

  /// No description provided for @actionStudy.
  ///
  /// In en, this message translates to:
  /// **'Study'**
  String get actionStudy;

  /// No description provided for @createFromTopic.
  ///
  /// In en, this message translates to:
  /// **'Create from topic'**
  String get createFromTopic;

  /// No description provided for @enterTopicHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a topic (e.g., \'Photosynthesis\')'**
  String get enterTopicHint;

  /// No description provided for @generateQuizButton.
  ///
  /// In en, this message translates to:
  /// **'Add Practice Topic'**
  String get generateQuizButton;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening...'**
  String get listening;

  /// No description provided for @sayYourTopic.
  ///
  /// In en, this message translates to:
  /// **'Say your topic'**
  String get sayYourTopic;

  /// No description provided for @speechNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition not available'**
  String get speechNotAvailable;

  /// No description provided for @pleaseEnterTopic.
  ///
  /// In en, this message translates to:
  /// **'Please enter a topic first'**
  String get pleaseEnterTopic;

  /// No description provided for @enterTopicDeepDive.
  ///
  /// In en, this message translates to:
  /// **'Enter a topic for a deep dive!'**
  String get enterTopicDeepDive;

  /// No description provided for @configureQuizTitle.
  ///
  /// In en, this message translates to:
  /// **'Configure Topic'**
  String get configureQuizTitle;

  /// No description provided for @topicLabel.
  ///
  /// In en, this message translates to:
  /// **'Topic'**
  String get topicLabel;

  /// No description provided for @difficultyLabel.
  ///
  /// In en, this message translates to:
  /// **'Difficulty'**
  String get difficultyLabel;

  /// No description provided for @questionCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Number of Questions'**
  String get questionCountLabel;

  /// No description provided for @startGeneratingButton.
  ///
  /// In en, this message translates to:
  /// **'Start Generating'**
  String get startGeneratingButton;

  /// No description provided for @failedToGenerate.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate quiz: '**
  String get failedToGenerate;

  /// No description provided for @difficultyEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get difficultyEasy;

  /// No description provided for @difficultyMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get difficultyMedium;

  /// No description provided for @difficultyHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get difficultyHard;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @yourLearningJourney1.
  ///
  /// In en, this message translates to:
  /// **'Your Learning\n'**
  String get yourLearningJourney1;

  /// No description provided for @yourLearningJourney2.
  ///
  /// In en, this message translates to:
  /// **'Journey'**
  String get yourLearningJourney2;

  /// No description provided for @reviewPastAchievements.
  ///
  /// In en, this message translates to:
  /// **'Review your past achievements and keep growing.'**
  String get reviewPastAchievements;

  /// No description provided for @tabQuizzes.
  ///
  /// In en, this message translates to:
  /// **'Quizzes'**
  String get tabQuizzes;

  /// No description provided for @tabProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get tabProgress;

  /// No description provided for @tabStats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get tabStats;

  /// No description provided for @progressSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Progress & Analytics\nComing Soon'**
  String get progressSubtitle;

  /// No description provided for @totalQuizzesLabel.
  ///
  /// In en, this message translates to:
  /// **'TOTAL QUIZZES'**
  String get totalQuizzesLabel;

  /// No description provided for @thisWeekLabel.
  ///
  /// In en, this message translates to:
  /// **'this week'**
  String get thisWeekLabel;

  /// No description provided for @avgScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'AVG. SCORE'**
  String get avgScoreLabel;

  /// No description provided for @recentHistoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Recent History'**
  String get recentHistoryLabel;

  /// No description provided for @viewAllLabel.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAllLabel;

  /// No description provided for @untitledQuiz.
  ///
  /// In en, this message translates to:
  /// **'Untitled Quiz'**
  String get untitledQuiz;

  /// No description provided for @dateToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dateToday;

  /// No description provided for @dateYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dateYesterday;

  /// No description provided for @incompleteLabel.
  ///
  /// In en, this message translates to:
  /// **'Incomplete'**
  String get incompleteLabel;

  /// No description provided for @continueQuizLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue Quiz'**
  String get continueQuizLabel;

  /// No description provided for @questionsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} Questions'**
  String questionsCountLabel(int count);

  /// No description provided for @viewStatsLabel.
  ///
  /// In en, this message translates to:
  /// **'View Stats'**
  String get viewStatsLabel;

  /// No description provided for @noHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'No Quizzes Yet'**
  String get noHistoryTitle;

  /// No description provided for @noHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'It looks a bit quiet here. Create your first quiz from your notes to get started!'**
  String get noHistorySubtitle;

  /// No description provided for @secondsPerQuestion.
  ///
  /// In en, this message translates to:
  /// **'30s per question'**
  String get secondsPerQuestion;

  /// No description provided for @tapToSelect.
  ///
  /// In en, this message translates to:
  /// **'Tap an option to select your answer'**
  String get tapToSelect;

  /// No description provided for @answerBeforeTimer.
  ///
  /// In en, this message translates to:
  /// **'Answer before the timer runs out'**
  String get answerBeforeTimer;

  /// No description provided for @tapNextToProceed.
  ///
  /// In en, this message translates to:
  /// **'Tap Next to proceed to the next question'**
  String get tapNextToProceed;

  /// No description provided for @flashcardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Flashcards'**
  String get flashcardsTitle;

  /// No description provided for @yourCollection.
  ///
  /// In en, this message translates to:
  /// **'Your Collection'**
  String get yourCollection;

  /// No description provided for @studySmarter1.
  ///
  /// In en, this message translates to:
  /// **'Study Smarter\n'**
  String get studySmarter1;

  /// No description provided for @studySmarter2.
  ///
  /// In en, this message translates to:
  /// **'With AI'**
  String get studySmarter2;

  /// No description provided for @studySmarterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create and study flashcards powered by AI.'**
  String get studySmarterSubtitle;

  /// No description provided for @whatsTheTopic.
  ///
  /// In en, this message translates to:
  /// **'What\'s the topic?'**
  String get whatsTheTopic;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
