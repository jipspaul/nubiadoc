import 'package:flutter_bloc/flutter_bloc.dart';

mixin SafeEmitMixin<S> on BlocBase<S> {
  void safeEmit(S state) {
    if (!isClosed) emit(state);
  }
}
