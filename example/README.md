# Google Photos Picker example

Enable the Google Photos Picker API and configure the platform OAuth clients
described in the package README, then run with the appropriate public client
ID:

```sh
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

On iOS or macOS use `GOOGLE_CLIENT_ID` for the platform client ID and configure
the reversed client ID URL scheme in the relevant `Info.plist`.
