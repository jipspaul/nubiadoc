import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_bloc.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_state.dart';

/// Lists the patient's dependents (ayants droit).
///
/// Reads [ProfileBloc] from context — must be within a [BlocProvider<ProfileBloc>].
class DependentsScreen extends StatelessWidget {
  const DependentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes proches')),
      body: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, state) {
          if (state is ProfileLoading || state is ProfileInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ProfileError) {
            return Center(child: Text(state.message));
          }
          if (state is ProfileLoaded) {
            return _DependentsContent(dependentIds: state.account.dependentIds);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DependentsContent extends StatelessWidget {
  const _DependentsContent({required this.dependentIds});

  final List<String> dependentIds;

  @override
  Widget build(BuildContext context) {
    if (dependentIds.isEmpty) {
      return _EmptyDependents();
    }
    return ListView.separated(
      itemCount: dependentIds.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => ListTile(
        leading: Icon(
          Icons.person_outline,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text('Ayant droit ${index + 1}'),
        subtitle: Text(dependentIds[index]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EmptyDependents extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun proche renseigné',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
