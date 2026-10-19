import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_constants.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/app_review_service.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_restart_scope.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/tab_header.dart';
import '../../auth/providers/auth_provider.dart';
import '../../feed/services/streak_service.dart';
import '../../feed/services/xp_service.dart';
import '../../subscription/services/usage_limits.dart';
import '../../subscription/widgets/limit_sheet.dart';
import 'privacy_policy_screen.dart';

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

  bool _loggingOut = false;
  bool _deleting = false;

  bool get _busy => _loggingOut || _deleting;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final user = ref.watch(authProvider).value;
    final pro = ref.watch(proStatusProvider);
    final streak = ref.watch(streakProvider).value ?? StreakInfo.none;
    final level = XpLevel.fromTotal(ref.watch(xpTotalProvider).value ?? 0);
    final totalXp = ref.watch(xpTotalProvider).value ?? 0;

    final name = user?.name.trim() ?? '';
    final email = user?.email.trim() ?? '';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const TabHeader(title: 'Profile', padding: EdgeInsets.zero),
            const SizedBox(height: 20),
            _ProfileHeader(
              name: name.isEmpty ? 'You' : name,
              email: email,
              photoUrl: user?.photoUrl,
            ),
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
            _SettingsGroup(
              children: [
                pro.isPro
                    ? _SettingsRow(
                        icon: Icons.workspace_premium_rounded,
                        title: 'Quirzy Pro',
                        subtitle: pro.expiresAt == null
                            ? 'Active'
                            : 'Active until ${DateFormat('d MMM yyyy').format(pro.expiresAt!)}',
                        onTap: () => openPaywall(context),
                      )
                    : _SettingsRow(
                        icon: Icons.workspace_premium_rounded,
                        title: 'Go Pro',
                        subtitle: 'Unlimited practice, flashcards and study sets',
                        onTap: () => openPaywall(context),
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
            _GroupTitle('Practice feed'),
            _SettingsGroup(
              children: [
                _SwitchRow(
                  icon: Icons.keyboard_double_arrow_up_rounded,
                  title: 'Auto-scroll',
                  subtitle: 'Move to the next card after a correct answer',
                  value: settings.autoAdvance,
                  onChanged: settings.setAutoAdvance,
                ),
                _SwitchRow(
                  icon: Icons.record_voice_over_rounded,
                  title: 'Read questions aloud',
                  subtitle: 'Uses your phone\'s text-to-speech voice',
                  value: settings.readAloud,
                  onChanged: settings.setReadAloud,
                ),
                _SwitchRow(
                  icon: Icons.music_note_rounded,
                  title: 'Sound effects',
                  subtitle: 'A short sound for right and wrong answers',
                  value: settings.soundEffects,
                  onChanged: settings.setSoundEffects,
                ),
              ],
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
                  icon: Icons.star_outline_rounded,
                  title: 'Rate Quirzy',
                  subtitle: 'Enjoying the app? Tell us on the Play Store',
                  onTap: _rateApp,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _GroupTitle('About'),
            _SettingsGroup(
              children: [
                _SettingsRow(
                  icon: Icons.shield_outlined,
                  title: 'Privacy policy',
                  subtitle: 'What we store and where',
                  onTap: () => _open(const PrivacyPolicyScreen()),
                ),
                _SettingsRow(
                  icon: Icons.description_outlined,
                  title: 'Terms of use',
                  subtitle: 'The rules for using Quirzy',
                  onTap: () => _open(const TermsScreen()),
                ),
                _SettingsRow(
                  icon: Icons.mail_outline_rounded,
                  title: 'Contact support',
                  subtitle: AppConstants.supportEmail,
                  onTap: _contactSupport,
                ),
              ],
            ),
            const SizedBox(height: 24),
            AppButton.secondary(
              label: 'Log out',
              icon: Icons.logout_rounded,
              loading: _loggingOut,
              onPressed: _busy ? null : _confirmLogout,
            ),
            const SizedBox(height: 12),
            _SettingsGroup(
              children: [
                _SettingsRow(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete account',
                  subtitle: 'Permanently close your Quirzy account',
                  danger: true,
                  loading: _deleting,
                  onTap: _busy ? null : _confirmDeleteAccount,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(child: Text('Quirzy 2.1.2', style: text.bodySmall)),
          ],
        ),
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _rateApp() async {
    try {
      await AppReviewService.rate();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open the Play Store")),
      );
    }
  }

  Future<void> _contactSupport() async {
    final uri = Uri.parse(
      'mailto:${AppConstants.supportEmail}?subject=${Uri.encodeComponent('Quirzy support')}',
    );
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app found. Write to ${AppConstants.supportEmail}')),
      );
    }
  }

  Future<void> _confirmLogout() async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Your practice progress, XP, streak and settings on this phone will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Log out', style: TextStyle(color: context.palette.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Grab everything that needs this widget before the async gap: once auth
    // flips to signed-out the router leaves this screen and disposes it.
    final router = GoRouter.of(context);
    final auth = ref.read(authProvider.notifier);
    setState(() => _loggingOut = true);
    await auth.logout();
    _restartSignedOut(router);
  }

  Future<void> _confirmDeleteAccount() async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This deletes your Quirzy profile and closes your account, so you '
          "won't be able to sign in with it again. Your practice progress, XP, "
          'streak and settings on this phone are erased too.\n\n'
          "This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Delete', style: TextStyle(color: context.palette.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final auth = ref.read(authProvider.notifier);
    setState(() => _deleting = true);
    try {
      await auth.deleteAccount();
    } catch (e) {
      debugPrint('Profile: delete account failed: $e');
      if (mounted) setState(() => _deleting = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't delete your account. Check your connection and try again."),
        ),
      );
      return;
    }
    _restartSignedOut(router);
  }

  /// Sends the user to sign-in and rebuilds every provider from scratch so
  /// nothing from the old account stays in memory. Uses the router's own
  /// navigator context, which outlives this (by now possibly disposed) screen.
  static void _restartSignedOut(GoRouter router) {
    router.go(AppRoutes.auth);
    final rootContext = router.routerDelegate.navigatorKey.currentContext;
    if (rootContext != null && rootContext.mounted) {
      AppRestartScope.restart(rootContext);
    }
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
              if (email.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
              ],
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
  final VoidCallback? onTap;
  final bool danger;
  final bool loading;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final tint = danger ? p.danger : p.accentText;
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: danger ? p.dangerSoft : p.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: tint, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: danger ? text.titleSmall!.copyWith(color: p.danger) : text.titleSmall),
                  Text(subtitle, style: text.bodySmall),
                ],
              ),
            ),
            if (loading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: tint),
              )
            else
              Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
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
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
