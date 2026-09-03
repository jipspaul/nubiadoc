import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// State of the pro shell's notification bell (#6263).
///
/// [unreadCount] is refreshed independently of [notifications] (polled via
/// `?unread_only=true`, cheaper than the full list) — [notifications] stays
/// `null` until the panel is opened for the first time.
class ProNotificationsState extends Equatable {
  const ProNotificationsState({
    this.unreadCount = 0,
    this.notifications,
    this.isLoadingList = false,
    this.error,
    this.lastIncoming,
    this.incomingSeq = 0,
  });

  final int unreadCount;

  /// Dernière notification poussée en temps réel (canal WS `notifications`),
  /// affichée en bandeau par la cloche. [incomingSeq] s'incrémente à chaque
  /// arrivée pour que le listener réagisse même à deux titres identiques.
  final IncomingNotification? lastIncoming;
  final int incomingSeq;
  final List<AppNotification>? notifications;
  final bool isLoadingList;
  final String? error;

  /// [error] uses a sentinel default (rather than `null`) so callers can
  /// distinguish "leave the current error untouched" (omit it, e.g. after a
  /// background [ProNotificationsState.unreadCount] poll) from "clear it"
  /// (pass `null` explicitly, e.g. when a list reload starts/succeeds).
  ProNotificationsState copyWith({
    int? unreadCount,
    List<AppNotification>? notifications,
    bool? isLoadingList,
    Object? error = _unset,
    IncomingNotification? lastIncoming,
    int? incomingSeq,
  }) {
    return ProNotificationsState(
      unreadCount: unreadCount ?? this.unreadCount,
      notifications: notifications ?? this.notifications,
      isLoadingList: isLoadingList ?? this.isLoadingList,
      error: identical(error, _unset) ? this.error : error as String?,
      lastIncoming: lastIncoming ?? this.lastIncoming,
      incomingSeq: incomingSeq ?? this.incomingSeq,
    );
  }

  @override
  List<Object?> get props =>
      [unreadCount, notifications, isLoadingList, error, incomingSeq];
}

const _unset = Object();
