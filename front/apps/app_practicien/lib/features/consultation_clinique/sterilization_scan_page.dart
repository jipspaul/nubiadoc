import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:share_plus/share_plus.dart';

/// Écran de scan Datamatrix/code-barres d'une pochette stérilisée (#4139),
/// pour l'associer à l'acte en cours (le dernier acte ajouté à la
/// séance), et impression/partage des étiquettes du cycle (#7180). Mirroir
/// technique de `app_pharmacie/features/pickup_scan/pickup_scan_page.dart`
/// — même scanner partagé ([NubiaQrScannerView]), même fallback saisie
/// manuelle (caméra non supportée sur Windows/Linux, refusée, ou code
/// illisible).
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
  bool _exportingPdf = false;
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

  /// Bouton « Imprimer les étiquettes » (#7180) — récupère la planche PDF du
  /// cycle courant (`GET .../labels.pdf`) puis la partage/imprime, même
  /// pattern que `cabinet_brief_page.dart`/`patient_fiche.dart` (#4983) :
  /// feuille de partage système partout, sauf desktop natif (Windows/Linux/
  /// macOS) où `Share.shareXFiles` n'est pas cohérent → enregistrement
  /// classique via [FilePickerService].
  Future<void> _printLabels() async {
    final cycle = _cycle;
    if (cycle == null || _exportingPdf) return;

    setState(() => _exportingPdf = true);
    final result = await GetIt.instance<GetSterilizationLabelsPdfUseCase>()(
      cycle.id,
    );
    if (!mounted) return;
    setState(() => _exportingPdf = false);

    final messenger = ScaffoldMessenger.of(context);
    await result.fold(
      (failure) async {
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      },
      (bytes) => _shareLabelsPdf(cycle, bytes),
    );
  }

  Future<void> _shareLabelsPdf(SterilizationCycle cycle, List<int> bytes) async {
    final filename =
        'etiquettes-sterilisation-${cycle.autoclaveRef}-${cycle.cycleNumber}.pdf';
    final data = Uint8List.fromList(bytes);
    if (_isDesktopPlatform) {
      await GetIt.instance<FilePickerService>()
          .saveFile(bytes: data, fileName: filename);
    } else {
      await Share.shareXFiles(
        [XFile.fromData(data, name: filename, mimeType: 'application/pdf')],
        subject: 'Étiquettes de stérilisation',
      );
    }
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
      appBar: AppBar(
        title: const Text('Scanner une pochette stérilisée'),
        actions: [
          if (_cycle != null)
            IconButton(
              key: const Key('sterilization_print_labels_button'),
              tooltip: 'Imprimer les étiquettes',
              icon: _exportingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_outlined),
              onPressed: _exportingPdf ? null : _printLabels,
            ),
        ],
      ),
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
          if (NubiaQrScannerView.isSupported)
            NubiaQrScannerView(onCode: _submit)
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

/// Desktop natif (Windows/Linux/macOS) : `Share.shareXFiles` (#4983) n'y
/// est pas cohérent (non implémenté sur Linux, feuille de partage système
/// hors sujet sans app tierce sur Windows/macOS) — un export y déclenche un
/// téléchargement/enregistrement classique à la place. Même convention que
/// `patient_fiche.dart`/`cabinet_brief_page.dart`.
bool get _isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);
