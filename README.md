# Thermal Pilot

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![Latest release](https://img.shields.io/github/v/release/itskerim/ThermalPilot)](https://github.com/itskerim/ThermalPilot/releases/latest)

**Thermal Pilot is a local-only macOS menu-bar utility for quick fan, CPU, memory, and thermal status.** It sits beside Control Center and reads everything from public macOS APIs and SMC keys — **no network, no telemetry, no accounts, no background daemon.**

At a glance, you can see:

- 🌀 **Fan speeds** — live RPM for every fan, plus where each one sits in its min–max range.
- 🧠 **What's eating your RAM** — top memory users grouped by app (so Chrome's 20 helper processes show up as one "Google Chrome" row), how much RAM is free, and a full Active / Wired / Compressed / Cached / Free breakdown.
- ⚙️ **CPU load** — total usage across all cores, with the chip model.
- 🌡️ **Temperature** — the hottest on-chip sensors (SoC, die, CPU proximity), in °C or °F.
- 🚦 **Slowdown indicator** — a single plain-English verdict ("No obvious bottleneck", "Memory pressure", "Thermal limit", "CPU-bound") so you don't have to interpret raw numbers.

> Heavy local model running? A runaway Node process? A browser quietly holding 11 GB? Thermal Pilot tells you which app it is and whether it's actually a problem — without sending a single byte off your machine.

---

## Screenshots

| Overview | Memory detail | Settings |
| --- | --- | --- |
| Fans, CPU, and memory at a glance | RAM breakdown + top users grouped by app | Refresh rate, menu-bar metric, °C/°F, login |

<!-- TODO: drop PNGs into assets/ and reference them here, e.g. ![Overview](assets/overview.png) -->

---

## Download

Grab the latest `.dmg` (or `.zip`) from the [**Releases page**](https://github.com/itskerim/ThermalPilot/releases/latest), open the disk image, and drag **Thermal Pilot** into Applications.

> [!NOTE]
> The app isn't notarized yet, so on first launch macOS may block it. Right-click the app → **Open**, or allow it under **System Settings → Privacy & Security → "Open Anyway"**. See [docs/INSTALL.md](docs/INSTALL.md) for the full walkthrough.

Thermal Pilot launches as a **menu-bar extra** (`LSUIElement` — no Dock icon, no window in the app switcher). Click the icon to open the panel.

---

## What you're looking at

Every number in the UI maps to a specific macOS API or SMC sensor. Full reference: **[docs/METRICS.md](docs/METRICS.md)**. The short version:

| Section | What it shows | Where it comes from |
| --- | --- | --- |
| **Fans** | Live RPM, min–max range, % of range | SMC keys `FNum`, `F0Ac`, `F0Mn`, `F0Mx`, … |
| **CPU** | Total usage %, core count, chip name | `host_statistics(HOST_CPU_LOAD_INFO)`, `sysctl machdep.cpu.brand_string` |
| **Memory** | Used %, available, pressure, compressed, full breakdown, top apps | `host_statistics64(HOST_VM_INFO64)`, `ps -axo rss` |
| **Temperature** | Hottest sensors in °C/°F | SMC keys `Tp09`, `Te05`, `TC0P`, `TC0E`, `TC0F` |
| **Slowdown** | One-line bottleneck verdict | Computed from the above (`BottleneckAnalyzer`) |

If a sensor isn't exposed on your Mac (common for fan/thermal SMC keys on some Apple Silicon models), Thermal Pilot shows **"Unavailable"** instead of failing or faking a number.

### Reading the memory panel

- **Memory use** — physical RAM in use (Active + Wired + Compressed) as a % of total. The "is my Mac full?" number.
- **Pressure** — how hard macOS is working to keep RAM available. High pressure → swapping/compression → slowdowns. This is the number that actually predicts lag, not raw "used".
- **RAM breakdown** — Active (apps in use), Wired (can't be moved), Compressed (squeezed to avoid disk), Cached (reclaimable file data), Free (instantly available).
- **Top memory users** — sorted by resident memory. Multi-process apps (Chrome, ChatGPT Atlas, Codex, Figma, Electron apps) are **grouped under one expandable parent row**; a raw `node` or `python` process running a local model shows up by name so you can spot it.

Tips for acting on it: high **pressure** (not just high "used") is what slows you down — macOS uses free RAM as cache on purpose, so a low "Free" number is normal and healthy. If pressure is high, the **Top memory users** list shows the app to quit first.

---

## Build and Test

Requires macOS 14+ and a recent Swift toolchain (Swift 6 / Xcode 16+).

```bash
swift test                       # run the unit test suite
scripts/package-app.sh release   # build, ad-hoc sign, and package the app
```

The packaging script produces:

```text
build/Thermal Pilot.app
build/ThermalPilot-0.1.0.dmg
build/ThermalPilot-0.1.0.zip
```

Run the freshly built app:

```bash
open "build/Thermal Pilot.app"
```

Architecture, module layout, and how packaging works: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

---

## Share

Upload or send `build/ThermalPilot-0.1.0.dmg`. People download it, open the disk image, and drag Thermal Pilot into Applications. A `.zip` is also generated for hosts that prefer zip downloads.

---

## QA and live accuracy checks

Thermal Pilot ships a JSONL sampler for validating the values shown in the UI against the raw provider snapshot:

```bash
swift run FanUsage --qa-sample --count 300 --interval 1
```

Each line includes raw CPU/RAM/fan/thermal readings, the exact display strings after rounding, provider timing, availability warnings, validation warnings, and the slowdown reason. Use `--temperature-unit fahrenheit` to validate Fahrenheit output.

Inspect raw sensors directly:

```bash
swift run FanUsage --diagnose-sensors   # dumps every SMC key Thermal Pilot reads
```

Cross-check against Apple's own tools:

```bash
top -l 2 -n 0      # CPU
vm_stat            # memory pages
memory_pressure    # pressure
```

CPU and RAM are validated against public macOS APIs and may differ slightly from Activity Monitor because sampling windows and memory categories vary. Fan and thermal SMC readings are best-effort: QA checks decoding, stability, plausible bounds, and agreement with reference tools when available. Details: **[docs/QA.md](docs/QA.md)**.

---

## Documentation

- **[docs/METRICS.md](docs/METRICS.md)** — what every metric means, the API/SMC source behind it, and how to act on it.
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — module layout, data flow, and the bottleneck/grouping logic.
- **[docs/INSTALL.md](docs/INSTALL.md)** — install, first-launch Gatekeeper steps, uninstall, privacy notes.
- **[docs/QA.md](docs/QA.md)** — the diagnostic flags and how readings are validated.
- **[docs/FAQ.md](docs/FAQ.md)** — common questions and troubleshooting.

---

## Privacy

Thermal Pilot makes **no network connections**, has **no analytics**, and stores nothing beyond a handful of `UserDefaults` preferences (refresh interval, temperature unit, menu-bar metric, launch-at-login). Everything is read locally from the kernel and the SMC. Verify it yourself — the entire data layer is in [`Sources/FanUsageCore`](Sources/FanUsageCore).

## License

[MIT](LICENSE).
