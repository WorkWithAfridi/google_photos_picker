import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_photos_picker/google_photos_picker.dart';

void main() {
  testWidgets('opens the hosted picker and cleans up a completed session', (
    WidgetTester tester,
  ) async {
    final _ReadyService service = _ReadyService();
    Uri? launchedUri;

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

    expect(launchedUri, Uri.parse('https://photos.google.com/picker/abc'));
    expect(service.maxItemCount, 3);
    expect(service.deletedSession, 'abc');
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
