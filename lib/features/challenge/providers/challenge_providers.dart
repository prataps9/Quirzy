import 'package:flutter_riverpod/legacy.dart';

import '../models/challenge.dart';

/// What a challenge link brought in: a challenge to open, or a link that
/// didn't work.
class IncomingChallenge {
  final Challenge? challenge;

  const IncomingChallenge.ok(Challenge this.challenge);
  const IncomingChallenge.broken() : challenge = null;
}

/// A challenge waiting to be opened. Set by the deep-link handler (which may
/// run before sign-in); the signed-in app shell opens it and clears it.
final pendingChallengeProvider = StateProvider<IncomingChallenge?>((ref) => null);
