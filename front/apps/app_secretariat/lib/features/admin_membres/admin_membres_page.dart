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
    return Scaffold(
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
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add_member_fab'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const InviteMemberDialog(),
        ),
        icon: const Icon(Icons.person_add),
        label: const Text('Ajouter membre'),
      ),
      body: BlocBuilder<AdminMembresBloc, AdminMembresState>(
        builder: (context, state) {
          if (state is AdminMembresLoaded) {
            return TabBarView(
              controller: _tabController,
              children: [
                _MembersList(members: state.members),
                _SecretariatsList(secretariats: state.secretariats),
              ],
            );
          }
          if (state is AdminMembresError) {
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () => context
                  .read<AdminMembresBloc>()
                  .add(const AdminMembresLoadRequested()),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
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
      return const Center(child: Text('Aucun membre enregistré.'));
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

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.person_outline),
      title: Text(member.fullName),
      subtitle: Text(member.email),
      trailing: Text(
        member.role.name,
        style: Theme.of(context).textTheme.bodySmall,
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
      return const Center(child: Text('Aucun secrétariat enregistré.'));
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
    return ListTile(
      leading: const Icon(Icons.business_outlined),
      title: Text(secretariat.name),
      subtitle: Text(secretariat.email),
    );
  }
}
