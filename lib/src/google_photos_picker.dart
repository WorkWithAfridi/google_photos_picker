import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'google_photos_models.dart';
import 'google_photos_picker_options.dart';
import 'google_photos_platform.dart';
import 'google_photos_picker_screen.dart';
import 'google_photos_service.dart';

/// Coordinates Google authentication and the Google Photos picker flow.
class GooglePhotosPicker {
  GooglePhotosPicker._();

  static const String readOnlyScope =
      'https://www.googleapis.com/auth/photospicker.mediaitems.readonly';

  /// Shared picker instance used by most applications.
  static final GooglePhotosPicker instance = GooglePhotosPicker._();

  factory GooglePhotosPicker() => instance;

  Future<void>? _initialization;
  GoogleSignInAccount? _account;

  GoogleSignInAccount? get account => _account;

  /// Initializes Google Sign-In. Repeated calls return the first future.
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? hostedDomain,
  }) {
    return _initialization ??= GoogleSignIn.instance.initialize(
      clientId: clientId,
      serverClientId: serverClientId,
      hostedDomain: hostedDomain,
    );
  }

  /// Picks and downloads one photo or video to temporary storage.
  Future<File?> pickFile({required BuildContext context}) async {
    final List<File>? files = await pick(
      context: context,
      options: const GooglePhotosPickerOptions(maxItems: 1),
    );
    return files == null || files.isEmpty ? null : files.first;
  }

  /// Picks and downloads photos and videos to temporary storage.
  Future<List<File>?> pickFiles({
    required BuildContext context,
    int? maxItems,
  }) {
    return pick(
      context: context,
      options: GooglePhotosPickerOptions(maxItems: maxItems),
    );
  }

  /// Opens a Google-hosted Photos picker with the supplied [options].
  Future<List<File>?> pick({
    required BuildContext context,
    GooglePhotosPickerOptions options = const GooglePhotosPickerOptions(),
  }) async {
    await initialize();
    final GoogleSignIn signIn = GoogleSignIn.instance;
    if (!signIn.supportsAuthenticate()) {
      throw UnsupportedError(
        'GooglePhotosPicker currently supports the interactive Android, iOS, '
        'and macOS Google Sign-In flow.',
      );
    }
    try {
      _account = await signIn.authenticate(
        scopeHint: const <String>[readOnlyScope],
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    }
    final Map<String, String>? headers = await _account?.authorizationClient
        .authorizationHeaders(const <String>[
          readOnlyScope,
        ], promptIfNecessary: true);
    if (headers == null) {
      throw const GooglePhotosAuthorizationException();
    }
    final _GoogleAuthClient client = _GoogleAuthClient(headers);
    try {
      if (!context.mounted) return null;
      return await Navigator.of(context).push<List<File>>(
        MaterialPageRoute<List<File>>(
          builder:
              (BuildContext context) => GooglePhotosPickerScreen(
                service: GooglePhotosApiService(client),
                options: options,
                sessionMonitorStarter:
                    Platform.isAndroid
                        ? (GooglePhotosPickingSession session) =>
                            GooglePhotosPlatform.startSessionMonitor(
                              sessionId: session.id,
                              headers: headers,
                              pollInterval:
                                  session.pollingConfig?.pollInterval ??
                                  const Duration(seconds: 2),
                              timeout:
                                  session.pollingConfig?.timeoutIn ??
                                  const Duration(minutes: 10),
                            )
                        : null,
                sessionMonitorStopper:
                    Platform.isAndroid
                        ? GooglePhotosPlatform.stopSessionMonitor
                        : null,
              ),
        ),
      );
    } finally {
      client.close();
    }
  }

  Future<void> signOut() async {
    await initialize();
    await GoogleSignIn.instance.signOut();
    _account = null;
  }
}

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers, {http.Client? client})
    : _client = client ?? http.Client();

  final Map<String, String> _headers;
  final http.Client _client;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}
