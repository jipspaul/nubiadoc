import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'admin_secretariats_bloc.dart';
import 'admin_secretariats_event.dart';
import 'admin_secretariats_state.dart';

/// Body-only content for the secrétariats admin list. Can be embedded in any
/// layout that provides [AdminSecretiariatsBloc] via [BlocProvider] (e.g.
/// [ProShell] bodyBuilder or the full-page [AdminSecretiariatsPage]).
class AdminSecretiariatsBody extends StatefulWidget {
  const AdminSecretiariatsBody({super.key});

  @override
  State<AdminSecretiariatsBody> createState() => _AdminSecretiariatsBodyState();
}

class _AdminSecretiariatsBodyState extends State<AdminSecretiariatsBody> {
  Completer<void>? _refreshCompleter;

  @override
  void initState() {
    super.initState();
    context
        .read<AdminSecretiariatsBloc>()
        .add(const AdminSecretiariatsLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AdminSecretiariatsBloc, AdminSecretiariatsState>(
      listener: (context, state) {
        if (state is AdminSecretiariatsLoaded ||
            state is AdminSecretiariatsEmpty ||
            state is AdminSecretiariatsError) {
          _refreshCompleter?.complete();
          _refreshCompleter = null;
        }
      },
      builder: (context, state) => switch (state) {
        AdminSecretiariatsInitial() ||
        AdminSecretiariatsLoading() =>
          const Center(child: CircularProgressIndicator()),
        AdminSecretiariatsEmpty() => const NubiaEmptyState(
            key: Key('admin_secretariats_empty'),
            icon: Icons.business_outlined,
            title: 'Aucun secrétariat enregistré.',
          ),
        AdminSecretiariatsLoaded(:final secretariats) => _SecretariatsList(
            secretariats: secretariats,
            onRefresh: () {
              _refreshCompleter = Completer<void>();
              context
                  .read<AdminSecretiariatsBloc>()
                  .add(const AdminSecretiariatsLoadRequested());
              return _refreshCompleter!.future;
            },
          ),
        AdminSecretiariatsError(:final message) => NubiaErrorWidget(
            message: message,
            onRetry: () => context
                .read<AdminSecretiariatsBloc>()
                .add(const AdminSecretiariatsLoadRequested()),
          ),
      },
    );
  }
}

class AdminSecretiariatsPage extends StatelessWidget {
  const AdminSecretiariatsPage({super.key});

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
                .read<AdminSecretiariatsBloc>()
                .add(const AdminSecretiariatsLoadRequested()),
          ),
        ],
      ),
      body: const AdminSecretiariatsBody(),
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

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.business_outlined),
      title: Text(secretariat.name),
      subtitle: Text(secretariat.email),
      trailing: secretariat.isActive
          ? const Icon(Icons.check_circle_outline, color: Colors.green)
          : const Icon(Icons.cancel_outlined, color: Colors.grey),
    );
  }
}
