import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'pro_register_cubit.dart';

/// Liste statique des spécialités dentaires.
const _kSpecialites = [
  'Chirurgie dentaire',
  'Orthodontie',
  'Parodontologie',
  'Chirurgie orale',
  'Pédodontie',
  'Endodontie',
  'Implantologie',
  'Occlusodontie',
  'Médecine buccale',
];

class ProRegisterPage extends StatefulWidget {
  const ProRegisterPage({super.key});

  @override
  State<ProRegisterPage> createState() => _ProRegisterPageState();
}

class _ProRegisterPageState extends State<ProRegisterPage> {
  // Controllers
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _rpps = TextEditingController();
  final _adeli = TextEditingController();
  final _raisonSociale = TextEditingController();
  final _siret = TextEditingController();
  String? _specialite;

  // Regex validators
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _rppsRe = RegExp(r'^\d{11}$');
  static final _adeliRe = RegExp(r'^\d{9}$');
  static final _siretRe = RegExp(r'^\d{14}$');

  bool get _emailValid => _emailRe.hasMatch(_email.text.trim());

  bool get _passwordValid {
    final p = _password.text;
    return p.length >= 8 &&
        RegExp(r'[0-9]').hasMatch(p) &&
        RegExp(r'[^a-zA-Z0-9]').hasMatch(p);
  }

  bool get _confirmPasswordValid =>
      _confirmPassword.text == _password.text && _confirmPassword.text.isNotEmpty;

  bool get _firstNameValid => _firstName.text.trim().isNotEmpty;
  bool get _lastNameValid => _lastName.text.trim().isNotEmpty;

  bool get _rppsOrAdeliValid {
    final hasRpps = _rpps.text.trim().isNotEmpty;
    final hasAdeli = _adeli.text.trim().isNotEmpty;
    if (!hasRpps && !hasAdeli) return false;
    if (hasRpps && !_rppsRe.hasMatch(_rpps.text.trim())) return false;
    if (hasAdeli && !_adeliRe.hasMatch(_adeli.text.trim())) return false;
    return true;
  }

  bool get _raisonSocialeValid => _raisonSociale.text.trim().isNotEmpty;

  bool get _siretValid {
    final v = _siret.text.trim();
    return v.isEmpty || _siretRe.hasMatch(v);
  }

  bool get _formValid =>
      _emailValid &&
      _passwordValid &&
      _confirmPasswordValid &&
      _firstNameValid &&
      _lastNameValid &&
      _rppsOrAdeliValid &&
      _raisonSocialeValid &&
      _siretValid &&
      _specialite != null;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _rpps.dispose();
    _adeli.dispose();
    _raisonSociale.dispose();
    _siret.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  String? get _emailError =>
      _email.text.trim().isNotEmpty && !_emailValid ? 'E-mail invalide.' : null;

  String? get _passwordError {
    final p = _password.text;
    if (p.isEmpty) return null;
    if (p.length < 8) return 'Au moins 8 caractères.';
    if (!RegExp(r'[0-9]').hasMatch(p)) return 'Au moins 1 chiffre.';
    if (!RegExp(r'[^a-zA-Z0-9]').hasMatch(p)) return 'Au moins 1 symbole.';
    return null;
  }

  String? get _confirmPasswordError =>
      _confirmPassword.text.isNotEmpty && !_confirmPasswordValid
          ? 'Les mots de passe ne correspondent pas.'
          : null;

  String? get _rppsError {
    final v = _rpps.text.trim();
    return v.isNotEmpty && !_rppsRe.hasMatch(v) ? '11 chiffres requis.' : null;
  }

  String? get _adeliError {
    final v = _adeli.text.trim();
    return v.isNotEmpty && !_adeliRe.hasMatch(v) ? '9 chiffres requis.' : null;
  }

  String? get _siretError {
    final v = _siret.text.trim();
    return v.isNotEmpty && !_siretRe.hasMatch(v) ? '14 chiffres requis.' : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte praticien')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: BlocConsumer<ProRegisterCubit, ProRegisterState>(
            listener: (context, state) {
              if (state is ProRegisterFailure) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.message)),
                );
              }
            },
            builder: (context, state) {
              final loading = state is ProRegisterLoading;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Informations personnelles',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _firstName,
                      label: 'Prénom',
                      onChanged: (_) => _refresh(),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _lastName,
                      label: 'Nom',
                      onChanged: (_) => _refresh(),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _email,
                      label: 'E-mail professionnel',
                      errorText: _emailError,
                      onChanged: (_) => _refresh(),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _password,
                      label: 'Mot de passe',
                      hint: '8 car. minimum, dont 1 chiffre et 1 symbole',
                      variant: NubiaTextFieldVariant.password,
                      errorText: _passwordError,
                      onChanged: (_) => _refresh(),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _confirmPassword,
                      label: 'Confirmer le mot de passe',
                      variant: NubiaTextFieldVariant.password,
                      errorText: _confirmPasswordError,
                      onChanged: (_) => _refresh(),
                    ),
                    const SizedBox(height: 24),
                    Text('Identifiants professionnels',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Renseignez au moins l\'un des deux identifiants.',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _rpps,
                      label: 'RPPS (11 chiffres)',
                      errorText: _rppsError,
                      onChanged: (_) => _refresh(),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _adeli,
                      label: 'ADELI (9 chiffres)',
                      errorText: _adeliError,
                      onChanged: (_) => _refresh(),
                    ),
                    const SizedBox(height: 24),
                    Text('Cabinet',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _raisonSociale,
                      label: 'Raison sociale',
                      onChanged: (_) => _refresh(),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _siret,
                      label: 'SIRET (14 chiffres, optionnel)',
                      errorText: _siretError,
                      onChanged: (_) => _refresh(),
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Spécialité',
                        border: OutlineInputBorder(),
                      ),
                      isEmpty: _specialite == null,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('specialite_dropdown'),
                          value: _specialite,
                          isDense: true,
                          onChanged: loading
                              ? null
                              : (v) => setState(() => _specialite = v),
                          items: _kSpecialites
                              .map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    NubiaButton(
                      label: 'Créer mon compte',
                      isLoading: loading,
                      onPressed: (!_formValid || loading)
                          ? null
                          : () => context.read<ProRegisterCubit>().submit(
                                ProRegisterRequest(
                                  email: _email.text.trim(),
                                  password: _password.text,
                                  firstName: _firstName.text.trim(),
                                  lastName: _lastName.text.trim(),
                                  rpps: _rpps.text.trim().isEmpty
                                      ? null
                                      : _rpps.text.trim(),
                                  adeli: _adeli.text.trim().isEmpty
                                      ? null
                                      : _adeli.text.trim(),
                                  raisonSociale: _raisonSociale.text.trim(),
                                  siret: _siret.text.trim().isEmpty
                                      ? null
                                      : _siret.text.trim(),
                                  specialite: _specialite!,
                                ),
                              ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
