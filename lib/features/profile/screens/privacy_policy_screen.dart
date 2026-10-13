import 'package:flutter/material.dart';

import '../../../config/app_constants.dart';
import '../../../shared/theme/app_palette.dart';

/// What Quirzy stores, where, and how to get rid of it.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PolicyPage(
      title: 'Privacy policy',
      intro: 'This is what Quirzy keeps about you, where it lives, and how to remove it.',
      sections: [
        _Section('Signing in', [
          'You sign in with your Google account. Quirzy uses Appwrite, a backend service, to create and manage your account.',
          'We get your name, email address and profile photo from Google. We never see your Google password.',
        ]),
        _Section('What is stored on our servers', [
          'Your name, email address and a link to your Google profile photo, kept in Appwrite.',
          'What you create in the app: the topics you enter and the flashcards and study sets made from them. Topics are sent to our server so that content can be generated.',
          'For the leaderboard: your name, total XP, number of questions answered and current streak. Other Quirzy users can see your name, XP and streak on the board.',
        ]),
        _Section('What stays on your device', [
          'Your answers, topics, bookmarks, exam choice and settings are stored only on this phone. Apart from the leaderboard totals above, they are not uploaded.',
          'Logging out or deleting your account erases them from the device.',
        ]),
        _Section('Payments', [
          'Quirzy Pro payments are handled by Razorpay. Quirzy never sees or stores your card, UPI or bank details. We only learn whether a payment succeeded.',
        ]),
        _Section('Ads, tracking and notifications', [
          'Quirzy shows no ads and does not use analytics or tracking tools.',
          'Reminders are local notifications scheduled on your phone. You can turn them off in Profile > Notifications.',
        ]),
        _Section('Deleting your account', [
          'Go to Profile > Delete account. This deletes your profile and your leaderboard entry, closes your account so it can no longer be signed in to, and erases everything Quirzy stored on this device.',
          'If you also want the flashcards and study sets you created removed from our servers, email us and we will delete them.',
        ]),
        _Section('Contact', [
          'Questions or requests: ${AppConstants.supportEmail}',
        ]),
      ],
    );
  }
}

/// The rules for using Quirzy, in plain words.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PolicyPage(
      title: 'Terms of use',
      intro: 'By using Quirzy you agree to these terms.',
      sections: [
        _Section('Using Quirzy', [
          'Quirzy is a study aid: practice questions, flashcards and study sets for your exam. It does not guarantee any exam result.',
          'Questions and study material may contain mistakes. If you spot one, use "Report a problem" and check important facts against your textbooks.',
        ]),
        _Section('Your account', [
          'You sign in with Google and are responsible for activity on your account. One account per person.',
          'Do not misuse the app: no attempts to break, overload or copy the service, and no illegal or abusive content in the topics you enter.',
        ]),
        _Section('Your content', [
          'The topics you enter and the material generated from them are yours to use for your own studying.',
        ]),
        _Section('Quirzy Pro', [
          'Some features need Quirzy Pro. Prices and what is included are shown before you pay. Payments are processed by Razorpay.',
          'For a refund or billing problem, email us with your payment details.',
        ]),
        _Section('Changes and ending', [
          'We may update the app and these terms. If a change is significant, we will tell you in the app.',
          'You can stop using Quirzy and delete your account at any time from Profile. We may suspend accounts that break these terms.',
        ]),
        _Section('Contact', [
          'Questions: ${AppConstants.supportEmail}',
        ]),
      ],
    );
  }
}

class _Section {
  final String heading;
  final List<String> paragraphs;

  const _Section(this.heading, this.paragraphs);
}

class _PolicyPage extends StatelessWidget {
  final String title;
  final String intro;
  final List<_Section> sections;

  const _PolicyPage({required this.title, required this.intro, required this.sections});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final body = text.bodyMedium!.copyWith(color: p.text, height: 1.5);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.xxl),
          children: [
            Text(intro, style: body.copyWith(color: p.textMuted)),
            for (final section in sections) ...[
              const SizedBox(height: AppSpace.xl),
              Text(section.heading, style: text.titleMedium),
              for (final paragraph in section.paragraphs) ...[
                const SizedBox(height: AppSpace.sm),
                Text(paragraph, style: body),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
