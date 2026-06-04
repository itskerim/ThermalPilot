# Install & Uninstall

## Requirements

- macOS **14 (Sonoma) or later**
- Apple Silicon or Intel Mac (fan/thermal readings depend on which SMC keys your model exposes)

## Install from a release

1. Download the latest `ThermalPilot-x.y.z.dmg` (or `.zip`) from the [Releases page](https://github.com/itskerim/ThermalPilot/releases/latest).
2. Open the `.dmg`. A Finder window shows **Thermal Pilot** and an **Applications** shortcut.
3. Drag **Thermal Pilot** onto **Applications**.
4. Eject the disk image.

## First launch (Gatekeeper)

Thermal Pilot is **ad-hoc signed but not notarized**, so macOS will warn on first launch. This is expected for an open-source app distributed outside the App Store.

**Option A — right-click open:**
1. In Applications, **right-click** (or Control-click) **Thermal Pilot** → **Open**.
2. Click **Open** in the dialog. macOS remembers the choice; future launches are normal.

**Option B — Privacy & Security:**
1. Try to open the app once (it gets blocked).
2. **System Settings → Privacy & Security**, scroll down, and click **"Open Anyway"** next to the Thermal Pilot notice.

Once open, Thermal Pilot appears as an **icon in the menu bar** (beside Control Center). It has **no Dock icon and no window** in the app switcher — that's intentional (`LSUIElement`). Click the menu-bar icon to open the panel.

## Launch at login

Open the panel → **Settings** → toggle **Launch at login**. This registers the app with macOS via `ServiceManagement` (`SMAppService`); no login items hackery, and you can revoke it in System Settings → General → Login Items.

## Build from source instead

```bash
git clone https://github.com/itskerim/ThermalPilot.git
cd ThermalPilot
swift test                       # optional: verify
scripts/package-app.sh release   # produces build/Thermal Pilot.app + .dmg + .zip
open "build/Thermal Pilot.app"
```

Building locally sidesteps the Gatekeeper prompt because the binary is signed on your own machine.

## Uninstall

1. Quit Thermal Pilot — open the panel → **Settings** → **Quit Thermal Pilot** (or click the menu-bar icon and quit).
2. Drag **Thermal Pilot** from Applications to the Trash.
3. (Optional) Remove its preferences:
   ```bash
   defaults delete local.thermalpilot.app 2>/dev/null || true
   ```
4. (Optional) If you enabled launch at login, confirm it's gone from **System Settings → General → Login Items**.

That's everything — Thermal Pilot installs no helpers, daemons, kernel extensions, or background services.

## Privacy

- **No network access.** The app never opens a socket. You can confirm with Little Snitch / `lsof` or by reading [`Sources/FanUsageCore`](../Sources/FanUsageCore).
- **No analytics, no accounts.**
- **Persisted state** is limited to four `UserDefaults` keys (refresh interval, temperature unit, menu-bar metric, launch-at-login).
- All readings come from the kernel (`host_statistics`), the SMC (IOKit), and `/bin/ps`, locally.
