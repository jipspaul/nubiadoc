import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/nubia_core.dart';

class _TestCubit extends Cubit<int> with SafeEmitMixin<int> {
  _TestCubit() : super(0);
}

void main() {
  group('SafeEmitMixin', () {
    test('emit normal après init → state observable', () {
      final cubit = _TestCubit();
      cubit.safeEmit(42);
      expect(cubit.state, 42);
      cubit.close();
    });

    test('safeEmit après close() → no-op, pas de StateError', () async {
      final cubit = _TestCubit();
      await cubit.close();
      expect(() => cubit.safeEmit(1), returnsNormally);
      expect(cubit.state, 0);
    });

    test('safeEmit en concurrence avec close → idempotent', () async {
      final cubit = _TestCubit();
      Future.microtask(() => cubit.safeEmit(99));
      await cubit.close();
      expect(cubit.state, anyOf(0, 99));
    });
  });
}
