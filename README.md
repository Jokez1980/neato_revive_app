# Vacuula – Flutter app for your Vacuula server

A mobile app (iPhone and Android) that controls your Neato through your own Vacuula server on your home network.

**Features**
- Start, pause/resume, stop, send to base and "Find me".
- Status and battery for all robots, using the same state names as the Vacuula web app. Refreshes every 10 seconds, or every 4 seconds while the robot is busy. Pull down to refresh right away.
- **Search network**: finds the Vacuula server automatically, even when mDNS does not work (for example Docker on a Mac).
- Cleaning mode per generation: Gen3 Normal/Eco, Gen4 Auto/Eco/Turbo/Max.
- **Notifications (Android)** when a robot starts, recharges mid-clean, pauses, finishes, needs help (stuck, picked up, brush, dust bin) or goes offline. Turn on in Settings > Notifications.
- Light and dark mode. App icon made from the Vacuula logo.

## Build and install (on your Mac)

1. Install Flutter: https://docs.flutter.dev/get-started/install/macos
   - For iPhone you also need **Xcode** from the App Store.
   - For Android you need **Android Studio**.
2. Unzip the project and run the setup script in Terminal:
   ```
   cd vacuula_app
   ./setup.sh
   ```
   The script creates the iOS and Android parts, allows the app to talk plain http to the server on your home network, and generates the app icon from the Vacuula logo.
3. Connect your phone with a cable and run:
   ```
   flutter run --release --dart-define=VACUULA_SERVER=192.168.1.250
   ```
   Change the address to your server's. You can leave out `--dart-define=…` and enter the address in the app instead.

**iPhone:** The first time, open `ios/Runner.xcworkspace` in Xcode, go to *Runner → Signing & Capabilities → Team* and choose your Apple ID (free). Also enable **Developer Mode** on the phone under Settings → Privacy & Security.

With a free Apple ID the app stops working after 7 days; just run `flutter run --release` again. With a paid developer account, or via TestFlight, it lasts a year.

**Android:** Enable USB debugging on the phone. You can also build an installable file with `flutter build apk --release`. It ends up in `build/app/outputs/flutter-apk/app-release.apk` and can be sent to the phone.

## First start
If no address was built in, the app opens Settings. Tap **Search network**, or type the server's IP address (for example `192.168.1.250`). Tap **Test**, then **Save**.

On iPhone the app asks for local network access. Choose **Allow**. If you said no, change it later under Settings → Privacy & Security → Local Network.

## Notifications (Android)
Turn on **Settings > Notifications > Notify me** and allow notifications when Android asks.
A background watcher then checks your robots every 15 seconds (every 5 while they work), also when the app is closed and after a reboot. Android shows a small, silent "Watching your robots" notification while it runs - that is required for background work.

- It works while the phone can reach the server: on the home network or through a VPN. Away from home it waits quietly and checks once a minute.
- For reliability, set *Android settings > Apps > Vacuula > Battery* to **Unrestricted**.
- You can mute the categories separately under *Android settings > Apps > Vacuula > Notifications*: "Robot status", "Robot needs help" and "Background watcher".

Built with the Flutter plugins `flutter_background_service` and `flutter_local_notifications`; `setup.sh` adds the Android permissions and settings they need (`android_extra/patch_android.py`). On iPhone, apps cannot keep running in the background like this, so the switch is hidden there.

## Away from home
Vacuula has no login, so never expose its port to the internet. Use a VPN into your home network instead, for example Tailscale (free), and enter the server's Tailscale address (100.x.x.x) in the app.

## Project layout
- `lib/api.dart`: client for the Vacuula API, using the same commands as the Vacuula web app.
- `lib/discovery.dart`: searches the home network for the server.
- `lib/settings.dart`: settings, stored in a small JSON file (no plugins).
- `lib/screens/`: home screen and settings.
- `lib/watch.dart`: turns the background watcher on/off.
- `lib/watcher/background.dart`: the background watcher (polls the server, posts notifications).
- `lib/watcher/robot_events.dart`: decides which status changes deserve a notification (tested in `test/robot_events_test.dart`).
- `lib/problems.dart`: texts for error codes, same wording as the Vacuula web app.
- `lib/widgets/robot_card.dart`: the card for each robot.
- `assets/`: the Vacuula logo and app icon images. To use the red icon instead, change `icon_light.png` to `icon_red.png` and `#ECEAE6` to `#8E0D24` in `pubspec.yaml`, then run `dart run flutter_launcher_icons`.
