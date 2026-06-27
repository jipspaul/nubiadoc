import 'package:bloc/bloc.dart';

mixin SafeEmitMixin<S> on BlocBase<S> {
  void safeEmit(S state) {
    if (!isClosed) emit(state);
  }
}
