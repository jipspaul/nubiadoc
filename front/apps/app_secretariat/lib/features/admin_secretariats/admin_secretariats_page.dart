import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'admin_secretariats_bloc.dart';
import 'admin_secretariats_event.dart';
import 'admin_secretariats_state.dart';
import 'invite_secretariat_dialog.dart';

/// Body-only content for the secrétariats admin list. Can be embedded in any
/// layout that provides [AdminSecretariatsBloc] via [BlocProvider] (e.g.
/// [ProShell] bodyBuilder or the full-page [AdminSecretariatsPage]).
class AdminSecretariatsBody extends StatefulWidget {
  const AdminSecretariatsBody({super.key});

  @override
  State<AdminSecretariatsBody> createState() => _AdminSecretariatsBodyState();
}

class _AdminSecretariatsBodyState extends State<AdminSecretariatsBody> {
  Completer<void>? _refreshCompleter;

  @override
  void initState() {
    super.initState();
    context
        .read<AdminSecretariatsBloc>()
        .add(const AdminSecretariatsLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AdminSecretariatsBloc, AdminSecretariatsState>(
      listener: (context, state) {
        if (state is AdminSecretariatsLoaded ||
            state is AdminSecretariatsEmpty ||
            state is AdminSecretariatsError) {
          _refreshCompleter?.complete();
          _refreshCompleter = null;
        }
        if (state is AdminSecretariatsInviteSent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invitation envoyée à ${state.email}.')),
          );
        }
        if (state is AdminSecretariatsInviteFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
          context
              .read<AdminSecretariatsBloc>()
              .add(const AdminSecretariatsLoadRequested());
        }
      },
      builder: (context, state) => switch (state) {
        AdminSecretariatsInitial() ||
        AdminSecretariatsLoading() ||
        AdminSecretariatsInviteSent() ||
        AdminSecretariatsInviteFailed() =>
          const _SecretariatsSkeleton(),
        AdminSecretariatsEmpty() => NubiaEmptyState(
            key: const Key('admin_secretariats_empty'),
            icon: Icons.business_outlined,
            title: 'Aucun secrétariat enregistré.',
            subtitle: 'Invitez un secrétariat pour déléguer la gestion '
                'administrative du cabinet.',
            action: NubiaButton(
              key: const Key('admin_secretariats_empty_cta'),
              label: 'Inviter un secrétariat',
              icon: Icons.add,
              onPressed: () => _openInviteDialog(context),
            ),
          ),
        AdminSecretariatsLoaded(:final secretariats) => _SecretariatsList(
            secretariats: secretariats,
            onRefresh: () {
              _refreshCompleter = Completer<void>();
              context
                  .read<AdminSecretariatsBloc>()
                  .add(const AdminSecretariatsLoadRequested());
              return _refreshCompleter!.future;
            },
          ),
        AdminSecretariatsError(:final message) => NubiaErrorWidget(
            message: message,
            onRetry: () => context
                .read<AdminSecretariatsBloc>()
                .add(const AdminSecretariatsLoadRequested()),
          ),
      },
    );
  }
}

/// Ouvre la modale d'invitation puis dispatche l'invitation réelle.
Future<void> _openInviteDialog(BuildContext context) async {
  final bloc = context.read<AdminSecretariatsBloc>();
  final result = await showDialog<({String name, String email})>(
    context: context,
    builder: (_) => const InviteSecretariatDialog(),
  );
  if (result != null) {
    bloc.add(AdminSecretariatsInviteRequested(
      name: result.name,
      email: result.email,
    ));
  }
}

class AdminSecretariatsPage extends StatelessWidget {
  const AdminSecretariatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('admin_secretariats_scaffold'),
      appBar: AppBar(
        title: const Text('Secrétariats'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<AdminSecretariatsBloc>()
                .add(const AdminSecretariatsLoadRequested()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('invite_secretariat_fab'),
        onPressed: () => _openInviteDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Inviter un secrétariat'),
      ),
      body: const AdminSecretariatsBody(),
    );
  }
}

class _SecretariatsList extends StatelessWidget {
  const _SecretariatsList({
    required this.secretariats,
    required this.onRefresh,
  });

  final List<Secretariat> secretariats;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      key: const Key('admin_secretariats_refresh'),
      onRefresh: onRefresh,
      child: ListView.builder(
        key: const Key('admin_secretariats_list'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: secretariats.length,
        itemBuilder: (_, i) => _SecretariatTile(secretariat: secretariats[i]),
      ),
    );
  }
}

class _SecretariatTile extends StatelessWidget {
  const _SecretariatTile({required this.secretariat});

  final Secretariat secretariat;

  static String _initials(String name) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = secretariat.phone != null && secretariat.phone!.isNotEmpty
        ? '${secretariat.email} · ${secretariat.phone}'
        : secretariat.email;

    return ListRow(
      key: Key('admin_secretariats_row_${secretariat.id}'),
      leading: NubiaAvatar(initials: _initials(secretariat.name)),
      title: secretariat.name,
      subtitle: subtitle,
      trailing: NubiaBadge.label(
        label: secretariat.isActive ? 'Actif' : 'Inactif',
        variant: secretariat.isActive
            ? NubiaBadgeVariant.success
            : NubiaBadgeVariant.neutral,
      ),
    );
  }
}

/// Skeleton de chargement : quelques lignes shimmer imitant la liste.
class _SecretariatsSkeleton extends StatelessWidget {
  const _SecretariatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('admin_secretariats_skeleton'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 5,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            NubiaSkeletonLoader(width: 40, height: 40, borderRadius: 999),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NubiaSkeletonLoader(width: 140, height: 14),
                  SizedBox(height: 8),
                  NubiaSkeletonLoader(width: 190, height: 12),
                ],
              ),
            ),
            SizedBox(width: 12),
            NubiaSkeletonLoader(width: 56, height: 22, borderRadius: 999),
          ],
        ),
      ),
    );
  }
}
