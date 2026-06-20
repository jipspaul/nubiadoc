import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
            return Center(
              child: Text(
                state.message,
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
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
      trailing: secretariat.isActive
          ? const Icon(Icons.check_circle_outline, color: Colors.green)
          : const Icon(Icons.cancel_outlined, color: Colors.grey),
    );
  }
}
