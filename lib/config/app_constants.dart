/// App Constants - All constant values used across the app
class AppConstants {
  // App Info
  static const String appName = 'Quirzy';
  static const String appTagline = 'AI-Powered Learning';
  
  // Routes
  static const String homeRoute = '/home';
  static const String quizRoute = '/quiz';
  static const String flashcardsRoute = '/flashcards';
  static const String profileRoute = '/profile';
  static const String settingsRoute = '/settings';
  static const String historyRoute = '/history';
  static const String analyticsRoute = '/analytics';
  static const String leaderboardRoute = '/leaderboard';
  
  // Storage Keys
  static const String userIdKey = 'user_id';
  static const String userNameKey = 'user_name';
  static const String userEmailKey = 'user_email';
  static const String userPhotoKey = 'user_photo_url';
  static const String authTokenKey = 'auth_token';
  static const String themeKey = 'app_theme';
  static const String languageKey = 'app_language';
  
  // Asset Paths
  static const String logoPath = 'assets/icon/quirzy_icon.png';
  static const String iconsPath = 'assets/icon/';
  
  // Default Values
  static const String defaultUserName = 'Quiz Master';
  static const String defaultLanguage = 'en';
  static const String defaultTheme = 'system';
  
  // Quiz Defaults
  static const String defaultDifficulty = 'Medium';
  static const int defaultQuestionCount = 10;
  static const int defaultTimePerQuestion = 30;
  
  // Rank Tiers
  static const List<String> rankTiers = [
    'Bronze',
    'Silver',
    'Gold',
    'Platinum',
    'Diamond',
    'Master',
    'Grandmaster',
    'Legend',
  ];
  
  // Achievement Categories
  static const List<String> achievementCategories = [
    'Quiz',
    'Streak',
    'Flashcard',
    'XP',
    'Rank',
    'Special',
  ];
  
  // Supported Languages
  static const Map<String, String> supportedLanguages = {
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'hi': 'Hindi',
  };
  
  // Contact & Support
  static const String supportEmail = 'support@quirzy.com';
  static const String privacyPolicyUrl = 'https://quirzy.com/privacy';
  static const String termsOfServiceUrl = 'https://quirzy.com/terms';
}
