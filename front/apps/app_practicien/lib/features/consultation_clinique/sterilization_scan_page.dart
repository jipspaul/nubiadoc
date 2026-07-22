import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Écran de scan Datamatrix/code-barres d'une pochette stérilisée (#4139),
/// pour l'associer à l'acte en cours (le dernier acte ajouté à la
/// séance). Mirroir technique de
/// `app_pharmacie/features/pickup_scan/pickup_scan_page.dart` — même
/// package `mobile_scanner`, même fallback saisie manuelle (caméra non
/// supportée sur Windows/Linux, refusée, ou code illisible).
///
/// Le cycle de stérilisation associé n'est PAS choisi par l'utilisateur ici
/// (l'issue ne demande pas d'écran de sélection de cycle) : le plus récent
/// (`GET /v1/cabinet/sterilization-cycles`, trié `started_at DESC`) est
/// utilisé automatiquement. Limitation documentée, pas un oubli — un
/// sélecteur explicite serait un ajout de scope non demandé/non testé.
class SterilizationScanPage extends StatefulWidget {
  const SterilizationScanPage({super.key, required this.consultationActId});

  final String consultationActId;

  @override
  State<SterilizationScanPage> createState() => _SterilizationScanPageState();
}

class _SterilizationScanPageState extends State<SterilizationScanPage> {
  SterilizationCycle? _cycle;
  bool _loadingCycle = true;
  bool _submitting = false;
  String? _error;
  String? _successPouchId;

  @override
  void initState() {
    super.initState();
    _loadCycle();
  }

  Future<void> _loadCycle() async {
    final result = await GetIt.instance<ListSterilizationCyclesUseCase>()();
    if (!mounted) return;
    setState(() {
      _loadingCycle = false;
      _cycle = result.fold((_) => null, (cycles) => cycles.firstOrNull);
    });
  }

  Future<void> _submit(String rawCode) async {
    final code = rawCode.trim();
    final cycle = _cycle;
    if (code.isEmpty || cycle == null || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await GetIt.instance<AddSterilizedPouchUseCase>()(
      cycle.id,
      code: code,
      consultationActId: widget.consultationActId,
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _submitting = false;
        _error = failure.message;
      }),
      (pouchId) => setState(() {
        _submitting = false;
        _successPouchId = pouchId;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner une pochette stérilisée')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_successPouchId != null) {
      return _SuccessView(pouchId: _successPouchId!);
    }
    if (_loadingCycle) {
      return const Center(
        key: Key('sterilization_scan_loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_cycle == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aucun cycle de stérilisation enregistré.',
            key: Key('sterilization_scan_no_cycle'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_ScannerView.isSupported)
            _ScannerView(onCode: _submit)
          else
            const NubiaCard(
              child: Text(
                'Le scan caméra n\'est pas disponible sur cette '
                'plateforme — saisissez le code ci-dessous.',
              ),
            ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Text(
              _error!,
              key: const Key('sterilization_scan_error'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          _ManualCodeField(enabled: !_submitting, onSubmit: _submit),
          if (_submitting) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}

/// Vue caméra — SEUL widget de app_practicien qui importe mobile_scanner
/// (même convention que `QrScannerView` côté app_pharmacie).
class _ScannerView extends StatelessWidget {
  const _ScannerView({required this.onCode});

  final ValueChanged<String> onCode;

  static bool get isSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 280,
        child: MobileScanner(
          onDetect: (capture) {
            final value = capture.barcodes.firstOrNull?.rawValue;
            if (value != null && value.isNotEmpty) {
              onCode(value);
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Caméra indisponible — utilisez la saisie manuelle '
                'ci-dessous.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ManualCodeField extends StatefulWidget {
  const _ManualCodeField({required this.onSubmit, this.enabled = true});

  final ValueChanged<String> onSubmit;
  final bool enabled;

  @override
  State<_ManualCodeField> createState() => _ManualCodeFieldState();
}

class _ManualCodeFieldState extends State<_ManualCodeField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ou saisissez le code imprimé sous le Datamatrix :',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        NubiaTextField(
          key: const Key('sterilization_scan_manual_code_field'),
          controller: _controller,
          label: 'Code de la pochette',
        ),
        const SizedBox(height: 8),
        NubiaButton(
          key: const Key('sterilization_scan_manual_submit'),
          label: 'Valider le code',
          onPressed:
              widget.enabled ? () => widget.onSubmit(_controller.text) : null,
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.pouchId});

  final String pouchId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('sterilization_scan_success'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Pochette associée à l\'acte',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 24),
            NubiaButton(
              key: const Key('sterilization_scan_done'),
              label: 'Terminer',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
