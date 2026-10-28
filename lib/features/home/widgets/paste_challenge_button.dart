import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_palette.dart';
import '../../../shared/utils/user_messages.dart';
import '../../challenge/models/challenge.dart';
import '../../challenge/screens/challenge_screen.dart';

/// For challenge links a chat app didn't make tappable: copy the message,
/// tap this, and the challenge opens.
class PasteChallengeButton extends StatelessWidget {
  const PasteChallengeButton({super.key});

  Future<void> _paste(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final link = ChallengeCodec.findIn(data?.text ?? '');
    if (link == null) {
      showAppSnack(context, 'No challenge link found. Copy the whole message your friend sent, then try again.');
      return;
    }
    try {
      final challenge = ChallengeCodec.decode(link);
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ChallengeScreen(challenge: challenge)));
    } on FormatException {
      if (context.mounted) showAppSnack(context, "That challenge link doesn't work. Ask your friend to send it again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _paste(context),
          icon: Icon(Icons.content_paste_go_rounded, color: context.palette.accentText),
          label: const Text('Got a challenge? Paste it'),
        ),
      ),
    );
  }
}
