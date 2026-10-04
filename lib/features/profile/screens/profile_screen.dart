import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/app_review_service.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../auth/providers/auth_provider.dart';
import '../../feed/services/streak_service.dart';
import '../../feed/services/xp_service.dart';

/// Profile: who you are, your streak and level, appearance, and the
/// handful of settings that actually do something.
class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String _userName = 'Practice Champ';
  String _userEmail = 'user@quirzy.com';
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final name = await _storage.read(key: 'user_name');
      final email = await _storage.read(key: 'user_email');
      final photoUrl = await _storage.read(key: 'user_photo_url');
      if (!mounted) return;
      setState(() {
        _userName = name?.isNotEmpty == true ? name! : 'Practice Champ';
        _userEmail = email?.isNotEmpty == true ? email! : 'user@quirzy.com';
        _photoUrl = photoUrl;
      });
    } catch (_) {
      // Keep the defaults if secure storage is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final streak = ref.watch(streakProvider).value ?? StreakInfo.none;
    final level = XpLevel.fromTotal(ref.watch(xpTotalProvider).value ?? 0);
    final totalXp = ref.watch(xpTotalProvider).value ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text('Profile', style: text.headlineMedium),
            const SizedBox(height: 20),
            _ProfileHeader(name: _userName, email: _userEmail, photoUrl: _photoUrl),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.local_fire_department_rounded,
                    iconColor: streak.current > 0 ? p.streak : p.textMuted,
                    label: 'STREAK',
                    value: '${streak.current}',
                    unit: streak.current == 1 ? 'day' : 'days',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.bolt_rounded,
                    iconColor: p.accentText,
                    label: 'LEVEL ${level.level}',
                    value: '$totalXp',
                    unit: 'XP',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _GroupTitle('Appearance'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: text.titleSmall),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, label: Text('System')),
                        ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                        ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (selection) {
                        HapticFeedback.selectionClick();
                        ref.read(settingsProvider.notifier).setThemeMode(selection.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _GroupTitle('Settings'),
            _SettingsGroup(
              children: [
                _SettingsRow(
                  icon: Icons.notifications_active_rounded,
                  title: 'Notifications',
                  subtitle: 'Revision reminders, streak alerts and more',
                  onTap: () => context.push(AppRoutes.notificationSettings),
                ),
                _SettingsRow(
                  icon: Icons.key_rounded,
                  title: 'API key',
                  subtitle: 'Use your own Gemini API key',
                  onTap: () => context.push(AppRoutes.apiKeySettings),
                ),
                _SettingsRow(
                  icon: Icons.star_outline_rounded,
                  title: 'Rate Quirzy',
                  subtitle: 'Enjoying the app? Tell us on the Play Store',
                  onTap: _rateApp,
                ),
              ],
            ),
            const SizedBox(height: 24),
            AppButton.secondary(
              label: 'Log out',
              icon: Icons.logout_rounded,
              onPressed: _showLogoutDialog,
            ),
            const SizedBox(height: 16),
            Center(child: Text('Quirzy 2.1.2', style: text.bodySmall)),
          ],
        ),
      ),
    );
  }

  Future<void> _rateApp() async {
    try {
      await AppReviewService.showReviewDialog(context);
    } catch (e) {
      try {
        final success = await AppReviewService().openStoreListing();
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to open Play Store')),
          );
        }
      } catch (e2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e2')));
        }
      }
    }
  }

  void _showLogoutDialog() {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out of your account?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              // Store references before the async gap.
              final navigator = Navigator.of(context);
              final router = GoRouter.of(context);

              navigator.pop(); // Close dialog
              await ref.read(authProvider.notifier).logout();
              router.go(AppRoutes.auth);
            },
            child: Text('Log out', style: TextStyle(color: context.palette.danger)),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String email;
  final String? photoUrl;

  const _ProfileHeader({required this.name, required this.email, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final firstName = name.split(' ').first;
    final initial = firstName.isEmpty ? 'Q' : firstName[0].toUpperCase();

    return Row(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: p.accent,
          foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl!),
          child: Text(initial, style: text.headlineMedium!.copyWith(color: p.onAccent)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(firstName, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.headlineSmall),
              const SizedBox(height: 2),
              Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String unit;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall!.copyWith(letterSpacing: 0.8, color: context.palette.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: text.headlineMedium),
              const SizedBox(width: 6),
              Text(unit, style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  final String title;

  const _GroupTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// A card holding several rows separated by hairlines.
class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 72, color: p.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
              child: Icon(icon, color: p.accentText, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall),
                  Text(subtitle, style: text.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}
