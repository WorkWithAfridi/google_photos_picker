## 1.0.0

- Stabilize the Google Photos Picker API after initial testing.
- Automatically return to the app after selection on Android and iOS.
- Add resilient session polling, streamed media downloads, and best-effort
  session cleanup.
- Document Android, iOS, and macOS setup, OAuth configuration, and usage.

## 0.1.0

- Initial Google Photos Picker API integration.
- Added Google Sign-In OAuth, hosted picker sessions, recommended polling,
  paginated media retrieval, photo/video downloads, and session cleanup.
- Added single/multiple selection APIs, progress and retry UI, tests, example,
  and platform setup documentation.
- Added an Android background session monitor so completed Chrome Custom Tabs
  return to the host app automatically, including on aggressive OEM firmware.
- Streamed downloads to disk and made completed-session cleanup best-effort.
