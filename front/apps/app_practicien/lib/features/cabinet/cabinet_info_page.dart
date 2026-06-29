import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../router/app_router.dart';
import 'cabinet_info_cubit.dart';

class CabinetInfoPage extends StatefulWidget {
  const CabinetInfoPage({super.key});

  @override
  State<CabinetInfoPage> createState() => _CabinetInfoPageState();
}

class _CabinetInfoPageState extends State<CabinetInfoPage> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _siret = TextEditingController();

  static final _phoneRe = RegExp(r'^(\+33|0033|0)[1-9]\d{8}$');
  static final _siretRe = RegExp(r'^\d{14}$');

  bool get _nameValid => _name.text.trim().isNotEmpty;
  bool get _addressValid => _address.text.trim().isNotEmpty;
  bool get _phoneValid => _phoneRe.hasMatch(_phone.text.trim());

  bool get _siretValid {
    final v = _siret.text.trim();
    return v.isEmpty || _siretRe.hasMatch(v);
  }

  bool get _formValid =>
      _nameValid && _addressValid && _phoneValid && _siretValid;

  String? get _phoneError {
    final v = _phone.text.trim();
    return v.isNotEmpty && !_phoneValid
        ? 'Format invalide (ex: 0612345678 ou +33612345678).'
        : null;
  }

  String? get _siretError {
    final v = _siret.text.trim();
    return v.isNotEmpty && !_siretRe.hasMatch(v) ? '14 chiffres requis.' : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _siret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: BlocConsumer<CabinetInfoCubit, CabinetInfoState>(
            listener: (context, state) {
              if (state is CabinetInfoFailure) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.message)),
                );
              } else if (state is CabinetInfoSuccess) {
                context.go(AppRouter.home);
              }
            },
            builder: (context, state) {
              final loading = state is CabinetInfoLoading;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Informations du cabinet',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Complétez les informations de votre cabinet',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    NubiaTextField(
                      controller: _name,
                      label: 'Nom du cabinet',
                      enabled: !loading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _address,
                      label: 'Adresse',
                      enabled: !loading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _phone,
                      label: 'Téléphone',
                      hint: '0612345678',
                      errorText: _phoneError,
                      enabled: !loading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _siret,
                      label: 'SIRET (14 chiffres, optionnel)',
                      errorText: _siretError,
                      enabled: !loading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 32),
                    NubiaButton(
                      label: 'Enregistrer',
                      isLoading: loading,
                      onPressed: (!_formValid || loading)
                          ? null
                          : () => context.read<CabinetInfoCubit>().submit(
                                name: _name.text.trim(),
                                address: _address.text.trim(),
                                phone: _phone.text.trim(),
                                siret: _siret.text.trim().isEmpty
                                    ? null
                                    : _siret.text.trim(),
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
