import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'google_photos_models.dart';
import 'google_photos_picker_options.dart';
import 'google_photos_service.dart';

typedef GooglePhotosUriLauncher = Future<bool> Function(Uri uri);

/// Progress UI shown while the user selects media in Google Photos.
class GooglePhotosPickerScreen extends StatefulWidget {
  const GooglePhotosPickerScreen({
    super.key,
    required this.service,
    this.options = const GooglePhotosPickerOptions(),
    this.uriLauncher,
  });

  final GooglePhotosService service;
  final GooglePhotosPickerOptions options;
  final GooglePhotosUriLauncher? uriLauncher;

  @override
  State<GooglePhotosPickerScreen> createState() =>
      _GooglePhotosPickerScreenState();
}

class _GooglePhotosPickerScreenState extends State<GooglePhotosPickerScreen> {
  String _status = 'Preparing Google Photos…';
  Object? _error;
  Uri? _pickerUri;
  bool _cancelled = false;
  bool _allowPop = false;
  Future<void>? _flow;
  int _downloaded = 0;
  int _downloadTotal = 0;

  @override
  void initState() {
    super.initState();
    _flow = _run();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return PopScope<List<File>?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (bool didPop, List<File>? result) {
        if (!didPop) unawaited(_cancelAndPop());
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Google Photos')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    _error == null
                        ? Icons.photo_library_outlined
                        : Icons.error_outline,
                    size: 64,
                    color: _error == null ? colors.primary : colors.error,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _error == null ? _status : 'Couldn’t open Google Photos',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_error == null) ...<Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _downloadTotal > 0
                          ? 'Downloading $_downloaded of $_downloadTotal'
                          : 'Choose your items in Google Photos, then tap Done. '
                              'Return here if this screen does not reopen automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ] else ...<Widget>[
                    Text(
                      _errorMessage(_error!),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                  if (_pickerUri != null && _error == null) ...<Widget>[
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _openPicker,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Google Photos again'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _cancelAndPop,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _run() async {
    String? sessionId;
    try {
      final GooglePhotosPickingSession initial = await widget.service
          .createSession(maxItemCount: widget.options.maxItems);
      sessionId = initial.id;
      _pickerUri = initial.pickerUri;
      if (_cancelled) return;
      setState(() => _status = 'Waiting for your selection…');

      if (!await _launch(initial.pickerUri)) {
        throw const GooglePhotosApiException(
          'No application could open the Google Photos picker.',
        );
      }

      GooglePhotosPickingSession session = initial;
      final Duration timeout =
          initial.pollingConfig?.timeoutIn ?? const Duration(minutes: 10);
      final DateTime deadline = DateTime.now().add(timeout);
      while (!session.mediaItemsSet) {
        if (_cancelled) return;
        if (!DateTime.now().isBefore(deadline)) {
          throw TimeoutException(
            'The Google Photos picking session timed out.',
          );
        }
        await Future<void>.delayed(
          session.pollingConfig?.pollInterval ?? const Duration(seconds: 2),
        );
        if (_cancelled) return;
        try {
          session = await widget.service.getSession(sessionId);
          if (mounted && _status != 'Waiting for your selection…') {
            setState(() => _status = 'Waiting for your selection…');
          }
        } on Object catch (error) {
          if (!_isRetryablePollError(error)) rethrow;
          if (mounted && _status != 'Connection interrupted. Retrying…') {
            setState(() => _status = 'Connection interrupted. Retrying…');
          }
        }
      }

      final List<GooglePhotosMediaItem> items = await widget.service
          .listMediaItems(sessionId);
      if (_cancelled) return;
      if (items.isEmpty) {
        await widget.service.deleteSession(sessionId);
        sessionId = null;
        if (mounted) {
          _allowPop = true;
          Navigator.of(context).pop(<File>[]);
        }
        return;
      }
      setState(() {
        _status = 'Downloading selected media…';
        _downloadTotal = items.length;
      });
      final List<File> files = <File>[];
      for (final GooglePhotosMediaItem item in items) {
        files.add(await widget.service.downloadMediaItem(item));
        if (_cancelled) return;
        setState(() => _downloaded = files.length);
      }
      await widget.service.deleteSession(sessionId);
      sessionId = null;
      if (mounted) {
        _allowPop = true;
        Navigator.of(context).pop(files);
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Google Photos picker failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted && !_cancelled) {
        setState(() => _error = error);
      }
    } finally {
      if (sessionId != null) {
        try {
          await widget.service.deleteSession(sessionId);
        } on Object catch (error) {
          debugPrint('Google Photos session cleanup failed: $error');
        }
      }
    }
  }

  Future<bool> _launch(Uri uri) {
    final GooglePhotosUriLauncher? launcher = widget.uriLauncher;
    if (launcher != null) return launcher(uri);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openPicker() async {
    final Uri? uri = _pickerUri;
    if (uri != null) await _launch(uri);
  }

  void _retry() {
    setState(() {
      _error = null;
      _pickerUri = null;
      _status = 'Preparing Google Photos…';
      _downloaded = 0;
      _downloadTotal = 0;
    });
    _cancelled = false;
    _flow = _run();
  }

  Future<void> _cancelAndPop() async {
    if (_cancelled) return;
    setState(() {
      _cancelled = true;
      _status = 'Closing Google Photos…';
    });
    await _flow;
    if (mounted) {
      _allowPop = true;
      Navigator.of(context).pop();
    }
  }

  String _errorMessage(Object error) {
    if (error case GooglePhotosApiException(:final String message)) {
      return message;
    }
    if (error is TimeoutException) return error.message ?? 'Session timed out.';
    return 'Please check your connection and Google Photos API configuration.';
  }

  bool _isRetryablePollError(Object error) {
    if (error is SocketException ||
        error is http.ClientException ||
        error is TimeoutException) {
      return true;
    }
    if (error case GooglePhotosApiException(:final int? statusCode)) {
      return statusCode == 408 ||
          statusCode == 429 ||
          (statusCode != null && statusCode >= 500);
    }
    return false;
  }
}
