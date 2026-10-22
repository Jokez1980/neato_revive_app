# Neato Revive App

Flutter app for your Vacuula server (previously called "Vacuula app").

A mobile app (iPhone and Android) that controls your Neato through your own Vacuula server on your home network.

**Features**
- Start, pause/resume, stop, send to base and "Find me".
- Status and battery for all robots, using the same state names as the Vacuula web app. Refreshes every 10 seconds, or every 4 seconds while the robot is busy. Pull down to refresh right away.
- **Search network**: finds the Vacuula server automatically, even when mDNS does not work (for example Docker on a Mac).
- **Cleaning options** (tap the line under *Start cleaning*): where (Gen3: **Map** - respects no-go lines, **Whole house** or **Spot** with size; Gen4: floorplan or whole home), suction (Gen3: Eco/Turbo; Gen4: Auto/Eco/Turbo/Max) and navigation (Gen3: Normal/Extra care/Deep; Gen4: Normal/Gentle). Your choice is remembered. Note: *Whole house* ignores no-go lines - use *Map* for that.
- **Maps**: view your robot's maps, rename them, switch them on/off, start mapping a new one. Draw **no-go lines**, **no-go areas** and **cleaning zones** with your finger, change or delete them, switch them off and on, and clean a single zone. Changes are saved to the robot/server right away, exactly like the Vacuula web app.
- **Remote control** (D3–D7, experimental): drive the robot with arrows on the phone.
- **Schedule**: see, add, change and delete scheduled cleanings - days, time, cleaning mode and (optionally) a zone. Gen3 schedules can be switched on/off as a whole; Gen4 events one by one.
- **Notifications (Android)** when a robot starts, recharges mid-clean, pauses, finishes, needs help (stuck, picked up, brush, dust bin) or goes offline. Turn on in Settings > Notifications.
- Light and dark mode. Its own app icon (a robot vacuum with a "revive" arrow).

## Download and install on Android

