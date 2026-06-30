import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../router/app_router.dart';
import 'signup_cubit.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _cguAccepted = false;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _emailValid => _emailRe.hasMatch(_email.text.trim());
  bool get _passwordValid =>
      _password.text.length >= 8 && RegExp(r'[0-9]').hasMatch(_password.text);
  bool get _formValid => _emailValid && _passwordValid && _cguAccepted;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('signup_scaffold'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: BlocConsumer<SignupCubit, SignupState>(
            listener: (context, state) {
              if (state is SignupFailure) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.message)),
                );
              } else if (state is SignupSuccess) {
                context.go(AppRouter.accountSetup);
              }
            },
            builder: (context, state) {
              final loading = state is SignupLoading;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Nubia',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text('Créer un compte',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 24),
                    NubiaTextField(
                      controller: _email,
                      label: 'E-mail',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _password,
                      label: 'Mot de passe',
                      hint: '8 caractères minimum, dont 1 chiffre',
                      variant: NubiaTextFieldVariant.password,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: _cguAccepted,
                          onChanged: loading
                              ? null
                              : (v) =>
                                  setState(() => _cguAccepted = v ?? false),
                        ),
                        Expanded(
                          child: Text(
                            "J'accepte les Conditions Générales d'Utilisation",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    NubiaButton(
                      label: 'Créer mon compte',
                      isLoading: loading,
                      onPressed: (!_formValid || loading)
                          ? null
                          : () => context.read<SignupCubit>().register(
                                _email.text.trim(),
                                _password.text,
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
