import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_photos_picker/google_photos_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('creates a session with the configured maximum', () async {
    late http.Request captured;
    final GooglePhotosApiService service = GooglePhotosApiService(
      MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'id': 'session-1',
            'pickerUri': 'https://photos.google.com/picker/session-1',
          }),
          200,
        );
      }),
    );

    final GooglePhotosPickingSession session = await service.createSession(
      maxItemCount: 5,
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/v1/sessions');
    expect(jsonDecode(captured.body), <String, Object?>{
      'pickingConfig': <String, Object?>{'maxItemCount': '5'},
    });
    expect(session.id, 'session-1');
  });

  test('rejects invalid selection limits before making a request', () async {
    final GooglePhotosApiService service = GooglePhotosApiService(
      MockClient((_) async => throw StateError('Request should not be sent.')),
    );

    await expectLater(
      service.createSession(maxItemCount: 2001),
      throwsArgumentError,
    );
  });

  test('paginates selected media items', () async {
    final GooglePhotosApiService service = GooglePhotosApiService(
      MockClient((http.Request request) async {
        final String? pageToken = request.url.queryParameters['pageToken'];
        return http.Response(
          jsonEncode(<String, Object?>{
            'mediaItems': <Object?>[_item(pageToken == null ? 'one' : 'two')],
            if (pageToken == null) 'nextPageToken': 'next',
          }),
          200,
        );
      }),
    );

    final List<GooglePhotosMediaItem> items = await service.listMediaItems(
      'session-1',
    );

    expect(items.map((GooglePhotosMediaItem item) => item.id), <String>[
      'one',
      'two',
    ]);
  });

  test('uses the correct photo and video download parameters', () async {
    final List<Uri> requests = <Uri>[];
    final GooglePhotosApiService service = GooglePhotosApiService(
      MockClient((http.Request request) async {
        requests.add(request.url);
        return http.Response.bytes(<int>[1, 2, 3], 200);
      }),
    );
    final Directory directory = await Directory.systemTemp.createTemp(
      'google_photos_picker_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    await service.downloadMediaItem(
      GooglePhotosMediaItem.fromJson(_item('photo')),
      directory: directory,
    );
    final Map<String, Object?> video = _item('video');
    video['type'] = 'VIDEO';
    (video['mediaFile']! as Map<String, Object?>)['mimeType'] = 'video/mp4';
    await service.downloadMediaItem(
      GooglePhotosMediaItem.fromJson(video),
      directory: directory,
    );

    expect(requests[0].toString(), endsWith('=d'));
    expect(requests[1].toString(), endsWith('=dv'));
  });

  test('surfaces Google API error messages', () async {
    final GooglePhotosApiService service = GooglePhotosApiService(
      MockClient(
        (_) async => http.Response(
          '{"error":{"message":"Picker API is disabled"}}',
          403,
        ),
      ),
    );

    expect(
      () => service.createSession(),
      throwsA(
        isA<GooglePhotosApiException>().having(
          (GooglePhotosApiException error) => error.message,
          'message',
          'Picker API is disabled',
        ),
      ),
    );
  });
}

Map<String, Object?> _item(String id) => <String, Object?>{
  'id': id,
  'type': 'PHOTO',
  'mediaFile': <String, Object?>{
    'filename': '$id.jpg',
    'mimeType': 'image/jpeg',
    'baseUrl': 'https://lh3.googleusercontent.com/$id',
  },
};
