// lib/presentation/widgets/nubia_text_field.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/nubia_colors.dart';

/// Variantes du [NubiaTextField].
enum NubiaTextFieldVariant {
  /// Bordure visible tout autour (Material OutlinedTextField).
  outlined,

  /// Fond rempli avec underline.
  filled,

  /// Champ de recherche avec icône loupe en prefix.
  search,

  /// Champ mot de passe avec bouton d'affichage/masquage.
  password,

  /// Champ multiligne (textarea) — `maxLines` est forcé à 4 si non précisé.
  multiline,

  /// Champ montant : suffixe `€`, clavier numérique, chiffres tabulaires.
  amount,

  /// Champ téléphone : icône préfixe + clavier téléphone.
  phone,

  /// Champ email : icône préfixe `mail` + clavier email.
  email,

  /// Champ avec widget suffixe personnalisé (ex. unité, bouton).
  withSuffix,

  /// Champ quantité : clavier numérique, pas à pas (+/-) et valeur
  /// plancher [NubiaTextField.min] — saisie non numérique impossible.
  numberStepper,
}

/// Champ texte Nubia : 10 variantes.
///
/// - [variant] : outlined / filled / search / password / multiline / amount /
///   phone / email / withSuffix / numberStepper.
/// - [controller] : contrôleur Flutter standard.
/// - [label] : libellé flottant.
/// - [hint] : texte placeholder.
/// - [errorText] : message d'erreur affiché sous le champ.
/// - [suffixWidget] : widget affiché à droite (variant `withSuffix` uniquement).
/// - [onChanged] : callback de changement de valeur.
/// - [onSubmitted] : callback à la validation clavier (Entrée en mono-ligne,
///   #4538 — un chat/composer doit pouvoir se soumettre ainsi, réflexe
///   universel). `null` par défaut : aucun changement de comportement pour
///   les champs existants qui ne le renseignent pas.
/// - [borderRadius] : rayon du contour (variantes `outlined`/`multiline`/
///   `email` uniquement, #4933). `null` par défaut : garde le rayon Material
///   par défaut pour les champs existants qui ne le renseignent pas.
/// - [min] : valeur plancher (variante `numberStepper` uniquement, #5177).
///   `1` par défaut. Le bouton `-` est désactivé et toute saisie/valeur
///   inférieure est ramenée à cette borne à la perte du focus.
class NubiaTextField extends StatefulWidget {
  const NubiaTextField({
    super.key,
    this.variant = NubiaTextFieldVariant.outlined,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.suffixWidget,
    this.onChanged,
    this.onSubmitted,
    this.maxLines,
    this.enabled = true,
    this.borderRadius,
    this.min = 1,
  });

  final NubiaTextFieldVariant variant;
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final Widget? suffixWidget;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? maxLines;
  final bool enabled;
  final double? borderRadius;
  final int min;

  @override
  State<NubiaTextField> createState() => _NubiaTextFieldState();
}

class _NubiaTextFieldState extends State<NubiaTextField> {
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    if (widget.variant == NubiaTextFieldVariant.numberStepper) {
      widget.controller?.addListener(_handleStepperControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleStepperControllerChanged);
    super.dispose();
  }

  void _handleStepperControllerChanged() => setState(() {});

  void _step(int delta) {
    final controller = widget.controller;
    if (controller == null) return;
    final current = int.tryParse(controller.text.trim()) ?? widget.min;
    final next = current + delta < widget.min ? widget.min : current + delta;
    controller.text = next.toString();
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    widget.onChanged?.call(controller.text);
  }

