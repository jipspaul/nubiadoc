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
  });

  final int unreadCount;
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
  }) {
    return ProNotificationsState(
      unreadCount: unreadCount ?? this.unreadCount,
      notifications: notifications ?? this.notifications,
      isLoadingList: isLoadingList ?? this.isLoadingList,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }

  @override
  List<Object?> get props => [unreadCount, notifications, isLoadingList, error];
}

const _unset = Object();
