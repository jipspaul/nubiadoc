import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'dependents_cubit.dart';

class DependentsPage extends StatelessWidget {
  const DependentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<DependentsCubit>()..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Mes proches')),
        body: const _DependentsBody(),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton.extended(
            key: const Key('add_dependent_fab'),
            onPressed: () => _openAddSheet(context),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Ajouter'),
          ),
        ),
      ),
    );
  }

  Future<void> _openAddSheet(BuildContext context) async {
    final cubit = context.read<DependentsCubit>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const _AddDependentSheet(),
      ),
    );
  }
}

class _DependentsBody extends StatelessWidget {
  const _DependentsBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DependentsCubit, DependentsState>(
      builder: (context, state) {
        if (state is DependentsLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is DependentsError) {
          return NubiaErrorWidget(
            message: state.message,
            onRetry: () => context.read<DependentsCubit>().load(),
          );
        }
        if (state is DependentsLoaded) {
          if (state.dependents.isEmpty) {
            return const NubiaEmptyState(
              key: Key('dependents_empty'),
              icon: Icons.people_outline,
              title: 'Aucun proche',
              subtitle: 'Ajoutez un enfant ou un proche que vous gérez.',
            );
          }
          return ListView.separated(
            key: const Key('dependents_list'),
            itemCount: state.dependents.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _DependentTile(
              dependent: state.dependents[i],
              disabled: state.mutating,
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _DependentTile extends StatelessWidget {
  const _DependentTile({required this.dependent, required this.disabled});
  final Dependent dependent;
  final bool disabled;

  String get _relationLabel {
    switch (dependent.relationship) {
      case DependentRelationship.enfant:
        return 'Enfant';
      case DependentRelationship.conjoint:
        return 'Conjoint';
      case DependentRelationship.autre:
        return 'Proche';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('dependent_${dependent.id}'),
      leading: const Icon(Icons.person_outline),
      title: Text('${dependent.firstName} ${dependent.lastName}'),
      subtitle: Text(_relationLabel),
      trailing: IconButton(
        key: Key('delete_dependent_${dependent.id}'),
        icon: const Icon(Icons.delete_outline),
        onPressed: disabled
            ? null
            : () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Retirer ce proche ?'),
                    content: Text(
                        '${dependent.firstName} ${dependent.lastName} ne sera plus rattaché à votre compte.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Retirer')),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  context.read<DependentsCubit>().remove(dependent.id);
                }
              },
      ),
    );
  }
}

class _AddDependentSheet extends StatefulWidget {
  const _AddDependentSheet();

  @override
  State<_AddDependentSheet> createState() => _AddDependentSheetState();
}

class _AddDependentSheetState extends State<_AddDependentSheet> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  DependentRelationship _relationship = DependentRelationship.enfant;

  bool get _valid =>
      _firstName.text.trim().isNotEmpty && _lastName.text.trim().isNotEmpty;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ajouter un proche',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          NubiaTextField(
            key: const Key('dependent_first_name'),
            controller: _firstName,
            label: 'Prénom',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          NubiaTextField(
            key: const Key('dependent_last_name'),
            controller: _lastName,
            label: 'Nom',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<DependentRelationship>(
            key: const Key('dependent_relationship'),
            initialValue: _relationship,
            decoration: const InputDecoration(
              labelText: 'Lien',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                  value: DependentRelationship.enfant, child: Text('Enfant')),
              DropdownMenuItem(
                  value: DependentRelationship.conjoint,
                  child: Text('Conjoint')),
              DropdownMenuItem(
                  value: DependentRelationship.autre, child: Text('Proche')),
            ],
            onChanged: (v) =>
                setState(() => _relationship = v ?? _relationship),
          ),
          const SizedBox(height: 24),
          NubiaButton(
            key: const Key('save_dependent_button'),
            label: 'Ajouter',
            onPressed: !_valid
                ? null
                : () {
                    context.read<DependentsCubit>().add(
                          firstName: _firstName.text.trim(),
                          lastName: _lastName.text.trim(),
                          relationship: _relationship,
                        );
                    Navigator.pop(context);
                  },
          ),
        ],
      ),
    );
  }
}
