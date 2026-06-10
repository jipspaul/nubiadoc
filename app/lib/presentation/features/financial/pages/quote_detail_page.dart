import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_bloc.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_event.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_state.dart';
import 'package:nubia_patient/presentation/features/financial/pages/signature_web_view_page.dart';
import 'package:nubia_patient/presentation/features/financial/widgets/quote_detail_header.dart';
import 'package:nubia_patient/presentation/features/financial/widgets/quote_line_item_tile.dart';
import 'package:nubia_patient/presentation/widgets/nubia_button.dart';

/// Page de détail d'un devis avec CTA « Signer le devis ».
///
/// Reçoit le [quoteId] depuis la route `/billing/quotes/:id/pay`.
/// Le [WedgeBloc] doit être injecté par l'appelant (cf. [AppRouter]).
class QuoteDetailPage extends StatefulWidget {
  const QuoteDetailPage({super.key, required this.quoteId});

  final String quoteId;

  @override
  State<QuoteDetailPage> createState() => _QuoteDetailPageState();
}

class _QuoteDetailPageState extends State<QuoteDetailPage> {
  // Idempotency-key fixée à la création de l'écran (une seule demande Yousign
  // même si l'utilisateur tape plusieurs fois sur le bouton avant le retour).
  late final String _signatureKey =
      '${widget.quoteId}-sig-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    context
        .read<WedgeBloc>()
        .add(WedgeQuoteLoadRequested(quoteId: widget.quoteId));
  }

  void _onSignTap(Quote quote) {
    context
        .read<WedgeBloc>()
        .add(WedgeSignatureRequested(idempotencyKey: _signatureKey));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WedgeBloc, WedgeState>(
      listenWhen: (_, next) =>
          next is WedgeSignatureInProgress ||
          next is WedgeQuoteExpired ||
          next is WedgeSignatureDone,
      listener: (context, state) {
        if (state is WedgeSignatureInProgress) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BlocProvider.value(
                value: context.read<WedgeBloc>(),
                child: SignatureWebViewPage(
                  signatureUrl: state.signatureUrl,
                  quoteId: state.quote.id,
                ),
              ),
            ),
          );
        }
        if (state is WedgeQuoteExpired) {
          _showExpiredDialog(context);
        }
      },
      builder: (context, state) {
        if (state is WedgeLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is WedgeError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Détail du devis')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  state.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          );
        }
        if (state is WedgeQuoteExpired) {
          return Scaffold(
            appBar: AppBar(title: const Text('Détail du devis')),
            body: const _ExpiredBody(),
          );
        }
        final Quote quote;
        if (state is WedgeQuoteLoaded) {
          quote = state.quote;
        } else if (state is WedgeSignatureInProgress) {
          quote = state.quote;
        } else if (state is WedgeSignatureDone) {
          quote = state.quote;
        } else {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final bool ctaEnabled = quote.canSign &&
            state is WedgeQuoteLoaded;

        return Scaffold(
          appBar: AppBar(title: const Text('Détail du devis')),
          body: _QuoteDetailBody(
            quote: quote,
            ctaEnabled: ctaEnabled,
            onSignTap: ctaEnabled ? () => _onSignTap(quote) : null,
          ),
        );
      },
    );
  }

  void _showExpiredDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Devis expiré'),
        content: const Text(
          'Ce devis n\'est plus valide. Contactez votre praticien pour en obtenir un nouveau.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context
                  .read<WedgeBloc>()
                  .add(const WedgeNewQuoteRequested());
            },
            child: const Text('Demander un nouveau devis'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _QuoteDetailBody extends StatelessWidget {
  const _QuoteDetailBody({
    required this.quote,
    required this.ctaEnabled,
    required this.onSignTap,
  });

  final Quote quote;
  final bool ctaEnabled;
  final VoidCallback? onSignTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                QuoteDetailHeader(quote: quote),
                const SizedBox(height: 24),
                Text(
                  'Détail des actes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ...quote.items.map(
                  (item) => QuoteLineItemTile(item: item),
                ),
              ],
            ),
          ),
        ),
        _QuoteDetailFooter(
          quote: quote,
          ctaEnabled: ctaEnabled,
          onSignTap: onSignTap,
        ),
      ],
    );
  }
}

class _QuoteDetailFooter extends StatelessWidget {
  const _QuoteDetailFooter({
    required this.quote,
    required this.ctaEnabled,
    required this.onSignTap,
  });

  final Quote quote;
  final bool ctaEnabled;
  final VoidCallback? onSignTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: NubiaButton(
            key: const Key('btn_sign_quote'),
            label: 'Signer le devis',
            size: NubiaButtonSize.lg,
            onPressed: onSignTap,
          ),
        ),
      ),
    );
  }
}

class _ExpiredBody extends StatelessWidget {
  const _ExpiredBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Devis expiré',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Ce devis n\'est plus valide. Contactez votre praticien pour en obtenir un nouveau.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
