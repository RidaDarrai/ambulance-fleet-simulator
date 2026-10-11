import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/tokens.dart';
import '../widgets/atoms.dart';
import 'help_screen.dart';
import 'medical_profile_screen.dart';
import 'settings_screen.dart';
import 'sign_in_screen.dart';

/// Profile tab (IA §3.10): guest sign-in card OR medical summary + edit.
/// Settings moved here as a pushed screen (approved 3-tab shell).
class ProfileScreen extends StatelessWidget {
  final AppState state;
  const ProfileScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Profile')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...(state.isAuthenticated
                  ? _authenticated(context, theme)
                  : _guest(theme, context)),
              gapH(24),
              _navTile(
                context,
                theme,
                icon: Icons.help_outline_rounded,
                label: 'Help & FAQ',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => HelpScreen(state: state)),
                ),
              ),
              gapH(8),
              _navTile(
                context,
                theme,
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => SettingsScreen(state: state)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _guest(ThemeData theme, BuildContext context) => [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppColors.radiusLg),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 40),
              gapW(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("You're using the app as a guest",
                        style: theme.textTheme.headlineSmall),
                    Text(
                        'Sign in to attach your medical profile to requests automatically.',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        gapH(16),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SignInScreen(state: state)),
          ),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: const Text('Sign in'),
        ),
      ];

  List<Widget> _authenticated(BuildContext context, ThemeData theme) {
    final p = state.medicalProfile;
    return [
      Text('Medical profile', style: theme.textTheme.headlineMedium),
      gapH(2),
      Text('Shared only when you send a request',
          style: theme.textTheme.labelSmall),
      gapH(12),
      MedicalCard(profile: p),
      if (p.contacts.isNotEmpty) ...[
        gapH(12),
        _FieldList(
            'Contacts', p.contacts.map((c) => '${c.name} · ${c.phone}').toList()),
      ],
      if (p.conditions.isNotEmpty) ...[
        gapH(12),
        _FieldList('Conditions', p.conditions),
      ],
      gapH(24),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => MedicalProfileScreen(state: state)),
        ),
        icon: const Icon(Icons.edit_rounded, size: 18),
        label: const Text('Edit medical profile'),
      ),
      gapH(8),
      TextButton(
        onPressed: () {
          state.signOut();
        },
        child: const Text('Sign out'),
      ),
    ];
  }

  Widget _navTile(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusMd),
          ),
          leading: Icon(icon, size: 22),
          title: Text(label, style: theme.textTheme.bodyLarge),
          trailing: Icon(Icons.chevron_right,
              size: 22, color: theme.colorScheme.outline),
          onTap: onTap,
        ),
      );
}

class _FieldList extends StatelessWidget {
  final String title;
  final List<String> items;
  const _FieldList(this.title, this.items);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text(title, style: theme.textTheme.labelLarge)),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in items)
                Chip(
                  label: Text(item, style: theme.textTheme.bodySmall),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
            ],
          ),
        ),
      ],
    );
  }
}