import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'google_photos_models.dart';

/// A failure returned by the Google Photos Picker API.
class GooglePhotosApiException implements Exception {
  const GooglePhotosApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'GooglePhotosApiException: $message';
}

/// A failure to obtain Google Photos authorization.
class GooglePhotosAuthorizationException implements Exception {
  const GooglePhotosAuthorizationException([
    this.message = 'Google Photos authorization was not granted.',
  ]);

  final String message;

  @override
  String toString() => 'GooglePhotosAuthorizationException: $message';
}

/// Operations used by the picker flow.
abstract interface class GooglePhotosService {
  Future<GooglePhotosPickingSession> createSession({int? maxItemCount});

  Future<GooglePhotosPickingSession> getSession(String sessionId);

  Future<List<GooglePhotosMediaItem>> listMediaItems(String sessionId);

  Future<File> downloadMediaItem(
    GooglePhotosMediaItem item, {
    Directory? directory,
  });

  Future<void> deleteSession(String sessionId);
}

/// REST implementation of the Google Photos Picker API.
class GooglePhotosApiService implements GooglePhotosService {
  GooglePhotosApiService(http.Client client) : _client = client;

  static final Uri _sessionsUri = Uri.parse(
    'https://photospicker.googleapis.com/v1/sessions',
  );
  static final Uri _mediaItemsUri = Uri.parse(
    'https://photospicker.googleapis.com/v1/mediaItems',
  );

  final http.Client _client;

  @override
  Future<GooglePhotosPickingSession> createSession({int? maxItemCount}) async {
    final Map<String, Object?> body = <String, Object?>{};
    if (maxItemCount != null) {
      body['pickingConfig'] = <String, String>{
        'maxItemCount': maxItemCount.toString(),
      };
    }
    final http.Response response = await _client.post(
      _sessionsUri,
      headers: const <String, String>{'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    return GooglePhotosPickingSession.fromJson(_decode(response));
  }

  @override
  Future<GooglePhotosPickingSession> getSession(String sessionId) async {
    final http.Response response = await _client.get(
      _sessionsUri.replace(path: '${_sessionsUri.path}/$sessionId'),
    );
    return GooglePhotosPickingSession.fromJson(_decode(response));
  }

  @override
  Future<List<GooglePhotosMediaItem>> listMediaItems(String sessionId) async {
    final List<GooglePhotosMediaItem> items = <GooglePhotosMediaItem>[];
    String? pageToken;
    do {
      final Uri uri = _mediaItemsUri.replace(
        queryParameters: <String, String>{
          'sessionId': sessionId,
          'pageSize': '100',
          if (pageToken != null) 'pageToken': pageToken,
        },
      );
      final Map<String, Object?> json = _decode(await _client.get(uri));
      final Object? mediaItems = json['mediaItems'];
      if (mediaItems is List<Object?>) {
        for (final Object? value in mediaItems) {
          if (value is Map<String, Object?>) {
            items.add(GooglePhotosMediaItem.fromJson(value));
          }
        }
      }
      pageToken = json['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return List<GooglePhotosMediaItem>.unmodifiable(items);
  }

  @override
  Future<File> downloadMediaItem(
    GooglePhotosMediaItem item, {
    Directory? directory,
  }) async {
    if (item.type == GooglePhotosMediaType.video &&
        item.videoProcessingStatus != null &&
        item.videoProcessingStatus != 'READY') {
      throw GooglePhotosApiException(
        '${item.filename} is not ready to download.',
      );
    }
    final String suffix =
        item.type == GooglePhotosMediaType.video ||
                item.mimeType.startsWith('video/')
            ? 'dv'
            : 'd';
    final Uri downloadUri = Uri.parse('${item.baseUrl}=$suffix');
    final http.Response response = await _client.get(downloadUri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFor(response);
    }

    final Directory destination = directory ?? await getTemporaryDirectory();
    await destination.create(recursive: true);
    final String safeName = _safeFilename(item.filename);
    final File output = await _availableFile(destination, safeName);
    return output.writeAsBytes(
      Uint8List.fromList(response.bodyBytes),
      flush: true,
    );
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    final http.Response response = await _client.delete(
      _sessionsUri.replace(path: '${_sessionsUri.path}/$sessionId'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFor(response);
    }
  }

  Map<String, Object?> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFor(response);
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Google Photos returned invalid JSON.');
    }
    return decoded;
  }

  GooglePhotosApiException _exceptionFor(http.Response response) {
    String message = 'Google Photos request failed (${response.statusCode}).';
    try {
      final Object? decoded = jsonDecode(response.body);
      if (decoded is Map<String, Object?>) {
        final Object? error = decoded['error'];
        if (error is Map<String, Object?> && error['message'] is String) {
          message = error['message']! as String;
        }
      }
    } on FormatException {
      // Keep the status-based fallback for non-JSON responses.
    }
    return GooglePhotosApiException(message, statusCode: response.statusCode);
  }

  String _safeFilename(String filename) {
    final String basename = path.basename(filename.trim());
    final String sanitized = basename.replaceAll(
      RegExp(r'[\\/:*?"<>|\x00-\x1F]'),
      '_',
    );
    return sanitized.isEmpty ? 'google-photo' : sanitized;
  }

  Future<File> _availableFile(Directory directory, String filename) async {
    File candidate = File(path.join(directory.path, filename));
    if (!await candidate.exists()) return candidate;
    final String extension = path.extension(filename);
    final String stem = path.basenameWithoutExtension(filename);
    for (int index = 2; ; index++) {
      candidate = File(path.join(directory.path, '$stem ($index)$extension'));
      if (!await candidate.exists()) return candidate;
    }
  }
}
