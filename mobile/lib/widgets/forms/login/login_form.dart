import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/infrastructure/repositories/settings.repository.dart';
import 'package:immich_mobile/kimono/kimono_connect.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/feature_message.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/oauth.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/view_intent/view_intent_handler.provider.dart';
import 'package:immich_mobile/repositories/permission.repository.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/provider_utils.dart';
import 'package:immich_mobile/utils/semver.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/utils/version_compatibility.dart';
import 'package:immich_mobile/widgets/common/immich_logo.dart';
import 'package:immich_mobile/widgets/common/immich_title_text.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
import 'package:package_info_plus/package_info_plus.dart';

class LoginForm extends HookConsumerWidget {
  LoginForm({super.key});

  final log = Logger('LoginForm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverEndpointController = useTextEditingController.fromValue(TextEditingValue.empty);
    final isOauthEnable = useState<bool>(false);
    final isPasswordLoginEnable = useState<bool>(false);
    final oAuthButtonLabel = useState<String>('OAuth');
    final serverInfo = ref.watch(serverInfoProvider);
    final warningMessage = useState<String?>(null);
    final loginFormKey = GlobalKey<FormState>();
    final ValueNotifier<String?> serverEndpoint = useState<String?>(null);
    final connecting = useState<bool>(KimonoConnect.server != null);
    final oauthFailed = useState<bool>(false);

    Future<void> checkVersionMismatch() async {
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        final appSemVer = SemVer.fromString(packageInfo.version);
        final serverSemVer = serverInfo.serverVersion;
        warningMessage.value = getVersionCompatibilityMessage(serverVersion: serverSemVer, appVersion: appSemVer);
      } catch (error) {
        warningMessage.value = 'Error checking version compatibility';
      }
    }

    /// Fetch the server login credential and enables oAuth login if necessary
    /// Returns true if successful, false otherwise
    Future<void> getServerAuthSettings() async {
      final sanitizeServerUrl = normalizeServerUrl(serverEndpointController.text);
      final serverUrl = punycodeEncodeUrl(sanitizeServerUrl);

      // Guard empty URL
      if (serverUrl.isEmpty) {
        ImmichToast.show(context: context, msg: context.t.login_form_server_empty, toastType: ToastType.error);
      }

      try {
        final endpoint = await ref.read(authProvider.notifier).validateServerUrl(serverUrl);
        if (!context.mounted) {
          return;
        }

        // Fetch and load server config and features
        await ref.read(serverInfoProvider.notifier).getServerInfo();
        if (!context.mounted) {
          return;
        }

        final serverInfo = ref.read(serverInfoProvider);
        final features = serverInfo.serverFeatures;
        final config = serverInfo.serverConfig;

        isOauthEnable.value = features.oauthEnabled;
        isPasswordLoginEnable.value = features.passwordLogin;
        oAuthButtonLabel.value = config.oauthButtonText.isNotEmpty ? config.oauthButtonText : 'OAuth';

        serverEndpoint.value = endpoint;
      } on ApiException catch (e) {
        if (!context.mounted) {
          return;
        }

        ImmichToast.show(
          context: context,
          msg: e.message ?? context.t.login_form_api_exception,
          toastType: ToastType.error,
          gravity: ToastGravity.TOP,
        );
        isOauthEnable.value = false;
        isPasswordLoginEnable.value = true;
      } on HandshakeException {
        if (!context.mounted) {
          return;
        }

        ImmichToast.show(
          context: context,
          msg: context.t.login_form_handshake_exception,
          toastType: ToastType.error,
          gravity: ToastGravity.TOP,
        );
        isOauthEnable.value = false;
        isPasswordLoginEnable.value = true;
      } catch (e) {
        if (!context.mounted) {
          return;
        }

        ImmichToast.show(
          context: context,
          msg: context.t.login_form_server_error,
          toastType: ToastType.error,
          gravity: ToastGravity.TOP,
        );
        isOauthEnable.value = false;
        isPasswordLoginEnable.value = true;
      }
    }