**Just want to use the app?** You don't need to build anything. The latest Android version (APK file) is in the folder
**[latest_app_release_to_download](https://github.com/Jokez1980/vacuula_app/tree/main/latest_app_release_to_download)** in this project.

You need Android 7.0 or newer, a [Vacuula server](https://github.com/vacuula/vacuula) on your home network with your robot already set up, and your phone on the same Wi-Fi. **No Developer mode or USB debugging is needed.**

1. **Download:** on your phone, open the [latest_app_release_to_download](https://github.com/Jokez1980/vacuula_app/tree/main/latest_app_release_to_download) folder, tap the `.apk` file and then the **download** button (the arrow ↓ at the top right of the file view, or *Download raw file* in the ⋯ menu).
2. **Open it:** tap the downloaded file in the browser's downloads or in the *Files* app.
3. **Allow the install:** Android says this source isn't allowed to install apps. Tap **Settings**, turn on **Allow from this source**, then go back. (You can switch it off again afterwards under *Settings → Apps → Special app access → Install unknown apps*.)
4. **Install:** tap **Install**. If Google Play Protect warns you, tap **More details → Install anyway** – the warning only appears because the app isn't from Google Play.
5. **Connect to your server:** open the app and tap **Search network**. If nothing is found, type your server's IP address (for example `192.168.1.50` – the same address you use for the Vacuula web page). Tap **Test**, then **Save**.
6. **Notifications (optional):** in the app go to **Settings → Notifications → Notify me** and allow notifications. Then set *Android Settings → Apps → Vacuula → Battery* to **Unrestricted** so Android doesn't stop it.

**Updating:** download the newest APK from the same folder and install it on top of the old one – your settings are kept. If Android says *"App not installed"*, uninstall the old app first.

More details, phone-specific battery tips and troubleshooting: **[INSTALL-ANDROID.md](INSTALL-ANDROID.md)**.

## Build and install (on your Mac)

1. Install Flutter: https://docs.flutter.dev/get-started/install/macos
   - For iPhone you also need **Xcode** from the App Store.
   - For Android you need **Android Studio**.
2. Unzip the project and run the setup script in Terminal:
   ```
   cd vacuula_app
   ./setup.sh
   ```
   The script creates the iOS and Android parts, allows the app to talk plain http to the server on your home network, and generates the app icon.
3. Connect your phone with a cable and run:
   ```
   flutter run --release --dart-define=VACUULA_SERVER=192.168.1.250
   ```
   Change the address to your server's. You can leave out `--dart-define=…` and enter the address in the app instead.

**iPhone:** The first time, open `ios/Runner.xcworkspace` in Xcode, go to *Runner → Signing & Capabilities → Team* and choose your Apple ID (free). Also enable **Developer Mode** on the phone under Settings → Privacy & Security.

With a free Apple ID the app stops working after 7 days; just run `flutter run --release` again. With a paid developer account, or via TestFlight, it lasts a year.

**Android:** Enable USB debugging on the phone to run it from your Mac.

**Sharing with testers (APK):** run `./build_apk.sh`. It builds `dist/neato-revive-<version>.apk` and prints its SHA-256. Put it in `latest_app_release_to_download/` (remove the old APK) and commit, or send the APK together with **INSTALL-ANDROID.md** (installation guide for testers - they do *not* need Developer mode). Don't build shared APKs with `--dart-define=VACUULA_SERVER=...`; testers find their own server with *Search network*. Bump `version:` in `pubspec.yaml` before each new build, and build on the same Mac so updates install on top of the old version.

## First start
If no address was built in, the app opens Settings. Tap **Search network**, or type the server's IP address (for example `192.168.1.250`). Tap **Test**, then **Save**.

On iPhone the app asks for local network access. Choose **Allow**. If you said no, change it later under Settings → Privacy & Security → Local Network.

## Notifications (Android)
Turn on **Settings > Notifications > Notify me** and allow notifications when Android asks.
A background watcher then checks your robots every 15 seconds (every 5 while they work), also when the app is closed and after a reboot. Android shows a small, silent "Watching your robots" notification while it runs - that is required for background work.

- It works while the phone can reach the server: on the home network or through a VPN. Away from home it waits quietly and checks once a minute.
- For reliability, set *Android settings > Apps > Neato Revive App > Battery* to **Unrestricted**.
- You can mute the categories separately under *Android settings > Apps > Neato Revive App > Notifications*: "Robot status", "Robot needs help" and "Background watcher".

Built with the Flutter plugins `flutter_background_service` and `flutter_local_notifications`; `setup.sh` adds the Android permissions and settings they need (`android_extra/patch_android.py`). On iPhone, apps cannot keep running in the background like this, so the switch is hidden there.

## Maps
Tap **Maps, no-go lines & zones** on a robot card and pick a map.
- Pinch to zoom, drag to move. Tap a line or zone to select it (Edit / Delete).
- **Add**: tap the map to place points. **Done** with 2+ points makes a no-go line; tap the first point (or **Close**) to close the shape and choose **Cleaning zone** or **No-go area/zone**.
- Gen3 (D3-D7) stores no-go lines and zones on the robot itself, so it must be connected while you edit.
- Gen3 robots have no real no-go zones, so a **no-go area** is saved as a no-go line that goes all the way around the area (the same thing you could draw by hand). Make sure the robot's base is outside it.
- Gen4 (D8-D10): zones are cleaning zones or no-go zones; the floorplan in use is updated automatically.

## Schedule
Tap **Schedule** on a robot card (the robot must be online - the schedule lives on the robot).
- **+ Add**: pick one or more days, a time, the cleaning mode and optionally a zone. Picking several days creates one cleaning per day.
- Tap a cleaning to change or delete it.
- Gen3: the switch at the top turns the whole schedule on/off. The robot keeps times in UTC; the app shows and edits them in your phone's time zone. After a daylight saving change the times move by an hour - edit them again if needed.
- Gen4: each cleaning has its own on/off switch; you can choose navigation mode and, with a floorplan in use, one or more zones.

## Remote control (D3–D7, experimental)
Botvac Connected and D3–D7 robots that support it get a **Drive** button on their card. It works like the remote control in the old Neato app: hold an arrow to move, let go to stop. You can also switch the brush, the vacuum and Eco on and off.

The app talks **directly to the robot** for this, so the phone must be on the same Wi-Fi as the robot. The robot only accepts a connection that is signed with its secret key. The Vacuula server knows the key, and you copy it into the app once. Run this on the computer with Vacuula, in the folder with its `docker-compose.yaml`:

```bash
docker compose exec vacuula python -c "import sqlite3; [print(r[0], r[1]) for r in sqlite3.connect('/server/data/vacuula.db').execute('select robot, password from gen3__data')]"
```

**Windows 11:** the same command works in PowerShell. In File Explorer, open the folder with Vacuula's `docker-compose.yaml`, right-click inside it and choose *Open in Terminal*, then paste the command. Make sure Docker Desktop is running.

If it doesn't work:
- *"no configuration file provided"* or *"service vacuula is not running"*: you are in the wrong folder, or the service has another name. Run `docker ps`, find the Vacuula container name in the last column, and use `docker exec <container-name> python -c "..."` with the same part in quotes.
- No lines are printed: the robot is not a Gen3 model (Botvac Connected, D3–D7), or it hasn't been set up with the Vacuula server yet.

The command prints `serial key` for each Gen3 robot. Paste the key for your robot into the app; the app stores it only on the phone. The robot must be idle (not cleaning). It leaves remote control by itself after about 30 seconds without commands.

This has been tested against a simulated robot, not yet against a real D7. If it doesn't connect, please report what the app shows.

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
- `lib/map/map_models.dart`: maps, map grid (RLE decoding), boundaries and the map API calls.
- `lib/map/map_painter.dart`: draws the map, zones, lines and the base.
- `lib/screens/maps_screen.dart`, `lib/screens/map_editor_screen.dart`: map list and editor.
- `lib/schedule/schedule_models.dart`, `lib/screens/schedule_screen.dart`: schedule commands (Gen3/Gen4), UTC conversion and the schedule screen.
- `lib/manual/manual_drive.dart`, `lib/screens/manual_screen.dart`: remote control (signed websocket straight to the robot).
- `lib/problems.dart`: texts for error codes, same wording as the Vacuula web app.
- `lib/widgets/robot_card.dart`: the card for each robot.
- `assets/`: app icon and in-app logo (original artwork - not the Vacuula or Neato logos).
