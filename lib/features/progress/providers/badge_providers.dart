import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/badge.dart';
import '../services/badge_service.dart';

final badgeServiceProvider = Provider<BadgeService>((ref) => BadgeService());

/// Every badge with its progress, for My Prep.
final badgeStatusesProvider = FutureProvider<List<BadgeStatus>>((ref) {
  return ref.watch(badgeServiceProvider).statuses();
});