    Future<void> handleSyncFlow() async {
      final backgroundManager = ref.read(backgroundSyncProvider);
      final viewIntentHandler = ref.read(viewIntentHandlerProvider);

      await backgroundManager.syncLocal(full: true);
      await backgroundManager.syncRemote();
      await viewIntentHandler.flushDeferredViewIntent();
      await backgroundManager.hashAssets();

      if (SettingsRepository.instance.appConfig.backup.syncAlbums) {
        await backgroundManager.syncLinkedAlbum();
      }
    }

    Future<void> getManageMediaPermission() async {
      final hasPermission = await ref.read(permissionRepositoryProvider).hasManageMediaPermission();
      if (!context.mounted) {
        return;
      }

      if (!hasPermission) {
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
              elevation: 5,
              title: Text(
                context.t.manage_media_access_title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.primaryColor),
              ),
              content: SingleChildScrollView(
                child: ListBody(
                  children: [
                    Text(context.t.manage_media_access_subtitle, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(context.t.manage_media_access_rationale, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    context.t.cancel,
                    style: TextStyle(fontWeight: FontWeight.w600, color: context.primaryColor),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    unawaited(ref.read(permissionRepositoryProvider).requestManageMediaPermission());
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    context.t.manage_media_access_settings,
                    style: TextStyle(fontWeight: FontWeight.w600, color: context.primaryColor),
                  ),
                ),
              ],
            );
          },
        );
      }
    }

    bool isSyncRemoteDeletionsMode() => Platform.isAndroid && Store.get(StoreKey.manageLocalMediaAndroid, false);

    String generateRandomString(int length) {
      const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
      final random = Random.secure();
      return String.fromCharCodes(Iterable.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
    }

    List<int> randomBytes(int length) {
      final random = Random.secure();
      return List<int>.generate(length, (i) => random.nextInt(256));
    }

    /// Per specification, the code verifier must be 43-128 characters long
    /// and consist of characters [A-Z, a-z, 0-9, "-", ".", "_", "~"]
    /// https://datatracker.ietf.org/doc/html/rfc7636#section-4.1
    String randomCodeVerifier() {
      return base64Url.encode(randomBytes(42));
    }

    Future<String> generatePKCECodeChallenge(String codeVerifier) async {
      final bytes = utf8.encode(codeVerifier);
      final digest = sha256.convert(bytes);
      return base64Url.encode(digest.bytes).replaceAll('=', '');
    }

    Future<bool> oAuthLogin() async {
      final oAuthService = ref.read(oAuthServiceProvider);
      String? oAuthServerUrl;

      final state = generateRandomString(32);

      final codeVerifier = randomCodeVerifier();
      final codeChallenge = await generatePKCECodeChallenge(codeVerifier);

      try {
        oAuthServerUrl = await oAuthService.getOAuthServerUrl(
          normalizeServerUrl(serverEndpointController.text),
          state,
          codeChallenge,
        );

        // Invalidate all api repository provider instance to take into account new access token
        invalidateAllApiRepositoryProviders(ref);
      } catch (error, stack) {
        log.severe('Error getting OAuth server Url: $error', stack);

        if (!context.mounted) {
          return false;
        }

        ImmichToast.show(
          context: context,
          msg: context.t.login_form_failed_get_oauth_server_config,
          toastType: ToastType.error,
          gravity: ToastGravity.TOP,
        );
        return false;
      }

      if (oAuthServerUrl != null) {
        try {
          final loginResponseDto = await oAuthService.oAuthLogin(oAuthServerUrl, state, codeVerifier);

          if (loginResponseDto == null || !context.mounted) {
            return false;
          }

          log.info("Finished OAuth login with response: ${loginResponseDto.userEmail}");

          final isSuccess = await ref
              .read(authProvider.notifier)
              .saveAuthInfo(accessToken: loginResponseDto.accessToken);

          if (isSuccess && context.mounted) {
            await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();
            if (isSyncRemoteDeletionsMode()) {
              await getManageMediaPermission();
            }
            unawaited(handleSyncFlow());
            if (!context.mounted) {
              return true;
            }

            unawaited(ref.read(featureMessageServiceProvider).markSeen());
            unawaited(context.router.replaceAll([const TabShellRoute()]));
            return true;
          }
        } catch (error, stack) {
          log.severe('Error logging in with OAuth: $error', stack);

          if (!context.mounted) {
            return false;
          }

          ImmichToast.show(
            context: context,
            msg: error.toString(),
            toastType: ToastType.error,
            gravity: ToastGravity.TOP,
          );
        } finally {}
      } else {
        if (!context.mounted) {
          return false;
        }

        ImmichToast.show(
          context: context,
          msg: context.t.login_form_failed_get_oauth_server_disable,
          toastType: ToastType.info,
          gravity: ToastGravity.TOP,
        );
        return false;
      }
      return false;
    }

    Future<void> connect() async {
      final server = KimonoConnect.server;
      if (server == null) {
        connecting.value = false;
        return;
      }
      serverEndpointController.text = server;
      serverEndpoint.value = null;
      connecting.value = true;
      oauthFailed.value = false;
      await getServerAuthSettings();
      if (!context.mounted) {
        return;
      }
      if (serverEndpoint.value != null && isOauthEnable.value && !KimonoConnect.signedOut) {
        await KimonoConnect.untilForeground();
        if (!context.mounted) {
          return;
        }
        final signedIn = await oAuthLogin();
        if (!context.mounted) {
          return;
        }
        oauthFailed.value = !signedIn;
      }
      connecting.value = false;
    }

    useEffect(() {
      void onLink() => unawaited(connect());
      KimonoConnect.requests.addListener(onLink);
      unawaited(connect());
      return () => KimonoConnect.requests.removeListener(onLink);
    }, []);

    SingleChildRenderObjectWidget buildVersionCompatWarning() {
      unawaited(checkVersionMismatch());

      if (warningMessage.value == null) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.isDarkTheme ? Colors.amber.shade700 : Colors.amber.shade100,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            border: Border.all(color: context.isDarkTheme ? Colors.amber.shade800 : Colors.amber[200]!, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(warningMessage.value!)),
              ),
            ],
          ),
        ),
      );
    }

    final serverSelectionOrLogin = connecting.value
        ? const Padding(
            padding: EdgeInsets.only(top: ImmichSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          )
        : serverEndpoint.value == null
        ? Padding(
            padding: const EdgeInsets.only(top: ImmichSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                if (KimonoConnect.server == null)
                  Text(
                    'Open Photos from Kimono on this phone to connect.',
                    style: context.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  )
                else
                  ImmichTextButton(
                    labelText: 'Try again',
                    icon: Icons.refresh_rounded,
                    variant: ImmichVariant.ghost,
                    onPressed: () => unawaited(connect()),
                  ),
              ],
            ),
          )
        // Kimono is the only way in: no email and password form, ever.
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.max,
            children: [
              buildVersionCompatWarning(),
              if (isOauthEnable.value)
                ImmichForm(
                  onSubmit: () async {
                    KimonoConnect.signedOut = false;
                    oauthFailed.value = !await oAuthLogin();
                  },
                  submitText: oAuthButtonLabel.value,
                  submitIcon: Icons.pin_outlined,
                  builder: (context, _) => const SizedBox.shrink(),
                )
              else
                Text(
                  'Kimono sign-in is off for Photos.',
                  style: context.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
            ],
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: constraints.maxHeight / 5),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ImmichLogo(),
                      Padding(padding: EdgeInsets.only(top: 8.0, bottom: 16), child: ImmichTitleText()),
                    ],
                  ),

                  // Note: This used to have an AnimatedSwitcher, but was removed
                  // because of https://github.com/flutter/flutter/issues/120874
                  Form(key: loginFormKey, child: serverSelectionOrLogin),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
