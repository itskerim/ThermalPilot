# Thermal Pilot

<img width="1672" height="941" alt="INCORRECT" src="https://github.com/user-attachments/assets/02cff2b7-7540-40a9-a2b9-fa9eed451cdf" />

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![Latest release](https://img.shields.io/github/v/release/itskerim/ThermalPilot)](https://github.com/itskerim/ThermalPilot/releases/latest)

Thermal Pilot is a lightweight menu bar app that shows what's happening inside your Mac in plain English. See CPU load, memory pressure, temperatures, fan activity, and the apps causing problems without opening Activity Monitor or digging through Terminal.

Built for Apple Silicon and Intel Macs.

## Download

Download the [latest release](https://github.com/itskerim/ThermalPilot/releases/latest) for macOS 14+.

Open the DMG, drag Thermal Pilot into Applications, and launch it from your menu bar.

## Why Thermal Pilot?

Most system monitors overwhelm you with numbers.

Thermal Pilot focuses on the information that actually matters:

- Is your Mac healthy?
- What's causing slowdowns?
- Which app is using all your memory?
- Are temperatures becoming a problem?
- Should you close something or leave it alone?

Instead of making you interpret dozens of metrics, Thermal Pilot gives you a clear overview and a simple verdict.

## Features

### • Everything in one place

CPU usage, memory pressure, temperatures, fan activity, and system health live in a single panel beside Control Center.

### • Find what's eating your RAM

See the largest memory consumers instantly. Chrome tabs are grouped together. Helper processes stay organized under their parent application. Rogue Node, Python, Docker, Ollama, LM Studio, and local AI workloads appear by name.

### • Understand memory pressure

Memory pressure is often a better indicator of system health than RAM usage alone. Thermal Pilot surfaces it prominently alongside a complete breakdown of Active, Wired, Compressed, Cached, and Free memory.

### • Know when performance is affected

A built-in slowdown indicator analyzes CPU load, memory pressure, temperatures, and fan activity to explain what's happening in plain English.

### • Fully local

No accounts. No analytics. No telemetry. No background services.

Everything runs locally on your Mac using public macOS APIs and hardware sensors.

### • Lightweight by design

Lives entirely in your menu bar. No Dock icon. No unnecessary background processes. Fast startup and configurable refresh intervals.

### • Built for real hardware

When a sensor isn't available on your Mac, Thermal Pilot tells you. It never invents readings or estimates values it cannot verify.

## What You Can See

### • CPU

Current CPU utilization, processor information, and overall system load.

### • Memory

Memory usage, memory pressure, memory composition, and the processes consuming the most RAM.

### • Temperature

The hottest available thermal sensors across your system with support for Celsius and Fahrenheit.

### • Fans

Current fan speeds, operating ranges, and utilization percentages where supported.

### • System Health

A simple explanation of whether your Mac is running normally or approaching a bottleneck.

## Privacy

Thermal Pilot never sends data anywhere.

No network traffic. No analytics. No accounts. No tracking.

Your preferences remain stored locally on your Mac.

## Open Source

Thermal Pilot is fully open source under the [MIT License](LICENSE).

Contributions, bug reports, and feature suggestions are welcome.

---

## Technical Details

This section covers how Thermal Pilot works under the hood — how each metric is collected, how the data is processed, and how the codebase is structured. Everything here is verifiable by reading the source in [`Sources/FanUsageCore`](Sources/FanUsageCore).

### • Architecture

Thermal Pilot is a Swift 6 package split into two targets:

- **`FanUsageCore`** — the data layer. A dependency-free library containing all metric reading, data models, and business logic. Links only `IOKit`. Has no UI dependencies and is fully unit-tested in isolation.
- **`FanUsageApp`** — the UI layer. A SwiftUI `MenuBarExtra` app that consumes `FanUsageCore`, renders the panel, and handles preferences.

This separation means the entire data pipeline — CPU sampling, memory page accounting, SMC decoding, bottleneck analysis — can be audited and tested without running the app.

### • CPU

CPU usage is measured using `host_statistics(HOST_CPU_LOAD_INFO)` from the Darwin kernel, which returns cumulative tick counts split into `user`, `system`, `idle`, and `nice` buckets.

Thermal Pilot takes two samples separated by the configured refresh interval and computes:

```
usage% = (totalDelta − idleDelta) / totalDelta × 100
```

This produces a whole-machine figure normalized to 0–100%, regardless of core count. The chip model is read from `sysctl machdep.cpu.brand_string` and the core count from `ProcessInfo.processorCount`.

The first reading after launch always shows 0% — there is no previous sample to diff against.

### • Memory

Memory statistics are read from `host_statistics64(HOST_VM_INFO64)`, which exposes the kernel's VM page counters. Page size is read from `host_page_size`. Total physical RAM comes from `ProcessInfo.physicalMemory`.

The raw page counts map to display categories as follows:

| Category | Source pages |
| --- | --- |
| Active | `active_count` |
| Wired | `wire_count` |
| Compressed | `compressor_page_count` |
| Cached | `inactive_count + speculative_count` |
| Free | `free_count` |
| Used | `active + wired + compressor` |
| Available | `free + inactive + speculative` |

Memory pressure is derived from used-vs-total and compressor pool size, then classified:

| Status | Condition |
| --- | --- |
| Normal | pressure < 74% and compressed < 10% of total RAM |
| Elevated | pressure ≥ 74%, or compressed > 10% of total RAM |
| High | pressure ≥ 88%, or compressed > 20% of total RAM |

Top memory consumers are read by running `/bin/ps -axo pid,ppid,rss,comm` and parsing resident set size (RSS). Processes are then grouped by their owning `.app` bundle — walking the command path up to the outermost `.app` directory — so all Chrome helpers, Electron workers, and renderer processes collapse under their parent application. Processes with no bundle (bare `node`, `python`, `ollama`, etc.) appear individually by name.

### • SMC and Sensors

Fan speeds and temperatures are read from the System Management Controller (SMC) over IOKit using the `AppleSMC` service.

The SMC protocol works by sending key-value requests over `IOConnectCallStructMethod`. Each key is a four-character code packed into a `UInt32`. Thermal Pilot reads the following keys:

**Fan keys:**

| Key | Meaning |
| --- | --- |
| `FNum` | Number of fans |
| `F0Ac`, `F1Ac`, … | Current RPM |
| `F0Mn`, `F1Mn`, … | Minimum RPM |
| `F0Mx`, `F1Mx`, … | Maximum RPM |
| `F0ID`, `F1ID`, … | Fan label string |

**Thermal keys:**

| Key | Sensor |
| --- | --- |
| `TC0P` | CPU Proximity |
| `TC0E` | CPU Core 1 |
| `TC0F` | CPU Core 2 |
| `Tp09` | SoC |
| `Te05` | Die |

SMC values are encoded in several binary formats. Thermal Pilot decodes all of them:

| SMC type | Encoding | Decoding |
| --- | --- | --- |
| `flt ` | IEEE 754 float, little-endian | `Float(bitPattern: UInt32)` |
| `fpe2` | Unsigned fixed-point, /4 | `UInt16 / 4.0` |
| `sp78` | Signed fixed-point, /256 | `Int16 / 256.0` |
| `ui8 ` | Unsigned 8-bit integer | Direct |
| `ui16` | Unsigned 16-bit integer, big-endian | `UInt16` |
| `ui32` | Unsigned 32-bit integer, big-endian | `UInt32` |

Raw thermal reads can spike or glitch. Thermal Pilot applies a stability filter per sensor key: values outside 15–115°C are rejected, jumps greater than 35°C between consecutive reads are suppressed, and the SoC sensor (`Tp09`) is cross-checked against the die sensor (`Te05`) to catch implausible drops. When a read is rejected, the last stable value is held until the next valid reading.

If the SMC service cannot be opened — due to sandboxing, permissions, or the key not being exposed on the current hardware — all reads return `nil` and the UI shows "Unavailable".

### • Bottleneck Analysis

The slowdown verdict is computed by `BottleneckAnalyzer` after every refresh. It evaluates conditions in priority order and returns the first match:

| Verdict | Condition |
| --- | --- |
| Memory pressure | Memory status is High |
| Thermal limit | Hottest sensor ≥ 88°C |
| CPU-bound | CPU usage ≥ 82% |
| Memory getting tight | Memory status is Elevated |
| Cooling active | Fan load ≥ 72% or hottest sensor ≥ 78°C |
| No obvious bottleneck | None of the above |

Each verdict carries a severity (`normal`, `notice`, `warning`, `critical`), a plain-English detail line, and a progress value that drives the indicator bar.

### • Refresh Loop

`MetricsModel` runs a refresh loop on the main actor. Every cycle it calls `CompositeHardwareProvider.snapshot()`, which fans out synchronously to `SystemCPUProvider`, `SystemMemoryProvider`, and `SMCSensorProvider`, assembles a `HardwareSnapshot`, runs validation, and returns.

The loop counts down second-by-second between refreshes so the UI can display "Next update in Ns". If a refresh is already running when the next interval fires, it is skipped — there is no queue buildup. A snapshot is flagged as stale if the read took longer than `2 × refreshInterval`.

### • Preferences

Four keys are persisted to `UserDefaults`. Nothing else is written to disk.

| Key | Default | Controls |
| --- | --- | --- |
| `refreshInterval` | `3.0` | Sampling cadence in seconds |
| `temperatureUnit` | `celsius` | °C or °F |
| `menuBarDisplayMode` | `cpu` | Metric shown in the menu bar label |
| `launchAtLogin` | `false` | Registered via `SMAppService` |

### • Validation

Every `HardwareSnapshot` passes through `MetricValidation` before being published. It checks for physically impossible values: negative or non-finite fan RPM, inverted fan ranges, CPU usage outside 0–100%, used memory exceeding total RAM, and temperatures outside 0–115°C. Any violations are appended as warnings to the snapshot and surfaced in QA output.

### • Build and Test

```bash
swift test                       # unit tests
scripts/package-app.sh release   # build, ad-hoc sign, produce .app + .dmg + .zip
open "build/Thermal Pilot.app"
```

The unit tests cover CPU tick math, memory page accounting and pressure classification, all six SMC numeric decodings, thermal spike rejection and recovery, display string rounding, validation flagging, and bottleneck precedence rules — without requiring real hardware, using `FixtureSMCReader` for injectable test data.

### • Diagnostics

```bash
# Stream JSONL samples — raw values, display strings, timing, warnings, bottleneck verdict
swift run FanUsage --qa-sample --count 300 --interval 1

# Dump every SMC key read — raw bytes, type tag, decoded value
swift run FanUsage --diagnose-sensors
```

Cross-check with Apple's own tools:

```bash
top -l 2 -n 0      # CPU ticks
vm_stat            # VM page counters
memory_pressure    # system pressure
```
