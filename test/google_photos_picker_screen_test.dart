import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_photos_picker/google_photos_picker.dart';
import 'package:http/http.dart' as http;

void main() {
  testWidgets('opens the hosted picker and cleans up a completed session', (
    WidgetTester tester,
  ) async {
    final _ReadyService service = _ReadyService();
    Uri? launchedUri;
    int closeCount = 0;
    int monitorStartCount = 0;
    int monitorStopCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (BuildContext context) => FilledButton(
                onPressed: () {
                  Navigator.of(context).push<List<File>>(
                    MaterialPageRoute<List<File>>(
                      builder:
                          (_) => GooglePhotosPickerScreen(
                            service: service,
                            options: const GooglePhotosPickerOptions(
                              maxItems: 3,
                            ),
                            uriLauncher: (Uri uri) async {
                              launchedUri = uri;
                              return true;
                            },
                            uriCloser: () async => closeCount++,
                            sessionMonitorStarter: (_) async {
                              monitorStartCount++;
                            },
                            sessionMonitorStopper: () async {
                              monitorStopCount++;
                            },
                          ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      launchedUri,
      Uri.parse('https://photos.google.com/picker/abc/autoclose'),
    );
    expect(service.maxItemCount, 3);
    expect(service.deletedSession, 'abc');
    expect(closeCount, 1);
    expect(monitorStartCount, 1);
    expect(monitorStopCount, 1);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('shows a useful API failure and retry action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GooglePhotosPickerScreen(
          service: _FailingService(),
          uriLauncher: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t open Google Photos'), findsOneWidget);
    expect(find.text('Picker API is disabled.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('returns a completed result when session cleanup fails', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (BuildContext context) => FilledButton(
                onPressed: () {
                  Navigator.of(context).push<List<File>>(
                    MaterialPageRoute<List<File>>(
                      builder:
                          (_) => GooglePhotosPickerScreen(
                            service: _FailingCleanupService(),
                            uriLauncher: (_) async => true,
                            uriCloser: () async {},
                          ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Couldn’t open Google Photos'), findsNothing);
  });

  testWidgets('hides the reopen action while downloading', (
    WidgetTester tester,
  ) async {
    final _DownloadingService service = _DownloadingService();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (BuildContext context) => FilledButton(
                onPressed: () {
                  Navigator.of(context).push<List<File>>(
                    MaterialPageRoute<List<File>>(
                      builder:
                          (_) => GooglePhotosPickerScreen(
                            service: service,
                            uriLauncher: (_) async => true,
                            uriCloser: () async {},
                          ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Downloading selected media'), findsOneWidget);
    expect(find.text('0 of 1'), findsOneWidget);
    expect(find.text('Open Google Photos again'), findsNothing);

    service.download.complete(File('downloaded.jpg'));
    await tester.pumpAndSettle();
  });

  testWidgets('keeps polling after a transient network failure', (
    WidgetTester tester,
  ) async {
    final _TransientPollingService service = _TransientPollingService();

    await tester.pumpWidget(
      MaterialApp(
        home: GooglePhotosPickerScreen(
          service: service,
          uriLauncher: (_) async => true,
          uriCloser: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.pollCount, 2);
    expect(service.deletedSession, 'abc');
    expect(find.text('Couldn’t open Google Photos'), findsNothing);
  });

  testWidgets('retries when a background poll hangs', (
    WidgetTester tester,
  ) async {
    final _HangingPollingService service = _HangingPollingService();

    await tester.pumpWidget(
      MaterialApp(
        home: GooglePhotosPickerScreen(
          service: service,
          uriLauncher: (_) async => true,
          uriCloser: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.pollCount, 2);
    expect(service.deletedSession, 'abc');
    expect(find.text('Couldn’t open Google Photos'), findsNothing);
  });
}

class _ReadyService implements GooglePhotosService {
  int? maxItemCount;
  String? deletedSession;

  @override
  Future<GooglePhotosPickingSession> createSession({int? maxItemCount}) async {
    this.maxItemCount = maxItemCount;
    return GooglePhotosPickingSession(
      id: 'abc',
      pickerUri: Uri.parse('https://photos.google.com/picker/abc'),
      mediaItemsSet: true,
    );
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    deletedSession = sessionId;
  }

  @override
  Future<File> downloadMediaItem(
    GooglePhotosMediaItem item, {
    Directory? directory,
  }) => throw UnimplementedError();

  @override
  Future<GooglePhotosPickingSession> getSession(String sessionId) =>
      throw UnimplementedError();

  @override
  Future<List<GooglePhotosMediaItem>> listMediaItems(String sessionId) async =>
      <GooglePhotosMediaItem>[];
}

class _FailingService extends _ReadyService {
  @override
  Future<GooglePhotosPickingSession> createSession({int? maxItemCount}) {
    throw const GooglePhotosApiException('Picker API is disabled.');
  }
}

class _FailingCleanupService extends _ReadyService {
  @override
  Future<void> deleteSession(String sessionId) {
    throw const GooglePhotosApiException('Cleanup failed.', statusCode: 500);
  }
}

class _DownloadingService extends _ReadyService {
  final Completer<File> download = Completer<File>();

  @override
  Future<List<GooglePhotosMediaItem>> listMediaItems(String sessionId) async {
    return <GooglePhotosMediaItem>[
      GooglePhotosMediaItem(
        id: 'photo-1',
        type: GooglePhotosMediaType.photo,
        baseUrl: Uri.parse('https://example.com/photo-1'),
        filename: 'photo-1.jpg',
        mimeType: 'image/jpeg',
      ),
    ];
  }

  @override
  Future<File> downloadMediaItem(
    GooglePhotosMediaItem item, {
    Directory? directory,
  }) {
    return download.future;
  }
}

class _TransientPollingService extends _ReadyService {
  int pollCount = 0;

  @override
  Future<GooglePhotosPickingSession> createSession({int? maxItemCount}) async {
    return GooglePhotosPickingSession(
      id: 'abc',
      pickerUri: Uri.parse('https://photos.google.com/picker/abc'),
      mediaItemsSet: false,
      pollingConfig: const GooglePhotosPollingConfig(
        pollInterval: Duration.zero,
        timeoutIn: Duration(seconds: 5),
      ),
    );
  }

  @override
  Future<GooglePhotosPickingSession> getSession(String sessionId) async {
    pollCount++;
    if (pollCount == 1) {
      throw http.ClientException('Temporary DNS failure');
    }
    return GooglePhotosPickingSession(id: sessionId, mediaItemsSet: true);
  }
}

class _HangingPollingService extends _TransientPollingService {
  @override
  Future<GooglePhotosPickingSession> getSession(String sessionId) {
    pollCount++;
    if (pollCount == 1) {
      return Completer<GooglePhotosPickingSession>().future;
    }
    return Future<GooglePhotosPickingSession>.value(
      GooglePhotosPickingSession(id: sessionId, mediaItemsSet: true),
    );
  }
}
