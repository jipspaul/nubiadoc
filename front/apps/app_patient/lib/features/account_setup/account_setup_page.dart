import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../router/app_router.dart';
import 'account_setup_cubit.dart';

class AccountSetupPage extends StatefulWidget {
  const AccountSetupPage({super.key});

  @override
  State<AccountSetupPage> createState() => _AccountSetupPageState();
}

class _AccountSetupPageState extends State<AccountSetupPage> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  DateTime? _dateOfBirth;

  static final _phoneRe = RegExp(r'^(\+33|0033|0)[1-9]\d{8}$');

  bool get _phoneValid => _phoneRe.hasMatch(_phone.text.trim());

  bool get _dobValid => _dateOfBirth != null && _isOldEnough(_dateOfBirth!);

  bool get _formValid =>
      _firstName.text.trim().isNotEmpty &&
      _lastName.text.trim().isNotEmpty &&
      _phoneValid &&
      _dobValid;

  static bool _isOldEnough(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age >= 13;
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(DateTime.now().year - 20),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('fr'),
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('account_setup_scaffold'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: BlocConsumer<AccountSetupCubit, AccountSetupState>(
            listener: (context, state) {
              if (state is AccountSetupFailure) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.message)),
                );
              } else if (state is AccountSetupSuccess) {
                context.go(AppRouter.coverageSetup);
              }
            },
            builder: (context, state) {
              final loading = switch (state) {
                AccountSetupIdle() => false,
                AccountSetupLoading() => true,
                AccountSetupSuccess() => false,
                AccountSetupFailure() => false,
              };
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Mon profil',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Complétez vos informations personnelles',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    NubiaTextField(
                      controller: _firstName,
                      label: 'Prénom',
                      enabled: !loading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _lastName,
                      label: 'Nom',
                      enabled: !loading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _phone,
                      label: 'Téléphone',
                      hint: '+33 6 12 34 56 78',
                      enabled: !loading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _DatePickerField(
                      label: 'Date de naissance',
                      value: _dateOfBirth != null
                          ? _formatDate(_dateOfBirth!)
                          : null,
                      onTap: loading ? null : () => _pickDate(context),
                    ),
                    const SizedBox(height: 24),
                    NubiaButton(
                      label: 'Continuer',
                      isLoading: loading,
                      onPressed: (!_formValid || loading)
                          ? null
                          : () => context.read<AccountSetupCubit>().submit(
                                firstName: _firstName.text.trim(),
                                lastName: _lastName.text.trim(),
                                phone: _phone.text.trim(),
                                dateOfBirth: _dateOfBirth!,
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

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'JJ/MM/AAAA',
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: value != null
            ? Text(value!, style: Theme.of(context).textTheme.bodyMedium)
            : const SizedBox.shrink(),
      ),
    );
  }
}
