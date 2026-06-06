import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/core/router/route_names.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_bloc.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_event.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_bloc.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_event.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_state.dart';
import 'package:nubia_patient/presentation/features/profile/widgets/profile_menu_tile.dart';

/// Profile screen — provides [ProfileBloc] and displays user info + menu.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<ProfileBloc>()..add(const ProfileLoadRequested()),
      child: const _ProfileBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _ProfileBody extends StatelessWidget {
  const _ProfileBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, state) {
          if (state is ProfileLoading || state is ProfileInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ProfileError) {
            return Center(child: Text(state.message));
          }
          if (state is ProfileLoaded) {
            return _ProfileContent(account: state.account);
          }
          return const SizedBox.shrink();
        },
      ),
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
      children: [
        _ProfileHeader(account: account),
        const Divider(),
        _PersonalInfoSection(account: account),
        const Divider(),
        ProfileMenuTile(
          icon: Icons.health_and_safety_outlined,
          title: 'Couverture santé',
          onTap: () => context.push(RouteNames.profileHealthCoverage),
        ),
        ProfileMenuTile(
          icon: Icons.people_outline,
          title: 'Mes proches',
          onTap: () => context.push(RouteNames.profileDependents),
        ),
        ProfileMenuTile(
          icon: Icons.local_hospital_outlined,
          title: 'Infos cabinet',
          onTap: () => context.push(RouteNames.profileCabinetInfo),
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
    final first = account.firstName.isNotEmpty
        ? account.firstName[0].toUpperCase()
        : '';
    final last = account.lastName.isNotEmpty
        ? account.lastName[0].toUpperCase()
        : '';
    return '$first$last';
  }
}

// ---------------------------------------------------------------------------

class _PersonalInfoSection extends StatelessWidget {
  const _PersonalInfoSection({required this.account});

  final PatientAccount account;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
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
        ],
      ),
    );
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
      padding: const EdgeInsets.symmetric(vertical: 6),
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

class _LogoutTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.logout,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(
        'Se déconnecter',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      onTap: () => context.read<AuthBloc>().add(const AuthLogoutRequested()),
    );
  }
}
