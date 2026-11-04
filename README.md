# SignCraft Player

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Flutter 3.38+](https://img.shields.io/badge/flutter-3.38%2B-blue.svg)

The display app for SignCraft, a digital signage system. It runs on an Android device connected to a screen, registers itself with the SignCraft backend, downloads the videos scheduled for that screen and plays them full screen at the right time.

Content is created and scheduled in the [SignCraft web app](https://github.com/DevByError/signcraft-frontend) and served by the [SignCraft backend](https://github.com/DevByError/signcraft-backend). This app only plays it.

## Features

- One-time setup: enter the screen ID shown in the web app's Screens page
- Live connection to the backend over Socket.IO, with an online indicator in the corner
- Pulls the screen's schedule when it starts and whenever the backend sends `refresh_content`
- Downloads each scheduled video to local storage before playing it, so playback does not depend on the network
- Checks the schedule every 5 seconds and switches content when a new time slot starts
- Landscape, full-screen immersive mode

## Hardware

| Component | Model | Purpose |
| --- | --- | --- |
| Player device | Any Android TV box, stick or tablet (Android 7.0 or newer) | Runs this app |
| Display | Any TV or monitor with HDMI | Shows the content |
| Network | Wi-Fi or Ethernet | Reaches the backend and the S3 bucket |
| Input | USB keyboard or TV remote with a text field | Entering the screen ID once during setup |

Recommended: 2 GB RAM or more, enough free storage for the scheduled videos, and hardware decoding for 1080p H.264, since the backend renders content as 1920x1080 MP4 by default.

The project also builds for Windows, macOS, Linux and iOS from the standard Flutter scaffolding, but only Android has been used in practice.

## How it works

```
Web app: user deploys a playlist to a screen
   -> Backend records the playlist to MP4, uploads it to S3, saves a schedule row
   -> Backend emits refresh_content to the screen's Socket.IO room
   -> Player calls GET /design/getscreencontent?screenId=<id>
   -> Player downloads any new videos to local storage
   -> Player plays the video whose start and end time cover the current time
```

## Requirements

- Flutter 3.38 or newer (Dart 3.10)
- Android SDK and either a device or an emulator
- A running SignCraft backend that the device can reach

## Installation

```bash
git clone https://github.com/DevByError/android-screen.git
cd android-screen
flutter pub get
```

## Configuration

The backend address is set at build time with `--dart-define`:

| Setting | Default | Description |
| --- | --- | --- |
| `SERVER_URL` | `http://10.0.2.2:5000` on Android, `http://localhost:5000` elsewhere | Base URL of the SignCraft backend. `10.0.2.2` is the host machine as seen from the Android emulator. |

For a real device, use the LAN address of the machine running the backend:

```bash
flutter run --dart-define=SERVER_URL=http://192.168.1.20:5000
```

The app allows plain HTTP (`usesCleartextTraffic`) so it works with a local backend. Use HTTPS in production.

## Usage

```bash
flutter run                                   # debug build on the connected device
flutter build apk --release --dart-define=SERVER_URL=http://<host>:5000
flutter test                                  # widget tests
flutter analyze                               # static analysis
```

Install the APK from `build/app/outputs/flutter-apk/app-release.apk`. On first launch, enter the screen ID from the web app and press Connect. The app then waits for scheduled content.

## Project structure

```
lib/main.dart      The whole app: socket manager, setup screen and player
test/              Widget tests
android/           Android project (manifest, Gradle files, launcher icons)
ios/ macos/ linux/ windows/ web/   Generated Flutter platform projects
```

## Troubleshooting

- **The button stays on "Connecting...".** Either the device cannot reach `SERVER_URL`, or the screen ID does not match an active screen in the web app. Open the URL in the device's browser to check the connection, and make sure the backend port is open on the host firewall. The app does not yet show the reason, so check the backend log for "Invalid Screen ID".
- **Stuck on "Waiting for scheduled content".** Nothing is scheduled for the current time, or the video download failed. Check the schedule in the web app and the device's network access to S3.
- **Video is stretched.** The player scales video to fill the screen. Design content at the display's aspect ratio.

## Roadmap

- Save the screen ID so the player reconnects automatically after a reboot
- Start automatically on boot
- Delete cached videos that are no longer scheduled
- Show a clear message when registration fails

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgements

Built with Flutter, socket_io_client, video_player, dio and path_provider.
