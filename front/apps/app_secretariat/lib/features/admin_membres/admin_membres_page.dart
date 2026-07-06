import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'admin_membres_bloc.dart';
import 'admin_membres_event.dart';
import 'admin_membres_state.dart';
import 'invite_member_dialog.dart';

class AdminMembresPage extends StatefulWidget {
  const AdminMembresPage({super.key});

  @override
  State<AdminMembresPage> createState() => _AdminMembresPageState();
}

class _AdminMembresPageState extends State<AdminMembresPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    context.read<AdminMembresBloc>().add(const AdminMembresLoadRequested());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // L'invitation (POST /members) est réservée aux admins. En cas de 403,
    // on masque le FAB pour ne pas proposer une action interdite (cul-de-sac).
    final canInvite =
        context.watch<AdminMembresBloc>().state is! AdminMembresForbidden;
    return Scaffold(
      key: const Key('admin_membres_scaffold'),
      appBar: AppBar(
        title: const Text('Membres & Secrétariats'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<AdminMembresBloc>()
                .add(const AdminMembresLoadRequested()),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Membres'),
            Tab(text: 'Secrétariats'),
          ],
        ),
      ),
      floatingActionButton: canInvite
          ? FloatingActionButton.extended(
              key: const Key('add_member_fab'),
              onPressed: () async {
                final bloc = context.read<AdminMembresBloc>();
                final result =
                    await showDialog<({String email, MemberRole role})>(
                  context: context,
                  builder: (_) => const InviteMemberDialog(),
                );
                if (result != null) {
                  bloc.add(
                    AdminMembresInviteRequested(
                      email: result.email,
                      role: result.role,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Ajouter membre'),
            )
          : null,
      body: BlocListener<AdminMembresBloc, AdminMembresState>(
        listenWhen: (_, state) => state is AdminMembresInviteSuccess,
        listener: (context, _) => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation envoyée.')),
        ),
        child: BlocBuilder<AdminMembresBloc, AdminMembresState>(
          buildWhen: (_, state) => state is! AdminMembresInviteSuccess,
          builder: (context, state) => switch (state) {
            AdminMembresInitial() ||
            AdminMembresLoading() ||
            AdminMembresInviteSuccess() =>
              const Center(
                child: CircularProgressIndicator(),
              ),
            AdminMembresEmpty() => const NubiaEmptyState(
                key: Key('admin_membres_empty'),
                icon: Icons.group_outlined,
                title: 'Aucun membre ni secrétariat enregistré.',
              ),
            AdminMembresLoaded(:final members, :final secretariats) =>
              TabBarView(
                controller: _tabController,
                children: [
                  _MembersList(members: members),
                  _SecretariatsList(secretariats: secretariats),
                ],
              ),
            AdminMembresForbidden(:final message) => NubiaEmptyState(
                key: const Key('admin_membres_forbidden'),
                icon: Icons.lock_outline,
                title: 'Accès réservé aux administrateurs',
                subtitle: message,
              ),
            AdminMembresError(:final message) => NubiaErrorWidget(
                message: message,
                onRetry: () => context
                    .read<AdminMembresBloc>()
                    .add(const AdminMembresLoadRequested()),
              ),
          },
        ),
      ),
    );
  }
}

class _MembersList extends StatelessWidget {
  const _MembersList({required this.members});

  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const NubiaEmptyState(
        icon: Icons.person_outline,
        title: 'Aucun membre enregistré.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: members.length,
      itemBuilder: (_, i) => _MemberTile(member: members[i]),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final Member member;

  static String _roleLabel(MemberRole role) {
    switch (role) {
      case MemberRole.practitioner:
        return 'Praticien';
      case MemberRole.assistant:
        return 'Assistant';
      case MemberRole.secretary:
        return 'Secrétaire';
      case MemberRole.admin:
        return 'Admin';
    }
  }

  static NubiaBadgeVariant _roleVariant(MemberRole role) =>
      role == MemberRole.admin
          ? NubiaBadgeVariant.warning
          : NubiaBadgeVariant.neutral;

  static String _initials(String first, String last) {
    final f = first.trim().isNotEmpty ? first.trim()[0] : '';
    final l = last.trim().isNotEmpty ? last.trim()[0] : '';
    final res = '$f$l'.toUpperCase();
    return res.isNotEmpty ? res : '?';
  }

  @override
  Widget build(BuildContext context) {
    return ListRow(
      leading: NubiaAvatar(
        initials: _initials(member.firstName, member.lastName),
      ),
      title: member.fullName,
      subtitle: member.email,
      trailing: NubiaBadge.label(
        label: _roleLabel(member.role),
        variant: _roleVariant(member.role),
      ),
    );
  }
}

class _SecretariatsList extends StatelessWidget {
  const _SecretariatsList({required this.secretariats});

  final List<Secretariat> secretariats;

  @override
  Widget build(BuildContext context) {
    if (secretariats.isEmpty) {
      return const NubiaEmptyState(
        icon: Icons.business_outlined,
        title: 'Aucun secrétariat enregistré.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: secretariats.length,
      itemBuilder: (_, i) => _SecretariatTile(secretariat: secretariats[i]),
    );
  }
}

class _SecretariatTile extends StatelessWidget {
  const _SecretariatTile({required this.secretariat});

  final Secretariat secretariat;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListRow(
      leading: CircleAvatar(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        child: const Icon(Icons.business_outlined, size: 20),
      ),
      title: secretariat.name,
      subtitle: secretariat.email,
    );
  }
}
