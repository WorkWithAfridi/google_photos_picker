import 'package:flutter_test/flutter_test.dart';
import 'package:google_photos_picker/google_photos_picker.dart';

void main() {
  test('parses picking sessions and Google duration values', () {
    final GooglePhotosPickingSession session =
        GooglePhotosPickingSession.fromJson(<String, Object?>{
          'id': 'session-1',
          'pickerUri': 'https://photos.google.com/picker/session-1',
          'mediaItemsSet': false,
          'pollingConfig': <String, Object?>{
            'pollInterval': '2.500s',
            'timeoutIn': '300s',
          },
          'expireTime': '2026-11-15T12:00:00Z',
        });

    expect(session.id, 'session-1');
    expect(
      session.pollingConfig?.pollInterval,
      const Duration(milliseconds: 2500),
    );
    expect(session.pollingConfig?.timeoutIn, const Duration(minutes: 5));
    expect(session.expireTime, DateTime.utc(2026, 11, 15, 12));
  });

  test('accepts a completed session without a picker URI', () {
    final GooglePhotosPickingSession session =
        GooglePhotosPickingSession.fromJson(<String, Object?>{
          'id': 'session-1',
          'mediaItemsSet': true,
        });

    expect(session.id, 'session-1');
    expect(session.mediaItemsSet, isTrue);
    expect(session.pickerUri, isNull);
  });

  test('parses selected photo metadata', () {
    final GooglePhotosMediaItem item = GooglePhotosMediaItem.fromJson(
      <String, Object?>{
        'id': 'photo-1',
        'type': 'PHOTO',
        'createTime': '2026-01-02T03:04:05Z',
        'mediaFile': <String, Object?>{
          'filename': 'IMG_0001.JPG',
          'mimeType': 'image/jpeg',
          'baseUrl': 'https://lh3.googleusercontent.com/photo',
          'mediaFileMetadata': <String, Object?>{'width': 4032, 'height': 3024},
        },
      },
    );

    expect(item.type, GooglePhotosMediaType.photo);
    expect(item.filename, 'IMG_0001.JPG');
    expect(item.width, 4032);
    expect(item.height, 3024);
  });

  test('validates the official selection limit', () {
    expect(() => GooglePhotosPickerOptions(maxItems: 0), throwsAssertionError);
    expect(
      () => GooglePhotosPickerOptions(maxItems: 2001),
      throwsAssertionError,
    );
    expect(const GooglePhotosPickerOptions(maxItems: 2000).maxItems, 2000);
  });
}
