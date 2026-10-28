import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../shared/appwrite/leaderboard/leaderboard_service.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/utils/user_messages.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/motion.dart';
import '../../feed/services/leaderboard_sync.dart';

/// Leaderboard Screen - one global ranking by lifetime XP.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  final _leaderboardService = LeaderboardService();
  final _storage = const FlutterSecureStorage();

  List<Map<String, dynamic>> _topPlayers = [];
  Map<String, dynamic> _userRank = {};
  String _userId = '';
  bool _isLoading = true;
  bool _hasLoaded = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    // Only show the full-screen spinner on the first load; a refresh keeps
    // the rows that are already on screen.
    setState(() {
      _isLoading = !_hasLoaded;
      _loadFailed = false;
    });

    try {
      // Push this device's latest XP first so the user sees themselves
      // where they actually are. Offline-safe: failures are swallowed.
      await ref.read(leaderboardSyncProvider).syncNow();

      final topPlayers = await _leaderboardService.getTopPlayers(limit: 50);
      final userId = await _storage.read(key: 'user_id') ?? '';
      final userRank = userId.isNotEmpty
          ? await _leaderboardService.getUserRank(userId: userId)
          : <String, dynamic>{};

      if (mounted) {
        setState(() {
          _topPlayers = topPlayers;
          _userId = userId;
          _userRank = Map<String, dynamic>.from(userRank);
          _isLoading = false;
          _hasLoaded = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
      // Rows already on screen stay put; just say the refresh failed.
      if (_topPlayers.isNotEmpty) {
        showAppSnack(
          context,
          "Couldn't refresh the leaderboard. Check your connection and try again.",
          onRetry: _loadLeaderboard,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadLeaderboard,
          ),
        ],
      ),
      body: _isLoading
          ? const SkeletonList(count: 7, itemHeight: 64)
          : RefreshIndicator(
              onRefresh: _loadLeaderboard,
              child: _loadFailed && _topPlayers.isEmpty
                  ? _buildErrorState()
                  : _buildGlobalLeaderboard(),
            ),
    );
  }

  Widget _buildErrorState() {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 120, 32, 32),
      children: [
        Icon(Icons.cloud_off_rounded, size: 64, color: p.textMuted),
        const SizedBox(height: 16),
        Text("Couldn't load the leaderboard", style: t.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Check your connection and try again.',
          textAlign: TextAlign.center,
          style: t.bodyMedium!.copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 24),
        Center(
          child: AppButton.secondary(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            expanded: false,
            onPressed: _loadLeaderboard,
          ),
        ),
      ],
    );
  }

  Widget _buildGlobalLeaderboard() {
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    if (_topPlayers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 120, 32, 32),
        children: [
          Icon(Icons.leaderboard, size: 64, color: p.textMuted),
          const SizedBox(height: 16),
          Text('No rankings yet', style: t.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Answer a question to join the board.',
            textAlign: TextAlign.center,
            style: t.bodyMedium!.copyWith(color: p.textMuted),
          ),
        ],
      );
    }

    final position = _userRank['position'] as int? ?? -1;
    final showOwnRow = position > _topPlayers.length;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _topPlayers.length + (showOwnRow ? 1 : 0),
      itemBuilder: (context, index) {
        // The user's own row at the bottom when they are outside the top list.
        if (index == _topPlayers.length) {
          return _buildPlayerCard(
            position: position,
            userName: 'You',
            totalXP: (_userRank['totalXP'] as num?)?.toInt() ?? 0,
            rank: _userRank['rank'] as String? ?? 'Unranked',
            isCurrentUser: true,
          );
        }

        final player = _topPlayers[index];
        final isMe = _userId.isNotEmpty && player['userId'] == _userId;
        return _buildPlayerCard(
          position: index + 1,
          userName: isMe ? '${player['userName'] ?? 'You'} (you)' : (player['userName'] ?? 'Unknown'),
          totalXP: (player['totalXP'] as num?)?.toInt() ?? 0,
          rank: player['rank'] as String? ?? 'Unranked',
          isCurrentUser: isMe,
        );
      },
    );
  }

  Widget _buildPlayerCard({
    required int position,
    required String userName,
    required int totalXP,
    required String rank,
    required bool isCurrentUser,
  }) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    // Top 3 get accent treatments: first place is the solid accent fill,
    // second and third use the soft accent tint.
    final Color badgeColor;
    final Color badgeTextColor;
    if (position == 1) {
      badgeColor = p.accent;
      badgeTextColor = p.onAccent;
    } else if (position <= 3) {
      badgeColor = p.accentSoft;
      badgeTextColor = p.accentText;
    } else {
      badgeColor = p.surfaceHigh;
      badgeTextColor = p.text;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        color: isCurrentUser ? p.accentSoft : null,
        borderColor: isCurrentUser ? p.accentText : null,
        child: Row(
          children: [
            // Rank Number
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$position',
                style: t.titleMedium!.copyWith(
                  fontWeight: FontWeight.w800,
                  color: badgeTextColor,
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Player Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(rank, style: t.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // XP
            Text(
              '$totalXP XP',
              style: t.titleMedium!.copyWith(
                fontWeight: FontWeight.w800,
                color: p.accentText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
