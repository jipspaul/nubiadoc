import 'package:flutter/material.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key, this.invitationToken});

  final String? invitationToken;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text('Bienvenue — inscription en cours…'),
      ),
    );
  }
}
