# Quirzy

Exam practice that feels like scrolling. Quirzy turns any topic into a
Reels-style feed of questions that adapts to what you like and what you get
wrong, with flashcards, a daily streak and a progress view alongside.

## What's in the app

| Tab | What it does |
|---|---|
| **Practice** | An endless, adaptive *For You* feed. Swipe up for the next card; it mixes multiple-choice questions, True/False, "Remember this?" facts from questions you missed, and due flashcards. Lanes for single topics, weak topics, revision and saved questions. Streak, daily goal, combo, XP and a session recap every 15 answers. |
| **Home** | Generate a new topic with AI (or add your own questions, paste notes, or build a study set) and jump into it. |
| **My Prep** | Streak, XP and level, per-topic accuracy, exam countdown, leaderboard and a shareable progress card. |
| **Cards** | AI-generated flashcard sets with spaced repetition, favourites and exam-specific suggestions. |
| **Profile** | Theme, practice-feed settings (auto-scroll, read aloud, sounds), reminders, Pro, privacy and account. |

Free accounts get 2 AI topics, 1 study set and 3 flashcard sets a day;
**Quirzy Pro** removes the limits. Practice progress lives on the device, so
the feed works offline once a topic has been downloaded.

## Tech

- Flutter 3.38 (Dart 3.10), Riverpod 3, go_router
- Appwrite (Google sign-in, database, AI generation functions)
- Local notifications with timezone-aware scheduling
- Razorpay for Pro payments

Code is organised by feature under `lib/features/` (feed, home, flashcards,
progress, profile, subscription, content, onboarding), with shared theme,
widgets and services under `lib/shared/`. The design system lives in
`lib/shared/theme/` (`context.palette`, `AppTheme`).

## Getting started

```bash
flutter pub get
flutter run
```

### Configuration

- **Appwrite:** endpoint, project and collection ids are in
  `lib/shared/appwrite/appwrite_client.dart`.
- **Razorpay:** set your live key id in `kRazorpayKeyId`
  (`lib/features/subscription/services/payment_service.dart`). Checkout
  won't open with the placeholder.
- **Release signing (Android):** create `android/key.properties` (never
  commit it, and keep the keystore outside the repo):

  ```properties
  storeFile=/absolute/path/to/upload-keystore.jks
  storePassword=…
  keyAlias=upload
  keyPassword=…
  ```

- **Icons and splash:** configured in `pubspec.yaml`; regenerate with
  `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`.

## Tests

```bash
flutter analyze
flutter test
```

Tests cover the feed ranker, mixer and controller, the feed screen
(auto-scroll, read-aloud, recap), streaks, usage limits and Pro, flashcard
preferences, and design guards (palette contrast, no off-palette colours).

## License

See [LICENSE](LICENSE).
