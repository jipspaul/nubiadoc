import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../session/auth_cubit.dart';
import 'profile_bloc.dart';
import 'profile_event.dart';
import 'profile_state.dart';

/// Profile body — must be placed inside a [BlocProvider<ProfileBloc>].
///
/// Displays account header, personal info, and navigation tiles for
/// coverage, dependents, consents, and notification preferences.
///
/// The caller is responsible for adding [ProfileLoadRequested] to the bloc
/// (typically via `..add(const ProfileLoadRequested())` in the BlocProvider's
/// `create` callback).
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        if (state is ProfileInitial || state is ProfileLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is ProfileError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.message),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () =>
                      context.read<ProfileBloc>().add(const ProfileLoadRequested()),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          );
        }
        if (state is ProfileLoaded) {
          return _ProfileContent(account: state.account);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.account});

  final PatientAccount account;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('profile_content'),
      children: [
        _ProfileHeader(account: account),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Informations personnelles',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        _InfoRow(label: 'Email', value: account.email),
        if (account.phone != null && account.phone!.isNotEmpty)
          _InfoRow(label: 'Téléphone', value: account.phone!),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Mon compte',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        _SectionTile(
          key: const Key('tile_coverage'),
          icon: Icons.health_and_safety_outlined,
          title: 'Couverture santé',
        ),
        _SectionTile(
          key: const Key('tile_dependents'),
          icon: Icons.people_outline,
          title: 'Mes proches',
        ),
        _SectionTile(
          key: const Key('tile_consents'),
          icon: Icons.verified_user_outlined,
          title: 'Consentements',
        ),
        _SectionTile(
          key: const Key('tile_notifications'),
          icon: Icons.notifications_outlined,
          title: 'Préférences notifications',
        ),
        const Divider(),
        _LogoutTile(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.account});

  final PatientAccount account;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              _initials(account),
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  account.email,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(PatientAccount account) {
    final first =
        account.firstName.isNotEmpty ? account.firstName[0].toUpperCase() : '';
    final last =
        account.lastName.isNotEmpty ? account.lastName[0].toUpperCase() : '';
    return '$first$last';
  }
}

// ---------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    super.key,
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

// ---------------------------------------------------------------------------

class _LogoutTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const Key('logout_tile'),
      leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
      title: Text(
        'Se déconnecter',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      onTap: () => context.read<AuthCubit>().signOut(),
    );
  }
}
