# Thermal Pilot

Thermal Pilot is a local-only macOS menu-bar utility for quick fan, CPU, memory, and thermal status.

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
