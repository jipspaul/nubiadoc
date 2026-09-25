import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:share_plus/share_plus.dart';

/// Bouton « Ma carte de visite » du dashboard praticien (DP-F26.a, #7146) :
/// récupère la vCard du cabinet (`GET /v1/cabinet/vcard`) et le QR associé
/// (`GET /v1/cabinet/vcard/qr.png`) puis les partage/envoie au patient — même
/// pattern que `cabinet_brief_page.dart`/`patient_fiche.dart`/
/// `sterilization_scan_page.dart` (#4983) : feuille de partage système
/// partout, sauf desktop natif (Windows/Linux/macOS) où `Share.shareXFiles`
/// n'est pas cohérent → enregistrement classique via [FilePickerService]
/// (uniquement la vCard dans ce cas, le QR étant redondant hors partage).
class CabinetVcardButton extends StatefulWidget {
  const CabinetVcardButton({super.key});

  @override
  State<CabinetVcardButton> createState() => _CabinetVcardButtonState();
}

class _CabinetVcardButtonState extends State<CabinetVcardButton> {
  bool _loading = false;

  Future<void> _shareVcard() async {
    if (_loading) return;
    setState(() => _loading = true);

    final vcardResult = await GetIt.instance<GetCabinetVcardUseCase>()();
    if (!mounted) return;

    await vcardResult.fold(
      (failure) async {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      },
      (vcardBytes) async {
        final qrResult = await GetIt.instance<GetCabinetVcardQrPngUseCase>()();
        if (!mounted) return;
        setState(() => _loading = false);
        final qrBytes = qrResult.fold((_) => null, (bytes) => bytes);
        await _share(vcardBytes, qrBytes);
      },
    );
  }

  Future<void> _share(List<int> vcardBytes, List<int>? qrBytes) async {
    final vcardData = Uint8List.fromList(vcardBytes);
    if (_isDesktopPlatform) {
      await GetIt.instance<FilePickerService>().saveFile(
        bytes: vcardData,
        fileName: 'cabinet.vcf',
      );
      return;
    }
    await Share.shareXFiles(
      [
        XFile.fromData(vcardData, name: 'cabinet.vcf', mimeType: 'text/vcard'),
        if (qrBytes != null)
          XFile.fromData(
            Uint8List.fromList(qrBytes),
            name: 'cabinet-qr.png',
            mimeType: 'image/png',
          ),
      ],
      subject: 'Carte de visite du cabinet',
    );
  }

  @override
  Widget build(BuildContext context) {
    return NubiaButton(
      key: const Key('dashboard_vcard_button'),
      label: 'Ma carte de visite',
      variant: NubiaButtonVariant.secondary,
      size: NubiaButtonSize.sm,
      icon: Icons.badge_outlined,
      isLoading: _loading,
      onPressed: _loading ? null : _shareVcard,
    );
  }
}

/// Desktop natif (Windows/Linux/macOS) : `Share.shareXFiles` n'y est pas
/// cohérent (non implémenté sur Linux, feuille de partage système hors sujet
/// sans app tierce sur Windows/macOS) — même convention que
/// `patient_fiche.dart`/`cabinet_brief_page.dart`/`sterilization_scan_page.dart`.
bool get _isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);
