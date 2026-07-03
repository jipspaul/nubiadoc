// ignore: deprecated_member_use
import 'dart:html' as html;

import 'kv_store.dart';

KvStore createKvStore() => _WebKvStore();

/// localStorage : persiste de façon fiable au rechargement de la page.
/// Les JWT sont des bearer tokens courts ; sur une SPA web ils ne peuvent de
/// toute façon pas être cachés du JS — c'est le modèle standard.
class _WebKvStore implements KvStore {
  @override
  Future<String?> read(String key) async =>
      html.window.localStorage[key];

  @override
  Future<void> write(String key, String value) async =>
      html.window.localStorage[key] = value;

  @override
  Future<void> delete(String key) async =>
      html.window.localStorage.remove(key);
}
