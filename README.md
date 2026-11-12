# Ledge — a second dock with live widgets for your Mac

Ledge puts a dark, rounded "second dock" just above your normal macOS Dock. Its tiles show
live info, and clicking a tile opens a bigger card above it.

| Widget | Tile shows | Click to open |
|---|---|---|
| **Clock & Calendar** | Time and date | Month view and your next events |
| **Weather** | Temperature and the next 3 days | 5-day forecast with high/low bars |
| **Apps & Folders** | 2×2 grid of favourite apps | All favourites, running apps, drag apps in to add |
| **Reminders** | Your next reminder | Check off, delete or add reminders (synced with Apple Reminders / iPhone) |
| **Now Playing** | Artwork, song, progress, ⏮ ⏯ ⏭ | Big artwork, seek bar, volume (Apple Music + Spotify) |
| **Quick Controls** | Wi-Fi, Bluetooth, Dark Mode, Mute buttons | Control Center-style toggles, brightness, sound, Screenshot, AirDrop, Sleep Display, Hide Dock |
| **System Stats** | CPU ring, battery, memory | CPU, memory, disk, battery bars |
| **Focus Timer** *(optional)* | Countdown ring | 5/15/25/50 min presets |
| **Clipboard** *(optional)* | Item count | Your last copied items; click one to copy it again |

Other features: Dark, Light and Glass styles, a size slider, three positions (above the Dock,
top of the screen, or floating so you can drag it anywhere), widget reordering, launch at login,
a switch to auto-hide the normal macOS Dock, and **⌥⌘D** to show or hide Ledge from anywhere.
Right-click the bar for quick settings.

Needs **macOS 13 Ventura or newer**.

---

## Option A — Build it on your Mac (about 5 minutes)

1. Copy this whole `Ledge` folder to your Mac (AirDrop, USB stick, iCloud Drive, whatever's easiest).
2. Open **Terminal** on the Mac. If you've never installed Apple's developer tools, run this
   first and click *Install* (takes a few minutes):
   ```bash
   xcode-select --install
   ```
3. In Terminal, type `cd ` (with a space), drag the `Ledge` folder into the Terminal window, press Return, then run:
   ```bash
   bash Scripts/build-dmg.sh
   ```
4. When it says **Done!**, open `build/Ledge.dmg` and drag **Ledge** into **Applications**.

## Option B — Have GitHub build the .dmg for you (no developer tools needed)

1. Make a free GitHub account and create a new repository.
2. Upload the contents of this `Ledge` folder (including the hidden `.github` folder).
3. Open the repo's **Actions** tab. The **Build Ledge DMG** job runs automatically (or click *Run workflow*).
4. When it finishes (about 3–5 minutes), download **Ledge-dmg** from the bottom of the run page, unzip it, and you've got `Ledge.dmg`.
   This version runs on both Apple Silicon and Intel Macs.

---

## First launch

Ledge isn't signed with a paid Apple Developer ID, so macOS will block it the first time:

1. Open Ledge from Applications. macOS says it can't verify it. Click **Done** or **Cancel**.
2. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Ledge.

If macOS says the app "is damaged", run this once in Terminal, then open it again:
```bash
xattr -cr /Applications/Ledge.app
```

Then allow the permission pop-ups as they appear. Each one turns on a feature:

- **Reminders / Calendars**: shows your reminders and events
- **Location**: local weather (or type a city in Settings → General)
- **Automation (Music, Spotify, System Events)**: music controls, Dark Mode toggle, hide Dock
- **Bluetooth**: the Bluetooth toggle

You can change any of these later in Ledge Settings → Permissions.

## Using it

- **Click a tile** to open its card. Click anywhere else or press **Esc** to close it.
- **Right-click the bar** to open Settings or change the position or style.
- **Menu bar icon**: show/hide, position, Settings, Quit.
- **⌥⌘D**: show/hide Ledge.
- To make Ledge your *only* dock, turn on **Settings → General → Auto-hide the regular macOS Dock**.
