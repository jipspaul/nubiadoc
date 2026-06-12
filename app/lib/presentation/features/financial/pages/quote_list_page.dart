import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/core/router/route_names.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/quote_list_cubit.dart';
import 'package:nubia_patient/presentation/features/financial/widgets/quote_list_tile.dart';
import 'package:nubia_patient/presentation/widgets/nubia_empty_state.dart';

/// Page listant tous les devis du patient.
///
/// Fournit [QuoteListCubit] via [BlocProvider] et délègue le rendu à
/// [_QuoteListBody].
class QuoteListPage extends StatelessWidget {
  const QuoteListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<QuoteListCubit>()..load(),
      child: const _QuoteListBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _QuoteListBody extends StatelessWidget {
  const _QuoteListBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes devis')),
      body: BlocBuilder<QuoteListCubit, QuoteListState>(
        builder: (context, state) {
          if (state is QuoteListLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is QuoteListError) {
            return Center(child: Text(state.message));
          }
          if (state is QuoteListLoaded) {
            return _QuoteListContent(state: state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _QuoteListContent extends StatelessWidget {
  const _QuoteListContent({required this.state});

  final QuoteListLoaded state;

  @override
  Widget build(BuildContext context) {
    if (state.quotes.isEmpty) {
      return const NubiaEmptyState(
        message: 'Aucun devis pour le moment.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<QuoteListCubit>().load(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.quotes.length,
        itemBuilder: (context, index) {
          final quote = state.quotes[index];
          return QuoteListTile(
            quote: quote,
            onTap: () => context.push(
              RouteNames.paymentFlow.replaceFirst(':id', quote.id),
            ),
          );
        },
      ),
    );
  }
}
