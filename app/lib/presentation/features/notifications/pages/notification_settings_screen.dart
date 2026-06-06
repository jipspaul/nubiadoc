import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_settings_cubit.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_settings_state.dart';
import 'package:nubia_patient/presentation/features/notifications/widgets/notification_settings_tile.dart';

/// Screen for managing notification opt-in preferences per category.
///
/// [NotificationSettingsCubit] must be provided above this widget
/// (typically by [AppRouter]).
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Préférences de notifications')),
      body: BlocBuilder<NotificationSettingsCubit, NotificationSettingsState>(
        builder: (context, state) {
          if (state is NotificationSettingsLoading ||
              state is NotificationSettingsInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is NotificationSettingsError) {
            return _NotificationSettingsError(message: state.message);
          }
          if (state is NotificationSettingsLoaded) {
            return _NotificationSettingsList(state: state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _NotificationSettingsList extends StatelessWidget {
  const _NotificationSettingsList({required this.state});

  final NotificationSettingsLoaded state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NotificationSettingsCubit>();
    final prefs = state.preferences;

    return ListView(
      children: [
        const _SectionHeader(title: 'Canaux'),
        NotificationSettingsTile(
          icon: Icons.calendar_today_outlined,
          label: 'Rendez-vous',
          subtitle: 'Rappels, modifications, annulations.',
          value: prefs.appointments,
          onChanged: (v) => cubit.toggle(appointments: v),
        ),
        NotificationSettingsTile(
          icon: Icons.folder_outlined,
          label: 'Documents',
          subtitle: 'Devis à signer, nouvelles ordonnances.',
          value: prefs.documents,
          onChanged: (v) => cubit.toggle(documents: v),
        ),
        NotificationSettingsTile(
          icon: Icons.chat_bubble_outline,
          label: 'Messages',
          subtitle: 'Nouveaux messages de votre cabinet.',
          value: prefs.messages,
          onChanged: (v) => cubit.toggle(messages: v),
        ),
        NotificationSettingsTile(
          icon: Icons.receipt_outlined,
          label: 'Paiements',
          subtitle: 'Factures, acomptes, rappels de règlement.',
          value: prefs.payments,
          onChanged: (v) => cubit.toggle(payments: v),
        ),
        NotificationSettingsTile(
          icon: Icons.health_and_safety_outlined,
          label: 'Prévention',
          subtitle: 'Rappels de contrôle annuel, détartrage.',
          value: prefs.prevention,
          onChanged: (v) => cubit.toggle(prevention: v),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _NotificationSettingsError extends StatelessWidget {
  const _NotificationSettingsError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () =>
                context.read<NotificationSettingsCubit>().load(),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
