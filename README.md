# Thermal Pilot

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg)](https://swift.org)
[![Latest release](https://img.shields.io/github/v/release/itskerim/ThermalPilot)](https://github.com/itskerim/ThermalPilot/releases/latest)

Thermal Pilot is a local-only macOS menu-bar utility for quick fan, CPU, memory, and thermal status. It sits beside Control Center and reads everything from public macOS APIs and SMC keys — no network, no telemetry, no accounts.

## Download

Grab the latest `.dmg` (or `.zip`) from the [**Releases page**](https://github.com/itskerim/ThermalPilot/releases/latest), open the disk image, and drag **Thermal Pilot** into Applications.

> The app isn't notarized yet, so on first launch macOS may block it. Right-click the app → **Open**, or allow it under System Settings → Privacy & Security → "Open Anyway".

<!-- TODO: add a screenshot of the menu-bar UI here, e.g. ![Thermal Pilot](assets/screenshot.png) -->

## Build and Test

```bash
swift test
scripts/package-app.sh release
```

The packaged app is created at:

```text
build/Thermal Pilot.app
build/ThermalPilot-0.1.0.dmg
build/ThermalPilot-0.1.0.zip
```

## Run

```bash
open "build/Thermal Pilot.app"
```

## Share

Upload or send `build/ThermalPilot-0.1.0.dmg`. People can download it, open the disk image, and drag Thermal Pilot into Applications. A zip is also generated for hosts that prefer zip downloads.

The app appears as a menu-bar extra beside Control Center. CPU usage uses public macOS host statistics. Fan RPM and temperature use SMC keys when macOS exposes them; unsupported readings are shown as unavailable instead of failing.

## QA and Live Accuracy Checks

Thermal Pilot includes a JSONL sampler for validating the values shown in the UI against the raw provider snapshot:

```bash
swift run FanUsage --qa-sample --count 300 --interval 1
```

Each line includes raw CPU/RAM/fan/thermal readings, the exact display strings after rounding, provider timing, warnings, validation warnings, and the slowdown reason. Use `--temperature-unit fahrenheit` to validate Fahrenheit display output.

For manual cross-checking:

```bash
swift run FanUsage --diagnose-sensors
top -l 2 -n 0
vm_stat
memory_pressure
```

CPU and RAM are validated against public macOS APIs and may differ slightly from Activity Monitor-style tools because sampling windows and memory categories vary. Fan and thermal SMC readings are best effort: QA checks decoding, stability, plausible bounds, and agreement with reference tools when available.
