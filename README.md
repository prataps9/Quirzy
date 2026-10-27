# Quirzy

Exam practice that feels like scrolling. Quirzy turns any topic into a
Reels-style feed of questions that adapts to what you like and what you get
wrong, with flashcards, a daily streak and a progress view alongside.

## What's in the app

| Tab | What it does |
|---|---|
| **Practice** | An endless, adaptive *For You* feed. Swipe up for the next card, left for the solution (with Ask AI, notes and save-as-flashcard), right for the topic dial. It mixes multiple-choice questions, True/False, "Remember this?" facts from questions you missed, and due flashcards. A **Daily 5** (same five questions all day, leaning on your weak topics, with an XP bonus for finishing) plus lanes for single topics, weak topics, revision and saved questions, all on the topic dial, which also shows how well each topic is going. Streak, daily goal, combo, XP and a session recap every 15 answers. |
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
- **Ask AI (`explain-question` function):** the solution panel's Ask AI box
  calls an Appwrite function with this id. Deploy it for Ask AI to work;
  until then the box says "Ask AI isn't available right now". It receives a
  JSON body and must return `{"answer": "<plain text>"}` (or `{"error": "…"}`):

  ```json
  {
    "question": "…", "options": ["…"], "correctIndex": 0,
    "explanation": "…", "topic": "…", "userId": "…",
    "mode": "simpler | example | others | memory | followUp",
    "followUp": "only when mode is followUp"
  }
  ```

  Free accounts get 5 AI answers a day (`UsageKind.aiExplain`); answers to
  the four canned modes are cached on the device and cost nothing again.
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
