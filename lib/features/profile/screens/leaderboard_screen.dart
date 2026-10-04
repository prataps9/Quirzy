import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../shared/appwrite/leaderboard/leaderboard_service.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Leaderboard Screen - Global rankings and competition
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> with SingleTickerProviderStateMixin {
  final _leaderboardService = LeaderboardService();
  final _storage = const FlutterSecureStorage();
  
  List<Map<String, dynamic>> _topPlayers = [];
  Map<String, dynamic> _userRank = {};
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _isLoading = true);

    try {
      final topPlayers = await _leaderboardService.getTopPlayers(limit: 50);
      final userId = await _storage.read(key: 'user_id') ?? '';
      final userRank = userId.isNotEmpty
          ? await _leaderboardService.getUserRank(userId: userId)
          : <String, dynamic>{};

      if (mounted) {
        setState(() {
          _topPlayers = topPlayers;
          _userRank = Map<String, dynamic>.from(userRank);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: p.border),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                labelColor: p.onAccent,
                unselectedLabelColor: p.textMuted,
                labelStyle: t.labelLarge,
                unselectedLabelStyle: t.labelLarge,
                tabs: const [
                  Tab(height: 38, child: _TabLabel(Icons.public, 'Global')),
                  Tab(height: 38, child: _TabLabel(Icons.people, 'Friends')),
                ],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLeaderboard,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildGlobalLeaderboard(),
                _buildFriendsLeaderboard(),
              ],
            ),
    );
  }

  Widget _buildGlobalLeaderboard() {
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    if (_topPlayers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.leaderboard, size: 64, color: p.textMuted),
            const SizedBox(height: 16),
            Text('No rankings yet', style: t.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Start practicing to climb the leaderboard!',
              style: t.bodyMedium!.copyWith(color: p.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _topPlayers.length + (_userRank.isNotEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        // Show user's rank at the bottom if not in top list
        if (index == _topPlayers.length) {
          final position = _userRank['position'] as int? ?? -1;
          if (position > _topPlayers.length) {
            return _buildPlayerCard(
              position: position,
              userName: 'You',
              totalXP: _userRank['totalXP'] as int? ?? 0,
              rank: _userRank['rank'] as String? ?? 'Unranked',
              isCurrentUser: true,
            );
          }
          return const SizedBox.shrink();
        }

        final player = _topPlayers[index];
        return _buildPlayerCard(
          position: index + 1,
          userName: player['userName'] ?? 'Unknown',
          totalXP: player['totalXP'] as int? ?? 0,
          rank: player['rank'] as String? ?? 'Unranked',
          isCurrentUser: false,
        ).animate().fadeIn(duration: 200.ms);
      },
    );
  }

  Widget _buildFriendsLeaderboard() {
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: p.textMuted),
          const SizedBox(height: 16),
          Text('Friends Coming Soon!', style: t.titleLarge),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Add friends to compete with them!',
              textAlign: TextAlign.center,
              style: t.bodyMedium!.copyWith(color: p.textMuted),
            ),
          ),
        ],
      ),
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

class _TabLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TabLabel(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
