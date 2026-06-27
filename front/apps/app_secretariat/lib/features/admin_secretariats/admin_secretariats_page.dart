import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'admin_secretariats_bloc.dart';
import 'admin_secretariats_event.dart';
import 'admin_secretariats_state.dart';

class AdminSecretiariatsPage extends StatefulWidget {
  const AdminSecretiariatsPage({super.key});

  @override
  State<AdminSecretiariatsPage> createState() => _AdminSecretiariatsPageState();
}

class _AdminSecretiariatsPageState extends State<AdminSecretiariatsPage> {
  @override
  void initState() {
    super.initState();
    context
        .read<AdminSecretiariatsBloc>()
        .add(const AdminSecretiariatsLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      body: BlocBuilder<AdminSecretiariatsBloc, AdminSecretiariatsState>(
        builder: (context, state) {
          if (state is AdminSecretiariatsLoaded) {
            return _SecretariatsList(secretariats: state.secretariats);
          }
          if (state is AdminSecretiariatsError) {
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () => context
                  .read<AdminSecretiariatsBloc>()
                  .add(const AdminSecretiariatsLoadRequested()),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

class _SecretariatsList extends StatefulWidget {
  const _SecretariatsList({required this.secretariats});

  final List<Secretariat> secretariats;

  @override
  State<_SecretariatsList> createState() => _SecretariatsListState();
}

class _SecretariatsListState extends State<_SecretariatsList> {
  Completer<void>? _refreshCompleter;

  @override
  Widget build(BuildContext context) {
    if (widget.secretariats.isEmpty) {
      return const NubiaEmptyState(
        icon: Icons.business_outlined,
        title: 'Aucun secrétariat enregistré.',
      );
    }
    return BlocListener<AdminSecretiariatsBloc, AdminSecretiariatsState>(
      listenWhen: (_, s) =>
          s is AdminSecretiariatsLoaded || s is AdminSecretiariatsError,
      listener: (_, __) {
        _refreshCompleter?.complete();
        _refreshCompleter = null;
      },
      child: RefreshIndicator(
        key: const Key('admin_secretariats_refresh'),
        onRefresh: () {
          _refreshCompleter = Completer<void>();
          context
              .read<AdminSecretiariatsBloc>()
              .add(const AdminSecretiariatsLoadRequested());
          return _refreshCompleter!.future;
        },
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: widget.secretariats.length,
          itemBuilder: (_, i) =>
              _SecretariatTile(secretariat: widget.secretariats[i]),
        ),
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
