import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/presentation/features/home/bloc/dashboard_bloc.dart';
import 'package:nubia_patient/presentation/features/home/widgets/dashboard_grid.dart';

/// Home dashboard screen.
///
/// Provides [DashboardBloc] via [BlocProvider] and delegates rendering to
/// [_HomeBody].
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<DashboardBloc>()..add(const DashboardLoadRequested()),
      child: const _HomeBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil'),
      ),
      body: BlocBuilder<DashboardBloc, DashboardState>(
        builder: (context, state) {
          if (state is DashboardLoading || state is DashboardInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DashboardError) {
            return Center(child: Text(state.message));
          }
          if (state is DashboardLoaded) {
            return SingleChildScrollView(
              child: DashboardGrid(summary: state.summary),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
