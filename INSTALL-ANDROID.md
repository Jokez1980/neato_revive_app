# Neato Revive App – installing the test version on Android

Neato Revive App is an app for controlling a Neato robot vacuum through your own **Vacuula server** (https://github.com/vacuula/vacuula). It lets you start/stop cleaning, see status and battery, edit maps, no-go lines and zones, and get notifications.

This is a test version that is not on Google Play, so you install it from an APK file. **You do not need Developer mode or USB debugging** – that is only for developers building the app.

## What you need

- An Android phone with **Android 7.0 or newer**.
- A **Vacuula server** running on your home network, with your robot already set up using the Vacuula installer.
- Your phone on the **same Wi-Fi** as the server (or connected to your home network through a VPN, see below).

## 1. Install the app

1. Get the file **`neato-revive-x.y.z.apk`** on your phone. The latest version is in the folder [latest_app_release_to_download](https://github.com/Jokez1980/vacuula_app/tree/main/latest_app_release_to_download): open it on your phone, tap the `.apk` file and then the **download** button (↓). You can also get it by e-mail, chat, Google Drive or USB cable.
2. Tap the file to open it. You can find it in the **Files** / **My Files** app under *Downloads*, or in your browser's downloads.
3. Android will say that this source is not allowed to install apps. Tap **Settings**, turn on **Allow from this source** for that app (Chrome, Files, Gmail…), and go back.
   - You can turn this off again after installing: *Settings → Apps → Special app access → Install unknown apps*.
4. Tap **Install**.
5. If **Google Play Protect** shows a warning ("Unsafe app blocked" or "App scan recommended"), tap **More details → Install anyway** (or **Scan app** and then **Install**). This appears because the app is not from Google Play.
6. Tap **Open**.

## 2. Connect to your server

The first time, the app opens **Settings**:

1. Tap **Search network**. The app looks for a Vacuula server on your Wi-Fi (takes a few seconds) and fills in the address.
   - Not found? Type the server's IP address yourself, for example `192.168.1.50`. It is the same address you use for the Vacuula web page in your browser. Add `:port` if your server does not use port 80.
2. Tap **Test**. It should say *Connected: Vacuula 1.x · 1 robot*.
3. Tap **Save**.

Your robot now shows up with its status and battery.

Tap the line under **Start cleaning** (for example *Map · Turbo*) to choose **where** (Map / Whole house / Spot), **suction** (Eco / Turbo) and **navigation** (Normal / Extra care / Deep). Use **Map** if you want the robot to respect your no-go lines.

## 3. Turn on notifications (optional)

Get a notification when the robot starts, recharges in the middle of a clean, finishes, needs help (stuck, picked up, brush, dust bin) or goes offline.

1. In the app, go to **Settings → Notifications → Notify me**, and tap **Save**.
2. Allow notifications when Android asks.
3. **Important for reliability:** *Android Settings → Apps → Vacuula → Battery →* **Unrestricted**.
   - **Samsung:** also *Settings → Battery → Background usage limits →* make sure Vacuula is not in *Sleeping apps*, or add it to *Never sleeping apps*.
   - **Xiaomi / Redmi / POCO:** *Settings → Apps → Vacuula →* turn on **Autostart**, and set *Battery saver* to **No restrictions**.
   - **Huawei / Honor:** *Settings → Battery → App launch → Vacuula →* manage manually and turn everything on.

While notifications are on, Android shows a small silent notification, **"Watching your robots"**. Android requires this for apps working in the background. You can hide it under *Settings → Apps → Vacuula → Notifications → Background watcher*.

Notifications work while your phone can reach the server – at home on Wi-Fi, or through a VPN. Away from home the app waits quietly until it can reach the server again.

## 4. Maps, no-go lines and zones

Tap **Maps, no-go lines & zones** on the robot card and pick a map.

- Pinch to zoom, drag to move the map.
- **Add** → tap the map to place points → **Done** makes a no-go line. Tap the first point again (or **Close**) to close the shape, then choose **Cleaning zone** or **No-go area**.
- Tap a line or zone to **Edit** or **Delete** it, switch no-go lines on/off, or **Clean** a single zone.
- Gen3 robots (D3–D7) keep no-go lines and zones on the robot itself, so the robot must be online while you edit.

## 5. Schedule

Tap **Schedule** on the robot card. Tap **+ Add**, pick days, time, cleaning mode and (optionally) a zone, and **Save**. Tap a cleaning to change or delete it. The robot must be online. Times are shown in your phone's time zone.

## 6. Robot details and history

Tap the robot's **name** on its card to rename it and see battery details (D3–D7) and statistics. **History** on the card lists earlier cleanings; tap one to see the map of where the robot cleaned and the details. When the robot shows an alert such as "dust bin full", tap **Dismiss** after you have fixed it.

## 7. Remote control (D3–D7, experimental)

If your robot supports it, its card has a **Drive** button. The first time, the app asks for the robot's secret key. Ask the person running the Vacuula server to run this in the server folder (Terminal on Mac/Linux, PowerShell on Windows) and send you the key for your robot:

```bash
docker compose exec vacuula python -c "import sqlite3; [print(r[0], r[1]) for r in sqlite3.connect('/server/data/vacuula.db').execute('select robot, password from gen3__data')]"
```

It prints the serial number and the key on one line - paste the key (the part after the space), or the whole line.

**Windows 11:** the same command works in PowerShell. In File Explorer, open the folder with Vacuula's `docker-compose.yaml`, right-click inside it and choose *Open in Terminal*, then paste the command. Make sure Docker Desktop is running.

If it doesn't work:
- *"no configuration file provided"* or *"service vacuula is not running"* (often with *Using name "system32"*): PowerShell is not in Vacuula's folder. Use this version instead - it finds the Vacuula container by itself and works from any folder (PowerShell, Mac and Linux):

  ```
  docker exec $(docker ps -q --filter "label=com.docker.compose.service=vacuula") python -c "import sqlite3; [print(r[0], r[1]) for r in sqlite3.connect('/server/data/vacuula.db').execute('select robot, password from gen3__data')]"
  ```
- No lines are printed: the robot is not a Gen3 model (Botvac Connected, D3–D7), or it hasn't been set up with the Vacuula server yet.

Your phone must be on the same Wi-Fi as the robot, and the robot must be idle. Hold an arrow to move, let go to stop, and use the red **STOP** button at any time. If an earlier remote-control session is stuck on the robot, the app ends it by itself and tries again (it never stops a real cleaning).

## Updating to a new test version

Download the newest APK from [latest_app_release_to_download](https://github.com/Jokez1980/vacuula_app/tree/main/latest_app_release_to_download) and install it on top of the old one – your settings are kept.
If Android says **"App not installed"** or *"conflicts with an existing package"*, the new file was signed differently: uninstall the old app (it may be called "Vacuula") first, then install the new one (you will need to enter the server address again).

## Using it away from home

The Vacuula server has **no password**, so never open it to the internet (no port forwarding in your router). To use the app away from home, install a VPN such as **Tailscale** (free) on both the server and your phone, and enter the server's Tailscale address (`100.x.x.x`) in the app's settings.

## Troubleshooting

| Problem | What to do |
|---|---|
| "Cannot reach the server" | Is the phone on the same Wi-Fi as the server (not a guest network)? Is the server running – does the Vacuula web page open in the phone's browser? |
| "Search network" finds nothing | Type the IP address manually. Some routers block devices from seeing each other ("AP/client isolation") – turn that off for your home Wi-Fi. |
| Robot shows "Not connected to the server" | The robot is offline: check that it is switched on and on Wi-Fi. Open the Vacuula web page to compare. |
| No notifications | Check *Settings → Apps → Vacuula → Notifications* is on, battery is **Unrestricted**, and that the "Watching your robots" notification is there. If you used *Force stop*, open the app once to restart it. |
| Can't edit no-go lines/zones | Gen3 robots must be online while editing. Wait until the robot card shows its status, then try again. |
| Play Protect removed the app | Install again and choose *Install anyway*. You can also open *Play Store → profile → Play Protect* and allow the app. |

## Feedback

Please report what works and what doesn't – include your phone model, Android version and robot model (for example *Pixel 7, Android 15, Botvac D7*). Screenshots help a lot.
