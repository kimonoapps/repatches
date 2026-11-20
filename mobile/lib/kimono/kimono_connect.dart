import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

/// Where Kimono Photos lives, and whether to go straight to Kimono sign-in.
///
/// The address comes from the `kimono-photos://connect?server=…` link the
/// Kimono Portal opens on this phone (or is baked in with
/// `--dart-define=KIMONO_PHOTOS_SERVER=…`). It is kept, never shown, and
/// can't be typed in: there is no address field anywhere in the app.
abstract final class KimonoConnect {
  static const _builtIn = String.fromEnvironment('KIMONO_PHOTOS_SERVER');

  /// Bumped when a connect link arrives, so an open sign-in screen follows it.
  static final requests = ValueNotifier<int>(0);

  /// True after someone taps Sign out, so the sign-in screen waits for them
  /// instead of sending them straight back into Kimono. Only that button sets
  /// it: the app also signs out on its own (e.g. at start-up with no saved
  /// session), and those must not stop the automatic sign-in.
  static bool signedOut = false;

  static String? get server {
    final saved = Store.tryGet(StoreKey.serverUrl);
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
    return _builtIn.isEmpty ? null : _builtIn;
  }

  /// Waits until the app is the active, foreground app. iOS refuses to show
  /// the sign-in sheet otherwise (ASWebAuthenticationSession error 3), and a
  /// connect link arrives while iOS is still dismissing its "Open in…?" prompt.
  static Future<void> untilForeground() async {
    final binding = WidgetsBinding.instance;
    if (binding.lifecycleState != AppLifecycleState.resumed) {
      final resumed = Completer<void>();
      final listener = AppLifecycleListener(
        onResume: () {
          if (!resumed.isCompleted) {
            resumed.complete();
          }
        },
      );
      await resumed.future.timeout(const Duration(seconds: 30), onTimeout: () {});
      listener.dispose();
    }
    await binding.endOfFrame;
  }

  static bool isConnectLink(Uri uri) => uri.scheme == 'kimono-photos' && uri.host == 'connect';

  /// Saves the address from a connect link. Plain http only in debug builds.
  static Future<bool> accept(Uri link) async {
    final raw = link.queryParameters['server'];
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) {
      return false;
    }
    if (uri.scheme != 'https' && !(kDebugMode && uri.scheme == 'http')) {
      return false;
    }
    await Store.put(StoreKey.serverUrl, uri.origin);
    signedOut = false;
    requests.value++;
    return true;
  }
}
