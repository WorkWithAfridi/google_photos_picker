import 'dart:async';
import 'dart:io';

import 'package:flutter_custom_tabs/flutter_custom_tabs.dart' as custom_tabs;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import 'google_photos_models.dart';
import 'google_photos_platform.dart';
import 'google_photos_picker_options.dart';
import 'google_photos_service.dart';

typedef GooglePhotosUriLauncher = Future<bool> Function(Uri uri);
typedef GooglePhotosUriCloser = Future<void> Function();
typedef GooglePhotosSessionMonitorStarter =
    Future<void> Function(GooglePhotosPickingSession session);
typedef GooglePhotosSessionMonitorStopper = Future<void> Function();

enum _PickerPhase { preparing, selecting, downloading, closing, error }

/// Progress UI shown while the user selects media in Google Photos.
class GooglePhotosPickerScreen extends StatefulWidget {
  const GooglePhotosPickerScreen({
    super.key,
    required this.service,
    this.options = const GooglePhotosPickerOptions(),
    this.uriLauncher,
    this.uriCloser,
    this.sessionMonitorStarter,
    this.sessionMonitorStopper,
  });

  final GooglePhotosService service;
  final GooglePhotosPickerOptions options;
  final GooglePhotosUriLauncher? uriLauncher;
  final GooglePhotosUriCloser? uriCloser;
  final GooglePhotosSessionMonitorStarter? sessionMonitorStarter;
  final GooglePhotosSessionMonitorStopper? sessionMonitorStopper;

  @override
  State<GooglePhotosPickerScreen> createState() =>
      _GooglePhotosPickerScreenState();
}

