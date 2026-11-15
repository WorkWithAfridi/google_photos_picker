/// Selection constraints applied to a Google Photos picking session.
final class GooglePhotosPickerOptions {
  const GooglePhotosPickerOptions({this.maxItems})
    : assert(
        maxItems == null || (maxItems > 0 && maxItems <= 2000),
        'maxItems must be between 1 and 2000.',
      );

  /// Maximum number of photos and videos the user may select.
  ///
  /// Google defaults this to 2,000 when omitted.
  final int? maxItems;
}
