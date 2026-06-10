import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_bloc.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_event.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_state.dart';
import 'package:nubia_patient/presentation/features/financial/pages/deposit_payment_page.dart';

/// Page de signature Yousign.
///
/// Ouvre l'URL Yousign dans le navigateur externe et attend le deep-link
/// de retour `nubia://signature/callback`. Le [WedgeBloc] écoute
/// [WedgeSignatureCallbackReceived] pour confirmer la signature côté serveur.
///
/// Note : l'usage d'un navigateur externe (url_launcher) est cohérent avec
/// le [SignatureBloc] existant du projet.  L'intégration `InAppWebView` est
/// reportée à la milestone M5 prod (package non encore listé dans pubspec.yaml).
class SignatureWebViewPage extends StatefulWidget {
  const SignatureWebViewPage({
    super.key,
    required this.signatureUrl,
    required this.quoteId,
  });

  final String signatureUrl;
  final String quoteId;

  @override
  State<SignatureWebViewPage> createState() => _SignatureWebViewPageState();
}

class _SignatureWebViewPageState extends State<SignatureWebViewPage>
    with WidgetsBindingObserver {
  bool _browserOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openBrowser();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openBrowser() async {
    final uri = Uri.parse(widget.signatureUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted) {
      setState(() => _browserOpened = launched);
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("Impossible d'ouvrir le lien de signature."),
        ),
      );
    }
  }

  /// Appelé quand l'app reprend le focus (retour depuis le navigateur externe).
  /// À ce stade le deep-link `nubia://signature/callback` a déjà été traité par
  /// [DeepLinkService] → [WedgeBloc.add(WedgeSignatureCallbackReceived())].
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed && _browserOpened) {
      // Émet l'événement si le bloc est encore en SignatureInProgress
      // (le deep-link peut ne pas avoir été reçu sur iOS cold-start).
      final state = context.read<WedgeBloc>().state;
      if (state is WedgeSignatureInProgress) {
        context
            .read<WedgeBloc>()
            .add(const WedgeSignatureCallbackReceived());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WedgeBloc, WedgeState>(
      listenWhen: (_, next) =>
          next is WedgeSignatureDone || next is WedgeError,
      listener: (context, state) {
        if (state is WedgeSignatureDone) {
          // Remplace cette page par la page de paiement.
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => BlocProvider.value(
                value: context.read<WedgeBloc>(),
                child: DepositPaymentPage(quoteId: widget.quoteId),
              ),
            ),
          );
        }
        if (state is WedgeError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: const Text('Signature Yousign')),
          body: _SignatureWaitingBody(
            signatureUrl: widget.signatureUrl,
            onReopen: _openBrowser,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _SignatureWaitingBody extends StatelessWidget {
  const _SignatureWaitingBody({
    required this.signatureUrl,
    required this.onReopen,
  });

  final String signatureUrl;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.open_in_browser_rounded,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Signature en cours',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Le processus de signature s\'est ouvert dans votre navigateur. '
              'Revenez ici une fois la signature terminée.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              key: const Key('btn_reopen_signature'),
              onPressed: onReopen,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Rouvrir le lien'),
            ),
          ],
        ),
      ),
    );
  }
}