class _GooglePhotosPickerScreenState extends State<GooglePhotosPickerScreen> {
  String _status = 'Preparing Google Photos…';
  _PickerPhase _phase = _PickerPhase.preparing;
  Object? _error;
  Uri? _pickerUri;
  bool _cancelled = false;
  bool _allowPop = false;
  bool _pickerOpen = false;
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
        appBar: AppBar(
          title: const Text('Google Photos'),
          leading: IconButton(
            onPressed: _cancelAndPop,
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Semantics(
                  liveRegion: true,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _buildContent(context, colors),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colors) {
    final bool hasError = _phase == _PickerPhase.error;
    final bool isDownloading = _phase == _PickerPhase.downloading;
    final double? progress =
        isDownloading && _downloadTotal > 0
            ? _downloaded / _downloadTotal
            : null;
    return Column(
      key: ValueKey<_PickerPhase>(_phase),
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: hasError ? colors.errorContainer : colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            hasError
                ? Icons.error_outline_rounded
                : isDownloading
                ? Icons.cloud_download_outlined
                : Icons.photo_library_outlined,
            size: 42,
            color:
                hasError ? colors.onErrorContainer : colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          _title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          hasError ? _errorMessage(_error!) : _description,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        if (isDownloading) ...<Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$_downloaded of $_downloadTotal',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant),
          ),
        ] else if (!hasError) ...<Widget>[
          const SizedBox.square(
            dimension: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ],
        if (hasError) ...<Widget>[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ),
        ] else if (_phase == _PickerPhase.selecting &&
            _pickerUri != null) ...<Widget>[
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openPicker,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Google Photos again'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextButton(
          onPressed: _phase == _PickerPhase.closing ? null : _cancelAndPop,
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  String get _title => switch (_phase) {
    _PickerPhase.preparing => 'Getting things ready',
    _PickerPhase.selecting => _status,
    _PickerPhase.downloading => 'Downloading selected media',
    _PickerPhase.closing => 'Closing Google Photos',
    _PickerPhase.error => 'Couldn’t open Google Photos',
  };

  String get _description => switch (_phase) {
    _PickerPhase.preparing =>
      'Creating a secure Google Photos selection session.',
    _PickerPhase.selecting =>
      'Choose your items in Google Photos and tap Done. You’ll return here automatically.',
    _PickerPhase.downloading =>
      'Keep the app open while your selected media is saved securely.',
    _PickerPhase.closing => 'Finishing your selection and cleaning up.',
    _PickerPhase.error => '',
  };

  Future<void> _run() async {
    String? sessionId;
    try {
      final GooglePhotosPickingSession initial = await widget.service
          .createSession(maxItemCount: widget.options.maxItems);
      sessionId = initial.id;
      final GooglePhotosSessionMonitorStarter? monitorStarter =
          widget.sessionMonitorStarter;
      if (monitorStarter != null) {
        unawaited(
          monitorStarter(initial).onError((
            Object error,
            StackTrace stackTrace,
          ) {
            debugPrint('Could not start Google Photos session monitor: $error');
          }),
        );
      }
      final Uri? pickerUri = initial.pickerUri;
      if (pickerUri == null) {
        throw const FormatException(
          'Google Photos created a session without a picker URI.',
        );
      }
      _pickerUri = _autocloseUri(pickerUri);
      if (_cancelled) return;
      setState(() {
        _phase = _PickerPhase.selecting;
        _status = 'Choose your media';
      });

      if (!await _launch(_pickerUri!)) {
        throw const GooglePhotosApiException(
          'No application could open the Google Photos picker.',
        );
      }
      _pickerOpen = true;

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
          session = await widget.service
              .getSession(sessionId)
              .timeout(const Duration(seconds: 8));
          if (mounted && _status != 'Choose your media') {
            setState(() => _status = 'Choose your media');
          }
        } on Object catch (error) {
          if (!_isRetryablePollError(error)) rethrow;
          if (mounted && _status != 'Connection interrupted. Retrying…') {
            setState(() => _status = 'Connection interrupted. Retrying…');
          }
        }
      }

      await _closePicker();

      final List<GooglePhotosMediaItem> items = await widget.service
          .listMediaItems(sessionId);
      if (_cancelled) return;
      if (items.isEmpty) {
        final String completedSessionId = sessionId;
        sessionId = null;
        await _deleteCompletedSession(completedSessionId);
        if (mounted) {
          _allowPop = true;
          Navigator.of(context).pop(<File>[]);
        }
        return;
      }
      setState(() {
        _phase = _PickerPhase.downloading;
        _status = 'Downloading selected media';
        _downloadTotal = items.length;
      });
      final List<File> files = <File>[];
      for (final GooglePhotosMediaItem item in items) {
        files.add(await widget.service.downloadMediaItem(item));
        if (_cancelled) return;
        setState(() => _downloaded = files.length);
      }
      final String completedSessionId = sessionId;
      sessionId = null;
      await _deleteCompletedSession(completedSessionId);
      if (mounted) {
        _allowPop = true;
        Navigator.of(context).pop(files);
      }
    } on Object catch (error, stackTrace) {
      await _closePicker();
      debugPrint('Google Photos picker failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted && !_cancelled) {
        setState(() {
          _phase = _PickerPhase.error;
          _error = error;
        });
      }
    } finally {
      final GooglePhotosSessionMonitorStopper? monitorStopper =
          widget.sessionMonitorStopper;
      if (monitorStopper != null) {
        try {
          await monitorStopper();
        } on Object catch (error) {
          debugPrint('Could not stop Google Photos session monitor: $error');
        }
      }
      if (sessionId != null) {
        try {
          await widget.service.deleteSession(sessionId);
        } on Object catch (error) {
          debugPrint('Google Photos session cleanup failed: $error');
        }
      }
    }
  }

  Future<bool> _launch(Uri uri) async {
    final GooglePhotosUriLauncher? launcher = widget.uriLauncher;
    if (launcher != null) return launcher(uri);
    if (!Platform.isAndroid && !Platform.isIOS) {
      return url_launcher.launchUrl(
        uri,
        mode: url_launcher.LaunchMode.externalApplication,
      );
    }
    try {
      await custom_tabs.launchUrl(
        uri,
        prefersDeepLink: false,
        customTabsOptions: custom_tabs.CustomTabsOptions(
          showTitle: true,
          closeButton: custom_tabs.CustomTabsCloseButton(
            icon: custom_tabs.CustomTabsCloseButtonIcons.back,
          ),
        ),
        safariVCOptions: const custom_tabs.SafariViewControllerOptions(
          dismissButtonStyle:
              custom_tabs.SafariViewControllerDismissButtonStyle.close,
        ),
      );
      return true;
    } on Object catch (error) {
      debugPrint('Could not launch Google Photos picker: $error');
      return false;
    }
  }

  Future<void> _closePicker() async {
    if (!_pickerOpen) return;
    _pickerOpen = false;
    try {
      final GooglePhotosUriCloser? closer = widget.uriCloser;
      if (closer != null) {
        await closer();
      } else if (Platform.isAndroid || Platform.isIOS) {
        await custom_tabs.closeCustomTabs();
        if (Platform.isAndroid) {
          // Some Android browsers place their Custom Tab in a separate task.
          // In that case closeCustomTabs cannot discover it, so explicitly
          // restore the host activity after the picking session completes.
          await GooglePhotosPlatform.returnToApp();
        }
      }
    } on Object catch (error) {
      debugPrint('Could not close Google Photos picker: $error');
    }
  }

  Future<void> _deleteCompletedSession(String sessionId) async {
    try {
      await widget.service.deleteSession(sessionId);
    } on Object catch (error) {
      // Cleanup must not discard media that was downloaded successfully.
      debugPrint('Google Photos session cleanup failed: $error');
    }
  }

  Uri _autocloseUri(Uri uri) {
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.last == 'autoclose') {
      return uri;
    }
    final String path =
        uri.path.endsWith('/')
            ? '${uri.path}autoclose'
            : '${uri.path}/autoclose';
    return uri.replace(path: path);
  }

  Future<void> _openPicker() async {
    final Uri? uri = _pickerUri;
    if (uri != null && await _launch(uri)) _pickerOpen = true;
  }

  void _retry() {
    setState(() {
      _error = null;
      _pickerUri = null;
      _phase = _PickerPhase.preparing;
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
      _phase = _PickerPhase.closing;
      _status = 'Closing Google Photos…';
    });
    await _closePicker();
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
