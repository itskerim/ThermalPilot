# Thermal Pilot
<img width="1672" height="941" alt="image" src="https://github.com/user-attachments/assets/98c04612-67dc-4b3e-a844-b0d352867f0e" />


[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![Latest release](https://img.shields.io/github/v/release/itskerim/ThermalPilot)](https://github.com/itskerim/ThermalPilot/releases/latest)

## See what your Mac is actually doing — right from your menu bar

Fans, CPU, memory, and temperature at a glance. No Activity Monitor, no terminal, no guessing.

<!-- TODO: drop a hero screenshot here, e.g. ![Thermal Pilot](assets/screenshot.png) -->

## Download

[**Download the latest release**](https://github.com/itskerim/ThermalPilot/releases/latest) (macOS 14+, Apple Silicon & Intel).

Open the `.dmg`, drag **Thermal Pilot** into Applications, and it lives in your menu bar. First launch needs a right-click → **Open** (it's not notarized yet) — see [INSTALL.md](docs/INSTALL.md).

## What It Does

Thermal Pilot lives in your menu bar and shows you what's happening under the hood — what's eating your RAM, how hard your CPU is working, how fast your fans are spinning, and how hot your Mac is running. Progress bars, plain-English labels, one clear verdict. No mental math required.

- **One glance.** Fans, CPU, memory, and temperature in one panel beside Control Center.
- **Find the RAM hog.** Top memory users ranked and grouped by app — a 20-process Chrome shows as one row; a runaway `node` or local model shows up by name.
- **Pressure, not just "used".** It surfaces macOS memory *pressure* — the number that actually predicts slowdowns — alongside a full Active / Wired / Compressed / Cached / Free breakdown.
- **One-line verdict.** A "Slowdown" indicator tells you in English whether you're fine, warming up, CPU-bound, or hitting a thermal/memory limit.
- **100% local.** No network, no telemetry, no accounts, no background daemon. Everything is read from public macOS APIs and SMC sensors.
- **Honest about hardware.** If your Mac doesn't expose a fan or thermal sensor, it says "Unavailable" instead of faking a number.
- **Lightweight.** Menu-bar only (no Dock icon), opens instantly, refreshes on a schedule you pick (1s / 3s / 5s / 10s).
- **Yours to configure.** Pick the menu-bar metric (CPU % / Fan RPM / Temperature / icon), °C or °F, and launch-at-login.

## What You Can See

| Panel | What it shows | Source |
| --- | --- | --- |
| **Fans** / live RPM, min–max range, % of range | how hard each fan is working | SMC keys (`FNum`, `F0Ac`, …) |
| **CPU** / total usage %, core count, chip name | whole-machine load | `host_statistics` |
| **Memory** / use %, pressure, breakdown, top apps | what's eating your RAM and how much is free | `host_statistics64` + `ps` |
| **Temperature** / hottest sensors in °C/°F | how hot your Mac is running | SMC keys (`Tp09`, `Te05`, …) |
| **Slowdown** / one-line bottleneck verdict | should you worry? | computed from the above |

Full reference — what every number means and how to act on it: [**docs/METRICS.md**](docs/METRICS.md).

## Reading the memory panel

The panel most people open when their Mac feels slow:

- **Memory use** — how full RAM is (Active + Wired + Compressed). The "is my Mac full?" number.
- **Pressure** — how hard macOS is working to keep memory available. **This is what predicts lag**, not raw "used".
- **RAM breakdown** — Active, Wired, Compressed, Cached, Free, with hover explanations.
- **Top memory users** — ranked by resident memory, grouped under their parent app (expand to see helpers), each with its real icon. A bare `node` / `python` / local-model process shows by name so you can spot the culprit and quit it.

> A low **Free** number is normal — macOS uses idle RAM as cache on purpose. Watch **Pressure** and **Available** instead.

## Documentation

- [**METRICS.md**](docs/METRICS.md) — what every metric means, its API/SMC source, and how to act on it.
- [**ARCHITECTURE.md**](docs/ARCHITECTURE.md) — module layout, data flow, SMC access, packaging, tests.
- [**INSTALL.md**](docs/INSTALL.md) — install, first-launch Gatekeeper steps, uninstall, privacy.
- [**QA.md**](docs/QA.md) — diagnostic flags and how readings are validated.
- [**FAQ.md**](docs/FAQ.md) — common questions and troubleshooting.

## Build from source

Requires macOS 14+ and a recent Swift toolchain (Swift 6 / Xcode 16+).

```bash
swift test                       # run the unit test suite
scripts/package-app.sh release   # build, ad-hoc sign, and package
open "build/Thermal Pilot.app"   # run it
```

Produces `build/Thermal Pilot.app`, plus a `.dmg` and `.zip` for sharing. Architecture and packaging details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Verify the numbers

Thermal Pilot ships diagnostics so you can audit every value against the raw sensors and Apple's own tools:

```bash
swift run FanUsage --qa-sample --count 300 --interval 1   # JSONL: raw vs displayed
swift run FanUsage --diagnose-sensors                     # raw SMC key dump
```

Cross-check with `top -l 2 -n 0`, `vm_stat`, and `memory_pressure`. Details: [docs/QA.md](docs/QA.md).

## Privacy

No network connections. No analytics. No accounts. The only persisted state is four `UserDefaults` preferences (refresh interval, temperature unit, menu-bar metric, launch-at-login). Verify it yourself — the entire data layer is in [`Sources/FanUsageCore`](Sources/FanUsageCore).

## Contributing

Issues and PRs welcome — new sensors, bug fixes, and ideas. Keep it simple and test your changes.

## License

[MIT](LICENSE).
