enum GooglePhotosMediaType { photo, video, unspecified }

/// Google Photos' recommended polling behavior for a picking session.
final class GooglePhotosPollingConfig {
  const GooglePhotosPollingConfig({this.pollInterval, this.timeoutIn});

  final Duration? pollInterval;
  final Duration? timeoutIn;

  factory GooglePhotosPollingConfig.fromJson(Map<String, Object?> json) {
    return GooglePhotosPollingConfig(
      pollInterval: _parseGoogleDuration(json['pollInterval'] as String?),
      timeoutIn: _parseGoogleDuration(json['timeoutIn'] as String?),
    );
  }
}

/// A server-side Google Photos picking session.
final class GooglePhotosPickingSession {
  const GooglePhotosPickingSession({
    required this.id,
    required this.pickerUri,
    required this.mediaItemsSet,
    this.pollingConfig,
    this.expireTime,
  });

  final String id;
  final Uri pickerUri;
  final bool mediaItemsSet;
  final GooglePhotosPollingConfig? pollingConfig;
  final DateTime? expireTime;

  factory GooglePhotosPickingSession.fromJson(Map<String, Object?> json) {
    final String? id = json['id'] as String?;
    final String? pickerUri = json['pickerUri'] as String?;
    if (id == null || pickerUri == null) {
      throw const FormatException(
        'Google Photos returned a session without an ID or picker URI.',
      );
    }
    final Object? pollingConfig = json['pollingConfig'];
    return GooglePhotosPickingSession(
      id: id,
      pickerUri: Uri.parse(pickerUri),
      mediaItemsSet: json['mediaItemsSet'] as bool? ?? false,
      pollingConfig:
          pollingConfig is Map<String, Object?>
              ? GooglePhotosPollingConfig.fromJson(pollingConfig)
              : null,
      expireTime: DateTime.tryParse(json['expireTime'] as String? ?? ''),
    );
  }
}

/// A photo or video explicitly shared through the Google Photos picker.
final class GooglePhotosMediaItem {
  const GooglePhotosMediaItem({
    required this.id,
    required this.type,
    required this.baseUrl,
    required this.filename,
    required this.mimeType,
    this.createTime,
    this.width,
    this.height,
    this.videoProcessingStatus,
  });

  final String id;
  final GooglePhotosMediaType type;
  final Uri baseUrl;
  final String filename;
  final String mimeType;
  final DateTime? createTime;
  final int? width;
  final int? height;
  final String? videoProcessingStatus;

  factory GooglePhotosMediaItem.fromJson(Map<String, Object?> json) {
    final Object? mediaFileValue = json['mediaFile'];
    if (mediaFileValue is! Map<String, Object?>) {
      throw const FormatException(
        'Google Photos returned an item without media file data.',
      );
    }
    final String? id = json['id'] as String?;
    final String? baseUrl = mediaFileValue['baseUrl'] as String?;
    if (id == null || baseUrl == null) {
      throw const FormatException(
        'Google Photos returned an item without an ID or base URL.',
      );
    }
    final Object? metadataValue = mediaFileValue['mediaFileMetadata'];
    final Map<String, Object?> metadata =
        metadataValue is Map<String, Object?>
            ? metadataValue
            : const <String, Object?>{};
    final Object? videoValue = metadata['videoMetadata'];
    final Map<String, Object?> video =
        videoValue is Map<String, Object?>
            ? videoValue
            : const <String, Object?>{};
    return GooglePhotosMediaItem(
      id: id,
      type: switch (json['type']) {
        'PHOTO' => GooglePhotosMediaType.photo,
        'VIDEO' => GooglePhotosMediaType.video,
        _ => GooglePhotosMediaType.unspecified,
      },
      baseUrl: Uri.parse(baseUrl),
      filename: mediaFileValue['filename'] as String? ?? 'google-photo',
      mimeType:
          mediaFileValue['mimeType'] as String? ?? 'application/octet-stream',
      createTime: DateTime.tryParse(json['createTime'] as String? ?? ''),
      width: (metadata['width'] as num?)?.toInt(),
      height: (metadata['height'] as num?)?.toInt(),
      videoProcessingStatus: video['processingStatus'] as String?,
    );
  }
}

Duration? _parseGoogleDuration(String? value) {
  if (value == null) return null;
  final Match? match = RegExp(
    r'^(-?)(\d+)(?:\.(\d{1,9}))?s$',
  ).firstMatch(value);
  if (match == null) return null;
  final int seconds = int.parse(match.group(2)!);
  final String fraction = (match.group(3) ?? '').padRight(9, '0');
  final int microseconds =
      fraction.isEmpty ? 0 : int.parse(fraction.substring(0, 6));
  final Duration duration = Duration(
    seconds: seconds,
    microseconds: microseconds,
  );
  return match.group(1) == '-' ? -duration : duration;
}
