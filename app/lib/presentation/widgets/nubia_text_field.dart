// lib/presentation/widgets/nubia_text_field.dart
import 'package:flutter/material.dart';

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

  /// Champ avec widget suffixe personnalisé (ex. unité, bouton).
  withSuffix,
}

/// Champ texte Nubia : 6 variantes.
///
/// - [variant] : outlined / filled / search / password / multiline / withSuffix.
/// - [controller] : contrôleur Flutter standard.
/// - [label] : libellé flottant.
/// - [hint] : texte placeholder.
/// - [errorText] : message d'erreur affiché sous le champ.
/// - [suffixWidget] : widget affiché à droite (variant `withSuffix` uniquement).
/// - [onChanged] : callback de changement de valeur.
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
    this.maxLines,
    this.enabled = true,
  });

  final NubiaTextFieldVariant variant;
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final Widget? suffixWidget;
  final ValueChanged<String>? onChanged;
  final int? maxLines;
  final bool enabled;

  @override
  State<NubiaTextField> createState() => _NubiaTextFieldState();
}

class _NubiaTextFieldState extends State<NubiaTextField> {
  bool _obscure = true;

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
      case NubiaTextFieldVariant.withSuffix:
        return _buildTextField(
          decoration: _withSuffix(context),
        );
    }
  }

  Widget _buildTextField({
    required InputDecoration decoration,
    bool obscureText = false,
    int? maxLines,
  }) {
    return TextField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : (maxLines ?? 1),
      enabled: widget.enabled,
      decoration: decoration.copyWith(
        errorText: widget.errorText,
      ),
    );
  }

  InputDecoration _base(BuildContext context) {
    return InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
    );
  }

  InputDecoration _outlined(BuildContext context) {
    return _base(context).copyWith(
      border: const OutlineInputBorder(),
    );
  }

  InputDecoration _filled(BuildContext context) {
    return _base(context).copyWith(
      filled: true,
      border: const UnderlineInputBorder(),
    );
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
        tooltip: _obscure ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
      ),
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
