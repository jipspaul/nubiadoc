import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/appointments/bloc/appointment_bloc.dart';
import 'features/appointments/data/appointment_repository.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';
import 'features/auth/bloc/auth_state.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/token_storage.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/bloc/dashboard_bloc.dart';
import 'features/dashboard/data/dashboard_repository.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/prescription/bloc/prescription_bloc.dart';
import 'features/prescription/data/prescription_repository.dart';
import 'theme/nubia_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AuthBloc(
            repository: FakeAuthRepository(),
            tokenStorage: InMemoryTokenStorage(),
          )..add(const AuthCheckRequested()),
        ),
        BlocProvider(
          create: (_) => DashboardBloc(
            repository: FakeDashboardRepository(),
          ),
        ),
        BlocProvider(
          create: (_) => AppointmentBloc(
            repository: FakeAppointmentRepository(),
          ),
        ),
        BlocProvider(
          create: (_) => PrescriptionBloc(
            repository: FakePrescriptionRepository(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Nubia',
        theme: NubiaTheme.light,
        darkTheme: NubiaTheme.dark,
        themeMode: ThemeMode.system,
        home: const _AuthGate(),
      ),
    );
  }
}

/// Routeur conditionnel : redirige vers [LoginScreen] ou [MyHomePage] selon l'état auth.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthAuthenticated) {
          return const DashboardScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _increment() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Demo'),
      ),
      body: Column(
        children: [
          const Text('Hello Flutter'),
          Text('$_counter'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('inc'),
        onPressed: _increment,
        child: const Icon(Icons.add),
      ),
    );
  }
}