  void _clampToMinOnFocusLost(bool hasFocus) {
    if (hasFocus) return;
    final controller = widget.controller;
    if (controller == null) return;
    final value = int.tryParse(controller.text.trim());
    if (value == null || value < widget.min) {
      controller.text = widget.min.toString();
      widget.onChanged?.call(controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.variant) {
      case NubiaTextFieldVariant.outlined:
        return _buildTextField(decoration: _outlined(context));
      case NubiaTextFieldVariant.filled:
        return _buildTextField(decoration: _filled(context));
      case NubiaTextFieldVariant.search:
        return _buildTextField(decoration: _search(context));
      case NubiaTextFieldVariant.password:
        return _buildTextField(
          decoration: _password(context),
          obscureText: _obscure,
        );
      case NubiaTextFieldVariant.multiline:
        return _buildTextField(
          decoration: _outlined(context),
          maxLines: widget.maxLines ?? 4,
        );
      case NubiaTextFieldVariant.amount:
        return _buildTextField(
          decoration: _amount(context),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        );
      case NubiaTextFieldVariant.phone:
        return _buildTextField(
          decoration: _phone(context),
          keyboardType: TextInputType.phone,
        );
      case NubiaTextFieldVariant.email:
        return _buildTextField(
          decoration: _email(context),
          keyboardType: TextInputType.emailAddress,
        );
      case NubiaTextFieldVariant.withSuffix:
        return _buildTextField(decoration: _withSuffix(context));
      case NubiaTextFieldVariant.numberStepper:
        return _buildTextField(
          decoration: _numberStepper(context),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          onFocusChange: _clampToMinOnFocusLost,
        );
    }
  }

  Widget _buildTextField({
    required InputDecoration decoration,
    bool obscureText = false,
    int? maxLines,
    TextInputType? keyboardType,
    TextStyle? style,
    List<TextInputFormatter>? inputFormatters,
    TextAlign textAlign = TextAlign.start,
    ValueChanged<bool>? onFocusChange,
  }) {
    final field = TextField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      // Entrée envoie (au lieu d'ajouter une ligne) uniquement quand
      // [onSubmitted] est fourni — un textarea multiligne sans callback de
      // soumission garde son comportement Entrée = saut de ligne.
      textInputAction: widget.onSubmitted != null
          ? TextInputAction.send
          : null,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : (maxLines ?? 1),
      enabled: widget.enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textAlign: textAlign,
      style: style,
      decoration: decoration.copyWith(errorText: widget.errorText),
    );
    if (onFocusChange == null) return field;
    return Focus(onFocusChange: onFocusChange, child: field);
  }

  InputDecoration _base(BuildContext context) {
    return InputDecoration(labelText: widget.label, hintText: widget.hint);
  }

  InputDecoration _outlined(BuildContext context) {
    return _base(context).copyWith(
      border: OutlineInputBorder(
        borderRadius: widget.borderRadius != null
            ? BorderRadius.circular(widget.borderRadius!)
            : const BorderRadius.all(Radius.circular(4)),
      ),
    );
  }

  InputDecoration _filled(BuildContext context) {
    return _base(
      context,
    ).copyWith(filled: true, border: const UnderlineInputBorder());
  }

  InputDecoration _search(BuildContext context) {
    return _base(context).copyWith(
      prefixIcon: const Icon(Icons.search),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
    );
  }

  InputDecoration _password(BuildContext context) {
    return _base(context).copyWith(
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
        onPressed: () => setState(() => _obscure = !_obscure),
        tooltip:
            _obscure ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
      ),
    );
  }

  InputDecoration _amount(BuildContext context) {
    return _base(context).copyWith(
      border: const OutlineInputBorder(),
      suffixText: '€',
      suffixStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  InputDecoration _phone(BuildContext context) {
    return _base(context).copyWith(
      border: const OutlineInputBorder(),
      prefixIcon: const Icon(Icons.phone_outlined),
    );
  }

  InputDecoration _email(BuildContext context) {
    return _base(context).copyWith(
      prefixIcon: const Icon(Icons.mail, color: NubiaColors.n400),
      border: OutlineInputBorder(
        borderRadius: widget.borderRadius != null
            ? BorderRadius.circular(widget.borderRadius!)
            : const BorderRadius.all(Radius.circular(4)),
      ),
    );
  }

  InputDecoration _numberStepper(BuildContext context) {
    final current = int.tryParse(widget.controller?.text.trim() ?? '');
    final atMin = current != null && current <= widget.min;
    return _base(context).copyWith(
      border: const OutlineInputBorder(),
      prefixIcon: IconButton(
        icon: const Icon(Icons.remove),
        tooltip: 'Diminuer',
        onPressed: atMin ? null : () => _step(-1),
      ),
      suffixIcon: IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'Augmenter',
        onPressed: () => _step(1),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    );
  }

  InputDecoration _withSuffix(BuildContext context) {
    return _base(context).copyWith(
      border: const OutlineInputBorder(),
      suffixIcon: widget.suffixWidget != null
          ? Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: widget.suffixWidget,
            )
          : null,
      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    );
  }
}
